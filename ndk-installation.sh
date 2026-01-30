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
# using mysql to test for NDK, it had to run as a deployment
vi mysql-full-stack.yaml
# 1. THE SERVICE (Headless service for StatefulSet)
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: ndk-test
  labels:
    app: mysql
spec:
  ports:
  - port: 3306
    name: mysql
  clusterIP: None
  selector:
    app: mysql
---
# 2. THE STATEFULSET (Includes the PVC definition)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql-sts
  namespace: ndk-test
  labels:
    app: mysql  # <--- This label is what the Application CR looks for
spec:
  serviceName: "mysql"
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        # Using your local registry image
        image: registry.ntnxlab.local/applications/mysql@sha256:df74fa37ff90ac07fb76363cfe272db16842aec38597efe7b454187a57e5a984
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "nutanix123"
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
  # This section creates the PVC automatically for the pod
  volumeClaimTemplates:
  - metadata:
      name: mysql-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "nutanix-volume"
      resources:
        requests:
          storage: 5Gi
---
# 3. THE APPLICATION CR (The missing link!)
apiVersion: dataservices.nutanix.com/v1alpha1
kind: Application
metadata:
  name: mysql-app
  namespace: ndk-test
spec:
  # This tells NDK to protect all resources with label "app: mysql"
  applicationSelector:
    resourceLabelSelectors:
      - labelSelector:
          matchLabels:
            app: mysql

k apply -f mysql-full-stack.yaml
# wait and watch for the pod running
k get po -n ndk-test -w

# create a protect plan to tell NDK 
# how to backup this application
vi protection-plan.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: ProtectionPlan
metadata:
  name: mysql-hourly-plan
  namespace: ndk-test
spec:
  scheduleName: default-schedule
  retentionPolicy:
    retentionCount: 2

k apply -f protection-plan.yaml

# bind and snapshot
vi protection-binding.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: AppProtectionPlan
metadata:
  name: mysql-binding
  namespace: ndk-test
spec:
  applicationName: mysql-app  # Matches the Application CR we just created
  protectionPlanNames:
    - mysql-hourly-plan

k apply -f protection-binding.yaml


# Trigger Snapshot
vi take-snapshot.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: ApplicationSnapshot
metadata:
  name: manual-test-snap-01
  namespace: ndk-test
spec:
  source:
    applicationRef:
      name: mysql-app
  expiresAfter: 2h #For example, 5m for 5 minutes or 2h for 2 hours


k apply -f take-snapshot.yaml 

# test for recovery
vi restore-test.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: ApplicationSnapshotRestore
metadata:
  name: restore-test-01
  namespace: ndk-test
spec:
  applicationSnapshotName: manual-test-snap-01
  applicationSnapshotNamespace: ndk-test




