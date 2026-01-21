# 1. Download the tar file
wget https://github.com/arttor/helmify/releases/download/v0.4.19/helmify_Linux_x86_64.tar.gz

# 2. Extract the tar file
tar -xvzf helmify_Linux_x86_64.tar.gz

# 3. Move the binary to /usr/local/bin (requires sudo)
sudo mv helmify /usr/local/bin/

# 4. Verify installation
helmify --version

# download nginx 
# do this on the internet
docker pull nginx:latest
docker save -o nginx-latest.tar nginx:latest

# Download kubectx
wget https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubectx_v0.9.5_linux_x86_64.tar.gz

# Download kubens
wget https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubens_v0.9.5_linux_x86_64.tar.gz

# Installation of kubectx and kubens
tar -zxvf kubectx_v0.9.5_linux_x86_64.tar.gz
tar -zxvf kubens_v0.9.5_linux_x86_64.tar.gz
sudo chmod 755 kubectx
sudo chmod 755 kubens
sudo cp kubectx /usr/bin/
sudo cp kubens /usr/bin/

# Compress 2 kubeconfig to single kubeconfig
export KUBECONFIG=baremetal.conf:workload01.conf
kubectl config view --flatten > merged-kubeconfig.yaml
cat merged-kubeconfig.yaml
export KUBECONFIG=merged-kubeconfig.yaml
kubectx # you should see 2 contexts available

# Setup autocomplete
mkdir autocomplete_bundle
cd autocomplete_bundle
mkdir -p scripts



dnf download --resolve bash-completion --destdir=./rpms

# Download kubectx and kubens scripts (These are NOT built into the binary)
wget https://raw.githubusercontent.com/ahmetb/kubectx/master/completion/kubectx.bash -O scripts/kubectx.bash
wget https://raw.githubusercontent.com/ahmetb/kubectx/master/completion/kubens.bash -O scripts/kubens.bash

# tar all bundle
tar -czvf autocomplete_kit.tar.gz autocomplete_kit/

# move over to airgapped env
# in airgapp env untar and install the autocomplete
tar -zxvf autocomplete_bundle.tar.gz
# Move the Scripts to a permanent location
sudo rpm -Uvh rpms/*.rpm
mkdir -p ~/.kube/completion
cp scripts/kubectx.bash ~/.kube/completion/
cp scripts/kubens.bash ~/.kube/completion/
vi ~/.bashrc
# --- AUTOCOMPLETE START ---

# 1. Load System Bash Completion (REQUIRED base)
[ -f /usr/share/bash-completion/bash_completion ] && source /usr/share/bash-completion/bash_completion

# 2. Kubectl Autocomplete + Alias 'k'
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k

# 3. Kubectx & Kubens (From the files we moved)
[ -f ~/.kube/completion/kubectx.bash ] && source ~/.kube/completion/kubectx.bash
[ -f ~/.kube/completion/kubens.bash ] && source ~/.kube/completion/kubens.bash

# 4. Helm Autocomplete (Built-in generation)
source <(helm completion bash)

# 5. NKP Autocomplete (Built-in generation)
# Note: Ensure 'nkp' binary is in your PATH
source <(nkp completion bash)

# --- AUTOCOMPLETE END ---

source ~/.bashrc
