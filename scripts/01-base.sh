#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating system packages"
apt-get update
apt-get upgrade -y

echo "==> Installing base packages"
apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    net-tools \
    htop \
    vim

echo "==> Base setup complete"
