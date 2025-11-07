tar -zxvf nkp.tar.gz
cd nkp
tar -zxvf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/bin/
tar -zxvf offline-docker-el9.tar.gz
cd docker-offline/
sudo dnf install -y *.rpm
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
# enter 3 times to generate ssh key
vi .env
# VM Setting
export CONTROL_PLANE_REPLICAS=1
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=1
export CONTROL_PLANE_MEMORY_GIB=32
export WORKER_REPLICAS=2
export WORKER_VCPUS=16
export WORKER_CORES_PER_VCPU=1
export WORKER_MEMORY_GIB=32
export SSH_KEY_FILE=/home/nutanix/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='lab01' # <-- the name you create on the VM
export CONTROL_PLANE_IP=10.129.42.22 # <-- your kubeVip
export LB_IP_RANGE=10.129.42.23-10.129.42.23 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://10.129.42.11:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=shukun
export NUTANIX_PASSWORD=P@ssw0rd
export IMAGE_NAME=nkp-rocky-9.6-release-cis-1.33.2-20250811224530
export PRISM_ELEMENT_CLUSTER_NAME=NKP
export SUBNET_NAME=Machine_Network_42
export NUTANIX_STORAGE_CONTAINER_NAME=SelfServiceContainer

# Container Registry
#export REGISTRY_URL="https://registry.ntnxlab.local"  #<-- make sure fqdn can resolved by your dns, if not use IP
#export REGISTRY_USERNAME=admin
#export REGISTRY_PASSWORD=Harbor12345
#export REGISTRY_CA=/home/nutanix/certs/nsk-ca-chain.crt

# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.16.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.16.0.tar"

# Mirror Registry
#export REGISTRY_MIRROR_URL=https://registry.ntnxlab.local/external/  #<-- make sure fqdn can resolved by your dns, if not use IP
#export REGISTRY_MIRROR_USERNAME=admin
#export REGISTRY_MIRROR_PASSWORD=Harbor12345
#export REGISTRY_MIRROR_CA=/home/nutanix/certs/nsk-ca-chain.crt

# Ingress
#export CLUSTER_HOSTNAME="nkp-upgrade.ntnxlab.local"
#export INGRESS_CERT=/home/nutanix/certs/nkp-upgrade.server.crt
#export INGRESS_KEY=/home/nutanix/certs/nkp-upgrade.server.key
#export INGRESS_CA=/home/nutanix/certs/nsk-ca-chain.crt


# installation of nkp
docker load -i konvoy-bootstrap-image-v2.16.0.tar && docker load -i nkp-image-builder-image-v2.16.0.tar


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
    --bundle=${KONVOY_IMAGE_BUNDLE},${KOMMANDER_IMAGE_BUNDLE} \
    --airgapped \
    --insecure \
    --timeout 120m



k9s
