# move airgapped bundle to bastion
tar -zxvf nkp-air-gapped-bundle_v2.17.1_linux_amd64.tar.gz
mv cli/nkp /usr/bin/
mv kubectl /usr/bin/
nkp push bundle --bundle ./container-images/kommander-image-bundle-v2.17.1.tar,./container-images/konvoy-image-bundle-v2.17.1.tar --to-internal-registry-mirror
nkp upgrade kommander --kommander-applications-repository ./application-repositories/kommander-applications-v2.17.1.tar.gz
export VM_IMAGE_NAME="nkp-ubuntu-24.04-release-cis-1.34.3-20260226170017.qcow2"
export MGMT_CLUSTER_NAME="rx2-nkp-mgt"
nkp upgrade cluster nutanix       --cluster-name ${MANAGEMENT_CLUSTER_NAME}       --vm-image ${VM_IMAGE_NAME}

