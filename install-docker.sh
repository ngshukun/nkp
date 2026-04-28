# to install docker for ubuntu noble version
# from internet download the following
#!/bin/bash
# Define version - 27.5.1 is stable for 2026
DOCKER_VERSION="27.5.1"
OUTPUT_FILE="docker-offline-bundle.tar.gz"

echo "Downloading Docker v${DOCKER_VERSION} static binaries..."
curl -L -o docker.tgz "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"

echo "Creating bundle..."
tar -czf $OUTPUT_FILE docker.tgz
rm docker.tgz

# moved the tarball to jumphost
tar -zxvf docker-offline-bundle.tar.gz
tar -xzvf docker.tgz
vi docker.sh
# update the following script
#!/bin/bash
# 1. Extract the binaries
tar -xzvf docker-offline-bundle.tar.gz
tar -xzvf docker.tgz

# 2. Move binaries to executable path
sudo cp docker/* /usr/bin/

# 3. Create the Docker group (for non-root access)
sudo groupadd docker || true
sudo usermod -aG docker $USER

# 4. Create the Systemd service file
cat <<EOF | sudo tee /etc/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF

# 5. Reload and Start
sudo systemctl daemon-reload
sudo systemctl enable --now docker

echo "Verifying installation..."
docker version

# save and exit

chmod +x docker.sh
./docker.sh

