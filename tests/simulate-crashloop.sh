#!/bin/bash

set -e

echo "=== Tasker CrashLoop Simulation ==="
echo "[1/3] Backing up current DB_HOST..."

CURRENT_HOST=$(kubectl get configmap tasker-tasker-chart-config \
  -n default \
  -o jsonpath='{.data.DB_HOST}')

echo "Current DB_HOST: $CURRENT_HOST"

echo "[2/3] Setting invalid DB_HOST..."
kubectl patch configmap tasker-tasker-chart-config \
  -n default \
  --type merge \
  -p '{"data":{"DB_HOST":""}}'

echo "[3/3] Restarting Tasker deployment..."
kubectl rollout restart deployment/tasker-tasker-chart -n default

echo ""
echo "CrashLoop simulation triggered."
echo "Watch with:"
echo "kubectl get pods -n default -w"
echo ""
echo "Recover with:"
echo "kubectl patch configmap tasker-tasker-chart-config -n default --type merge -p '{\"data\":{\"DB_HOST\":\"tasker-postgresql\"}}'"
echo "kubectl rollout restart deployment/tasker-tasker-chart -n default"
