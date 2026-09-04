#!/bin/bash

echo "Cleaning up any existing listeners on 3000/9090/9093..."
sudo ss -tlnp | grep -E ':3000|:9090|:9093' | grep -oP 'pid=\K[0-9]+' | xargs -r sudo kill -9
sleep 1

echo "Starting port-forwards..."
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 --address 0.0.0.0 > /tmp/pf-grafana.log 2>&1 &
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 --address 0.0.0.0 > /tmp/pf-prom.log 2>&1 &
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093 --address 0.0.0.0 > /tmp/pf-am.log 2>&1 &
sleep 2

echo ""
echo "=== jobs ==="
jobs -l

echo ""
echo "=== sanity check ==="
for entry in "3000:Grafana:/tmp/pf-grafana.log" "9090:Prometheus:/tmp/pf-prom.log" "9093:Alertmanager:/tmp/pf-am.log"; do
  port=$(echo "$entry" | cut -d: -f1)
  name=$(echo "$entry" | cut -d: -f2)
  log=$(echo "$entry" | cut -d: -f3)
  if grep -q "Forwarding from" "$log" && ! grep -q "error" "$log"; then
    echo "[OK]   $name ($port)"
  else
    echo "[FAIL] $name ($port) — see $log"
    cat "$log"
  fi
done
