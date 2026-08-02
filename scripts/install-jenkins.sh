bash
#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo:"
  echo "sudo ./install-jenkins.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "Updating packages..."
apt-get update

echo "Installing Java 21 and required tools..."
apt-get install -y \
  fontconfig \
  openjdk-21-jre \
  git \
  curl \
  wget \
  unzip \
  ca-certificates \
  gnupg

echo "Adding Jenkins repository..."
install -d -m 0755 /etc/apt/keyrings

wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

echo "Installing Jenkins..."
apt-get update
apt-get install -y jenkins

echo "Enabling Jenkins..."
systemctl enable --now jenkins

echo
echo "Installation verification:"
java -version
systemctl is-active jenkins

echo
echo "Jenkins installation completed."
echo "Open: http://SERVER_PUBLIC_IP:8080"
echo
echo "Initial administrator password:"
cat /var/lib/jenkins/secrets/initialAdminPassword

