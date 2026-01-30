# from internet download the scrip
vi opentofu.sh
#!/bin/bash

# --- Configuration ---
TOFU_VERSION="1.9.0"         # Set desired OpenTofu version
NUTANIX_PROVIDER_VERSION="1.9.5" # Set desired Nutanix Provider version
OS_ARCH="linux_amd64"        # Architecture (usually linux_amd64)
OUTPUT_DIR="tofu_airgap_bundle"

# --- Setup Directories ---
mkdir -p "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}" || exit

echo "[1/3] Detecting OS for OpenTofu binary..."
if [ -f /etc/redhat-release ]; then
    echo "      -> Detected RHEL/CentOS system."
    PKG_TYPE="rpm"
    # For RHEL, we often just grab the binary tarball/zip to be safe across versions
    TOFU_URL="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.tar.gz"
    FILE_NAME="tofu_${TOFU_VERSION}_linux_amd64.tar.gz"
elif [ -f /etc/debian_version ]; then
    echo "      -> Detected Ubuntu/Debian system."
    PKG_TYPE="deb"
    TOFU_URL="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.tar.gz"
    FILE_NAME="tofu_${TOFU_VERSION}_linux_amd64.tar.gz"
else
    echo "      -> Unknown OS. Defaulting to generic Linux tar.gz."
    TOFU_URL="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.tar.gz"
    FILE_NAME="tofu_${TOFU_VERSION}_linux_amd64.tar.gz"
fi

echo "[2/3] Downloading OpenTofu v${TOFU_VERSION}..."
curl -L -o "${FILE_NAME}" "${TOFU_URL}"
echo "      -> Downloaded ${FILE_NAME}"

echo "[3/3] Downloading Nutanix Provider v${NUTANIX_PROVIDER_VERSION}..."
# Create the specific directory structure OpenTofu expects for filesystem mirrors
# Structure: registry.opentofu.org/nutanix/nutanix/VERSION/OS_ARCH
PROVIDER_DIR="registry.opentofu.org/nutanix/nutanix/${NUTANIX_PROVIDER_VERSION}/${OS_ARCH}"
mkdir -p "${PROVIDER_DIR}"

PROVIDER_URL="https://github.com/nutanix/terraform-provider-nutanix/releases/download/v${NUTANIX_PROVIDER_VERSION}/terraform-provider-nutanix_${NUTANIX_PROVIDER_VERSION}_${OS_ARCH}.zip"
curl -L -o "${PROVIDER_DIR}/terraform-provider-nutanix_${NUTANIX_PROVIDER_VERSION}_${OS_ARCH}.zip" "${PROVIDER_URL}"

# Unzip the provider immediately so it's ready to use
cd "${PROVIDER_DIR}" || exit
unzip -o "terraform-provider-nutanix_${NUTANIX_PROVIDER_VERSION}_${OS_ARCH}.zip"
rm "terraform-provider-nutanix_${NUTANIX_PROVIDER_VERSION}_${OS_ARCH}.zip"
cd - > /dev/null || exit

echo ""
echo "SUCCESS! The '${OUTPUT_DIR}' directory is ready."
echo "Transfer this directory to your air-gapped machine."