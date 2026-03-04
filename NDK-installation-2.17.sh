# download NDK tar from ntnx portal
# ensure to helm helm install, this require helm cli

tar -zxvf ndk-2.1.0.tar
cd ndk-2.1.0/
docker load -i ndk-2.1.0.tar
docker images #<-- to check for the images loaded

# if you loading to cncf registry, perform the following  in a new terminal topush container images to cncf registry
k get svc -n registry-system # <-- check for the name of your registry, look for the one without 'headless'
k port-forward -n registry-system svc/cncf-distribution-registry-docker-registry 5000:443 #<-- take note of the port forwarding, if your port is pointing to 5000, your port forward will be 5000:500, in this example, my registry port is 443.

# docker tag before pushed to cncf or any registry you defined
for img in ndk/manager:2.1.0 ndk/kubectl:v1.32.3 ndk/kube-rbac-proxy:v0.20.1 ndk/job-scheduler:2.1.0 ndk/infra-manager:2.1.0; do docker tag $img localhost:5000/${img}; done

docker push localhost:5000/ndk/infra-manager:2.1.0 && docker push localhost:5000/ndk/job-scheduler:2.1.0 && docker push localhost:5000/ndk/kube-rbac-proxy:v0.20.1 && docker push localhost:5000/ndk/kubectl:v1.32.3 && docker push localhost:5000/ndk/manager:2.1.0

vi ndk-2.1.0/chart/values.yaml #<-- update the following with the url you pushed container images to
# manager:
#   # -- Image Repository
#   repository: localhost:5000/ndk/manager # <-- here
#   # -- Image tag
#   # @default -- .Chart.AppVersion
#   tag: 2.1.0 # <-- here
#   # -- Image digest
#   digest:
#   # -- Image pull policy
#   pullPolicy: Always

# infraManager:
#   # -- Image Repository
#   repository: localhost:5000/ndk/infra-manager # <-- here
#   # -- Image tag
#   # @default -- .Chart.AppVersion
#   tag: 2.1.0 # <-- here
#   # -- Image digest
#   digest:
#   # -- Image pull policy
#   pullPolicy: Always

# kubeRbacProxy:
#   # -- Image Repository
#   repository: localhost:5000/ndk/kube-rbac-proxy # <-- here
#   # -- Image tag
#   tag: v0.20.1 # <-- here
#   # -- Image digest
#   digest:

# kubectl:
#   # -- Image Repository
#   repository: localhost:5000/ndk/kubectl # <-- here
#   # -- Image tag
#   tag: 
#   # -- Image digest
#   digest: v1.32.3 # <-- here
#   # -- Image pull policy
# .
# .
# .
# jobScheduler:
#   # -- Image Repository
#   repository: localhost:5000/ndk/job-scheduler
#   # -- Image tag
#   # @default -- .Chart.AppVersion
#   tag: 2.1.0
#   # -- Image digest
#   digest:
#   # -- Image pull policy
#   pullPolicy: Always
# .
# .
# .
# clusterName: nkp-target # <-- update your cluster name

# create secret for PC authentication
kubectl create secret generic ntnx-pc-secret -n ntnx-system   --from-literal=key="10.161.16.218:9440:admin:nx2Tech198!"

helm install ndk -n ntnx-system ndk-2.1.0/chart/

---
# install mysql for test
# transfer mysql-14.0.3.tgz to bastion
helm install mysql-ndk ./mysql-14.0.3.tgz \
  --namespace ndk-test \
  --set image.repository=bitnamilegacy/mysql \
  --set image.tag=8.0-debian-11 \
  --set primary.persistence.storageClass=nutanix-volumes \
  --set auth.rootPassword=ndktestpassword

# insert sample data
CREATE DATABASE ndk_test_db;
USE ndk_test_db;
CREATE TABLE cluster_validation (
    id INT AUTO_INCREMENT PRIMARY KEY,
    cluster_name VARCHAR(50),
    test_note VARCHAR(255),
    snapshot_flag BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO cluster_validation (cluster_name, test_note) 
VALUES ('NKP-MGT-Cluster', 'Data inserted before NDK Snapshot Test');
SELECT * FROM cluster_validation;
----------------------------------------------------------------------------------------------------
# READ BEFORE PROCEEDING

# Overview of NDK CR
# 1. StorageCluster:
# The Warehouse,To connect the hardware. Kubernetes needs to know which Nutanix physical storage (Prism Element) it is allowed to use to store your data.
# 2. Remote:
# The GPS Address to find the other cluster. Without this, your primary cluster has no "phone number" or IP address to call when it wants to send data to a backup site.
# 3. ReplicationTarget
# The Room Number to specify the destination. It maps a specific "folder" (Namespace) on your local cluster to a "folder" on the remote cluster so data doesn't get lost or mixed up.
# 4. JobScheduler:
# The Alarm Clock to automate the timing. It defines "when" things happen (e.g., every hour, every day) so you don't have to manually click "backup" every time.
# 5. ProtectionPlan:
# The Manager to define the rules. It combines the "When" (Scheduler) with the "How" (Retention rules and Replication settings). It is the master policy for your data.
# 6. AppProtectionPlan:
#The Active Contract to start the work. This links a specific Application to a ProtectionPlan. Without this, the plan exists, but it isn't actually protecting anything yet.



# create storagecluster, this is to register NDK with PC/PE, in plan english, this is where my data will live on the other hard disk
vi storage-class-cluster.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: StorageCluster
metadata:
 name: pc-nkp # <-- give storage cluster a name
spec:
 storageServerUuid: 000622c1-636a-e6fb-0000-000000027af9    # <-- this is your prism-element-uuid
 managementServerUuid: 4e3de98b-80f6-4baa-9ce7-3170baf1219c   # <-- this is your prism-central-uuid

k create -f storage-class-cluster.yaml

# create remote CR, this is to connect from source to target
# think of this like a name card, if want to connect to target cluster remote CR give you the infomation of target cluster, like a name card. in plain english, this is the the address of my other other disk
vi remote-source.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: Remote
metadata:
  name: source-remote
spec:
  clusterName: yy-nkptesting
  ndkServiceIp: 10.129.42.181
  ndkServicePort: 2021
  tlsConfig:
    skipTLSVerify: true

k apply -f remote-source.yaml


# create replication target using remote, tell the primary source where exactly the resource to restore to. in plain english, this is the details such as the floow and unit of where the hard disk are located
vi replicationtarget.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: ReplicationTarget
metadata:
  name: target  # <-- name of this object
  namespace: ndk-test # <-- namespace of the primary cluster 
spec:
  namespaceName: sk-test # <--the name of the secondat cluster that you want the data to reside
  remoteName: source-remote  # <-- the name of your remote CR.
  serviceAccountName: default

k apply -f replicationtarget.yaml
# create job scheduler and create  protectionplan CR something like velero backupschedule
vi jobscheduler.yaml
apiVersion: scheduler.nutanix.com/v1alpha1
kind: JobScheduler
metadata:
 name: ndk-test-schedule
 namespace: ndk-test # <-- namespace that you want to schedule
spec:
 interval:
  minutes: 60 # <-- to schedule evetu 60 min
    #startTime: "2025-10-06T19:39:30.936566+00:00"  # Optional. Defines when the scheduler should begin triggering jobs.
    #timeZoneName: <timezone-name>
    #
---
apiVersion: dataservices.nutanix.com/v1alpha1
kind: ProtectionPlan
metadata:
 name: ndk-protection-plan
 namespace: ndk-test
spec:
 protectionType: async
 scheduleName: ndk-test-schedule
 retentionPolicy:
     retentionCount: 2
 replicationConfigs:
   - replicationTargetName: target # <-- name of the replicationtarget

k apply -f replicationtarget.yaml

# create appprotectionplan, it puts all of the above into actions
vi appprotectionplan.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: AppProtectionPlan
metadata:
 name: sk-plan  # <-- name of this object
 namespace: ndk-test # <-- namespace of the source
spec:
  applicationName: mysql # <-- name of the particular app to be backup
  labels:
    appName: mysql
  protectionPlanNames:
  - ndk-protection-plan # <-- name of the protection plan



# create Application CR
vi mysql-application.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: Application
metadata:
  name: mysql
  namespace: ndk-test
spec:
  applicationSelector:

k apply -f mysql-application.yaml

  # creat applicationsnapshot
vi applicationsnapshot.yaml
apiVersion: dataservices.nutanix.com/v1alpha1
kind: ApplicationSnapshot
metadata:
  name: mysql-snap-1
  namespace: ndk-test
spec:
  source:
    applicationRef:
      name: mysql
  expiresAfter: 60m

k apply -f applicationsnapshot.yaml









