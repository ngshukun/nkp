# This show how to upgrade NKP from 2.14 --> 2.15 --> 2.16
# In this cluster, we create a sample application, and perform backup on it.
# Create namespace and manifest create as below

kubectl create ns demo

cat <<EOF | kubectl -n demo apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-deploy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
      - name: hello
        image: nginx:stable
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: hello-html
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: hello-html
data:
  index.html: |
    <html><body><h1>Hello World — NKP Upgrade Test</h1></body></html>
---
apiVersion: v1
kind: Service
metadata:
  name: hello-svc
spec:
  selector:
    app: hello
  ports:
  - port: 80
    targetPort: 80
EOF

# Check for pod and svc is up
k -n demo get pods,svc

# Performing a pre-upgrade of demo app
velero backup create demo-preupgrade --include-namespaces demo
velero backup describe demo-preupgrade --details
velero backup get

# Add Pod Disruption Budget for the app
cat <<'EOF' | kubectl -n demo apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: hello-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: hello
EOF

#verify PDB
kubectl -n demo get pdb
kubectl -n demo describe pdb hello-pdb

# upgrade kommamnder to 2.15.1
cd nkp-v2.15.1/
sudo cp cli/nkp /usr/bin/
nkp version
export KUBECONFIG=/home/nutanix/nkp-v2.14.2/sk-upgrade.conf
k get no
nkp upgrade kommander   --kommander-applications-repository ./application-repositories/kommander-applications-v2.15.1.tar.gz --charts-bundle ./application-charts/nkp-kommander-charts-bundle-v2.15.1.tar.gz
# check for all deployments and pod 
kubectl -n kommander get deployments,pods


# upgrade Management Cluster (konvoy +  Kubernetes) to 2.15.1
export VM_IMAGE_NAME=nkp-rocky-9.5-release-1.32.3-20250430150550.qcow2
export MGMT_CLUSTER_NAME=sk-upgrade
nkp upgrade cluster nutanix \
  --cluster-name ${MGMT_CLUSTER_NAME} \
  --vm-image ${VM_IMAGE_NAME}



