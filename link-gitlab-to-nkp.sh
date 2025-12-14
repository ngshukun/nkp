# create nsmaspace gitops
kubectl create namespace gitops

# create gitlab secret creds
kubectl -n gitops create secret generic gitlab-creds \
  --from-literal=username='<GITLAB_USERNAME_OR_DEPLOY_TOKEN_NAME>' \
  --from-literal=password='<GITLAB_TOKEN>' \
  --from-file=ca.crt=/home/nutanix/certs/ca-chain.crt

# create flux gitrepo resource
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: nkp-gitops
  namespace: gitops
spec:
  interval: 1m
  url: https://gitlab.ntnxlab.local/shukun/nkp-gitops.git
  ref:
    branch: main
  secretRef:
    name: gitlab-creds

kubectl apply -f gitrepository.yaml
kubectl -n gitops get gitrepositories

# expected results
# NAME         URL                                                  READY   STATUS
# nkp-gitops   https://gitlab.ntnxlab.local/shukun/nkp-gitops.git   True    stored artifact for revision 'main@sha1:<commit>'
