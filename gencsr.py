#!/usr/bin/env python3
"""
gencsr.py - Interactive Certificate Signing Request (CSR) generator with SAN support.

Collects certificate details interactively and produces three artifacts:

  1. An OpenSSL-style configuration file (default: ``server.conf``)
  2. A private key (RSA or ECDSA, optionally passphrase-protected)
  3. A PKCS#10 Certificate Signing Request (CSR) carrying Subject Alternative Names

The configuration file is written so that its ``[req_distinguished_name]`` and
``[alt_names]`` sections mirror exactly what is signed into the CSR. That means the
config is a faithful record of the request and can be reused with the OpenSSL CLI:

    openssl req -new -key <key> -config server.conf -out <csr>

Everything is built on the ``cryptography`` library; no external ``openssl``
binary is required.

Requirements (Python >= 3.9):
    pip install -r requirements.txt
    # or individually:
    pip install "cryptography>=41.0" "colorama>=0.4.6"

The script will detect missing packages on startup and offer to install them
automatically via pip.

Platforms: Linux, macOS, Windows (PowerShell / CMD / WSL).

Based on the original Nutanix Professional Services CSR script by Athmane Ogba,
re-architected for consistency, validation, and portability.
"""

from __future__ import annotations

import argparse
import getpass
import ipaddress
import logging
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

# --------------------------------------------------------------------------- #
# Version
# --------------------------------------------------------------------------- #
__version__ = "2.1.0"

# --------------------------------------------------------------------------- #
# Prerequisite check — runs before any third-party import.
# Offers to install missing packages via pip, then re-executes the script so
# fresh imports take effect.
# --------------------------------------------------------------------------- #
_REQUIRED: dict[str, str] = {"cryptography": "cryptography>=41.0"}
_OPTIONAL: dict[str, str] = {"colorama":     "colorama>=0.4.6"}


def _missing_modules(pkg_map: dict[str, str]) -> list[str]:
    missing: list[str] = []
    for module, spec in pkg_map.items():
        try:
            __import__(module)
        except ImportError:
            missing.append(spec)
    return missing


def _pip_install(specs: list[str]) -> None:
    cmd = [sys.executable, "-m", "pip", "install", "--quiet"] + specs
    print(f"  Running: {' '.join(cmd)}")
    result = subprocess.run(cmd)
    if result.returncode != 0:
        print("pip install failed. Please install the packages manually and re-run.")
        sys.exit(1)


def _check_dependencies() -> None:
    missing_req = _missing_modules(_REQUIRED)
    missing_opt = _missing_modules(_OPTIONAL)

    if missing_opt and not missing_req:
        # Only optional missing — skip silently (colorama degrades gracefully).
        pass

    if not missing_req:
        return

    sep = "=" * 68
    print(sep)
    print("Missing required package(s):")
    for spec in missing_req:
        print(f"  - {spec}")
    print()
    print("Install with:")
    print("  pip install -r requirements.txt")
    print(f"  # or: pip install {' '.join(missing_req)}")
    print(sep)

    try:
        answer = input("Install missing packages automatically now? [Y/n]: ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        print()
        sys.exit(1)

    if answer in ("", "y", "yes"):
        all_missing = missing_req + missing_opt  # grab optional while we're at it
        _pip_install(all_missing)
        print("Installation complete. Restarting script…\n")
        # Replace current process with a fresh one so the new imports are available.
        if sys.platform == "win32":  # type: ignore[misc]
            # os.execv is less reliable on Windows; subprocess + exit is safer.
            result = subprocess.run([sys.executable] + sys.argv)
            sys.exit(result.returncode)
        else:
            os.execv(sys.executable, [sys.executable] + sys.argv)
    else:
        print(f"\nRe-run after installing:  pip install {' '.join(missing_req)}")
        sys.exit(1)


_check_dependencies()

# Third-party imports — guaranteed present after _check_dependencies() above.
from cryptography.exceptions import UnsupportedAlgorithm          # type: ignore[import]  # noqa: E402
from cryptography.hazmat.primitives import hashes, serialization  # type: ignore[import]  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import ec, rsa     # type: ignore[import]  # noqa: E402
from cryptography import x509                                      # type: ignore[import]  # noqa: E402
from cryptography.x509.oid import NameOID                         # type: ignore[import]  # noqa: E402

# --------------------------------------------------------------------------- #
# Optional colour support — degrades gracefully on any platform.
# colorama handles Windows console ANSI codes automatically.
# --------------------------------------------------------------------------- #
try:
    from colorama import Fore, Style, init as _colorama_init

    _colorama_init(autoreset=False)
    SUCCESS = Fore.GREEN  + Style.BRIGHT
    ERROR   = Fore.RED    + Style.BRIGHT
    INFO    = Fore.CYAN   + Style.BRIGHT
    INPUT   = Fore.BLUE   + Style.BRIGHT
    WARN    = Fore.YELLOW + Style.BRIGHT
    RESET   = Style.RESET_ALL
except ImportError:
    SUCCESS = ERROR = INFO = INPUT = WARN = RESET = ""

# --------------------------------------------------------------------------- #
# Audit log — written to ~/.gencsr/gencsr.log (always writable cross-platform)
# --------------------------------------------------------------------------- #
_LOG_FILE: str | None = None
try:
    _log_dir = Path.home() / ".gencsr"
    _log_dir.mkdir(exist_ok=True)
    _LOG_FILE = str(_log_dir / "gencsr.log")
    logging.basicConfig(
        filename=_LOG_FILE,
        level=logging.INFO,
        format="%(asctime)s %(levelname)-8s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
except OSError:
    logging.disable(logging.CRITICAL)  # suppress all logging if log dir is unwritable

_log = logging.getLogger(__name__)


# --------------------------------------------------------------------------- #
# Custom exceptions
# --------------------------------------------------------------------------- #
class GenCSRError(Exception):
    """Base for all expected failures in this script."""


class FileConflictError(GenCSRError):
    """User declined to overwrite an existing output file."""


class KeyGenerationError(GenCSRError):
    """Private key generation failed."""


class CSRBuildError(GenCSRError):
    """CSR construction failed."""


# --------------------------------------------------------------------------- #
# Data model
# --------------------------------------------------------------------------- #
@dataclass
class CertRequest:
    """Everything needed to render a config file and build a CSR."""

    common_name: str
    country: str = ""
    state: str = ""
    locality: str = ""
    organization: str = ""
    organizational_unit: str = ""
    email: str = ""
    dns_names: list[str] = field(default_factory=list)
    ip_addresses: list[str] = field(default_factory=list)


# --------------------------------------------------------------------------- #
# Console helpers
# --------------------------------------------------------------------------- #
def info(msg: str) -> None:
    print(f"{INFO}{msg}{RESET}")


def success(msg: str) -> None:
    print(f"{SUCCESS}{msg}{RESET}")


def warn(msg: str) -> None:
    # warnings go to stderr so they stand out but don't pollute captured stdout
    print(f"{WARN}WARNING: {msg}{RESET}", file=sys.stderr)


def error(msg: str) -> None:
    print(f"{ERROR}{msg}{RESET}", file=sys.stderr)


def ask(
    label: str,
    *,
    required: bool = False,
    default: str | None = None,
    validator=None,
    max_retries: int = 10,
) -> str:
    """Prompt for a value, re-prompting on validation failure up to *max_retries*."""
    suffix = f" [{default}]" if default else ""
    attempts = 0
    while True:
        try:
            raw = input(f"{INPUT}{label}{suffix}: {RESET}").strip()
        except EOFError:
            raise GenCSRError("Input stream closed unexpectedly (non-interactive mode?).")

        if not raw and default is not None:
            raw = default
        if not raw:
            if required:
                error("This field is required.")
                continue
            return ""

        if validator is not None:
            ok, message = validator(raw)
            if not ok:
                attempts += 1
                error(message)
                if attempts >= max_retries:
                    raise GenCSRError(
                        f"Too many invalid attempts for '{label}' ({max_retries})."
                    )
                continue

        return raw


def ask_choice(label: str, options: list[tuple[str, str]], max_retries: int = 10) -> str:
    """Present a numbered menu and return the key of the chosen option."""
    info(label)
    for index, (_, description) in enumerate(options, start=1):
        print(f"  {index} - {description}")
    attempts = 0
    while True:
        try:
            raw = input(f"{INPUT}Enter the number of your choice: {RESET}").strip()
        except EOFError:
            raise GenCSRError("Input stream closed unexpectedly (non-interactive mode?).")

        if raw.isdigit() and 1 <= int(raw) <= len(options):
            return options[int(raw) - 1][0]

        attempts += 1
        error(f"Invalid choice. Please enter a number between 1 and {len(options)}.")
        if attempts >= max_retries:
            raise GenCSRError(f"Too many invalid menu selections ({max_retries}).")


# --------------------------------------------------------------------------- #
# Validators
# --------------------------------------------------------------------------- #
def validate_country(value: str) -> tuple[bool, str]:
    if len(value) == 2 and value.isalpha():
        return True, ""
    return False, "Country must be a 2-letter ISO code (e.g., US, AE, GB)."


def validate_email(value: str) -> tuple[bool, str]:
    if re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", value):
        return True, ""
    return False, "Please enter a valid email address."


def validate_hostname(value: str) -> tuple[bool, str]:
    """Loose RFC-1123 check — rejects obvious garbage without being overly strict."""
    label_pat = r"[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?"
    pattern = rf"^(\*\.)?({label_pat}\.)*{label_pat}$"
    if re.match(pattern, value):
        return True, ""
    return False, f"'{value}' does not look like a valid hostname or wildcard DNS name."


def validate_san_entry(value: str) -> tuple[bool, str]:
    """Accept valid IP addresses and valid DNS names; reject everything else."""
    try:
        ipaddress.ip_address(value)
        return True, ""
    except ValueError:
        pass
    ok, msg = validate_hostname(value)
    if ok:
        return True, ""
    return False, f"'{value}' is not a valid IP address or DNS name. {msg}"


# --------------------------------------------------------------------------- #
# File conflict guard
# --------------------------------------------------------------------------- #
def _confirm_overwrite(path: Path) -> None:
    """Prompt to overwrite *path*. Raises FileConflictError if user declines."""
    warn(f"File already exists: {path}")
    choice = ask_choice(
        "Overwrite it?",
        [("yes", "Yes, overwrite"), ("no", "No, abort")],
    )
    if choice == "no":
        raise FileConflictError(f"Aborted — will not overwrite {path}.")


def check_output_paths(*paths: Path) -> None:
    """For each path that exists, ask the user for permission to overwrite it."""
    for p in paths:
        if p.exists():
            _confirm_overwrite(p)


# --------------------------------------------------------------------------- #
# Interactive collection
# --------------------------------------------------------------------------- #
def collect_subject() -> CertRequest:
    info("Enter the certificate subject details (only the Common Name is mandatory).")
    common_name         = ask("Common Name (CN, e.g., server1.example.com)", required=True)
    country             = ask("Country (2-letter code)", validator=validate_country)
    state               = ask("State or Province (full name)")
    locality            = ask("Locality / City")
    organization        = ask("Organization")
    organizational_unit = ask("Organizational Unit")
    email               = ask("Email Address", validator=validate_email)

    return CertRequest(
        common_name=common_name,
        country=country.upper(),
        state=state,
        locality=locality,
        organization=organization,
        organizational_unit=organizational_unit,
        email=email,
    )


def collect_sans(default_cn: str) -> tuple[list[str], list[str]]:
    """Collect SAN entries, auto-classifying each as an IP address or DNS name."""
    info("Enter Subject Alternative Names (SANs). Leave blank to finish.")
    info("Each entry is auto-detected as an IP address or a DNS name.")
    dns_names:    list[str] = []
    ip_addresses: list[str] = []

    while True:
        try:
            raw = input(f"{INPUT}SAN entry (DNS name or IP): {RESET}").strip()
        except EOFError:
            break
        if not raw:
            break

        ok, msg = validate_san_entry(raw)
        if not ok:
            error(msg)
            continue

        try:
            # Normalize the IP to its canonical string form.
            normalized = str(ipaddress.ip_address(raw))
            if normalized in ip_addresses:
                warn(f"Duplicate IP SAN skipped: {normalized}")
            else:
                ip_addresses.append(normalized)
                info(f"  + IP  : {normalized}")
        except ValueError:
            if raw in dns_names:
                warn(f"Duplicate DNS SAN skipped: {raw}")
            else:
                dns_names.append(raw)
                info(f"  + DNS : {raw}")

    # Best practice: CN should also appear as a SAN.
    if default_cn and default_cn not in dns_names and default_cn not in ip_addresses:
        try:
            normalized_cn = str(ipaddress.ip_address(default_cn))
            is_ip = True
        except ValueError:
            normalized_cn = default_cn
            is_ip = False

        if normalized_cn not in (ip_addresses if is_ip else dns_names):
            choice = ask_choice(
                f"Include the Common Name '{default_cn}' as a SAN (recommended)?",
                [("yes", "Yes"), ("no", "No")],
            )
            if choice == "yes":
                (ip_addresses if is_ip else dns_names).insert(0, normalized_cn)

    if not dns_names and not ip_addresses:
        warn("No SANs were added. Many CAs and modern browsers require at least one SAN.")

    return dns_names, ip_addresses


def generate_private_key() -> tuple[object, str]:
    """Generate an RSA or ECDSA key and return (key_object, human_label)."""
    key_type = ask_choice(
        "Choose the private key type:",
        [("rsa", "RSA"), ("ecdsa", "ECDSA")],
    )

    try:
        if key_type == "rsa":
            bits = ask_choice(
                "Choose the RSA key size:",
                [("2048", "2048 bits"), ("3072", "3072 bits"), ("4096", "4096 bits")],
            )
            info(f"Generating a {bits}-bit RSA key…")
            key = rsa.generate_private_key(public_exponent=65537, key_size=int(bits))
            _log.info("Generated RSA %s-bit key.", bits)
            return key, f"RSA {bits}-bit"

        curve_key = ask_choice(
            "Choose the ECDSA curve:",
            [
                ("prime256v1", "prime256v1 (NIST P-256)"),
                ("secp384r1",  "secp384r1  (NIST P-384)"),
                ("secp521r1",  "secp521r1  (NIST P-521)"),
            ],
        )
        curves: dict[str, ec.EllipticCurve] = {
            "prime256v1": ec.SECP256R1(),
            "secp384r1":  ec.SECP384R1(),
            "secp521r1":  ec.SECP521R1(),
        }
        info(f"Generating an ECDSA key on {curve_key}…")
        key = ec.generate_private_key(curves[curve_key])
        _log.info("Generated ECDSA %s key.", curve_key)
        return key, f"ECDSA {curve_key}"

    except (UnsupportedAlgorithm, ValueError) as exc:
        raise KeyGenerationError(f"Key generation failed: {exc}") from exc
    except MemoryError:
        raise KeyGenerationError(
            "Not enough memory to generate the key. Try a smaller key size."
        )


def ask_passphrase() -> bytes | None:
    """Optionally protect the private key with a passphrase."""
    choice = ask_choice(
        "Protect the private key with a passphrase?",
        [("no", "No (unencrypted key)"), ("yes", "Yes (recommended)")],
    )
    if choice == "no":
        return None

    max_attempts = 5
    for attempt in range(1, max_attempts + 1):
        try:
            first = getpass.getpass("Enter passphrase: ")
        except (EOFError, KeyboardInterrupt):
            raise GenCSRError("Passphrase entry interrupted.")

        # Check length before asking for confirmation — better UX.
        if len(first) < 8:
            error(
                f"Passphrase must be at least 8 characters. "
                f"({attempt}/{max_attempts})"
            )
            continue

        try:
            second = getpass.getpass("Confirm passphrase: ")
        except (EOFError, KeyboardInterrupt):
            raise GenCSRError("Passphrase entry interrupted.")

        if first != second:
            error(f"Passphrases do not match. ({attempt}/{max_attempts})")
            continue

        return first.encode("utf-8")

    raise GenCSRError(f"Too many failed passphrase attempts ({max_attempts}).")


# --------------------------------------------------------------------------- #
# Request summary — lets the user review before the key is generated
# --------------------------------------------------------------------------- #
def print_request_summary(req: CertRequest) -> None:
    info("\nCertificate request summary:")
    print(f"  Common Name : {req.common_name}")
    if req.country:             print(f"  Country     : {req.country}")
    if req.state:               print(f"  State       : {req.state}")
    if req.locality:            print(f"  Locality    : {req.locality}")
    if req.organization:        print(f"  Org         : {req.organization}")
    if req.organizational_unit: print(f"  OU          : {req.organizational_unit}")
    if req.email:               print(f"  Email       : {req.email}")
    if req.dns_names:
        print(f"  DNS SANs    : {', '.join(req.dns_names)}")
    if req.ip_addresses:
        print(f"  IP SANs     : {', '.join(req.ip_addresses)}")
    if not req.dns_names and not req.ip_addresses:
        warn("SANs: none — most modern CAs and browsers will reject this certificate.")
    print()


# --------------------------------------------------------------------------- #
# Rendering
# --------------------------------------------------------------------------- #
def build_config(req: CertRequest) -> str:
    """Render an OpenSSL config whose DN and SANs match the CSR exactly."""
    has_sans = bool(req.dns_names or req.ip_addresses)

    lines = ["[req]", "prompt = no", "distinguished_name = req_distinguished_name"]
    if has_sans:
        lines.append("req_extensions = v3_req")
    lines += ["", "[req_distinguished_name]"]

    dn_fields = [
        ("countryName",            req.country),
        ("stateOrProvinceName",    req.state),
        ("localityName",           req.locality),
        ("organizationName",       req.organization),
        ("organizationalUnitName", req.organizational_unit),
        ("commonName",             req.common_name),
        ("emailAddress",           req.email),
    ]
    for field_name, value in dn_fields:
        if value:
            lines.append(f"{field_name} = {value}")

    if has_sans:
        lines += ["", "[v3_req]", "subjectAltName = @alt_names", "", "[alt_names]"]
        # OpenSSL [alt_names] uses 1-based indices.
        for idx, name in enumerate(req.dns_names, start=1):
            lines.append(f"DNS.{idx} = {name}")
        for idx, addr in enumerate(req.ip_addresses, start=1):
            lines.append(f"IP.{idx} = {addr}")

    return "\n".join(lines) + "\n"


def build_csr(req: CertRequest, key: object) -> x509.CertificateSigningRequest:
    """Build and sign the CSR from the request data and private key."""
    try:
        attributes = [x509.NameAttribute(NameOID.COMMON_NAME, req.common_name)]
        optional = [
            (NameOID.COUNTRY_NAME,             req.country),
            (NameOID.STATE_OR_PROVINCE_NAME,   req.state),
            (NameOID.LOCALITY_NAME,            req.locality),
            (NameOID.ORGANIZATION_NAME,        req.organization),
            (NameOID.ORGANIZATIONAL_UNIT_NAME, req.organizational_unit),
            (NameOID.EMAIL_ADDRESS,            req.email),
        ]
        for oid, value in optional:
            if value:
                attributes.append(x509.NameAttribute(oid, value))

        builder = x509.CertificateSigningRequestBuilder().subject_name(
            x509.Name(attributes)
        )

        san_entries: list[x509.GeneralName] = [
            x509.DNSName(name) for name in req.dns_names
        ]
        san_entries += [
            x509.IPAddress(ipaddress.ip_address(addr)) for addr in req.ip_addresses
        ]
        if san_entries:
            builder = builder.add_extension(
                x509.SubjectAlternativeName(san_entries), critical=False
            )

        return builder.sign(private_key=key, algorithm=hashes.SHA256())

    except (ValueError, TypeError) as exc:
        raise CSRBuildError(f"Invalid certificate data: {exc}") from exc
    except UnsupportedAlgorithm as exc:
        raise CSRBuildError(f"Algorithm not supported on this platform: {exc}") from exc
    except Exception as exc:
        raise CSRBuildError(f"Unexpected CSR build failure: {exc}") from exc


# --------------------------------------------------------------------------- #
# File output with cross-platform key permissions
# --------------------------------------------------------------------------- #
def _restrict_key_permissions(path: Path) -> None:
    """Restrict key file access to the current user — cross-platform."""
    if sys.platform == "win32":  # type: ignore[misc]
        _restrict_key_windows(path)
    else:
        _restrict_key_unix(path)


def _restrict_key_unix(path: Path) -> None:
    try:
        os.chmod(path, 0o600)
    except OSError as exc:
        warn(f"Could not set permissions on {path}: {exc}")
        warn("Set them manually:  chmod 600 " + str(path))


def _restrict_key_windows(path: Path) -> None:
    """Use icacls to grant only the current user access on Windows."""
    try:
        username = getpass.getuser()
        result = subprocess.run(
            [
                "icacls", str(path),
                "/inheritance:r",
                "/grant:r", f"{username}:(F)",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        _log.info("icacls output: %s", result.stdout.strip())
    except FileNotFoundError:
        warn(f"icacls not found — could not restrict permissions on {path}.")
        warn(
            "Run manually:  "
            f'icacls "{path}" /inheritance:r /grant:r "%USERNAME%:(F)"'
        )
    except subprocess.CalledProcessError as exc:
        warn(f"icacls failed for {path}: {exc.stderr.strip()}")
    except Exception as exc:
        warn(f"Could not restrict permissions on {path}: {exc}")


def write_private_key(key: object, path: Path, passphrase: bytes | None) -> None:
    encryption = (
        serialization.BestAvailableEncryption(passphrase)
        if passphrase
        else serialization.NoEncryption()
    )
    try:
        pem = key.private_bytes(  # type: ignore[union-attr]
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=encryption,
        )
        path.write_bytes(pem)
    except OSError as exc:
        raise GenCSRError(f"Could not write private key to {path}: {exc}") from exc

    _restrict_key_permissions(path)


def write_csr(csr: x509.CertificateSigningRequest, path: Path) -> None:
    try:
        path.write_bytes(csr.public_bytes(serialization.Encoding.PEM))
    except OSError as exc:
        raise GenCSRError(f"Could not write CSR to {path}: {exc}") from exc


def write_config(config_text: str, path: Path) -> None:
    try:
        # Always write LF line endings — OpenSSL parses these on all platforms.
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(config_text)
    except OSError as exc:
        raise GenCSRError(f"Could not write config to {path}: {exc}") from exc


# --------------------------------------------------------------------------- #
# Partial-output cleanup on failure
# --------------------------------------------------------------------------- #
def _cleanup(paths: list[Path]) -> None:
    """Remove any files already written before a failure, to avoid leaving partial output."""
    for p in paths:
        try:
            if p.exists():
                p.unlink()
                _log.info("Cleaned up partial output: %s", p)
        except OSError:
            pass


# --------------------------------------------------------------------------- #
# Banner / CLI
# --------------------------------------------------------------------------- #
BANNER = f"""\
*****************************************************************************
* Certificate Signing Request (CSR) generator with SAN support  v{__version__}
*****************************************************************************
USE AT YOUR OWN RISK. This tool is provided "as is" without warranty.
 - Store private keys securely and never share them.
 - Verify the generated config and CSR against your organization's policy.
*****************************************************************************
"""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Interactively generate a private key, OpenSSL config, and CSR.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  %(prog)s\n"
            "  %(prog)s -o /tmp/certs -n myserver\n"
            "  %(prog)s -o ./out -n api --force\n"
        ),
    )
    parser.add_argument(
        "-o", "--output-dir",
        help="Directory for the generated files (prompted if omitted).",
    )
    parser.add_argument(
        "-n", "--name",
        help="Base name for the .key and .csr files, e.g. 'server' (prompted if omitted).",
    )
    parser.add_argument(
        "-c", "--config-name", default="server.conf",
        help="File name for the OpenSSL config (default: server.conf).",
    )
    parser.add_argument(
        "--force", action="store_true",
        help="Overwrite existing output files without prompting.",
    )
    parser.add_argument(
        "--version", action="version", version=f"%(prog)s {__version__}",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    info(BANNER)

    if _LOG_FILE is not None:
        _log.info("Session started (v%s, platform=%s).", __version__, sys.platform)

    # ── 1. Resolve output directory ───────────────────────────────────────
    try:
        output_dir = Path(
            args.output_dir or ask("Output directory", default=".")
        ).expanduser().resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        error(f"Cannot create output directory: {exc}")
        return 1

    if not os.access(output_dir, os.W_OK):
        error(f"Output directory is not writable: {output_dir}")
        return 1

    base_name = args.name or ask(
        "Base name for output files (e.g., server)", required=True
    )
    # Path(base_name).stem strips extensions and neutralises path traversal.
    stem = Path(base_name).stem
    if not stem:
        error(
            f"Cannot derive a valid file name from '{base_name}'. "
            "Please provide a simple name such as 'server' or 'my-cert'."
        )
        return 1

    config_path = output_dir / args.config_name
    key_path    = output_dir / f"{stem}.key"
    csr_path    = output_dir / f"{stem}.csr"

    # ── 2. Overwrite check ────────────────────────────────────────────────
    if not args.force:
        try:
            check_output_paths(config_path, key_path, csr_path)
        except FileConflictError as exc:
            error(str(exc))
            return 1

    # ── 3. Collect certificate details ────────────────────────────────────
    try:
        req = collect_subject()
        req.dns_names, req.ip_addresses = collect_sans(req.common_name)
    except GenCSRError as exc:
        error(str(exc))
        _log.error("Aborted during input collection: %s", exc)
        return 1

    print_request_summary(req)

    # Let the user review before committing to key generation (which can be slow).
    try:
        proceed = ask_choice(
            "Proceed with key generation?",
            [("yes", "Yes, generate key and CSR"), ("no", "No, abort")],
        )
    except GenCSRError as exc:
        error(str(exc))
        return 1

    if proceed == "no":
        info("Aborted.")
        return 0

    try:
        key, key_label = generate_private_key()
        passphrase = ask_passphrase()
    except GenCSRError as exc:
        error(str(exc))
        _log.error("Aborted during key/passphrase collection: %s", exc)
        return 1

    _log.info(
        "CSR requested: CN=%s SANs(DNS)=%s SANs(IP)=%s",
        req.common_name, req.dns_names, req.ip_addresses,
    )

    # ── 4. Write artifacts — clean up on any failure ──────────────────────
    info("\nWriting output files…")
    written: list[Path] = []
    try:
        write_config(build_config(req), config_path)
        written.append(config_path)

        write_private_key(key, key_path, passphrase)
        written.append(key_path)

        csr = build_csr(req, key)
        write_csr(csr, csr_path)
        written.append(csr_path)

    except (GenCSRError, CSRBuildError) as exc:
        error(str(exc))
        _log.error("Generation failed: %s", exc)
        _cleanup(written)
        return 1
    except Exception as exc:
        error(f"Unexpected error: {exc}")
        _log.exception("Unexpected failure during generation.")
        _cleanup(written)
        return 1

    _log.info("Artifacts written: %s", [str(p) for p in written])

    # ── 5. Final summary ──────────────────────────────────────────────────
    print()
    success("Done. Created the following files:")
    success(f"  Config      : {config_path}")
    success(
        f"  Private key : {key_path}  "
        f"({key_label}{', encrypted' if passphrase else ', unencrypted'})"
    )
    success(f"  CSR         : {csr_path}")
    print()
    info(f"Send the CSR ({csr_path.name}) to your Certificate Authority.")
    warn(f"Keep the private key ({key_path.name}) secret — never share it.")

    if _LOG_FILE is not None:
        info(f"Audit log    : {_LOG_FILE}")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        error("\nOperation aborted by the user.")
        sys.exit(130)