# Create ca-chain  cert
mkdir -p certs
cd certs

COUNTRY="SG"
ORG="nutanix"
ROOT_CN="nutanix"
ICA_CN="nutanix"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="rx-mgt.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="rx-mgt.ntnxlab.local"
SERVER_IP1="10.161.44.102"
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



# This section is for generate of server cert, such as harbor, nkp, or workload cert
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
# cat server.crt ica.crt > server-fullchain.crt


# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt server.crt


vi .nonprd-env-mgmt
# VM Setting
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=1
export CONTROL_PLANE_MEMORY_GIB=16
export WORKER_REPLICAS=4
export WORKER_VCPUS=8
export WORKER_CORES_PER_VCPU=1
export WORKER_MEMORY_GIB=16
export SSH_KEY_FILE=/home/nutanix/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='rx-nkp-mgt' # <-- the name you create on the VM
export CONTROL_PLANE_IP=10.21.102.101 # <-- your kubeVip
export LB_IP_RANGE=10.21.102.102-10.21.102.105 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://10.21.102.154:9440/
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=nx2Tech609!
export IMAGE_NAME=nkp-ubuntu-24.04-release-cis-1.34.1-20251206061851.qcow2
export PRISM_ELEMENT_CLUSTER_NAME=kestrel01-2
export SUBNET_NAME=NKP_Network
export NUTANIX_STORAGE_CONTAINER_NAME=SelfServiceContainer

# Container Registry
# export REGISTRY_URL="https://registry.ntnxlab.local"  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_USERNAME=shukun
# export REGISTRY_PASSWORD=Harbor12345
# export REGISTRY_CA=/home/nutanix/certs/ca-chain.crt

# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.17.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.17.0.tar"

# Mirror Registry
# export REGISTRY_MIRROR_URL=https://registry.ntnxlab.local/mirror/  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_MIRROR_USERNAME=admin
# export REGISTRY_MIRROR_PASSWORD=Harbor12345
# export REGISTRY_MIRROR_CA=/home/nutanix/certs/ca-chain.crt

# ingress
export CLUSTER_HOSTNAME="rx-mgt.ntnxlab.local"
export INGRESS_CERT=/home/nutanix/nkp-v2.17.0/certs/server.crt
export INGRESS_KEY=/home/nutanix/nkp-v2.17.0/certs/server.key
export INGRESS_CA=/home/nutanix/nkp-v2.17.0/certs/ca-chain.crt

nkp create cluster nutanix --cluster-name $CLUSTER_NAME \
    --endpoint $NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT \
    --control-plane-endpoint-ip $CONTROL_PLANE_IP \
    --control-plane-vm-image $IMAGE_NAME \
    --control-plane-prism-element-cluster $PRISM_ELEMENT_CLUSTER_NAME \
    --control-plane-subnets $SUBNET_NAME \
    --control-plane-replicas $CONTROL_PLANE_REPLICAS \
    --control-plane-vcpus $CONTROL_PLANE_VCPUS \
    --control-plane-cores-per-vcpu $CONTROL_PLANE_CORES_PER_VCPU \
    --control-plane-memory $CONTROL_PLANE_MEMORY_GIB \
    --control-plane-disk-size 200 \
    --worker-vm-image $IMAGE_NAME \
    --worker-prism-element-cluster $PRISM_ELEMENT_CLUSTER_NAME \
    --worker-subnets $SUBNET_NAME \
    --worker-replicas $WORKER_REPLICAS \
    --worker-vcpus $WORKER_VCPUS \
    --worker-cores-per-vcpu $WORKER_CORES_PER_VCPU \
    --worker-memory $WORKER_MEMORY_GIB \
    --worker-disk-size 200 \
    --ssh-public-key-file $SSH_KEY_FILE \
    --csi-storage-container $NUTANIX_STORAGE_CONTAINER_NAME \
    --kubernetes-service-load-balancer-ip-range $LB_IP_RANGE \
    --self-managed \
    --cluster-hostname ${CLUSTER_HOSTNAME} \
    --ingress-ca ${INGRESS_CA} \
    --ingress-certificate ${INGRESS_CERT} \
    --ingress-private-key ${INGRESS_KEY} \
    --bundle=${KONVOY_IMAGE_BUNDLE},${KOMMANDER_IMAGE_BUNDLE} \
    --airgapped \
    --insecure \
    --timeout 120m