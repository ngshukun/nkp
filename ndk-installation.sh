# prerequitie, download the ndk tar file from
# https://portal.nutanix.com/page/downloads?product=ndk
# in bastion ensure you ldocker login to your private repo
docker login registry.ntnxlab.local
tar -zxvf ndk-2.1.0.tar
tar -xvf ndk-2.1.0.tar
docker image load -i ndk-2.1.0/ndk-2.1.0.tar
docker images # ensure ndk images are loaded
docker tag ndk/manager:2.1.0 registry.ntnxlab.local/ndk/ndk/manager:2.1.0
docker push registry.ntnxlab.local/ndk/ndk/manager:2.1.0
docker tag ndk/infra-manager:2.1.0 registry.ntnxlab.local/ndk/ndk/infra-manager:2.1.0
docker push registry.ntnxlab.local/ndk/ndk/infra-manager:2.1.0
docker tag ndk/job-scheduler:2.1.0 registry.ntnxlab.local/ndk/ndk/job-scheduler:2.1.0
docker push registry.ntnxlab.local/ndk/ndk/job-scheduler:2.1.0
docker tag ndk/kube-rbac-proxy:v0.20.1 registry.ntnxlab.local/ndk/ndk/kube-rbac-proxy:v0.20.1
docker push registry.ntnxlab.local/ndk/ndk/kube-rbac-proxy:v0.20.1
docker tag ndk/kubectl:v1.32.3 registry.ntnxlab.local/ndk/ndk/ndk/kubectl:v1.32.3
docker push registry.ntnxlab.local/ndk/ndk/ndk/kubectl:v1.32.3

# check if all images pushed to your private repo

helm install ndk -n ntnx-system /home/nutanix/ndk-2.1.0/chart/ \
--set manager.repository=registry.ntnxlab.local/ndk/manager \
--set manager.tag=2.1.0 \
--set infraManager.repository=registry.ntnxlab.local/ndk/infra-manager \
--set infraManager.tag=2.1.0 \
--set kubeRbacProxy.repository=registry.ntnxlab.local/ndk/kube-rbac-proxy \
--set kubeRbacProxy.tag=v0.20.1 \
--set kubectl.repository=registry.ntnxlab.local/ndk/kubectl \
--set kubectl.tag=v1.32.3 \
--set jobScheduler.repository=registry.ntnxlab.local/ndk/job-scheduler \
--set jobScheduler.tag=2.1.0 \
--set tls.server.clusterName=baremetal \
--set config.secret.name=ntnx-pc-secret


# ==============================================================================
# TROUBLESHOOTING: Fix "NODE IMAGEPULLERROR"
# ==============================================================================
# if you had pull error, one of the possible issue is the node unable to pull due cert issue
# import the ca-chain.crt to all the node and do the following
# sudo cp ca-chain.crt /usr/local/share/ca-certificates/registry.crt
# sudo update-ca-certificates
# test you can pull from the nodes
# sudo ctr -n k8s.io images pull --user shukun:Harbor12345 registry.ntnxlab.local/ndk/ndk/manager:2.1.0


# manifest for metalln and l2
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: for-ndk
  namespace: metallb-system
spec:
  addresses:
  - 172.138.0.18-172.138.0.19
  # autoAssign: true # Default is true. Set to false if you only want specific Services to request this pool by annotation.
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: prd-nkp-cts-lb-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - for-ndk

# to verify
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# PE UUID: 000622c1-636a-e6fb-0000-000000027af9
# PC UUID: 4e3de98b-80f6-4baa-9ce7-3170baf1219c
# configure storagecluster
vi storage-cluster.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: StorageCluster
metadata:
  name: baremetal-storage-cluster  # You can name this whatever you like
  namespace: ntnx-system           # Must match your NDK installation namespace
spec:
  # Your PE UUID (Cluster: NKP)
  storageServerUuid: "000622c1-636a-e6fb-0000-000000027af9"
  # Your PC UUID (Cluster: PC-NKP)
  managementServerUuid: "4e3de98b-80f6-4baa-9ce7-3170baf1219c"

# Apply the configuration
kubectl apply -f storage-cluster.yaml

# Check the status (Wait a few seconds if needed)
kubectl get storagecluster -n ntnx-system

# ==============================================================================
# TROUBLESHOOTING: Fix "IncorrectUuid" / "StorageClusterUnavailable" Status
# ==============================================================================
# SYMPTOM: 
#   kubectl get storagecluster -n ntnx-system -> Available: false
#   Error: "ManagementServerUuid and/or StorageServerUuid is incorrect"
#
# CAUSE: 
#   Kubernetes nodes are labeled with the Cluster Name (e.g., "bare-metal") 
#   instead of the Prism Element UUID. NDK requires UUIDs to match.
# ==============================================================================

# 1. Set variables (Match these to your StorageCluster YAML)
PE_UUID="000622c1-636a-e6fb-0000-000000027af9"
PC_UUID="4e3de98b-80f6-4baa-9ce7-3170baf1219c"

# 2. Run this loop to overwrite ALL Nutanix labels on ALL nodes
for node in $(kubectl get nodes -o name); do
  echo "Patching node: $node"
  
  # Patch Modern CSI Labels (Topology)
  kubectl label $node topology.csi.nutanix.com/cluster=$PE_UUID --overwrite
  kubectl label $node topology.csi.nutanix.com/prism-element-uuid=$PE_UUID --overwrite

  # Patch Legacy CSI Labels (Crucial for backward compatibility)
  kubectl label $node csi.nutanix.com/prism-element-uuid=$PE_UUID --overwrite
  kubectl label $node csi.nutanix.com/prism-central-uuid=$PC_UUID --overwrite
done

# 3. Restart NDK to apply changes immediately
kubectl delete pod -l app.kubernetes.io/name=ndk -n ntnx-system

# 4. Verify
# kubectl get storagecluster -n ntnx-system

# Configuration of NDK

#to continue the actual configure of NDK 






