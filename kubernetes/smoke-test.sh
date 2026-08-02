#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="springboot-devsecops"
SERVICE="springboot-devsecops"
LOCAL_PORT="18080"
REMOTE_PORT="8080"
HEALTH_PATH="/swagger-ui.html"

cleanup() {
  if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
    kill "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi
}

trap cleanup EXIT

echo "Waiting for deployment rollout..."

kubectl rollout status \
  deployment/springboot-devsecops \
  --namespace "${NAMESPACE}" \
  --timeout=180s

echo "Starting port-forward..."

kubectl port-forward \
  --namespace "${NAMESPACE}" \
  "service/${SERVICE}" \
  "${LOCAL_PORT}:${REMOTE_PORT}" \
  > /tmp/springboot-port-forward.log 2>&1 &

PORT_FORWARD_PID=$!

sleep 5

echo "Running smoke test..."

HTTP_STATUS="$(curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}" \
  "http://localhost:${LOCAL_PORT}${HEALTH_PATH}")"

if [[ "${HTTP_STATUS}" == "200" || "${HTTP_STATUS}" == "302" ]]; then
  echo "Smoke test passed. HTTP status: ${HTTP_STATUS}"
else
  echo "Smoke test failed. HTTP status: ${HTTP_STATUS}"
  cat /tmp/springboot-port-forward.log
  exit 1
fi