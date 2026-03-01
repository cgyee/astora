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
  user_data = templatefile("../cloud-init/user-data.yml.tpl", {
    ssh_public_key = local.ssh_public_key
  })
}

source "qemu" "debian-leader" {
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

  headless    = true
  accelerator = "kvm"
  memory      = 2048
  cpus        = 2
  boot_wait   = "15s"

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
  sources = ["source.qemu.debian-leader"]

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

  # Install Docker for running Grafana stack
  provisioner "shell" {
    script          = "../install-docker.sh"
    execute_command = "sudo sh -c '{{ .Path }}'"
  }

  # Install dnsmasq for local DNS
  provisioner "shell" {
    script          = "../install-dnsmasq.sh"
    execute_command = "sudo sh -c '{{ .Path }}'"
  }

  # Copy Grafana stack files
  provisioner "file" {
    source      = "./docker-compose.yaml"
    destination = "/tmp/docker-compose.yaml"
  }

  provisioner "file" {
    source      = "./provisioning"
    destination = "/tmp/provisioning"
  }

  provisioner "file" {
    source      = "./dashboards"
    destination = "/tmp/dashboards"
  }

  provisioner "file" {
    source      = "./loki-config.yaml"
    destination = "/tmp/loki-config.yaml"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /grafana",
      "sudo mv /tmp/docker-compose.yaml /grafana/docker-compose.yaml",
      "sudo mv /tmp/loki-config.yaml /grafana/loki-config.yaml",
      "sudo mv /tmp/provisioning /grafana/provisioning",
      "sudo mv /tmp/dashboards /grafana/dashboards",
      "sudo chmod -R 644 /grafana/*.yaml /grafana/provisioning/* /grafana/dashboards/*",
      "sudo chmod 755 /grafana /grafana/provisioning /grafana/provisioning/dashboards /grafana/dashboards"
    ]
  }

  # Create systemd service to start Grafana stack on boot
  provisioner "shell" {
    inline = [
      "cat << 'EOF' | sudo tee /etc/systemd/system/grafana-stack.service",
      "[Unit]",
      "Description=Grafana Observability Stack",
      "Requires=docker.service",
      "After=docker.service",
      "",
      "[Service]",
      "Type=oneshot",
      "RemainAfterExit=yes",
      "WorkingDirectory=/grafana",
      "ExecStart=/usr/bin/docker compose up -d",
      "ExecStop=/usr/bin/docker compose down",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable grafana-stack.service"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "sudo cp output/packer-debian-leader /var/lib/libvirt/images/debian-leader.qcow2",
      "rm -rf output",
    ]
  }
}
