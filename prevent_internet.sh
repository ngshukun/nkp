#to prevent internet access for your bastion
# 1. Allow internal "loopback" traffic (Required for many Linux services)
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# 2. Allow established sessions
# This ensures that if you send a request, the "reply" is allowed back in/out
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 3. Allow SSH (Port 22) from your specific management subnet
# Replace 10.161.74.0/24 with your actual management/workstation network
sudo iptables -A INPUT -p tcp --dport 22 -s 10.161.74.0/24 -j ACCEPT

# 4. Allow NKP/K8s API traffic
# NKP usually needs to talk to the Nutanix VIP and Cluster VIPs
sudo iptables -A OUTPUT -d 10.161.74.0/24 -j ACCEPT

# 5. DROP everything else going to the Internet
# This blocks any traffic leaving the bastion that isn't for your local subnet
sudo iptables -A OUTPUT -o ens3 ! -d 10.161.74.0/24 -j DROP

# to allow internet
sudo iptables -F
