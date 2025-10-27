# Create ca-chain  cert
mkdir -p certs
cd certs

COUNTRY="SG"
ORG="YourOrg Ltd"
ROOT_CN="YourOrg Root CA"
ICA_CN="YourOrg Intermediate CA"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="registry.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="registry.ntnxlab.local"
SERVER_IP1="10.129.42.93"
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.129.42.94"


# generate root ca cert
cat > v3_ca.ext <<'EOF'
[v3_ca]
basicConstraints=critical,CA:TRUE,pathlen:1
keyUsage=critical,keycertsSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always
EOF

openssl genrsa -aes256 -out root.key 4096
chmod 600 root.key

openssl req -new -x509 -sha256 -days "$ROOT_DAYS" \
  -key root.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$ROOT_CN" \
  -extfile v3_ca.ext -extensions v3_ca \
  -out root.crt

#create Intermediate cert
openssl genrsa -aes256 -out ica.key 4096
chmod 600 ica.key

openssl req -new -sha256 \
  -key ica.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$ICA_CN" \
  -out ica.csr

cat > v3_ica.ext <<'EOF'
[v3_ica]
basicConstraints=critical,CA:TRUE,pathlen=0
keyUsage=critical,keycertsSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

openssl x509 -req -sha256 -days "$ICA_DAYS" \
  -in ica.csr \
  -CA root.crt -CAkey root.key -CAcreateserial \
  -extfile v3_ica.ext -extensions v3_ica \
  -out ica.crt

cat ica.crt root.crt > ca-chain.crt



# This section is for generate of server cert
openssl genrsa -out server.key 2048

# CSR
openssl req -new -sha256 \
  -key server.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out server.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > v3_server.ext <<EOF
[v3_server]
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
subjectAltName=@alt_names

[alt_names]
DNS.1 = $SERVER_HOST1
IP.1  = $SERVER_IP1
EOF

# Sign server cert with ICA
openssl x509 -req -sha256 -days "$SERVER_DAYS" \
  -in server.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile v3_server.ext -extensions v3_server \
  -out server.crt

# Full chains for deployment
# - server-fullchain: server + ICA (what most servers present)
cat server.crt ica.crt > server-fullchain.crt


# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt server.crt

