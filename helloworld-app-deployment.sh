# Helloworld-app-manifest
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