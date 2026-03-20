#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing OpenJDK 21"
apt-get install -y openjdk-21-jdk-headless

JAVA_HOME_PATH=$(dirname $(dirname $(readlink -f $(which java))))
echo "JAVA_HOME=${JAVA_HOME_PATH}" >> /etc/environment
export JAVA_HOME="${JAVA_HOME_PATH}"

echo "==> Java version: $(java -version 2>&1 | head -1)"
echo "==> Java install complete"
