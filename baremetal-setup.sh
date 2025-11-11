# .20 for kubevip
# .21 for metallb
# preparing for the machine
# generate ssh pub key so that we can ssh to worker nodes
ssh-keygen 
# create X number of VMs on PC with following cloud init
# this will allow bastion to ssh into these VM
# without password
#cloud-config
preserve_hostname: false
fqdn: ubuntu-pro-node

users:
  - default

  - name: konvoy
    gecos: "Konvoy User"
    groups: [sudo]             # Ubuntu: sudo group, not wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDG7+w3foxaDg9fLRQX2RIxZeHvmI/tbAy1owDYvDP3H9n0eS8oOd30MG2/zRCcx4HOz0bsA21f+Kl2FbyWW8R05iZEdYcG4vpzebHtBNIQVsrL4j5w04GoNJYB1yJgbsDma6bqxdruC6oKerFWjjqpqzlPuZSHtrVdvmlLHxoPpzfErO5j+4G2vRztk2iFMFOpNeDWvUvfjii9xFbY4OV1YC6Wck9BFI5gBOgIZCj5OpUjYRR3bSYpaSDvm9ZTkORTEZCIM1+ZlWi57xqwvNP7/9Zk1yP+xzA+5MkDFnECJ9C5a2f9HwPipGG1RB/8+LwojLXDf+bGt+n8VXswJcqav7feXA/UqS8gr3XA0qrfjKsJOWMRdHnzJVeHf+J2kv3zZB7Tjtty1wpj7Tf9xzmbaEpnxoSfDuj4LB+rWVm+5edxz0h2SWlwwp+f4pv/uiC3Svmc5dihuT5jS2zAv7LP7Hj6QEL8t78I4XDeFRyYQ7p9OSgHYpWQ5NQD8t485mU= nutanix@nutanix

ssh_pwauth: false   # disable password SSH login; key-only

runcmd:
  # On Ubuntu the service name is usually "ssh", but this is mostly redundant
  - systemctl enable --now ssh

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
cd ~

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
cd ~

# in internet connect laptop, run the following command
cd nkp-v2.16.0/kib
./konvoy-image create-package-bundle -os ubuntu-22.04

#Replace with the IP Addresses of your Control Plane VMs
export CONTROL_PLANE_1_ADDRESS="xxx.yyy.zzz.51"
export CONTROL_PLANE_2_ADDRESS="xxx.yyy.zzz.52"
export CONTROL_PLANE_3_ADDRESS="xxx.yyy.zzz.53"

#Replace with the IP Addresses of your Non-DGX Worker Node Pool VMs
export WORKER_1_ADDRESS="xxx.yyy.zzz.54"
export WORKER_2_ADDRESS="xxx.yyy.zzz.55"
export WORKER_3_ADDRESS="xxx.yyy.zzz.56"
export WORKER_4_ADDRESS="xxx.yyy.zzz.57"

#Replace konvoy with the username you created on the Virtual Machines
export SSH_USER="konvoy"

#Replace with the path of your actual private key associated with the public key you used for the authorized keys.
export SSH_PRIVATE_KEY_FILE="/home/nutanix/.ssh/id_rsa"

#Replace 1.31.4_ubuntu_22.04_x86_64.tar.gz with the name of the package bundle you downloaded within the /nkp-version/kib/artifacts directory earlier
export OS_PACKAGES_BUNDLE=1.31.4_ubuntu_22.04_x86_64.tar.gz

#Replace containerd-1.7.22-d2iq.1-ubuntu-22.04-x86_64.tar.gz with the name of the respective containerd bundle and OS type within the /nkp-version/kib/artifacts directory. 
export CONTAINERD_BUNDLE=containerd-1.7.24-d2iq.1-ubuntu-22.04-x86_64.tar.gz

#Ensure that you’re in the /nkp-'version'/kib/ directory
#replace 'version' with the actual version of NKP
cd ~/nkp-'version'/kib/

# Prepare an Inventory of VMs to push the bundles to.
cat <<EOF > inventory.yaml
all:
  vars:
    ansible_user: $SSH_USER
    ansible_port: 22
    ansible_ssh_private_key_file: $SSH_PRIVATE_KEY_FILE
  hosts:
    $CONTROL_PLANE_1_ADDRESS:
      ansible_host: $CONTROL_PLANE_1_ADDRESS
    $CONTROL_PLANE_2_ADDRESS:
      ansible_host: $CONTROL_PLANE_2_ADDRESS
    $CONTROL_PLANE_3_ADDRESS:
      ansible_host: $CONTROL_PLANE_3_ADDRESS
    $WORKER_1_ADDRESS:
      ansible_host: $WORKER_1_ADDRESS
    $WORKER_2_ADDRESS:
      ansible_host: $WORKER_2_ADDRESS
    $WORKER_3_ADDRESS:
      ansible_host: $WORKER_3_ADDRESS
    $WORKER_4_ADDRESS:
      ansible_host: $WORKER_4_ADDRESS
EOF

# push images to the vm
# ensure the inventory.yaml are located on ./konvoy-image
./konvoy-image upload artifacts \
              --container-images-dir=./artifacts/images/ \
              --os-packages-bundle=./artifacts/$OS_PACKAGES_BUNDLE \
              --containerd-bundle=artifacts/$CONTAINERD_BUNDLE \
              --pip-packages-bundle=./artifacts/pip-packages.tar.gz


#Ensure that you’re in the /nkp-'version' directory
#replace 'version' with the actual version of NKP
cd ~/nkp/nkp-v2.16.0/
docker load -i konvoy-bootstrap-image-v2.16.0.tar
cd ~/nkp-'version'
nkp create bootstrap

vi .env
#Ensure that we’re using a registry FQDN, with the suffix to the repository that we’re going to be mirroring the images to.
export REGISTRY_URL=https://registry.ntnxlab.local/mirror
#Replace the Username with your actual username
export REGISTRY_USERNAME=admin
#Replace the Password with your actual password
export REGISTRY_PASSWORD=Harbor12345
#Path to the CA Cert of the Registry, if it is an Internal CA.
export REGISTRY_CA=/home/nutanix/certs/nsk-ca-chain.crt

#Set NKP Cluster Name
export CLUSTER_NAME=baremetal

#Set NKP KubeAPI Server VIP
#Replace with the desired IP Address for the KubeAPI Server. Make sure it’s on the same subnet as your Virtual Machines.
export CLUSTER_VIP="10.129.42.20"

#Set VM Ethernet Interface Name
#Replace with the actual interface name in the control plane VMs. find it by using `ip address` and looking for the interface with the VM’s IP Address
export CLUSTER_VIP_ETH_INTERFACE="ens3"

#Set Control Plane VMs information
#Replace with the IP Addresses of your Control Plane VMs
export CONTROL_PLANE_1_ADDRESS="10.129.42.59"

#Set Worker Node VMs Information
#Replace with the IP Addresses of your Non-DGX Worker Node Pool VMs
export WORKER_1_ADDRESS="10.129.42.152"
export WORKER_2_ADDRESS="10.129.42.129"

#Set SSH Information to Virtual Machines
#Replace konvoy with the username you created on the Virtual Machines
export SSH_USER="konvoy"

#Set SSH Private Key File to Virtual Machines
#Replace with the path of your actual private key associated with the public key you used for the authorized keys.
export SSH_PRIVATE_KEY_FILE="/home/nutanix/.ssh/id_rsa"

#Dont change this line
export SSH_PRIVATE_KEY_SECRET_NAME=${CLUSTER_NAME}-ssh-key

# CREATE LIST OF VM INVENTORY FOR NKP TO INSTALL NKP ON

cat <<EOF > preprovisioned_inventory.yaml
---
apiVersion: infrastructure.cluster.konvoy.d2iq.io/v1alpha1
kind: PreprovisionedInventory
metadata:
  name: $CLUSTER_NAME-control-plane
  #ensure namespace is correct if we are attaching to a workspace
  namespace: default
  labels:
    cluster.x-k8s.io/cluster-name: $CLUSTER_NAME
    clusterctl.cluster.x-k8s.io/move: ""
spec:
  hosts:
    # Create as many of these as needed to match your infrastructure
    # Note that the command line parameter --control-plane-replicas determines how many control plane nodes will actually be used.
    #
    - address: $CONTROL_PLANE_1_ADDRESS
 #   - address: $CONTROL_PLANE_2_ADDRESS
 #   - address: $CONTROL_PLANE_3_ADDRESS
  sshConfig:
    port: 22
    # This is the username used to connect to your infrastructure. This user must be root or
    # have the ability to use sudo without a password
    user: $SSH_USER
    privateKeyRef:
      # This is the name of the secret you created in the previous step. It must exist in the same
      # namespace as this inventory object.
      name: $SSH_PRIVATE_KEY_SECRET_NAME
      #ensure namespace is correct if we are attaching to a workspace
      namespace: default
---
apiVersion: infrastructure.cluster.konvoy.d2iq.io/v1alpha1
kind: PreprovisionedInventory
metadata:
  name: $CLUSTER_NAME-md-0
  #ensure namespace is correct if we are attaching to a workspace
  namespace: default
  labels:
    cluster.x-k8s.io/cluster-name: $CLUSTER_NAME
    clusterctl.cluster.x-k8s.io/move: ""
spec:
  hosts:
    - address: $WORKER_1_ADDRESS
    - address: $WORKER_2_ADDRESS
#    - address: $WORKER_3_ADDRESS
#    - address: $WORKER_4_ADDRESS
  sshConfig:
    port: 22
    user: $SSH_USER
    privateKeyRef:
      name: $SSH_PRIVATE_KEY_SECRET_NAME
      #ensure namespace is correct if we are attaching to a workspace
      namespace: default
EOF


#Create Secrets for the SSH Private Key for the Bootstrapper to authenticate
kubectl create secret generic ${SSH_PRIVATE_KEY_SECRET_NAME} --from-file=ssh-privatekey="$SSH_PRIVATE_KEY_FILE"
kubectl label secret ${SSH_PRIVATE_KEY_SECRET_NAME} clusterctl.cluster.x-k8s.io/move=""

# ssh to all the master and worker nodes
sudo ls /opt/dkp/packages/offline-repo/Packages || sudo bash -c 'gunzip -c /opt/dkp/packages/offline-repo/Packages.gz > /opt/dkp/packages/offline-repo/Packages'

nkp create cluster preprovisioned \
  --cluster-name ${CLUSTER_NAME} \
  --control-plane-endpoint-host ${CLUSTER_VIP} \
  --virtual-ip-interface ${CLUSTER_VIP_ETH_INTERFACE} \
  --pre-provisioned-inventory-file=/home/nutanix/nkp/nkp-v2.16.0/preprovisioned_inventory.yaml \
  --ssh-private-key-file=${SSH_PRIVATE_KEY_FILE} \
  --registry-mirror-url=${REGISTRY_URL} \
  --registry-mirror-username=${REGISTRY_USERNAME} \
  --registry-mirror-password=${REGISTRY_PASSWORD} \
  --registry-mirror-cacert=${REGISTRY_CA} \
  --worker-replicas=2 \
  --control-plane-replicas=1 \
  --dry-run \
  --output=yaml \
  > ${CLUSTER_NAME}.yaml

# Apply the Cluster Manifest to create the cluster
kubectl create -f ${CLUSTER_NAME}.yaml

nkp describe cluster -c ${CLUSTER_NAME}


#Control Flow command to wait for Control Planes to come up
kubectl wait --for=condition=ControlPlaneReady "clusters/${CLUSTER_NAME}" --timeout=20m

#Get kubeconfig of the created cluster
nkp get kubeconfig -c ${CLUSTER_NAME} > ~/${CLUSTER_NAME}.conf

#Control Flow command to check that all nodes, including worker nodes are online.
kubectl --kubeconfig ~/${CLUSTER_NAME}.conf wait --for=condition=Ready nodes --all --timeout=30m

# install external-snapshotter from
# https://github.com/kubernetes-csi/external-snapshotter
tar zxvf v8.x.x.tar.gz

#Install the snapshot-controller CRDs and Controller 
#CRDs
kubectl --kubeconfig ~/${CLUSTER_NAME}.conf kustomize external-snapshotter-8.x.x/client/config/crd | kubectl --kubeconfig ~/${CLUSTER_NAME}.conf apply -f -

#Snapshot Controller
kubectl --kubeconfig ~/${CLUSTER_NAME}.conf kustomize external-snapshotter-8.x.x/deploy/kubernetes/snapshot-controller/ | kubectl --kubeconfig ~/${CLUSTER_NAME}.conf apply -f 

# install csi
# download csi from 
# https://github.com/nutanix/helm-releases/releases/download/nutanix-csi-storage-3.3.8/nutanix-csi-storage-3.3.8.tgz
tar -zxvf nutanix-csi-storage-3.3.8.tgz
helm --kubeconfig ${CLUSTER_NAME}.conf \
-n ntnx-system install nutanix-csi \
./nutanix-csi-storage \
--create-namespace \
--set kubernetesClusterDeploymentType=bare-metal \
--set createSecret=false \
--set prismCentralEndPoint="10.129.42.11" \
--set pcUsername="shukun" \
--set pcPassword="P@ssw0rd"


#Create a Nutanix Volumes CSI Storage Class
vi storage-storage.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
    name: nutanix-volume
    annotations:
      storageclass.kubernetes.io/is-default-class: "true"
parameters:
   prismElementRef: 000622c1-636a-e6fb-0000-000000027af9 #PrismElement uuid. SSH into PE and use "ncli cluster info" to get the uuid
   csi.storage.k8s.io/fstype: ext4
   storageContainer: SelfServiceContainer #Change this if you want to use another storage container
   storageType: NutanixVolumes
provisioner: csi.nutanix.com
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate

k --kubeconfig baremetal.conf  apply -f storage-class.yaml

# test if storageclass works
vi pvc-test.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-rwo-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nutanix-volume
  resources:
    requests:
      storage: 1Gi

k --kubeconfig baremetal.conf apply -f pvc-test.yaml

# Remove the localvolumeprovisioner as a default storage class
kubectl --kubeconfig ${CLUSTER_NAME}.conf patch storageclass localvolumeprovisioner -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'


# Create CAPI components on the NKP Cluster.
# if timeout occurred, check if the pvc are still bound to local provisioner
# delete the pvc and recreate the capi-components
nkp create capi-components --kubeconfig ${CLUSTER_NAME}.conf

# Move CAPI resources into actual cluster
nkp move capi-resources --to-kubeconfig ${CLUSTER_NAME}.conf

# verifying move is successfull
kubectl --kubeconfig=${CLUSTER_NAME}.conf get nodes
kubectl --kubeconfig=${CLUSTER_NAME}.conf get preprovisionedinventories
kubectl --kubeconfig=${CLUSTER_NAME}.conf get preprovisionedmachines
kubectl --kubeconfig=${CLUSTER_NAME}.conf get machines
kubectl --kubeconfig=${CLUSTER_NAME}.conf get clusters


# delete bootstrap cluster
nkp delete bootstrap