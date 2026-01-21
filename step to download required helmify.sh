# 1. Download the tar file
wget https://github.com/arttor/helmify/releases/download/v0.4.19/helmify_Linux_x86_64.tar.gz

# 2. Extract the tar file
tar -xvzf helmify_Linux_x86_64.tar.gz

# 3. Move the binary to /usr/local/bin (requires sudo)
sudo mv helmify /usr/local/bin/

# 4. Verify installation
helmify --version