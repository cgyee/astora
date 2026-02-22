packer {
    required_plugins {
      qemu = {
        version = ">= 1.0.0"
        source  = "github.com/hashicorp/qemu"
      }
    }
  }

  variable "base_image" {
    type    = string
    default = "/var/lib/libvirt/images/debian-13-generic-amd64.qcow2"
  }

  variable "ssh_public_key_path" {
    type        = string
    default     = "~/.ssh/id_ed25519.pub"
    description = "Path to SSH public key for VM access"
  }

  locals {
    ssh_public_key = file(pathexpand(var.ssh_public_key_path))
    user_data      = templatefile("../cloud-init/user-data.yml.tpl", {
      ssh_public_key = local.ssh_public_key
    })
  }

  source "qemu" "debian-alloy" {
    iso_url          = var.base_image
    iso_checksum     = "none"
    disk_image       = true
    output_directory = "output"
    format           = "qcow2"
    disk_size        = "20G"
    disk_compression = true

    ssh_username           = "debian"
    ssh_password           = "debian"
    ssh_timeout            = "10m"
    ssh_handshake_attempts = 100

    shutdown_command = "sudo shutdown -P now"

    headless       = true
    accelerator    = "kvm"
    memory         = 2048
    cpus           = 2
    boot_wait      = "15s"

    net_device     = "virtio-net"
    disk_interface = "virtio"

    qemuargs = [
      ["-cpu", "host"]
    ]

    cd_content = {
      "user-data"      = local.user_data
      "meta-data"      = ""
      "network-config" = file("../cloud-init/network-config.yml")
    }
    cd_label = "cidata"
  }

  build {
    sources = ["source.qemu.debian-alloy"]

    provisioner "shell" {
      inline = [
        "sudo cloud-init status --wait || true",
        "echo '=== cloud-init logs ==='",
        "sudo cat /var/log/cloud-init-output.log || true",
        "sudo cat /var/log/cloud-init.log | tail -100 || true",
        "echo '=== checking cloud-init status ==='",
        "sudo cloud-init status"
      ]
    }

    provisioner "shell" {
      script          = "../install-docker.sh"
      execute_command = "sudo sh -c '{{ .Path }}'"
    }

    provisioner "shell" {
      script          = "../install-alloy.sh"
      execute_command = "sudo sh -c '{{ .Path }}'"
    }

    post-processor "shell-local" {
      inline = [
        "sudo cp output/packer-debian-alloy /var/lib/libvirt/images/debian-alloy.qcow2",
        "rm -rf output",
      ]
    }
  }
