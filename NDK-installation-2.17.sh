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


# create secret for PC authentication
kubectl create secret generic ntnx-pc-secret -n ntnx-system   --from-literal=key="10.161.16.218:9440:admin:nx2Tech198!"






