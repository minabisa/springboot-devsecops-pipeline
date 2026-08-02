bash
#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo:"
  echo "sudo ./install-sonarqube.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

SONAR_DIRECTORY="/opt/sonarqube"
POSTGRES_PASSWORD="minabisa@8990!"

echo "Updating packages..."
apt-get update

echo "Installing Docker and Docker Compose..."
apt-get install -y \
  docker.io \
  docker-compose-v2 \
  curl \
  ca-certificates

systemctl enable --now docker

echo "Configuring SonarQube host requirements..."

cat > /etc/sysctl.d/99-sonarqube.conf <<EOF
vm.max_map_count=524288
fs.file-max=131072
EOF

sysctl --system

cat > /etc/security/limits.d/99-sonarqube.conf <<EOF
* soft nofile 131072
* hard nofile 131072
* soft nproc 8192
* hard nproc 8192
EOF

echo "Creating SonarQube directory..."
mkdir -p "${SONAR_DIRECTORY}"

cat > "${SONAR_DIRECTORY}/compose.yaml" <<EOF
services:
  database:
    image: postgres:16
    container_name: sonarqube-database
    restart: unless-stopped
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: sonar
    volumes:
      - postgresql_data:/var/lib/postgresql/data
    networks:
      - sonarqube-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sonar -d sonar"]
      interval: 10s
      timeout: 5s
      retries: 10

  sonarqube:
    image: sonarqube:community
    container_name: sonarqube
    restart: unless-stopped
    depends_on:
      database:
        condition: service_healthy
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://database:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "9000:9000"
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_logs:/opt/sonarqube/logs
      - sonarqube_extensions:/opt/sonarqube/extensions
    networks:
      - sonarqube-network

networks:
  sonarqube-network:

volumes:
  postgresql_data:
  sonarqube_data:
  sonarqube_logs:
  sonarqube_extensions:
EOF

chmod 600 "${SONAR_DIRECTORY}/compose.yaml"

echo "Starting SonarQube..."
cd "${SONAR_DIRECTORY}"
docker compose up -d

echo
echo "Container status:"
docker compose ps

echo
echo "SonarQube installation started."
echo "Open: http://SERVER_PUBLIC_IP:9000"
echo "Default username: admin"
echo "Default password: admin"
echo
echo "View startup logs with:"
echo "cd ${SONAR_DIRECTORY} && sudo docker compose logs -f sonarqube"

