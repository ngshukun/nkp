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
export CLUSTER_NAME='sk-upgrade' # <-- the name you create on the VM
export CONTROL_PLANE_IP= 172.16.108.10/20/30/40/50/60/70/80/90/110 # <-- ivan provide 10 kubevip
export LB_IP_RANGE=10.129.42.30-10.129.42.30 # <-- ivan provide 10 metallb
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://172.16.101.30:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=shukun.ng
export NUTANIX_PASSWORD=ntnx/4DEMO
export IMAGE_NAME=nkp-rocky-9.6-release-cis-1.33.2 # to update
export PRISM_ELEMENT_CLUSTER_NAME=SGNTNXWLPE_AZ03
export SUBNET_NAME="VLAN108"
export NUTANIX_STORAGE_CONTAINER_NAME=SelfServiceContainer

# Container Registry
# export REGISTRY_URL="https://registry.ntnxlab.local"  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_USERNAME=admin
# export REGISTRY_PASSWORD=Harbor12345
# export REGISTRY_CA=/home/nutanix/certs/nsk-ca-chain.crt

# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.16.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.16.0.tar"

# Mirror Registry
# export REGISTRY_MIRROR_URL=https://registry.ntnxlab.local/external/  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_MIRROR_USERNAME=admin
# export REGISTRY_MIRROR_PASSWORD=Harbor12345
# export REGISTRY_MIRROR_CA=/home/nutanix/certs/nsk-ca-chain.crt

# Ingress
# export CLUSTER_HOSTNAME="nkp-upgrade.ntnxlab.local"
# export INGRESS_CERT=/home/nutanix/certs/nkp-upgrade.server.crt
# export INGRESS_KEY=/home/nutanix/certs/nkp-upgrade.server.key
# export INGRESS_CA=/home/nutanix/certs/nsk-ca-chain.crt

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