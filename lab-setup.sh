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
export CONTROL_PLANE_IP=10.129.42.29 # <-- ivan provide 10 kubevip
export LB_IP_RANGE=10.129.42.30-10.129.42.30 # <-- ivan provide 10 metallb
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://172.16.101.30:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=shukun.ng
export NUTANIX_PASSWORD=ntnx/4DEMO
export IMAGE_NAME=nkp-rocky-9.6-release-cis-1.33.2 # to update
export PRISM_ELEMENT_CLUSTER_NAME=SGNTNXWLPE_AZ03
export SUBNET_NAME="Internal VLAN 108"
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

