#cloud-config
users:
  - default
  - name: debian
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${ssh_public_key}

chpasswd:
  expire: false
  users:
    - name: debian
      password: debian
      type: text

ssh_pwauth: true
