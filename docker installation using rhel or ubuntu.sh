# to install docker for rhel
tar -zxvf offline-docker-rhel96.tar.gz
cd docker-rhel96-offline
sudo dnf install -y \
  container-selinux*.rpm iptables*.rpm nftables*.rpm \
  fuse3*.rpm fuse-overlayfs*.rpm slirp4netns*.rpm \
  libnetfilter_conntrack*.rpm libnfnetlink*.rpm libnftnl*.rpm \
  conntrack-tools*.rpm libmnl*.rpm jansson*.rpm \
  containerd.io-*.rpm docker-ce-cli-*.rpm \
  docker-buildx-plugin-*.rpm docker-compose-plugin-*.rpm \
  docker-ce-*.rpm \
  --disablerepo='*' --nogpgcheck \
&& sudo systemctl daemon-reexec \
&& sudo systemctl enable --now docker
rpm -q container-selinux selinux-policy selinux-policy-base selinux-policy-targeted nftables python3-nftables
ls -1 | egrep 'libnetfilter_(cthelper|cttimeout|queue)-.*\.rpm' || true
sudo dnf install -y ./libnetfilter_cthelper-*.rpm ./libnetfilter_cttimeout-*.rpm ./libnetfilter_queue-*.rpm \
  --disablerepo='*' --nogpgcheck
sudo dnf install -y \
  iptables*.rpm \
  fuse3*.rpm fuse-overlayfs*.rpm slirp4netns*.rpm \
  libnetfilter_conntrack*.rpm libnfnetlink*.rpm libnftnl*.rpm \
  conntrack-tools*.rpm libmnl*.rpm jansson*.rpm \
  containerd.io-*.rpm docker-ce-cli-*.rpm \
  docker-buildx-plugin-*.rpm docker-compose-plugin-*.rpm \
  docker-ce-*.rpm \
  --disablerepo='*' --nogpgcheck

sudo systemctl daemon-reexec
sudo systemctl enable --now docker
docker version

# to install docker for ubuntu
