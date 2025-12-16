# vi .env
# input OS_PACKAGES_BUNDLE under .env
export OS_PACKAGES_BUNDLE=1.33.5_ubuntu_22.04_x86_64.tar.gz
# input containerd under .env
export CONTAINERD_BUNDLE=containerd-1.7.27-d2iq.1-ubuntu-22.04-x86_64.tar.gz
#Ensure that we’re using a registry FQDN, with the suffix to the repository that we’re going to be mirroring the images to.
export REGISTRY_URL=https://registry.ntnxlab.local/mirror
#Replace the Username with your actual username
export REGISTRY_USERNAME=shukun
#Replace the Password with your actual password
export REGISTRY_PASSWORD=Harbor12345
#Path to the CA Cert of the Registry, if it is an Internal CA.
export REGISTRY_CA=/home/nutanix/certs/ca-chain.crt

#Set NKP Cluster Name
export CLUSTER_NAME=workload-dev

#Set NKP KubeAPI Server VIP
#Replace with the desired IP Address for the KubeAPI Server. Make sure it’s on the same subnet as your Virtual Machines.
export CLUSTER_VIP="10.129.42.27"

#Set VM Ethernet Interface Name
#Replace with the actual interface name in the control plane VMs. find it by using `ip address` and looking for the interface with the VM’s IP Address
export CLUSTER_VIP_ETH_INTERFACE="ens3"

#Set Control Plane VMs information
#Replace with the IP Addresses of your Control Plane VMs
export CONTROL_PLANE_1_ADDRESS="10.129.42.151"
export CONTROL_PLANE_2_ADDRESS="10.129.42.126"
export CONTROL_PLANE_3_ADDRESS="10.129.42.120"

#Set Worker Node VMs Information
#Replace with the IP Addresses of your Non-DGX Worker Node Pool VMs
export WORKER_1_ADDRESS="10.129.42.121"
export WORKER_2_ADDRESS="10.129.42.91"
export WORKER_3_ADDRESS="10.129.42.142"
export WORKER_4_ADDRESS="10.129.42.46"

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
    - address: $CONTROL_PLANE_2_ADDRESS
    - address: $CONTROL_PLANE_3_ADDRESS
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
    - address: $WORKER_3_ADDRESS
    - address: $WORKER_4_ADDRESS
  sshConfig:
    port: 22
    user: $SSH_USER
    privateKeyRef:
      name: $SSH_PRIVATE_KEY_SECRET_NAME
      #ensure namespace is correct if we are attaching to a workspace
      namespace: default
EOF

