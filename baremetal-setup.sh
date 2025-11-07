# .20 for kubevip
# .21 for metallb
tar -zxvf nkp.tar.gz
cd nkp
tar -zxvf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/bin/
tar -zxvf offline-docker-el9.tar.gz
cd docker-offline/
sudo dnf install -y *.rpm --disablerepo='*' --nogpgcheck
sudo systemctl enable --now docker
# let you run docker without sudo
sudo usermod -aG docker $USER
# log out/in OR:
newgrp docker
#check if docker is enable
docker ps

# configure auto complete 
grep -qxF 'source <(kubectl completion bash)' ~/.bashrc || \
  echo 'source <(kubectl completion bash)' >> ~/.bashrc
grep -qxF 'alias k=kubectl' ~/.bashrc || \
  echo 'alias k=kubectl' >> ~/.bashrc
source ~/.bashrc

cd ..
tar -zxvf nkp-air-gapped-bundle_v2.16.0_linux_amd64.tar.gz
cd nkp-v2.16.0
sudo mv cli/nkp /usr/bin/
nkp version         # to verify nkp version
sudo mv kubectl /usr/bin/
k version           # to verify the kubectl version
# generate ssh pub key so that we can ssh to worker nodes
ssh-keygen 


# in internet connect laptop, run the following command
cd nkp-v2.16.0/kib
./konvoy-image create-package-bundle -os ubuntu-22.04