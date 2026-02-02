# Install RHEL 8.10, ideally minimal install but add on tooling like vim for 
# e.g. also make sure it's not massively sized, ideally less than 20GB else we need to use 
# flags to override.
# ensure swapoff, ensure cloud init is installed. make sure to generalize hostkeys and all.
# shutdown VM
# in prism central -> images -> add image -> VM Disk -> Select the VM which was just created. OS Disk
nkp create image nutanix \
rhel-8.10 \
--cluster <Prism_Element_cluster_name> \
--endpoint <Prism_Central_endpoint_URL> \
--subnet <subnet_name_or_UUID_associated_with_Prism_Element> \
--source-image <base_image_name_or_UUID_or_URL> \
PKR_VAR_disk_size_gb=<size of vm> # if vm disk is more then 20Gib

# example
export NUTANIX_ENDPOINT=https://10.21.102.154
export NUTANIX_CLUSTER=kestrel01-2
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=nx2Tech094!
export SUBNET=NKP_Network
export BASE_IMAGE="nkp-2.17-jumphost-noble-server-cloudimg-amd64.img"
export OS=ubuntu-24.04
export ARTIFACTS_DIRECTORY_FLAG="--artifacts-directory=/home/ubuntu/nkp-v2.17.0/image-artifacts"
export BUNDLE_FLAG="bundle /home/ubuntu/nkp-v2.17.0/container-images/konvoy-image-bundle-v2.17.0.tar"


PKR_VAR_disk_size_gb=120 nkp create image nutanix $OS \
    --endpoint "${NUTANIX_ENDPOINT}" \
    --cluster "${NUTANIX_CLUSTER}" \
    --subnet "${SUBNET}" \
    --source-image "${BASE_IMAGE}" \
    "${ARTIFACTS_DIRECTORY_FLAG:-""}" \
    --${BUNDLE_FLAG:-""} \
    --insecure \
    -v6