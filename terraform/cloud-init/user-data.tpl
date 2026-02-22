#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.lab.local

users:
  - default
  - name: cyee
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
    - ${key}
%{ endfor ~}

chpasswd:
  expire: false
  users:
    - name: cyee
      password: temppassword
      type: text

ssh_pwauth: true