#!/bin/bash
set -ex

echo "=== Starting Grafana Alloy install ==="
sudo apt update
sudo apt install gpg -y

sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 644 /etc/apt/keyrings/grafana.asc
echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt-get update
sudo apt-get install alloy -y

sudo systemctl enable alloy.service
sudo systemctl start alloy.service

echo "=== Cleaning up ==="
cloud-init clean
apt-get clean

echo "=== Done ==="
