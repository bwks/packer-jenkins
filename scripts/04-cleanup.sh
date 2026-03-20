#!/bin/bash
set -euo pipefail

echo "==> Cleaning apt cache"
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "==> Cleaning temp files"
rm -rf /tmp/* /var/tmp/*

echo "==> Removing packer build user"
userdel -r packer 2>/dev/null || true

echo "==> Resetting machine-id (regenerated on first boot)"
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "==> Truncating logs"
find /var/log -type f | xargs truncate -s 0 2>/dev/null || true

echo "==> Removing SSH host keys (regenerated on first boot)"
rm -f /etc/ssh/ssh_host_*

echo "==> Resetting cloud-init state (allows re-run on new deployments)"
cloud-init clean --logs

echo "==> Cleanup complete"
