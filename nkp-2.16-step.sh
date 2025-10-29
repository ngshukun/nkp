#create cloud init for bastion
#cloud-config
preserve_hostname: false
fqdn: nutanix

# Create the user and give sudo
users:
  - default
  - name: nutanix
    groups: [wheel]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash

# Set password (plaintext) – not recommended for production
ssh_pwauth: true
chpasswd:
  expire: false
  users:
    - name: nutanix
      password: "nutanix/4u"   # quotes avoid any YAML surprises
      type: text

# sshd is usually enabled already, but harmless:
runcmd:
  - systemctl enable --now sshd

# install bash complete
mkdir -p auto-complete

# from internet machine, download the following
sudo dnf install -y dnf-plugins-core
dnf download --resolve bash-completion

# Transfer the entire folder to your airgapped machine
sudo rpm -Uvh *.rpm

# --- For current user ---
grep -qxF 'source <(kubectl completion bash)' ~/.bashrc || \
  echo 'source <(kubectl completion bash)' >> ~/.bashrc

grep -qxF 'alias k=kubectl' ~/.bashrc || \
  echo 'alias k=kubectl' >> ~/.bashrc

grep -qxF 'complete -o default -F __start_kubectl k' ~/.bashrc || \
  echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# --- For root user ---
sudo bash -c '
  grep -qxF "source <(kubectl completion bash)" /root/.bashrc || \
    echo "source <(kubectl completion bash)" >> /root/.bashrc
  grep -qxF "alias k=kubectl" /root/.bashrc || \
    echo "alias k=kubectl" >> /root/.bashrc
  grep -qxF "complete -o default -F __start_kubectl k" /root/.bashrc || \
    echo "complete -o default -F __start_kubectl k" >> /root/.bashrc
'

# Apply immediately without relogin ---
source ~/.bashrc


# Install docker
tar -zxvf offline-docker-el9.tar.gz
cd docker-offline/
sudo dnf install -y *.rpm
sudo systemctl enable --now docker

# let you run docker without sudo
sudo usermod -aG docker $USER

# log out/in OR:
newgrp docker
#check if docker is enable
sudo docker ps

# generate cert for all required server
# Example below is to create a cert for cluster "nkp-upgrade"
cat > nkp-openssl.cnf <<'EOF'
[ req ]
default_bits        = 2048
prompt              = no
default_md          = sha256
distinguished_name  = dn
req_extensions      = v3_req_csr

[ dn ]
CN = nkp.ntnxlab.local

[ v3_req_csr ]
basicConstraints = CA:FALSE
keyUsage         = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName   = @alt_names

[ v3_leaf ]
basicConstraints      = CA:FALSE
keyUsage              = critical, digitalSignature, keyEncipherment
extendedKeyUsage      = serverAuth, clientAuth
subjectAltName        = @alt_names
subjectKeyIdentifier  = hash
authorityKeyIdentifier= keyid,issuer

[ alt_names ]
DNS.1 = nkp-upgrade.ntnxlab.local
DNS.2 = *.nkp-upgrade.ntnxlab.local
# add more SANs if needed:
# DNS.3 = api.nkp.ntnxlab.local
# DNS.4 = ingress.nkp.ntnxlab.local
EOF

openssl genrsa -out nkp-upgrade.server.key 2048
openssl req -new -key nkp-upgrade.server.key -out nkp-upgrade.server.csr -config nkp-openssl.cnf

x509 -req -in nkp-upgrade.server.csr \
  -CA nsk-intermediate-ca.crt -CAkey nsk-intermediate-ca.key \
  -CAserial nsk-intermediate-ca.srl \
  -out nkp-upgrade.server.crt -days 3650 -sha256 \
  -extensions v3_leaf -extfile nkp-openssl.cnf

# To check if the generated cert matches the ca-chain.cert
openssl verify -CAfile nsk-ca-chain.crt nkp-upgrade.server.crt

#install k9s


#update the harbor registry path
sudo vi /etc/hosts
10.129.42.93 registry.ntnxlab.local #<-- append this so ybastion will know the fqdn is point to which IP. if you had DNS then no need for this

#transfer nkp-air-gapped-bundle_v2.16.0_linux_amd64.tar.gz to bastion untar the tar ball
tar -zxvf nkp-air-gapped-bundle_v2.16.0_linux_amd64.tar.gz


#create .env file to store all our variable
vi .env
# VM Setting 
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=2
export CONTROL_PLANE_CORES_PER_VCPU=2
export CONTROL_PLANE_MEMORY_GIB=16
export WORKER_REPLICAS=4
export WORKER_VCPUS=2
export WORKER_CORES_PER_VCPU=4
export WORKER_MEMORY_GIB=32
export SSH_KEY_FILE=/home/nutanix/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='sk-upgrade' # <-- the name you create on the VM
export CONTROL_PLANE_IP=10.129.42.29 # <-- your kubeVip
export LB_IP_RANGE=10.129.42.30-10.129.42.30 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://10.129.42.11:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=shukun
export NUTANIX_PASSWORD=P@ssw0rd
export IMAGE_NAME=nkp-rocky-9.5-release-1.31.4-20250214003015.qcow2
export PRISM_ELEMENT_CLUSTER_NAME=NKP
export SUBNET_NAME=Machine_Network_42
export NUTANIX_STORAGE_CONTAINER_NAME=SelfServiceContainer

# Container Registry
export REGISTRY_URL="https://registry.ntnxlab.local"  #<-- make sure fqdn can resolved by your dns, if not use IP
export REGISTRY_USERNAME=admin
export REGISTRY_PASSWORD=Harbor12345
export REGISTRY_CA=/home/nutanix/certs/nsk-ca-chain.crt

# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.16.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.16.0.tar"

# Mirror Registry
export REGISTRY_MIRROR_URL=https://registry.ntnxlab.local/external/  #<-- make sure fqdn can resolved by your dns, if not use IP
export REGISTRY_MIRROR_USERNAME=admin
export REGISTRY_MIRROR_PASSWORD=Harbor12345
export REGISTRY_MIRROR_CA=/home/nutanix/certs/nsk-ca-chain.crt

# Ingress
export CLUSTER_HOSTNAME="nkp-upgrade.ntnxlab.local"
export INGRESS_CERT=/home/nutanix/certs/nkp-upgrade.server.crt
export INGRESS_KEY=/home/nutanix/certs/nkp-upgrade.server.key
export INGRESS_CA=/home/nutanix/certs/nsk-ca-chain.crt


# For nkp 2.16, run command to create nkp cluster
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
    --registry-url $REGISTRY_URL \
    --registry-cacert $REGISTRY_CA \
    --registry-username $REGISTRY_USERNAME \
    --registry-password $REGISTRY_PASSWORD \
    --cluster-hostname ${CLUSTER_HOSTNAME} \
    --ingress-ca ${INGRESS_CA} \
    --ingress-certificate ${INGRESS_CERT} \
    --ingress-private-key ${INGRESS_KEY} \
    --bundle=${KONVOY_IMAGE_BUNDLE},${KOMMANDER_IMAGE_BUNDLE} \
    --airgapped \
    --insecure \
    --timeout 120m


#for nkp2.14
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
  --registry-url $REGISTRY_URL \
  --registry-cacert $REGISTRY_CA \
  --registry-username $REGISTRY_USERNAME \
  --registry-password $REGISTRY_PASSWORD \
  --registry-mirror-url $REGISTRY_MIRROR_URL \
  --registry-mirror-cacert $REGISTRY_MIRROR_CA \
  --registry-mirror-username $REGISTRY_MIRROR_USERNAME \
  --registry-mirror-password $REGISTRY_MIRROR_PASSWORD \
  --cluster-hostname ${CLUSTER_HOSTNAME} \
  --ingress-ca ${INGRESS_CA} \
  --ingress-certificate ${INGRESS_CERT} \
  --ingress-private-key ${INGRESS_KEY} \
  --airgapped \
  --insecure \
  --timeout 120m


# Tips, to chck for the logs on the control /worker plane you can perform the follow command
# ssh to the node
sudo journalctl -u kubelet -xe --no-pager
sudo less /var/log/cloud-init-output.log
sudo crictl ps -a | head

