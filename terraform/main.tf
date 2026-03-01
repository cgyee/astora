terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.2"
    }
  }
}

provider "libvirt" {
  uri = "qemu+sshcmd://solaire@astora/system"
}

variable "vms" {
  default = {
    leader       = { mac = "52:54:00:11:22:00", memory = 4194304, vcpu = 2, base_image = "debian-leader", static_ip = "192.168.173.50" }
    bastion-vm   = { mac = "52:54:00:11:22:33", memory = 2097152, vcpu = 2, base_image = "debian-docker", static_ip = "" }
    general-vm-1 = { mac = "52:54:00:11:22:44", memory = 2097152, vcpu = 2, base_image = "debian-docker", static_ip = "" }
    general-vm-2 = { mac = "52:54:00:11:22:55", memory = 2097152, vcpu = 2, base_image = "debian-docker", static_ip = "" }
    general-vm-3 = { mac = "52:54:00:11:22:66", memory = 2097152, vcpu = 2, base_image = "debian-docker", static_ip = "" }
  }
}

variable "network" {
  default = {
    gateway    = "192.168.173.1"
    dns_server = "192.168.173.50" # leader
  }
}

variable "ssh_public_key_paths" {
  type        = list(string)
  default     = ["~/.ssh/id_ed25519.pub"]
  description = "Paths to SSH public keys for VM access"
}

locals {
  ssh_keys = [for path in var.ssh_public_key_paths : trimspace(file(pathexpand(path)))]
}

# VM disks (copy-on-write from base)
resource "libvirt_volume" "vm_disk" {
  for_each = var.vms
  name     = "${each.key}-disk.qcow2"
  pool     = "images"
  capacity = 21474836480

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = "/var/lib/libvirt/images/${each.value.base_image}.qcow2"
    format = {
      type = "qcow2"
    }
  }
}

# Cloud-init disks
resource "libvirt_cloudinit_disk" "init" {
  for_each = var.vms
  name     = "${each.key}-cloudinit"

  user_data = templatefile("${path.module}/cloud-init/user-data.tpl", {
    hostname = each.key
    ssh_keys = local.ssh_keys
  })

  meta_data = templatefile("${path.module}/cloud-init/meta-data.tpl", {
    hostname = each.key
  })

  network_config = templatefile("${path.module}/cloud-init/network-config.yaml.tpl", {
    static_ip  = each.value.static_ip
    gateway    = var.network.gateway
    dns_server = var.network.dns_server
  })
}

# Cloud-init volumes (ISO from cloudinit_disk)
resource "libvirt_volume" "cloudinit" {
  for_each = var.vms
  name     = "${each.key}-cloudinit.iso"
  pool     = "images"

  create = {
    content = {
      url = libvirt_cloudinit_disk.init[each.key].path
    }
  }
}

# VMs
resource "libvirt_domain" "vm" {
  for_each = var.vms
  name     = each.key
  memory   = each.value.memory
  vcpu     = each.value.vcpu
  type     = "kvm"

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.vm_disk[each.key].pool
            volume = libvirt_volume.vm_disk[each.key].name
          }
        }
        target = {
          bus = "virtio"
          dev = "vda"
        }
        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.cloudinit[each.key].pool
            volume = libvirt_volume.cloudinit[each.key].name
          }
        }
        target = {
          bus = "sata"
          dev = "sda"
        }
      }
    ]

    interfaces = [
      {
        type = "bridge"
        mac = {
          address = each.value.mac
        }
        model = {
          type = "virtio"
        }
        source = {
          bridge = {
            bridge = "br0"
          }
        }
      }
    ]

    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]

    consoles = [
      {
        target = {
          type = "virtio"
          port = 0
        }
      }
    ]
  }

  running = true
}

output "vms" {
  value = {
    for k, v in var.vms : k => {
      mac  = v.mac
      vcpu = v.vcpu
    }
  }
}
