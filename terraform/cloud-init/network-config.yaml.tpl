version: 2
ethernets:
  enp1s0:
%{ if static_ip != "" ~}
    addresses:
      - ${static_ip}/24
    gateway4: ${gateway}
    nameservers:
      addresses: [${dns_server}]
      search: [lab.local]
%{ else ~}
    dhcp4: true
%{ endif ~}
