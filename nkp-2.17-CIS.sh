# cis-1.2.12-patches.yaml
cat <<EOF > cis-1.2.12-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
name: ${CLUSTER_NAME}-control-plane
spec:
kubeadmConfigSpec:
clusterConfiguration:
apiServer:
extraArgs:
enable-admission-plugins: "AlwaysPullImages"
EOF

# cis-1.2.32-patches.yaml 
cat <<EOF > cis-1.2.32-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      apiServer:
        extraArgs:
          tls-cipher-suites: "TLS_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384,TLS_CHACHA20_POLY1305_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256,TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,TLS_RSA_WITH_3DES_EDE_CBC_SHA,TLS_RSA_WITH_AES_128_CBC_SHA,TLS_RSA_WITH_AES_128_GCM_SHA256,TLS_RSA_WITH_AES_256_CBC_SHA,TLS_RSA_WITH_AES_256_GCM_SHA384"
EOF

# cis-1.2.16-patches.yaml
cat <<EOF > cis-1.2.16-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      apiServer:
        extraArgs:
          profiling: "false"
EOF

# cis-4.1.9-patches.yaml
cat <<EOF > cis-4.1.9-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    postKubeadmCommands:
    - chmod 600 /var/lib/kubelet/config.yaml
---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: ${CLUSTER_NAME}-md-0
spec:
  template:
    spec:
      postKubeadmCommands:
      - chmod 600 /var/lib/kubelet/config.yaml
EOF

# cis-1.2.18-patches.yaml 
cat <<EOF > cis-1.2.18-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      apiServer:
        extraArgs:
          profiling: "false"
EOF

# cis-4.2.13-patches.yaml
cat <<EOF > cis-4.2.13-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    initConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          tls-cipher-suites: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_128_GCM_SHA256"
    joinConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          tls-cipher-suites: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_128_GCM_SHA256"
---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: ${CLUSTER_NAME}-md-0
spec:
  template:
    spec:
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
            tls-cipher-suites: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_128_GCM_SHA256"
EOF

# cis-1.3.2-patches.yaml
cat <<EOF > cis-1.3.2-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      controllerManager:
        extraArgs:
          profiling: "false"
EOF

# cis-4.2.9-patches.yaml 
cat <<EOF > cis-4.2.9-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    initConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          event-qps: "0"
    joinConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          event-qps: "0"
---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: ${CLUSTER_NAME}-md-0
spec:
  template:
    spec:
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
            event-qps: "0"
EOF

# cis-4.2.6-patches.yaml
cat <<EOF > cis-4.2.6-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    initConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          protect-kernel-defaults: "true"
    joinConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          protect-kernel-defaults: "true"
---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: ${CLUSTER_NAME}-md-0
spec:
  template:
    spec:
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
            protect-kernel-defaults: "true"
EOF

# cis-1.3.1-patches.yaml
cat <<EOF > cis-1.3.1-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      controllerManager:
        extraArgs:
          terminated-pod-gc-threshold: "12500"
EOF

# cis-4.1.1-patches.yaml
cat <<EOF > cis-4.1.1-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    postKubeadmCommands:
    - chmod 600 /lib/systemd/system/kubelet.service
---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: ${CLUSTER_NAME}-md-0
spec:
  template:
    spec:
      postKubeadmCommands:
      - chmod 600 /lib/systemd/system/kubelet.service
EOF

# cis-1.4.1-patches.yaml
cat <<EOF > cis-1.4.1-patches.yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: ${CLUSTER_NAME}-control-plane
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      scheduler:
        extraArgs:
          profiling: "false"
EOF

# create kustomization.yaml
cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ${CLUSTER_NAME}.yaml
patches:
  - cis-1.2.12-patches.yaml
  - cis-1.2.16-patches.yaml
  - cis-1.2.18-patches.yaml
  - cis-1.2.32-patches.yaml
  - cis-1.3.1-patches.yaml
  - cis-1.3.2-patches.yaml
  - cis-1.4.1-patches.yaml
  - cis-4.1.9-patches.yaml
  - cis-4.1.1-patches.yaml
  - cis-4.2.6-patches.yaml
  - cis-4.2.9-patches.yaml
  - cis-4.2.13-patches.yaml
 EOF