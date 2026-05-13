# in rx, if you need to mimit airgap, use the following
sudo iptables -A OUTPUT -o ens3 ! -d 10.161.83.0/24 -m conntrack --ctstate NEW -j REJECT

vi ~/.bashrc

# Toggle Air-Gap
alias unblock-internet='sudo iptables -D OUTPUT -o ens3 ! -d 10.161.83.0/24 -m conntrack --ctstate NEW -j REJECT 2>/dev/null'
alias block-internet='sudo iptables -A OUTPUT -o ens3 ! -d 10.161.83.0/24 -m conntrack --ctstate NEW -j REJECT'

source ~/.bashrc