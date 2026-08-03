#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo "Installation failed on line ${LINENO}."' ERR

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with sudo:"
    echo "sudo ./scripts/install-sonarqube.sh"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

SONAR_DIR="/opt/sonarqube"
SONAR_ENV="${SONAR_DIR}/.env"
SONAR_COMPOSE="${SONAR_DIR}/compose.yaml"

echo "========================================"
echo " Installing SonarQube"
echo "========================================"

echo "[1/7] Updating Ubuntu..."
apt-get update

echo "[2/7] Removing conflicting Docker packages..."

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

echo "[3/7] Installing required packages..."

apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    openssl \
    jq

echo "[4/7] Installing Docker Engine..."

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

usermod -aG docker ubuntu

echo "[5/7] Configuring SonarQube host requirements..."

cat > /etc/sysctl.d/99-sonarqube.conf <<'EOF'
vm.max_map_count=524288
fs.file-max=131072
EOF

sysctl --system

cat > /etc/security/limits.d/99-sonarqube.conf <<'EOF'
* soft nofile 131072
* hard nofile 131072
* soft nproc 8192
* hard nproc 8192
EOF

echo "[6/7] Creating SonarQube Docker Compose configuration..."

mkdir -p "${SONAR_DIR}"

if [[ ! -f "${SONAR_ENV}" ]]; then
    POSTGRES_PASSWORD="$(openssl rand -hex 24)"

    cat > "${SONAR_ENV}" <<EOF
POSTGRES_USER=sonar
POSTGRES_DB=sonar
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
EOF

    chmod 600 "${SONAR_ENV}"
fi

cat > "${SONAR_COMPOSE}" <<'EOF'
services:
  database:
    image: postgres:16
    container_name: sonarqube-database
    restart: unless-stopped

    env_file:
      - .env

    volumes:
      - postgresql_data:/var/lib/postgresql/data

    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sonar -d sonar"]
      interval: 10s
      timeout: 5s
      retries: 20
      start_period: 20s

    networks:
      - sonarqube-network

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
    driver: bridge

volumes:
  postgresql_data:
  sonarqube_data:
  sonarqube_logs:
  sonarqube_extensions:
EOF

chmod 600 "${SONAR_COMPOSE}"

echo "[7/7] Starting SonarQube..."

cd "${SONAR_DIR}"

docker compose pull
docker compose up -d

echo
echo "Waiting for SonarQube to respond..."

READY=false

for attempt in $(seq 1 60); do
    if curl -fsS http://localhost:9000/api/system/status \
        | grep -q '"status":"UP"'; then
        READY=true
        break
    fi

    echo "Attempt ${attempt}/60: SonarQube is still starting..."
    sleep 10
done

echo
echo "Container status:"
docker compose ps

if [[ "${READY}" == "true" ]]; then
    echo
    echo "========================================"
    echo " SonarQube is ready"
    echo "========================================"
else
    echo
    echo "SonarQube has not reported UP yet."
    echo "Check its logs with:"
    echo "cd ${SONAR_DIR} && sudo docker compose logs -f sonarqube"
fi

echo
echo "Open:"
echo "http://SONARQUBE_PUBLIC_IP:9000"
echo
echo "Initial username: admin"
echo "Initial password: admin"
echo
echo "PostgreSQL credentials are stored in:"
echo "${SONAR_ENV}"
echo
echo "Do not commit ${SONAR_ENV} to Git."
