# copy nkp binary to /use/bin
sudo cp cli/nkp /usr/bin/

# copy kubectl binary to /usr/bin
sudo cp kubectl /usr/bin/

vi .env
# VM Setting 
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=1
export CONTROL_PLANE_MEMORY_GIB=32
export WORKER_REPLICAS=4
export WORKER_VCPUS=16
export WORKER_CORES_PER_VCPU=1
export WORKER_MEMORY_GIB=32
export SSH_KEY_FILE=/root/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='nkp-target' # <-- the name you create on the VM
export CONTROL_PLANE_IP= 10.161.54.61 # <-- ivan provide 10 kubevip
export LB_IP_RANGE=10.161.54.62-10.161.54.65 # <-- ivan provide 10 metallb
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://10.161.16.218::9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=nx2Tech198!
export IMAGE_NAME=nkp-ubuntu-24.04-release-cis-1.34.1-20251206061851.qcow2 # to update
export PRISM_ELEMENT_CLUSTER_NAME=kestrel06-2
export SUBNET_NAME=nkp
export NUTANIX_STORAGE_CONTAINER_NAME=SelfServiceContainer

# Container Registry
# export REGISTRY_URL="https://registry.ntnxlab.local"  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_USERNAME=admin
# export REGISTRY_PASSWORD=Harbor12345
# export REGISTRY_CA=/home/nutanix/certs/nsk-ca-chain.crt

# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.17.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.17.0.tar"

# Mirror Registry
# export REGISTRY_MIRROR_URL=https://registry.ntnxlab.local/external/  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_MIRROR_USERNAME=admin
# export REGISTRY_MIRROR_PASSWORD=Harbor12345
# export REGISTRY_MIRROR_CA=/home/nutanix/certs/nsk-ca-chain.crt

# Ingress
export CLUSTER_HOSTNAME="nkp-target.ntnxlab.local"
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