# .20 for kubevip
# .21 for metallb
tar -zxvf nkp.tar.gz
cd nkp
tar -zxvf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/bin/
tar -zxvf offline-docker-el9.tar.gz
cd docker-offline/
sudo dnf install -y *.rpm --disablerepo='*' --nogpgcheck
sudo systemctl enable --now docker
# let you run docker without sudo
sudo usermod -aG docker $USER
# log out/in OR:
newgrp docker
#check if docker is enable
docker ps

# configure auto complete 
grep -qxF 'source <(kubectl completion bash)' ~/.bashrc || \
  echo 'source <(kubectl completion bash)' >> ~/.bashrc
grep -qxF 'alias k=kubectl' ~/.bashrc || \
  echo 'alias k=kubectl' >> ~/.bashrc
source ~/.bashrc

cd ..
tar -zxvf nkp-air-gapped-bundle_v2.16.0_linux_amd64.tar.gz
cd nkp-v2.16.0
sudo mv cli/nkp /usr/bin/
nkp version         # to verify nkp version
sudo mv kubectl /usr/bin/
k version           # to verify the kubectl version
# generate ssh pub key so that we can ssh to worker nodes
ssh-keygen 

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
SERVER_CN="baremetal.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="baremetal.ntnxlab.local"
SERVER_IP1="10.129.42.20"
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.129.42.94"


# generate root ca cert
cat > v3_ca.ext <<'EOF'
[ req ]
x509_extensions    = v3_ca
prompt             = no

[ v3_ca ]
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

openssl genrsa -out root.key 4096
chmod 600 root.key

openssl req -new -x509 -sha256 -days "$ROOT_DAYS" \
  -key root.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$ROOT_CN" \
  -config v3_ca.ext -extensions v3_ca \
  -out root.crt

#create Intermediate cert
openssl genrsa -out ica.key 4096
chmod 600 ica.key

openssl req -new -sha256 \
  -key ica.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$ICA_CN" \
  -out ica.csr

cat > v3_ica.ext <<'EOF'
[ req ]
x509_extensions    = v3_ica
prompt             = no

[ v3_ica ]
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

openssl x509 -req -sha256 -days "$ICA_DAYS" \
  -in ica.csr \
  -CA root.crt -CAkey root.key -CAcreateserial \
  -extfile v3_ica.ext -extensions v3_ica \
  -out ica.crt

cat ica.crt root.crt > ca-chain.crt


# in internet connect laptop, run the following command
cd nkp-v2.16.0/kib
./konvoy-image create-package-bundle -os ubuntu-22.04