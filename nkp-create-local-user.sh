htpasswd -n -B -b -C 10 shukun "password" # the password will generate a hash string. copy the string.
# example: shukun:$2y$10$VQIk..Mtea052HhgugjhbjKYAD/CC7EedYa  #<-- this is what you will see if you run the above command.
vi dex-overrides.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dex-overrides
  namespace: kommander
data:
  values.yaml: |
    config:
      staticPasswords:
      - email: "shukun@local"
        hash: "$2y$10$VQIk..Mtea052HhgugjhbjKYAD/CC7EedYa"   # <-- the hashed password you generated
        username: "shukun"
        userID: "shukun"

kubectl apply -f dex-overrides.yaml

# create role binding
vi admin-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: "shukun@local" # Must match the 'email' field from Step dex-overrides.

kubectl apply -f admin-binding.yaml

# you can login using shukun#local to test
# iwillbeback4u

