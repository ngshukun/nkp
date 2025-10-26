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



