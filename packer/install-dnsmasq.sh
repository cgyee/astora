#!/bin/bash
set -ex

echo "=== Installing dnsmasq ==="
apt-get update
apt-get install -y dnsmasq

# Disable dnsmasq service - Ansible will configure and enable it
systemctl disable dnsmasq
systemctl stop dnsmasq || true

echo "=== dnsmasq installed ==="
