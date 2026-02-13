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
        default: true
        cacert: xxxx     # Corrected indentation
        config:
          region: us-east-1
          s3ForcePathStyle: "true"
          insecureSkipTLSVerify: "false"
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

