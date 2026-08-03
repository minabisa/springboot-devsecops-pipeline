#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo "Installation failed on line ${LINENO}."' ERR

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with sudo:"
    echo "sudo ./scripts/install-jenkins.sh"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "========================================"
echo " Installing Jenkins Controller"
echo "========================================"

echo "[1/6] Updating Ubuntu..."
apt-get update
apt-get upgrade -y

echo "[2/6] Installing Java 21 and utilities..."
apt-get install -y \
    fontconfig \
    openjdk-21-jdk \
    git \
    curl \
    wget \
    unzip \
    jq \
    ca-certificates \
    gnupg \
    lsb-release

JAVA21_HOME="/usr/lib/jvm/java-21-openjdk-amd64"

if [[ ! -x "${JAVA21_HOME}/bin/java" ]]; then
    JAVA21_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi

cat > /etc/profile.d/java21.sh <<EOF
export JAVA_HOME=${JAVA21_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF

echo "[3/6] Adding Jenkins repository..."

install -d -m 0755 /etc/apt/keyrings

curl -fsSL \
    https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
    -o /etc/apt/keyrings/jenkins-keyring.asc

chmod 644 /etc/apt/keyrings/jenkins-keyring.asc

cat > /etc/apt/sources.list.d/jenkins.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/
EOF

echo "[4/6] Installing Jenkins..."
apt-get update
apt-get install -y jenkins

echo "[5/6] Configuring Jenkins Java runtime..."

mkdir -p /etc/systemd/system/jenkins.service.d

cat > /etc/systemd/system/jenkins.service.d/java.conf <<EOF
[Service]
Environment="JAVA_HOME=${JAVA21_HOME}"
Environment="PATH=${JAVA21_HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF

systemctl daemon-reload
systemctl enable --now jenkins

echo "[6/6] Verifying Jenkins..."

sleep 10

java -version
systemctl is-active --quiet jenkins

echo
echo "Jenkins service status:"
systemctl status jenkins --no-pager --lines=10 || true

echo
echo "Port 8080:"
ss -lntp | grep ':8080' || true

echo
echo "========================================"
echo " Jenkins installation completed"
echo "========================================"
echo
echo "Open Jenkins:"
echo "http://JENKINS_PUBLIC_IP:8080"
echo
echo "Initial administrator password:"

if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
    cat /var/lib/jenkins/secrets/initialAdminPassword
else
    echo "Password file is not available yet."
    echo "Run this command after one minute:"
    echo "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
fi
