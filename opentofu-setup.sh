# from internet download the script for rhel 
vi opentofu.sh
#!/bin/bash
# Download Script for RHEL
TOFU_VERSION="1.9.0"
NUTANIX_VER="1.9.5"

mkdir -p airgap_rhel
cd airgap_rhel

# 1. Download OpenTofu Tarball (Works on all Linux distros)
curl -L -O "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.tar.gz"

# 2. Download Nutanix Provider
mkdir -p registry.opentofu.org/nutanix/nutanix/${NUTANIX_VER}/linux_amd64
curl -L -o registry.opentofu.org/nutanix/nutanix/${NUTANIX_VER}/linux_amd64/provider.zip \
"https://github.com/nutanix/terraform-provider-nutanix/releases/download/v${NUTANIX_VER}/terraform-provider-nutanix_${NUTANIX_VER}_linux_amd64.zip"

# from internet download the script for ubuntu
vi opentofu.sh
#!/bin/bash
# Download Script for Ubuntu
TOFU_VERSION="1.9.0"
NUTANIX_VER="1.9.5"

mkdir -p airgap_ubuntu
cd airgap_ubuntu

# 1. Download OpenTofu Tarball
curl -L -O "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.tar.gz"

# 2. Download Nutanix Provider
mkdir -p registry.opentofu.org/nutanix/nutanix/${NUTANIX_VER}/linux_amd64
curl -L -o registry.opentofu.org/nutanix/nutanix/${NUTANIX_VER}/linux_amd64/provider.zip \
"https://github.com/nutanix/terraform-provider-nutanix/releases/download/v${NUTANIX_VER}/terraform-provider-nutanix_${NUTANIX_VER}_linux_amd64.zip"

cd airgap_rhel/
ll
tar -zxvf tofu_1.9.0_linux_amd64.tar.gz
sudo mv tofu /usr/bin/
cd # make sure you in youe /home path
vi .tofurc
provider_installation {
  filesystem_mirror {
    path    = "/home/nutanix/airgap_rhel"
    include = ["registry.opentofu.org/*/*"]
  }
}
tofu init
# expected command.... OpenTofu initialized in an empty directory!

mkdir nkp_vms
cd nkp_vms
vi main.tf
terraform {
  required_providers {
    nutanix = {
      source  = "nutanix/nutanix"
      version = "1.9.5" # Matches your air-gapped setup
    }
  }
}

provider "nutanix" {
  # Credentials should be set via environment variables:
  # export NUTANIX_USERNAME='admin'
  # export NUTANIX_PASSWORD='password'
  # export NUTANIX_ENDPOINT='x.x.x.x'
  insecure     = true
  wait_timeout = 60
}

# ==============================================================================
# 1. CONFIGURATION (EDIT THIS SECTION)
# ==============================================================================
locals {
  # --- Infrastructure ---
  nutanix_cluster_name = "NKP"  # Your Prism Element Cluster Name
  subnet_name          = "Machine_Network_42"  # Your Network Name
  image_name           = "nkp-ubuntu-24.04-release-cis-1.34.1-20251206061851.qcow2" # Your Image Name

  # --- VM Sizing (NKP Minimums) ---
  cp_count    = 3
  cp_vcpu     = 4
  cp_memory   = 8192  # 8 GB (Minimum for Etcd/Control Plane)
  
  worker_count  = 3
  worker_vcpu   = 4
  worker_memory = 16384 # 16 GB (Recommended for workloads)

  # --- Access (CRITICAL) ---
  # Paste your public key here (cat ~/.ssh/id_rsa.pub)
  # This allows NKP to SSH into the nodes to install Kubernetes.
  ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC59r77NH6JCGYh0RBEITUoVI8w1Yi4LG8jVdl1A88M2CKs7wLeA3haeW6QniLmU0vkIDb01VZQAqALZzkeCu3IWqKRbVFxKa9LARIKFPqxSw8ScMcpy0NfAp//GbBHiLie5l3sTj7htnv02tkghD8ZtjJnxjB00r/HC0vzWtlCSI0PSWekwnLZ3BhvKd8TryNdUZ3btiXZ51CVLqXjBHfZjtIil6iP2u/R+ycVW7hSPtLG+xKzHyQ2OUdeTr9jX2r+CBp0R+mCITgyVJL85JLdT2+sxsyhOj1MjWMTYbYNaV6GMbOeOswaOlVoRN6FUURFa9tf8Grv/vHLznn/zqkguKddo+8cjWl5JOtuEMeTUSpF/uiRLHA4EeQHLxP91NjzKzS2aeBUFhRszfTDleZaXSJnRaUp1iHLvhJ4RstZgb/5R0LxYmIVuQCOTfUAq9YsEOoX0ZyR+R+v2mJTz94pZTFLDp31J0t8V1S8Se9fjl3/shfYcgffg7VxPsWQaTM= nutanix@bastion"
}

# ==============================================================================
# 2. DATA SOURCES (LOOKUPS)
# ==============================================================================
data "nutanix_cluster" "cluster" {
  name = local.nutanix_cluster_name
}

data "nutanix_subnet" "subnet" {
  subnet_name = local.subnet_name
}

data "nutanix_image" "os_image" {
  image_name = local.image_name
}

# ==============================================================================
# 3. RESOURCES (VM CREATION)
# ==============================================================================

# --- Control Plane Nodes ---
resource "nutanix_virtual_machine" "control_plane" {
  count        = local.cp_count
  name         = "nkp-cp-${count.index + 1}"
  cluster_uuid = data.nutanix_cluster.cluster.id

  num_sockets          = 1
  num_vcpus_per_socket = local.cp_vcpu
  memory_size_mib      = local.cp_memory

  nic_list {
    subnet_uuid = data.nutanix_subnet.subnet.id
  }

  disk_list {
    data_source_reference = {
      kind = "image"
      uuid = data.nutanix_image.os_image.id
    }
    device_properties {
      device_type = "DISK"
      disk_address = {
        adapter_type = "SCSI"
        device_index = 0
      }
    }
    disk_size_mib = 81920 # 80 GB
  }

  # Inject SSH Key so NKP can login
  guest_customization_cloud_init {
    user_data = base64encode(<<EOF
#cloud-config
ssh_authorized_keys:
  - ${local.ssh_public_key}
users:
  - default
EOF
    )
  }
}

# --- Worker Nodes ---
resource "nutanix_virtual_machine" "worker" {
  count        = local.worker_count
  name         = "nkp-worker-${count.index + 1}"
  cluster_uuid = data.nutanix_cluster.cluster.id

  num_sockets          = 1
  num_vcpus_per_socket = local.worker_vcpu
  memory_size_mib      = local.worker_memory

  nic_list {
    subnet_uuid = data.nutanix_subnet.subnet.id
  }

  disk_list {
    data_source_reference = {
      kind = "image"
      uuid = data.nutanix_image.os_image.id
    }
    device_properties {
      device_type = "DISK"
      disk_address = {
        adapter_type = "SCSI"
        device_index = 0
      }
    }
    disk_size_mib = 102400 # 100 GB
  }

  # Inject SSH Key
  guest_customization_cloud_init {
    user_data = base64encode(<<EOF
#cloud-config
ssh_authorized_keys:
  - ${local.ssh_public_key}
users:
  - default
EOF
    )
  }
}

# ==============================================================================
# 4. OUTPUTS (NEXT STEPS)
# ==============================================================================
output "nkp_command_flags" {
  description = "Copy these flags directly into your 'nkp create cluster' command"
  value = <<EOT

  --control-plane-ips ${join(",", nutanix_virtual_machine.control_plane[*].nic_list[0].ip_endpoint_list[0].ip)} \
  --worker-ips ${join(",", nutanix_virtual_machine.worker[*].nic_list[0].ip_endpoint_list[0].ip)}

EOT
}


tofu init

export NUTANIX_USERNAME='shukun'
export NUTANIX_PASSWORD='P@ssw0rd'
export NUTANIX_ENDPOINT='10.129.42.11:944