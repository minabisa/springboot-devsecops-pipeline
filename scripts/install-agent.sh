bash
#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo:"
  echo "sudo ./install-agent.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "Updating packages..."
apt-get update

echo "Installing Java 11, Maven and required tools..."
apt-get install -y \
  openjdk-11-jdk \
  maven \
  docker.io \
  git \
  curl \
  wget \
  unzip \
  ca-certificates \
  gnupg \
  apt-transport-https

echo "Configuring Java 11..."
JAVA_HOME_PATH="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"

cat > /etc/profile.d/java11.sh <<EOF
export JAVA_HOME=${JAVA_HOME_PATH}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF

export JAVA_HOME="${JAVA_HOME_PATH}"
export PATH="${JAVA_HOME}/bin:${PATH}"

echo "Creating Jenkins agent user..."
if ! id jenkins-agent >/dev/null 2>&1; then
  useradd \
    --create-home \
    --shell /bin/bash \
    jenkins-agent
fi

echo "Configuring Docker..."
systemctl enable --now docker

usermod -aG docker ubuntu
usermod -aG docker jenkins-agent

echo "Preparing Jenkins workspace..."
mkdir -p /home/jenkins-agent/jenkins
chown -R jenkins-agent:jenkins-agent /home/jenkins-agent

echo "Installing Trivy..."
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --dearmor \
  | tee /usr/share/keyrings/trivy.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  > /etc/apt/sources.list.d/trivy.list

apt-get update
apt-get install -y trivy

echo
echo "Installation verification:"
java -version
javac -version
mvn -version
docker --version
git --version
trivy --version

echo
echo "Jenkins agent tools installed successfully."
echo "Log out and reconnect before using Docker without sudo."
