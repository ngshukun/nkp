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
    [velero-backup] # give a meaningful name for this profile
    aws_access_key_id = BpDowo9cZSwU_q4lVmvrSIrb8XjJ7Uv2
    aws_secret_access_key = hsC3gyY5LJWVzleTKBow70Oj_BijsVVn
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
        default: true     # Corrected indentation
        config:
          region: us-east-1
          s3ForcePathStyle: "true"
          insecureSkipTLSVerify: "true"
          s3Url: "https://velero-backup.nkp.sub1.ntnxlab.local"   #FQDN/IP of your object and port
          profile: velero-backup #this profile name is the same as give in your secret,
        credential:
          key: aws
          name: velero-nutanix-credentials    #the name of your secret
k apply -f velero-config-map.yaml

# update velero
kubectl --kubeconfig=sk-upgrade.conf -n kommander patch \
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
  namespace: workload01  # you workspace
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

nkp create cluster preprovisioned --cluster-name ${CLUSTER_NAME}
--control-plane-endpoint-host <control plane endpoint host>
--control-plane-endpoint-port <control plane endpoint port, if different than 6443>
--pre-provisioned-inventory-file preprovisioned_inventory.yaml
--ssh-private-key-file <path-to-ssh-private-key>
--registry-mirror-url=${REGISTRY_URL} \
--registry-mirror-cacert=${REGISTRY_CA} \
--registry-mirror-username=${REGISTRY_USERNAME}