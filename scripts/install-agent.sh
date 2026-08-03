#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo "Installation failed on line ${LINENO}."' ERR

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with sudo:"
    echo "sudo ./scripts/install-agent.sh"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

JENKINS_AGENT_USER="jenkins-agent"
JENKINS_AGENT_HOME="/home/${JENKINS_AGENT_USER}"
JENKINS_WORKDIR="${JENKINS_AGENT_HOME}/jenkins"
SONAR_SCANNER_VERSION="7.1.0.4889"
SONAR_SCANNER_DIR="/opt/sonar-scanner"

echo "========================================"
echo " Installing Jenkins Build Agent"
echo "========================================"

echo "[1/9] Updating Ubuntu..."
apt-get update

echo "[2/9] Removing conflicting Docker packages..."

for package in \
    docker.io \
    docker-compose \
    docker-compose-v2 \
    docker-doc \
    podman-docker \
    containerd \
    runc
do
    apt-get remove -y "${package}" 2>/dev/null || true
done

echo "[3/9] Installing Java, Maven and utilities..."

apt-get install -y \
    openjdk-11-jdk \
    openjdk-21-jdk \
    maven \
    git \
    curl \
    wget \
    unzip \
    jq \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    openssh-server

systemctl enable --now ssh

echo "[4/9] Installing Docker Engine..."

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable
EOF

apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable --now docker

echo "[5/9] Creating Jenkins agent user..."

if ! id "${JENKINS_AGENT_USER}" >/dev/null 2>&1; then
    useradd \
        --create-home \
        --home-dir "${JENKINS_AGENT_HOME}" \
        --shell /bin/bash \
        "${JENKINS_AGENT_USER}"
fi

usermod -aG docker "${JENKINS_AGENT_USER}"
usermod -aG docker ubuntu

mkdir -p "${JENKINS_WORKDIR}"
mkdir -p "${JENKINS_AGENT_HOME}/.ssh"

touch "${JENKINS_AGENT_HOME}/.ssh/authorized_keys"

chmod 700 "${JENKINS_AGENT_HOME}/.ssh"
chmod 600 "${JENKINS_AGENT_HOME}/.ssh/authorized_keys"

chown -R \
    "${JENKINS_AGENT_USER}:${JENKINS_AGENT_USER}" \
    "${JENKINS_AGENT_HOME}"

echo "[6/9] Configuring Java versions..."

cat > /etc/profile.d/java-build-tools.sh <<'EOF'
export JAVA11_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export JAVA21_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
EOF

cat > "${JENKINS_AGENT_HOME}/.mavenrc" <<'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
EOF

chown \
    "${JENKINS_AGENT_USER}:${JENKINS_AGENT_USER}" \
    "${JENKINS_AGENT_HOME}/.mavenrc"

echo "[7/9] Installing Trivy..."

curl -fsSL \
    https://aquasecurity.github.io/trivy-repo/deb/public.key \
    | gpg --dearmor \
    -o /usr/share/keyrings/trivy.gpg

chmod 644 /usr/share/keyrings/trivy.gpg

cat > /etc/apt/sources.list.d/trivy.list <<'EOF'
deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main
EOF

apt-get update
apt-get install -y trivy

echo "[8/9] Installing SonarScanner CLI..."

ARCH="$(uname -m)"

case "${ARCH}" in
    x86_64)
        SONAR_ARCH="linux-x64"
        ;;
    aarch64|arm64)
        SONAR_ARCH="linux-aarch64"
        ;;
    *)
        echo "Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

SONAR_ZIP="sonar-scanner-cli-${SONAR_SCANNER_VERSION}-${SONAR_ARCH}.zip"
SONAR_URL="https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/${SONAR_ZIP}"

rm -rf "${SONAR_SCANNER_DIR}"
rm -f "/tmp/${SONAR_ZIP}"

curl -fL "${SONAR_URL}" -o "/tmp/${SONAR_ZIP}"

unzip -q "/tmp/${SONAR_ZIP}" -d /opt

mv \
    "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}-${SONAR_ARCH}" \
    "${SONAR_SCANNER_DIR}"

chown -R \
    "${JENKINS_AGENT_USER}:${JENKINS_AGENT_USER}" \
    "${SONAR_SCANNER_DIR}"

chmod +x "${SONAR_SCANNER_DIR}/bin/sonar-scanner"

ln -sf \
    "${SONAR_SCANNER_DIR}/bin/sonar-scanner" \
    /usr/local/bin/sonar-scanner

echo "[9/9] Configuring 4 GB swap..."

if ! swapon --show | grep -q '/swapfile'; then
    if [[ ! -f /swapfile ]]; then
        fallocate -l 4G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
    fi

    swapon /swapfile
fi

if ! grep -q '^/swapfile ' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo
echo "========================================"
echo " Verification"
echo "========================================"

echo
echo "Java 21 for the Jenkins agent:"
/usr/lib/jvm/java-21-openjdk-amd64/bin/java -version

echo
echo "Java 11 for Maven builds:"
/usr/lib/jvm/java-11-openjdk-amd64/bin/java -version

echo
echo "Maven:"
mvn -version

echo
echo "Docker:"
docker --version
docker compose version

echo
echo "Git:"
git --version

echo
echo "Trivy:"
trivy --version

echo
echo "SonarScanner with Java 21:"
sudo -u "${JENKINS_AGENT_USER}" env \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:/usr/local/bin:/usr/bin:/bin \
    "${SONAR_SCANNER_DIR}/bin/sonar-scanner" --version

echo
echo "Memory and swap:"
free -h

echo
echo "Agent user:"
id "${JENKINS_AGENT_USER}"

echo
echo "Workspace:"
ls -ld "${JENKINS_WORKDIR}"

echo
echo "========================================"
echo " Jenkins agent installation completed"
echo "========================================"
echo
echo "Use this remote root directory in Jenkins:"
echo "${JENKINS_WORKDIR}"
echo
echo "Use this Java path when launching the agent:"
echo "/usr/lib/jvm/java-21-openjdk-amd64/bin/java"
echo
echo "Log out and reconnect before using Docker as ubuntu."
