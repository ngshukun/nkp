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











