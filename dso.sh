# resource required dso folder
# bash-completion-pkg.tar
# helm-v3.19.0-linux-64.tar
# k9s
# velero
# ubuntu-server-cloudimg-amd64
# ubuntu-24.04-server-cloudimg-amd64
# nkp-air-gapped-bundle_v2.16.1_linux_amd64.tar

# create VM
# cloud init 
#cloud-config
preserve_hostname: false
fqdn: jumphost

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

# prep the following in ~/.bashrc
sudo -i 
vi ~/.bashrc
alias k='kubectl'
source ~/.bashrc

# install docker
tar -zxvf docker-offline-bundle.tar.gz
tar -xvf docker.tgz
cp /home/nutanix/docker/* /usr/bin/
vi /etc/systemd/system/docker.service
# input the following 
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target

# Reload systemd
sudo systemctl daemon-reload

# Start the service
sudo systemctl start docker

# Ensure it starts automatically on reboot
sudo systemctl enable docker
docker ps

# Extract and move binaries
tar -zxf nkp-air-gapped-bundle_v2.16.1_linux_amd64.tar.gz
cd /home/nutanix/nkp-v2.16.1/
sudo cp cli/nkp /usr/bin/
sudo cp kubectl /usr/bin/

# Install autocomplete packages
cd /home/nutanix/
tar -xvf bash-completion-pkg.tar
sudo dpkg -i ./bash-completion-pkg/*.deb

# Generate kubectl completion file
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null

# UNCOMMENT the bash-completion block in .bashrc 
# This finds the commented lines and removes the '#'
sed -i '/#if \[ -f \/etc\/bash_completion \]/s/^#//' ~/.bashrc
sed -i '/#! shopt -oq posix; then/s/^#//' ~/.bashrc
sed -i '/#. \/etc\/bash_completion/s/^#//' ~/.bashrc
sed -i '/#fi/s/^#//' ~/.bashrc

# Add 'k' alias and alias-completion to .bashrc (if not already there)
if ! grep -q "alias k='kubectl'" ~/.bashrc; then
    echo "alias k='kubectl'" >> ~/.bashrc
    echo 'complete -F __start_kubectl k' >> ~/.bashrc
fi

# Optional: Add NKP completion as well
nkp completion bash | sudo tee /etc/bash_completion.d/nkp > /dev/null

# Final Step: Source the changes for the current session
source ~/.bashrc

# create ssh key
ssh-keygen -t rsa

# install k9s
sudo tar -zxvf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/bin/

# go back to /home/nutanix/nkp-v2.16.1 path 

# for reference only
# kubevip range 10.161.83.140-10.161.83.149
# metallb range 10.161.83.150 - 10.161.83.160
# generate self-sign cert
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
SERVER_CN="dso-mgt.ntnxlab.local"  # < -- change  # CN not used for matching, but keep it tidy
SERVER_HOST1="dso-mgt.ntnxlab.local" # < -- change 
SERVER_IP1="10.161.83.150"   # < -- change 
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.161.83.140"


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
openssl genrsa -out dso-mgt.ntnxlab.local-server.key 2048 # < -- change 

# CSR
openssl req -new -sha256 \
  -key dso-mgt.ntnxlab.local-server.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out dso-mgt.ntnxlab.local-server.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > dso-mgt.ntnxlab.local-v3_server.ext <<EOF
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
  -in dso-mgt.ntnxlab.local-server.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile dso-mgt.ntnxlab.local-v3_server.ext -extensions v3_server \
  -out dso-mgt.ntnxlab.local-server.crt

# Full chains for deployment
# - server-fullchain: server + ICA (what most servers present)
# cat server.crt ica.crt > server-fullchain.crt


# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt dso-mgt.ntnxlab.local-server.crt

cd /home/nutanix/nkp-v2.16.1/

docker load -i konvoy-bootstrap-image-v2.16.1.tar && docker load -i nkp-image-builder-image-v2.16.1.tar

# put registry cert to docker path /etc/docker/certs.d/registry.ntnxlab.local
# perform restart on your docker
# sudo systemctl restart docker
# sudo systemctl status docker
# docker login registry.ntnxlab.local

#sudo nkp push bundle --bundle ./container-images/kommander-image-bundle-v2.17.0.tar \
#--to-registry registry.ntnxlab.local/mirror \
#--to-registry-username shukun \
#--to-registry-password Harbor12345 \
#--to-registry-ca-cert-file /home/nutanix/htx120126/cert/ca-chain.crt  # ensure to set your ca cert to 755

#sudo nkp push bundle --bundle ./container-images/konvoy-image-bundle-v2.17.0.tar \
#--to-registry registry.ntnxlab.local/mirror \
#--to-registry-username shukun \
#--to-registry-password Harbor12345 \
#--to-registry-ca-cert-file /home/nutanix/htx120126/cert/ca-chain.crt # ensure to set your ca cert to 755



# dso-mgt 
# VM Setting
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=1
export CONTROL_PLANE_MEMORY_GIB=16
export WORKER_REPLICAS=4
export WORKER_VCPUS=8
export WORKER_CORES_PER_VCPU=1
export WORKER_MEMORY_GIB=8
export SSH_KEY_FILE=/root/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='dso-mgt' # <-- the name you create on the VM
export CONTROL_PLANE_IP=10.161.83.140 # <-- your kubeVip
export LB_IP_RANGE=10.161.83.150-10.161.83.154 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://10.161.20.138:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=admin
export NUTANIX_PASSWORD='nx2Tech864!'
export IMAGE_NAME=nkp-ubuntu-22.04-release-cis-1.33.5-20260504054007.qcow2
export PRISM_ELEMENT_CLUSTER_NAME=kestrel21-1
export SUBNET_NAME=VLAN293
export NUTANIX_STORAGE_CONTAINER_NAME=SelfServiceContainer

# Container Registry
# export REGISTRY_URL="https://registry.ntnxlab.local"  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_USERNAME=shukun
# export REGISTRY_PASSWORD=Harbor12345
# export REGISTRY_CA=/home/nutanix/certs/ca-chain.crt

# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="/home/nutanix/nkp-v2.16.1/container-images/konvoy-image-bundle-v2.16.1.tar"
export KOMMANDER_IMAGE_BUNDLE="/home/nutanix/nkp-v2.16.1/container-images/kommander-image-bundle-v2.16.1.tar"

# Mirror Registry
# export REGISTRY_MIRROR_URL=https://registry.ntnxlab.local/mirror/  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_MIRROR_USERNAME=admin
# export REGISTRY_MIRROR_PASSWORD=Harbor12345
# export REGISTRY_MIRROR_CA=/home/nutanix/certs/ca-chain.crt

# Ingress
export CLUSTER_HOSTNAME="dso-mgt.ntnxlab.local"
export INGRESS_CERT=/home/nutanix/nkp-v2.16.1/certs/dso-mgt.ntnxlab.local-server.crt
export INGRESS_KEY=/home/nutanix/nkp-v2.16.1/certs/dso-mgt.ntnxlab.local-server.key
export INGRESS_CA=/home/nutanix/nkp-v2.16.1/certs/ca-chain.crt

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


# License Key AEAAG-AAA65-W7DP4-VMH59-8AN23-NEWA4-ABF8P
---------------------------------------------------------------------------------------------------------------------------------------
# dso-wl cluster 
nkp create workspace dev-wl
cd /home/nutanix/nkp-v2.16.1/certs

COUNTRY="SG"
ORG="nutanix"
ROOT_CN="nutanix"
ICA_CN="nutanix"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="dso-wl.ntnxlab.local"  # < -- change  # CN not used for matching, but keep it tidy
SERVER_HOST1="dso-wl.ntnxlab.local" # < -- change 
SERVER_IP1="10.161.83.155"   # < -- change 
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.161.83.140"
# dso-workload cluster
openssl genrsa -out dso-wl.ntnxlab.local-server.key 2048 # < -- change 

# CSR
openssl req -new -sha256 \
  -key dso-wl.ntnxlab.local-server.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out dso-wl.ntnxlab.local-server.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > dso-wl.ntnxlab.local-v3_server.ext <<EOF
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
  -in dso-wl.ntnxlab.local-server.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile dso-wl.ntnxlab.local-v3_server.ext -extensions v3_server \
  -out dso-wl.ntnxlab.local-server.crt

# Full chains for deployment
# - server-fullchain: server + ICA (what most servers present)
# cat server.crt ica.crt > server-fullchain.crt


# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt dso-wl.ntnxlab.local-server.crt


# VM Setting
export CONTROL_PLANE_REPLICAS=1
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=1
export CONTROL_PLANE_MEMORY_GIB=8
export WORKER_REPLICAS=2
export WORKER_VCPUS=8
export WORKER_CORES_PER_VCPU=1
export WORKER_MEMORY_GIB=8
export SSH_KEY_FILE=/root/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='dso-wl' # <-- the name you create on the VM
export CONTROL_PLANE_IP=10.161.83.141 # <-- your kubeVip
export LB_IP_RANGE=10.161.83.155-10.161.83.159 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://10.161.20.138:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=admin
export NUTANIX_PASSWORD='nx2Tech864!'
export IMAGE_NAME=nkp-ubuntu-22.04-release-cis-1.33.5-20260504054007.qcow2
export PRISM_ELEMENT_CLUSTER_NAME=kestrel21-1
export SUBNET_NAME=VLAN293
export NUTANIX_STORAGE_CONTAINER_NAME=SelfServiceContainer

# Container Registry
# export REGISTRY_URL="https://registry.ntnxlab.local"  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_USERNAME=shukun
# export REGISTRY_PASSWORD=Harbor12345
# export REGISTRY_CA=/home/nutanix/certs/ca-chain.crt

# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="/home/nutanix/nkp-v2.16.1/container-images/konvoy-image-bundle-v2.16.1.tar"
export KOMMANDER_IMAGE_BUNDLE="/home/nutanix/nkp-v2.16.1/container-images/kommander-image-bundle-v2.16.1.tar"

# Mirror Registry
# export REGISTRY_MIRROR_URL=https://registry.ntnxlab.local/mirror/  #<-- make sure fqdn can resolved by your dns, if not use IP
# export REGISTRY_MIRROR_USERNAME=admin
#export REGISTRY_MIRROR_PASSWORD=Harbor12345
#export REGISTRY_MIRROR_CA=/home/nutanix/certs/ca-chain.crt

# Ingress
export CLUSTER_HOSTNAME="dso-wl.ntnxlab.local"
export INGRESS_CERT=/home/nutanix/nkp-v2.16.1/certs/dso-wl.ntnxlab.local-server.crt
export INGRESS_KEY=/home/nutanix/nkp-v2.16.1/certs/dso-wl.ntnxlab.local-server.key
export INGRESS_CA=/home/nutanix/nkp-v2.16.1/certs/ca-chain.crt

# Workspace
export WORKSPACE_NAMESPACE=dev-wl-gpjcr-qrhm5

cd /home/nutanix/nkp-v2.16.1/

nkp create cluster nutanix --cluster-name $CLUSTER_NAME \
    --namespace $WORKSPACE_NAMESPACE \
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
    --cluster-hostname ${CLUSTER_HOSTNAME} \
    --ingress-ca ${INGRESS_CA} \
    --ingress-certificate ${INGRESS_CERT} \
    --ingress-private-key ${INGRESS_KEY} \
    --bundle=${KONVOY_IMAGE_BUNDLE},${KOMMANDER_IMAGE_BUNDLE} \
    --airgapped \
    --insecure \
    --timeout 200m

# download kubeconfig from GUI


# install helm
cd /home/nutanix/
tar -zxvf helm-v3.19.0-linux-amd64.tar.gz
cp linux-amd64/helm /usr/bin/

docker load -i kasten-images-8.5.8.tar
docker push your-internal-registry.local/kasten/...

helm install k10 ./k10-8.5.8.tgz --namespace kasten-io \
  --create-namespace \
  --set global.airgapped.repository=your-internal-registry.local/kasten

---------------------------------------------------------------------------------------------------------------------------------------


# update ipaddresspoll and l2advertisement for addition worker nodes
k config use-context prd-nkp-cts-admin@prd-nkp-cts
# metallb and l2advertisement
vi metallb-additional-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: prd-nkp-cts-lb
  namespace: metallb-system
spec:
  addresses:
  - 172.138.0.151-172.138.0.200
  # autoAssign: true # Default is true. Set to false if you only want specific Services to request this pool by annotation.
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: prd-nkp-cts-lb-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - prd-nkp-cts-lb

# verify namespace
kubectl get pods -A | grep metallb
# Output should show pods in 'metallb-system' or similar. Update the YAML namespace if different.
kubectl apply -f metallb-additional-pool.yaml
# verification
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system


root@ubuntu:/home/ubuntu/htx120126/nkp-v2.17.0# k get ipaddresspool -n metallb-system -oyaml
apiVersion: v1
items:
- apiVersion: metallb.io/v1beta1
  kind: IPAddressPool
  metadata:
    creationTimestamp: "2026-01-14T09:42:44Z"
    generation: 1
    name: metallb
    namespace: metallb-system
    resourceVersion: "25885"
    uid: 7c6c34a6-7f6f-48a8-93c2-3d63cc5670d5
  spec:
    addresses:
    - 172.138.0.96-172.138.0.100
    autoAssign: true
    avoidBuggyIPs: false
  status:
    assignedIPv4: 1
    assignedIPv6: 0
    availableIPv4: 4
    availableIPv6: 0
kind: List
metadata:
  resourceVersion: ""


root@ubuntu:/home/ubuntu/htx120126/nkp-v2.17.0# k get l2advertisement -n metallb-system -oyaml
apiVersion: v1
items:
- apiVersion: metallb.io/v1beta1
  kind: L2Advertisement
  metadata:
    creationTimestamp: "2026-01-14T09:42:44Z"
    generation: 1
    name: metallb
    namespace: metallb-system
    resourceVersion: "2579"
    uid: aea0bce0-c011-4894-af55-b9a236fbc2d7
  spec:
    ipAddressPools:
    - metallb
kind: List
metadata:
  resourceVersion: ""
root@ubuntu:/home/ubuntu/htx120126/nkp-v2.17.0#


# Taint the Default 4 Nodes
kubectl taint nodes <node-name-1> <node-name-2> <node-name-3> <node-name-4> dedicated=infra:NoSchedule
# In NKP GUI, add node pool and in label annotated label as followed:
# node_role=application



# example
export NUTANIX_ENDPOINT=https://ctsmgtv0001.ntnxlab.local
export NUTANIX_CLUSTER=kestrel21-1
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=Nutanix/4all!
export SUBNET=vlan_tnt_cts_c1_01
export BASE_IMAGE="nkp-rhel-9.6-500gb-v1.1-image"
export OS=rhel-9.6
export ARTIFACTS_DIRECTORY_FLAG="--artifacts-directory=/home/ubuntu/htx120126/nkp-v2.17.0/image-artifacts"
export BUNDLE_FLAG="bundle /home/ubuntu/htx120126/nkp-v2.17.0/*.tar"



p2admin

!Ra7XmM500tV!&

### ONLY FOR CIS LEVEL2 HARDENED IMAGES

#1 Create output directory to configure variables
mkdir build 
PKR_VAR_disk_size_gb=550 nkp create image nutanix $OS --endpoint "https://ctsmgtv0001.ntnxlab.local" --cluster "kestrel21-1"     --subnet  "vlan_tnt_cts_c1_01"     --source-image "nkp-rhel-9.6-500gb-v1.1-image"     --artifacts-directory "./image-artifacts"      --insecure     -v6 --debug --output-directory ./build --extra-build-name "-550gb-nogpu" --bundle ./container-images/konvoy-image-bundle-v2.17.0.tar

#2 in ./build/packer.pkr.hcl under the cloud-config line
#cloud-config
users:
  - name: ${var.ssh_username}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo, wheel
    lock_passwd: true
    ssh_authorized_keys:
      - ${local.ssh_public_key}
runcmd:
  - sudo mount -o remount,exec /tmp 
  #<- Add this but without this comment
  - sudo mount -o remount,exec /var/tmp 
  #<- Add this but without this comment
  - sed -i 's/^UMASK.*/UMASK 022/' /etc/login.defs 
  #<- Add this but without this comment
  - mkdir -p /opt/container-images
  #<- Add this but without this comment
  - chmod 777 -R /opt 
  #<- rhel 9.6 doesnt have systemd-resolvd so we symlink. add without this comment
  - mkdir -p /run/systemd/resolve 
  #<- rhel 9.6 doesnt have systemd-resolvd so we symlink. add without this comment
  - ln -sf /etc/resolv.conf /run/systemd/resolve/resolv.conf 


#3a Edit the ./build/playbooks/roles/repo/templates/rpm-offline.repo
[offline]
name=D2IQ offline repo
gpgcheck=0
repo_gpgcheck=0 #<- Add this line, but without this comment
localpkg_gpgcheck=0 #<- Add this line, but without this comment. This is also optional
baseurl=file://{{ offline.os_packages_remote_filesystem_repo_path }}

#3b Edit the ./build/playbooks/group_vars/all/defaults.yaml and change the following: ## NOTE MAY NO NEED TO DO THIS
images_cache: /tmp/dkp/images
mindthegap_binary_location_on_remote: /tmp/mindthegap


#4 Run the actual build command after the above changes
PKR_VAR_disk_size_gb=550 nkp create image nutanix $OS \
 --endpoint "https://ctsmgtv0001.ntnxlab.local" \
 --cluster "kestrel21-1" \
 --subnet  "vlan_tnt_cts_c1_01" \
 --source-image "nkp-rhel-9.6-500gb-v1.1-image" \
 --artifacts-directory "./image-artifacts" \
 --insecure \
 -v6 --debug --from-directory ./build/ --extra-build-name "-550gb-nogpu" 

#5 The debug flag is set so that we can make changes to the umask from 022 back to 027 to maintain CIS hardening
# Once you see this line, go back into the VM and edit the /etc/login.defs to change umask 022 to 027
# ==> nutanix.nkp_image: Pausing after run of step 'StepProvision'. Press enter to continue.

##Changes made to kubeadmconfigtemplate in management cluster for CTS cluster
# default kubeadmconfigtemplate in the prd-nkp-cts-xxx namespace. under the nkp-nutanix-worker-v2.17.0 kubeadmconfigtemplate
#Add this in at the highlighted
#      - content: |
#          apiVersion: kubelet.config.k8s.io/v1beta1
#          kind: KubeletConfiguration
#          # 4.2.4 Ensure that the --read-only-port argument is set to 0
#          readOnlyPort: 0
#          # 4.2.5 Ensure that the --streaming-connection-idle-timeout argument is not set to 0
#          # Recommendation: Set to 5m instead of 4h as per CIS guidelines
#          streamingConnectionIdleTimeout: "5m"
#          # 4.2.8 Ensure that the event-qps argument is set to a level which ensures appropriate event capture
#          eventRecordQPS: 5
#          # 4.2.12 Updated with recommended strong cipher suites
#          tlsCipherSuites: [TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256, TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305, TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305, TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384]
#          # 4.2.13 Ensure that a limit is set on pod PIDs
#          podPidsLimit: 4096
#          resolvConf: /etc/resolv.conf #<--- Add this line in

# This will trigger the clusterclass to reconcile the infra worker nodes and actual worker nodes to use this new flag

#Observations
# 1. RHEL 9.6 doesnt come with /run/systemd/resolve/resolv.conf as it relies on systemd-resolvd so we need to make the above change
# 2. CIS hardening might cause some tasks to fail, hence we need to do the above steps to get past the hardening
# 3. image upload can fail. to get past it we use the --debug flag so that once the VM has completed its prep steps, 
# we can SSH/console into the VM to do manual stuff like adding the images in
# mindthegap can be found in docker ps --> running container called konvoy-image-builder. 
# It's located in /usr/local/bin/mindthegap and you can cp it. to the directory you spawn into. it is mapped to the jumphost directory
# after the image is successfully built, we dont press enter to go ahead and stop and delete the VM yet. we need to console/ssh into the VM so that we can scp the container-images/konvoy-image-bundle-version as well as mindthegap into the "image". we then use ./mindthegap import image-bundle --image-bundle=konvoy-image-bundle-version.tar
# only after the above is done then we press "enter" for the image build process to complete.

# example on how to exec to the container
# docker exec -it e1670668476f /bin/bash
# ls -l 
# cp mindthegap ~    - that how you copy mindthegap out





##### KAISENSE a1 cluster setup
COUNTRY="SG"
ORG="nutanix"
ROOT_CN="nutanix"
ICA_CN="nutanix"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="prd-nkp-app-nks-a.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="prd-nkp-app-nks-a.ntnxlab.local"
SERVER_IP1="172.128.1.96"
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.129.42.94"

# This section is for generate of server cert, such as harbor, nkp, or workload cert
openssl genrsa -out prd-nkp-app-nks-a-server.key 2048

# CSR
openssl req -new -sha256 \
  -key prd-nkp-app-nks-a-server.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out prd-nkp-app-nks-a-server.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > prd-nkp-app-nks-a-v3_server.ext <<EOF
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
  -in prd-nkp-app-nks-a-server.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile prd-nkp-app-nks-a-v3_server.ext -extensions v3_server \
  -out prd-nkp-app-nks-a-server.crt

# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt prd-nkp-app-nks-a-server.crt

# VM Setting
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=2
export CONTROL_PLANE_MEMORY_GIB=64
export WORKER_REPLICAS=4
export WORKER_VCPUS=8
export WORKER_CORES_PER_VCPU=2
export WORKER_MEMORY_GIB=64
export SSH_KEY_FILE=/root/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='prd-nkp-app-nks-a' # <-- the name you create on the VM
export CONTROL_PLANE_IP=172.128.1.95 # <-- your kubeVip
export LB_IP_RANGE=172.128.1.96-172.128.1.100 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://ctsmgtv0001.ntnxlab.local:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=Nutanix/4all!
export IMAGE_NAME=nkp-ubuntu-22.04-release-cis-1.33.5-20260504054007.qcow2
export PRISM_ELEMENT_CLUSTER_NAME=ntxmgtv0001
export SUBNET_NAME=VLAN_KAISENSE_XAIP_A1
export NUTANIX_STORAGE_CONTAINER_NAME=SelfServiceContainer


# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.17.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.17.0.tar"

# Ingress
export CLUSTER_HOSTNAME="prd-nkp-app-a.ntnxlab.local"
export INGRESS_CERT=/home/nutanix/nkp-v2.16.1/certs/prd-nkp-app-nks-a-server.crt
export INGRESS_KEY=/home/nutanix/nkp-v2.16.1/certs/prd-nkp-app-nks-a-server.key
export INGRESS_CA=/home/nutanix/nkp-v2.16.1/certs/ca-chain.crt

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
    --cluster-hostname ${CLUSTER_HOSTNAME} \
    --ingress-ca ${INGRESS_CA} \
    --ingress-certificate ${INGRESS_CERT} \
    --ingress-private-key ${INGRESS_KEY} \
    --bundle=${KONVOY_IMAGE_BUNDLE},${KOMMANDER_IMAGE_BUNDLE} \
    --airgapped \
    --insecure \
    --timeout 120m







##### XAIP cluster setup
COUNTRY="SG"
ORG="nutanix"
ROOT_CN="nutanix"
ICA_CN="nutanix"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="prd-nkp-app-xaip-a.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="prd-nkp-app-xaip-a.ntnxlab.local"
SERVER_IP1="172.128.2.196"
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.129.42.94"

# This section is for generate of server cert, such as harbor, nkp, or workload cert
openssl genrsa -out prd-nkp-app-xaip-a-server.key 2048

# CSR
openssl req -new -sha256 \
  -key prd-nkp-app-xaip-a-server.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out prd-nkp-app-xaip-a-server.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > prd-nkp-app-xaip-a-v3_server.ext <<EOF
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
  -in prd-nkp-app-xaip-a-server.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile prd-nkp-app-xaip-a-v3_server.ext -extensions v3_server \
  -out prd-nkp-app-xaip-a-server.crt

# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt prd-nkp-app-xaip-a-server.crt


# VM Setting
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=2
export CONTROL_PLANE_MEMORY_GIB=64
export WORKER_REPLICAS=4
export WORKER_VCPUS=8
export WORKER_CORES_PER_VCPU=2
export WORKER_MEMORY_GIB=64
export SSH_KEY_FILE=/root/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='prd-nkp-app-xaip-a' # <-- the name you create on the VM
export CONTROL_PLANE_IP=172.128.2.195 # <-- your kubeVip
export LB_IP_RANGE=172.128.2.196-172.128.2.200 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://ctsmgtv0001.ntnxlab.local:9440
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=Nutanix/4all!
export IMAGE_NAME=nkp-ubuntu-22.04-release-cis-1.33.5-20260504054007.qcow2
export PRISM_ELEMENT_CLUSTER_NAME=ntxmgtv0002
export SUBNET_NAME=VLAN_KAISENSE_XAIP_A2
export NUTANIX_STORAGE_CONTAINER_NAME=SelfServiceContainer

# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.17.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.17.0.tar"

# Ingress
export CLUSTER_HOSTNAME="prd-nkp-app-a.ntnxlab.local"
export INGRESS_CERT=/home/nutanix/nkp-v2.16.1/certs/prd-nkp-app-xaip-a-server.crt
export INGRESS_KEY=/home/nutanix/nkp-v2.16.1/certs/prd-nkp-app-xaip-a-server.key
export INGRESS_CA=/home/nutanix/nkp-v2.16.1/certs/ca-chain.crt

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
    --cluster-hostname ${CLUSTER_HOSTNAME} \
    --ingress-ca ${INGRESS_CA} \
    --ingress-certificate ${INGRESS_CERT} \
    --ingress-private-key ${INGRESS_KEY} \
    --bundle=${KONVOY_IMAGE_BUNDLE},${KOMMANDER_IMAGE_BUNDLE} \
    --airgapped \
    --insecure \
    --timeout 120m





# cert for nkp infra
COUNTRY="SG"
ORG="nutanix"
ROOT_CN="nutanix"
ICA_CN="nutanix"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="dso-mgt.ntnxlab.local.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="dso-mgt.ntnxlab.local.ntnxlab.local"
SERVER_IP1="10.161.83.150"
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.129.42.94"

# This section is for generate of server cert, such as harbor, nkp, or workload cert
openssl genrsa -out dso-mgt.infra-server.key 2048

# CSR
openssl req -new -sha256 \
  -key dso-mgt.infra-server.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out dso-mgt.infra-server.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > dso-mgt.infra-v3_server.ext <<EOF
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
  -in dso-mgt.infra-server.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile dso-mgt.infra-v3_server.ext -extensions v3_server \
  -out dso-mgt.infra-server.crt

# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt dso-mgt.infra-server.crt



 

# UPDATE ipaddresspool and l2advertisement for addition worker nodes for nks
export KUBECONFIG=prd-nkp-app-nks-a.conf
# metallb and l2advertisement
vi nks-metallb-additional-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: prd-nkp-nks-lb
  namespace: metallb-system
spec:
  addresses:
  - 172.138.3.1-172.138.5.255
  # autoAssign: true # Default is true. Set to false if you only want specific Services to request this pool by annotation.
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: prd-nkp-nks-lb-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - prd-nkp-nks-lb

# verify namespace
kubectl get pods -A | grep metallb
# Output should show pods in 'metallb-system' or similar. Update the YAML namespace if different.
kubectl apply -f nks-metallb-additional-pool.yaml
# verification
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system




# UPDATE ipaddresspool and l2advertisement for addition worker nodes for xaip
export KUBECONFIG=prd-nkp-app-xaip-a.conf
# metallb and l2advertisement
vi xaip-metallb-additional-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: prd-nkp-xaip-lb
  namespace: metallb-system
spec:
  addresses:
  - 172.138.6.1-172.138.8.255
  # autoAssign: true # Default is true. Set to false if you only want specific Services to request this pool by annotation.
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: prd-nkp-xaip-lb-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - prd-nkp-xaip-lb

# verify namespace
kubectl get pods -A | grep metallb
# Output should show pods in 'metallb-system' or similar. Update the YAML namespace if different.
kubectl apply -f xaip-metallb-additional-pool.yaml
# verification
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system









##### 090226 infra cluster setup
COUNTRY="SG"
ORG="nutanix"
ROOT_CN="nutanix"
ICA_CN="nutanix"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="dso-mgt.ntnxlab.local.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="dso-mgt.ntnxlab.local.ntnxlab.local"
SERVER_IP1="10.161.83.150"

# This section is for generate of server cert, such as harbor, nkp, or workload cert
openssl genrsa -out dso-mgt.ntnxlab.local-server.key 2048

# CSR
openssl req -new -sha256 \
  -key dso-mgt.ntnxlab.local-server.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out dso-mgt.ntnxlab.local-server.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > dso-mgt.ntnxlab.local-v3_server.ext <<EOF
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
  -in dso-mgt.ntnxlab.local-server.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile dso-mgt.ntnxlab.local-v3_server.ext -extensions v3_server \
  -out dso-mgt.ntnxlab.local-server.crt

# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt dso-mgt.ntnxlab.local-server.crt


vi .prd-env-mgmt
# VM Setting
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=2
export CONTROL_PLANE_MEMORY_GIB=64
export WORKER_REPLICAS=4
export WORKER_VCPUS=8
export WORKER_CORES_PER_VCPU=2
export WORKER_MEMORY_GIB=64
export SSH_KEY_FILE=/root/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='dso-mgt' # <-- the name you create on the VM
export CONTROL_PLANE_IP=10.161.83.140 # <-- your kubeVip
export LB_IP_RANGE=10.161.83.150-10.161.83.154 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://ctsmgtv0001.ntnxlab.local:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=Nutanix/4all!
export IMAGE_NAME=nkp-ubuntu-24.04-release-cis-ntxcntrc1-1.34.1-20251206061851
export PRISM_ELEMENT_CLUSTER_NAME=kestrel21-1
export SUBNET_NAME=VLAN293
export NUTANIX_STORAGE_CONTAINER_NAME=ntxcntrC1

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

# Ingress
export CLUSTER_HOSTNAME="dso-mgt.ntnxlab.local.ntnxlab.local"
export INGRESS_CERT=/data/nkp-v2.17.0/certs/dso-mgt.ntnxlab.local-server.crt
export INGRESS_KEY=/data/nkp-v2.17.0/certs/dso-mgt.ntnxlab.local-server.key
export INGRESS_CA=/data/nkp-v2.17.0/certs/ca-chain.crt

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
    --ntp-servers "172.140.132.14" \
    --airgapped \
    --insecure \
    --timeout 120m




#### cts for 090226


COUNTRY="SG"
ORG="nutanix"
ROOT_CN="nutanix"
ICA_CN="nutanix"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="prd-nkp-cts.infra-prd.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="prd-nkp-cts.infra-prd.ntnxlab.local"
SERVER_IP1="172.138.0.96"
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.129.42.94"

# This section is for generate of server cert, such as harbor, nkp, or workload cert
openssl genrsa -out prd-nkp-cts.infra-prd.key 2048

# CSR
openssl req -new -sha256 \
  -key prd-nkp-cts.infra-prd.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out prd-nkp-cts.infra-prd.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > prd-nkp-cts.infra-prd-v3_server.ext <<EOF
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
  -in prd-nkp-cts.infra-prd.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile prd-nkp-cts.infra-prd-v3_server.ext -extensions v3_server \
  -out prd-nkp-cts.infra-prd-server.crt

# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt prd-nkp-cts.infra-prd-server.crt

# VM Setting
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=2
export CONTROL_PLANE_MEMORY_GIB=64
export WORKER_REPLICAS=4
export WORKER_VCPUS=8
export WORKER_CORES_PER_VCPU=2
export WORKER_MEMORY_GIB=64
export SSH_KEY_FILE=/root/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='prd-nkp-cts' # <-- the name you create on the VM
export CONTROL_PLANE_IP=172.138.0.95 # <-- your kubeVip
export LB_IP_RANGE=172.138.0.96-172.138.0.100 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://ctsmgtv0001.ntnxlab.local:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=Nutanix/4all!
export IMAGE_NAME=nkp-ubuntu-24.04-release-cis-ntxcntrc1-1.34.1-20251206061851
export PRISM_ELEMENT_CLUSTER_NAME=kestrel21-1
export SUBNET_NAME=vlan_tnt_cts_c1_01
export NUTANIX_STORAGE_CONTAINER_NAME=ntxcntrC1


# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.17.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.17.0.tar"

# Ingress
export CLUSTER_HOSTNAME="prd-nkp-cts.infra-prd.ntnxlab.local"
export INGRESS_CERT=/data/nkp-v2.17.0/certs/prd-nkp-cts.infra-prd-server.crt
export INGRESS_KEY=/data/nkp-v2.17.0/certs/prd-nkp-cts.infra-prd.key
export INGRESS_CA=/data/nkp-v2.17.0/certs/ca-chain.crt

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
    --cluster-hostname ${CLUSTER_HOSTNAME} \
    --ingress-ca ${INGRESS_CA} \
    --ingress-certificate ${INGRESS_CERT} \
    --ingress-private-key ${INGRESS_KEY} \
    --bundle=${KONVOY_IMAGE_BUNDLE},${KOMMANDER_IMAGE_BUNDLE} \
    --airgapped \
    --ntp-servers "172.140.132.14" \
    --insecure \
    --timeout 120m



## A1 cluater 090226

COUNTRY="SG"
ORG="nutanix"
ROOT_CN="nutanix"
ICA_CN="nutanix"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="prd-nkp-app-nks-a.infra-prd.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="prd-nkp-app-nks-a.infra-prd.ntnxlab.local"
SERVER_IP1="172.128.0.12"
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.129.42.94"

# This section is for generate of server cert, such as harbor, nkp, or workload cert
openssl genrsa -out prd-nkp-app-nks-a.infra-prd.key 2048

# CSR
openssl req -new -sha256 \
  -key prd-nkp-app-nks-a.infra-prd.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out prd-nkp-app-nks-a.infra-prd.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > prd-nkp-app-nks-a.infra-prd-v3_server.ext <<EOF
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
  -in prd-nkp-app-nks-a.infra-prd.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile prd-nkp-app-nks-a.infra-prd-v3_server.ext -extensions v3_server \
  -out prd-nkp-app-nks-a.infra-prd-server.crt

# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt prd-nkp-app-nks-a.infra-prd-server.crt

# VM Setting
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=2
export CONTROL_PLANE_MEMORY_GIB=64
export WORKER_REPLICAS=4
export WORKER_VCPUS=8
export WORKER_CORES_PER_VCPU=2
export WORKER_MEMORY_GIB=64
export SSH_KEY_FILE=/root/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='prd-nkp-app-nks-a' # <-- the name you create on the VM
export CONTROL_PLANE_IP=172.128.0.11 # <-- your kubeVip
export LB_IP_RANGE=172.128.0.12-172.128.0.15 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://ctsmgtv0001.ntnxlab.local:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=Nutanix/4all!
export IMAGE_NAME=nkp-ubuntu-24.04-release-cis-ntxcntra-syncrepl-cls-a1-1.34.1-20251206061851
export PRISM_ELEMENT_CLUSTER_NAME=ntxmgtv0001
export SUBNET_NAME=VLAN_KAISENSE_XAIP_A1
export NUTANIX_STORAGE_CONTAINER_NAME=ntxcntrA-SyncRepl


# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.17.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.17.0.tar"

# Ingress
export CLUSTER_HOSTNAME="prd-nkp-app-nks-a.infra-prd.ntnxlab.local"
export INGRESS_CERT=/data/nkp-v2.17.0/certs/prd-nkp-app-nks-a.infra-prd-server.crt
export INGRESS_KEY=/data/nkp-v2.17.0/certs/prd-nkp-app-nks-a.infra-prd.key
export INGRESS_CA=/data/nkp-v2.17.0/certs/ca-chain.crt

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
    --cluster-hostname ${CLUSTER_HOSTNAME} \
    --ingress-ca ${INGRESS_CA} \
    --ingress-certificate ${INGRESS_CERT} \
    --ingress-private-key ${INGRESS_KEY} \
    --bundle=${KONVOY_IMAGE_BUNDLE},${KOMMANDER_IMAGE_BUNDLE} \
    --airgapped \
    --ntp-servers "172.140.132.14" \
    --insecure \
    --timeout 120m





#  A2 xaip cluster 090226

COUNTRY="SG"
ORG="nutanix"
ROOT_CN="nutanix"
ICA_CN="nutanix"
ROOT_DAYS=3650                             # ~10 years
ICA_DAYS=3650
SERVER_DAYS=825                            # ~27 months (common max for public TLS)
# For v3_server.ext
SERVER_CN="prd-nkp-app-xaip-a.infra-prd.ntnxlab.local"   # CN not used for matching, but keep it tidy
SERVER_HOST1="prd-nkp-app-xaip-a.infra-prd.ntnxlab.local"
SERVER_IP1="172.128.0.17"
# SERVER_HOST2="*.ntnxlab.local"
# SERVER_IP2="10.129.42.94"

# This section is for generate of server cert, such as harbor, nkp, or workload cert
openssl genrsa -out prd-nkp-app-xaip-a.infra-prd.key 2048

# CSR
openssl req -new -sha256 \
  -key prd-nkp-app-xaip-a.infra-prd.key \
  -subj "/C=$COUNTRY/O=$ORG/CN=$SERVER_CN" \
  -out prd-nkp-app-xaip-a.infra-prd.csr

# Build v3_server.ext. If you need to add more SANs, append lines:
#   echo "DNS.2 = *.ntnxlab.local" >> v3_server.ext
#   echo "IP.2  = 10.129.42.94"     >> v3_server.ext
cat > prd-nkp-app-xaip-a.infra-prd-v3_server.ext <<EOF
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
  -in prd-nkp-app-xaip-a.infra-prd.csr \
  -CA ica.crt -CAkey ica.key -CAcreateserial \
  -extfile prd-nkp-app-xaip-a.infra-prd-v3_server.ext -extensions v3_server \
  -out prd-nkp-app-xaip-a.infra-prd-server.crt

# ---- Verification ----------------------------------------------------------
echo "== Verify server against CA chain =="
openssl verify -CAfile ca-chain.crt prd-nkp-app-xaip-a.infra-prd-server.crt

# VM Setting
export CONTROL_PLANE_REPLICAS=3
export CONTROL_PLANE_VCPUS=8
export CONTROL_PLANE_CORES_PER_VCPU=2
export CONTROL_PLANE_MEMORY_GIB=64
export WORKER_REPLICAS=4
export WORKER_VCPUS=8
export WORKER_CORES_PER_VCPU=2
export WORKER_MEMORY_GIB=64
export SSH_KEY_FILE=/root/.ssh/id_rsa.pub

# Nutanix Prism Central
export CLUSTER_NAME='prd-nkp-app-xaip-a' # <-- the name you create on the VM
export CONTROL_PLANE_IP=172.128.0.16 # <-- your kubeVip
export LB_IP_RANGE=172.128.0.17-172.128.0.20 # <-- your metallb IP range
export NUTANIX_PC_FQDN_ENDPOINT_WITH_PORT=https://ctsmgtv0001.ntnxlab.local:9440
#export NUTANIX_PC_CA=/path/to/pc_ca_chain.crt
#export NUTANIX_PC_CA_B64="$(base64 -w 0 < "$NUTANIX_PC_CA")"
export NUTANIX_USER=admin
export NUTANIX_PASSWORD=Nutanix/4all!
export IMAGE_NAME=nkp-ubuntu-24.04-release-cis-ntxcntra-syncrepl-cls-a2-1.34.1-20251206061851
export PRISM_ELEMENT_CLUSTER_NAME=ntxmgtv0002
export SUBNET_NAME=VLAN_KAISENSE_XAIP_A2
export NUTANIX_STORAGE_CONTAINER_NAME=ntxcntrA-SyncRepl


# In-cluster  registry (for NKP Images)
export KONVOY_IMAGE_BUNDLE="./container-images/konvoy-image-bundle-v2.17.0.tar"
export KOMMANDER_IMAGE_BUNDLE="./container-images/kommander-image-bundle-v2.17.0.tar"

# Ingress
export CLUSTER_HOSTNAME="prd-nkp-app-nks-a.infra-prd.ntnxlab.local"
export INGRESS_CERT=/data/nkp-v2.17.0/certs/prd-nkp-app-xaip-a.infra-prd-server.crt
export INGRESS_KEY=/data/nkp-v2.17.0/certs/prd-nkp-app-xaip-a.infra-prd.key
export INGRESS_CA=/data/nkp-v2.17.0/certs/ca-chain.crt

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
    --cluster-hostname ${CLUSTER_HOSTNAME} \
    --ingress-ca ${INGRESS_CA} \
    --ingress-certificate ${INGRESS_CERT} \
    --ingress-private-key ${INGRESS_KEY} \
    --bundle=${KONVOY_IMAGE_BUNDLE},${KOMMANDER_IMAGE_BUNDLE} \
    --ntp-servers "172.140.132.14" \
    --airgapped \
    --insecure \
    --timeout 120m








# load nvidia driver image for rhel9.6
./cli/nkp push bundle --bundle 580.82.07-rhel9.6.tar \
  --to-internal-registry-mirror \
  --kubeconfig your-cluster.conf \
  --bundle ./container-images/kommander-image-bundle-v2.17.0.tar \
  --bundle ./container-images/konvoy-image-bundle-v2.17.0.tar



# install driver on all gpu nodes
ssh konvoy@IP-address
sudo rpm -iv nvidia-driver-local-repo-rhel9-580.82.07-1.0-1.x86_64.rpm

# on cluster, reboot the node
k drain prd-nkp-app-xaip-a-xlgpu-p6ztp-29ppg-54dj6-mkz96 --ignore-daemonsets --delete-emptydir-data



driver:
  enabled: false
  values: |
    toolkit:
      version: v1.17.8-ubi8




k delete cluster -n prd-nkp-cts-kvp8q-7z66q prd-nkp-cts


------------------------------------------------------
# Configure Velero as Object Backup
# In NKP UI, enable Velero application, ignore the warning from 
# rook ceph, you are not using rook ceph
# in you bastion, configure the following file

vi velero-nutanix-credentials.yaml
apiVersion: v1
kind: Secret
metadata:
  name: velero-nutanix-credentials #you can create your own name
  namespace: kommander  #tthe namespace you want your secret to be in
type: Opaque
stringData:
  aws: |
    [velero-dso-mgt-backup] # give a meaningful name for this profile
    aws_access_key_id = F75UPJ2XQWPVA1PAORSZ
    aws_secret_access_key = 3ukY/WTzPRsMg+Y46YmMuPB7cXceHRrOVVle9n2S
k apply -f velero-nutanix-credentials.yaml

vi velero-config-map.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: kommander
  name: velero-overrides #give config-map a name
data:
  values.yaml: |
    credentials:
      extraSecretRef: ""
    configuration:
      backupStorageLocation:
      - name: velero-backup #give a name for your BSL
        bucket: velero-backup #the name of the bucket, I will reference to the name I give for object
        provider: "aws"   # Corrected indentation (align with `name` and `bucket`)
        default: true
        cacert: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUZtakNDQTRLZ0F3SUJBZ0lRYXRKQ09LNHlqcEZEY2FFMGxHbEkwakFOQmdrcWhraUc5dzBCQVFzRkFEQlUKTVJnd0ZnWUtDWkltaVpQeUxHUUJHUllJYVc1MFpYSnVZV3d4RmpBVUJnb0praWFKay9Jc1pBRVpGZ1pPUjBsTwpSVEl4SURBZUJnTlZCQU1URjA1SFNVNUZNaTVKYm5SbGNtNWhiQ0JTYjI5MElFTkJNQjRYRFRJMk1ESXhNekExCk1UVTFNRm9YRFRRMk1ESXhNekExTWpVME9Gb3dWREVZTUJZR0NnbVNKb21UOGl4a0FSa1dDR2x1ZEdWeWJtRnMKTVJZd0ZBWUtDWkltaVpQeUxHUUJHUllHVGtkSlRrVXlNU0F3SGdZRFZRUURFeGRPUjBsT1JUSXVTVzUwWlhKdQpZV3dnVW05dmRDQkRRVENDQWlJd0RRWUpLb1pJaHZjTkFRRUJCUUFEZ2dJUEFEQ0NBZ29DZ2dJQkFNeThHd0owCm1QMnR1QkRiVzFtNFhkZmpBV291NU82OEV3b0hGVTJmSENQa2lrbU1GaHZZdks3a0M1TncyNXRJNVVxdnRkVk0KQ2pMdkhCZ0dRTFFmTjhLajBjdHVKM1Jnam9iZnpVUHAzemhWQVE4QURMQTFzb29JRkJyWkNyRjQ1a1lkQ2pMUwpYZmhqV2FISmxTMHNXcFBmbjdBbW80b2hpY1l4YXp2TE9wdFBjR2NPODhaOWF6WUZTaytWTFpZWFRxTzBpbERMCk1keXhOdWFhdzl5NUpyK2tWYmpocUV2NWFURjgzUlBCa2pBMUp2dmJJeTV0VWpKdi9abi8rUTFIS3NxRWRwNE0KTW4yNGZCdDA3TENCS0Z2Q0haZlJyQUJjWG1JR3EzTEh3em10NTU1TU45VktuaU1KR0dmVW1hdi8yVGxaemFCWgpMTkJBand3V2pOSzViUkc5UTBjcE1velJvYkY3TkRoVG9ZakVkUmc0dFE5ZlN0VmZEai82ZE9kZWcwVlZCaWpCCnBLUFB5d0dWUTNCMUZwbGNVQml3WHp3VjJuUkl0ejF6Z0lBemQvcWJzS0dJVG9hZ0FQQUxYSWRzbU5qRStEWE0KdXZZVkI5cXk4NG1DKzJmZnZmVEUrdllFNkxqRURIUXRBRWJnd1A4Rk9XYWxqVDJiZ0x4VHpYc2dMU3ovQTl1SApTWWE4RkJOaFFNKzhaM3JRUStRT2lIUk5YTVkvaFdRaU5aNVlVeTU0bC9uRzUxZlB3aHJVK2hmWWJTSlliaWc1Ck1HYU92cVBRdkhMamxNNHphOURGY1hvem90Zk1FaWdaVHVEcUFSdklDQm9UY09kQnVKTm9iN3d5WEVCbzVIRUgKMVhFeThNc1NXWDcxS0pONVFDVW5HTWVQMUYzb25sdkNCQms1QWdNQkFBR2phREJtTUFzR0ExVWREd1FFQXdJQgpoakFQQmdOVkhSTUJBZjhFQlRBREFRSC9NQjBHQTFVZERnUVdCQlFIZ0lCYzd3dzZwbXhjQTJXU2N6TFAyOWdZCjV6QVFCZ2tyQmdFRUFZSTNGUUVFQXdJQkFEQVZCZ05WSFNBRURqQU1NQW9HQ0NvREJJc3ZRMWtGTUEwR0NTcUcKU0liM0RRRUJDd1VBQTRJQ0FRQUdRSUhCaDNvWHpUMmJiQ1IwdmRkeXJFZXRsVDhiNExHVjdWYnhIL2Vmd2pPMApQNTRFMkdPdUx0MlpWK2VLOUZGa0hEMEdtdXdrTXRTdVNkZk45K2Z6VnRhUjBHYUJFVVcrVFlFSW92NUR3Z2dWCkc0YmVRQzZaK2xlTTZkMzVpUkJRSWdjeUxuSm82b0ZNblZCYjJjSUdpNkVsZ1VNMXk3VEd0MWllcS9kcXpsODgKV08vRzhTamdWbDZaMGhpd1d5alhhVkdBQVdPcWFwTVd1WU1PWWt1RVNscy9RSzcvZEEva2VGcVVwSXVNQlVqNgpMdUQyQjloRGRrOGVjeE50RkFzbUUwT0FKcVM3c2VucjNMUWJxNXhqNWtTMGQvOXgrM3hjMlNPdTR5dnVhcCthCmpXNlc0K2tNd3N6RFJZdlFkMkFCWjVNQzdya2x2SHJTcHo1a0lFSy9hVlNoM2dmNEtmQ2IxTHYwQVEyMW1Qa2sKN1dyWEZrNXlQRzVyc2pkYzlzNU8rc240Y1FXYnZDUUtGZFY0c0tveUNWMk9NMzdVdkwwUTV3cXFuWisyNStGbgptdVhSSXhRcTVCZW52UEkxNFdvNWQxYTUwKzFUUDBrNDdOK3BLTFArMWVvWmo4ZXlQRkhRaDlTOHI3OHl3NmdyCkFkSUlyUkVaM0w1RmZlM0oya2RrTC9Xc0haZlFhSnN0MVFBWnFUOUUzbFpOQVFTcEN1WUFQSEJvMThRaVZEYlMKYUgwRXAvSjdqZld4SnYwditrakJMRFRRakxJVVl1emhHUytKTjFOMEdveEZRVEJCaDY3cWEvdXBBVUc3Z243QwpadkhqeXZCanhhV25FRFR5c3RxU1hRdXlGMEM2WFNzbzEza3lGaTBKVzlZZGRNVzZPNnJjYzcybGlFTGJKZz09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K   # Corrected indentation
        config:
          region: us-east-1
          s3ForcePathStyle: "true"
          insecureSkipTLSVerify: "true"
          s3Url: "https://prd.vast.infra-prd.ntnxlab.local"   #FQDN/IP of your object and port
          profile: velero-dso-mgt-backup #this profile name is the same as give in your secret,
        credential:
          key: aws
          name: velero-nutanix-credentials   #the name of your secret
k apply -f velero-config-map.yaml

# update velero
kubectl -n prd-nkp-cts-n68hf patch \
appdeployment velero --type="merge" --patch-file=/dev/stdin <<EOF
spec:
  configOverrides:
    name: velero-overrides
EOF

kubectl --kubeconfig=sk-upgrade.conf get hr -n kommander velero -o
jsonpath='{.spec.valuesFrom[?(@.name=="velero-overrides")]}'

kubectl --kubeconfig=sk-upgrade.conf get pods -A --kubeconfig=
sk-upgrade.conf |grep velero

kubectl --kubeconfig=sk-upgrade.conf get bsl -n kommander

# Testing for backup and restore
export VELERO_NAMESPACE=kommander
velero backup get
kubectl delete ns demo --wait=true
velero restore create --from-backup demo-preupgrade
velero restore get

# To be able to see the UI from node, use the command
kubectl -n demo patch svc hello-svc -p '{"spec":{"type":"NodePort"}}'

# To reset back to clusterIP
kubectl -n demo patch svc hello-svc -p '{"spec":{"type":"ClusterIP"}}'



# to setup velero for workload cluster
# do these on managememt cluster
# vi workload-cluster-override.yaml
# enable velero on workspace "workload01"
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: Kommander  # you workspace
  name: velero-overrides #give config-map a name
data:
  values.yaml: |
    credentials:
      extraSecretRef: ""
    configuration:
      backupStorageLocation:
      - name: velero-backup #give a name for your BSL
        bucket: velero-backup #the name of the bucket, I will reference to the name I give for object
        provider: "aws"   # Corrected indentation (align with `name` and `bucket`)
        default: true     # Corrected indentation
        config:
          region: us-east-1
          s3ForcePathStyle: "true"
          insecureSkipTLSVerify: "true"
          s3Url: "https://velero-backup.nkp.sub1.ntnxlab.local"   #FQDN of your object and port
          profile: velero-backup #this profile name is the same as give in your secret,
        credential:
          key: aws
          name: velero-nutanix-credentials

k apply -f  velero-config-map.yaml

kubectl -n $workload01 patch appdeployment velero \
  --type='merge' \
  -p '{
    "spec": {
      "configOverrides": { "name": "velero-overrides" }
    }
  }'

# switch to workload kubeconfig, perform the following
# velero-nutanix-credentials.yaml
apiVersion: v1
kind: Secret
metadata:
  name: velero-nutanix-credentials #you can create your own name
  namespace: workload01  #tthe namespace you want your secret to be in
type: Opaque
stringData:
  aws: |
    [velero-backup] # give a meaningful name for this profile
    aws_access_key_id = BpDowo9cZSwU_q4lVmvrSIrb8XjJ7Uv2
    aws_secret_access_key = hsC3gyY5LJWVzleTKBow70Oj_BijsVVn


k apply -f velero-nutanix-credentials.yaml

# From the mgmt cluster, when you create config override on workload01, 
# and applied the patch on appdeployment, the configuration will 
# applied on that workspace,, when you kubeconfig to workload,
# just need to apply secret to autenticate will do.




k get secret -n prd-nkp-app-xaip-a-rspwk  nkp-mgmt-harbor-ca -ojsonpath='{.data.ca\.crt}' |base64 -d | openssl x509 -text -noout


updated-nkp-mgmt-harbor-ca