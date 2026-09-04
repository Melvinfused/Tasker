#!/bin/bash

set -e

echo "=== Tasker High CPU Simulation ==="
echo "[1/2] Starting bounded CPU stress process..."

kubectl exec -n default deploy/tasker-tasker-chart -- \
  sh -c 'timeout 400 sh -c "while true; do :; done"'

echo ""
echo "CPU stress simulation finished."
echo "Verify recovery with:"
echo "kubectl top pod -n default"
echo ""
echo "Check the alert with:"
echo "curl -s http://localhost:9090/api/v1/alerts"
