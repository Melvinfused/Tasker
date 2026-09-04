#!/bin/bash
#
# demo-crashloop.sh
# Interactive stepped demo script for INC-001 (CrashLoopBackOff) simulation.
# Run this on your VM in a dedicated terminal window.
# Press [ENTER] at each step to advance — this gives you time to switch to
# Prometheus/Grafana in the browser between steps.
#
# Usage: bash tests/demo-crashloop.sh

set -e

NAMESPACE="default"
CONFIGMAP="tasker-tasker-chart-config"
DEPLOYMENT="tasker-tasker-chart"

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
banner() {
  echo ""
  echo "══════════════════════════════════════════════════"
  echo "  $1"
  echo "══════════════════════════════════════════════════"
}

pause() {
  echo ""
  read -rp "  ▶  $1  [Press ENTER to continue] "
  echo ""
}

# ─────────────────────────────────────────────
# STEP 1 — Baseline health check
# ─────────────────────────────────────────────
banner "STEP 1 of 4 — Baseline Health Check"

echo "Pods:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "Current DB_HOST value:"
kubectl get configmap "$CONFIGMAP" -n "$NAMESPACE" \
  -o jsonpath='{.data.DB_HOST}'; echo ""

pause "Baseline looks healthy. Switch to Prometheus/Grafana to show green alerts, then come back."

# ─────────────────────────────────────────────
# STEP 2 — Inject the fault
# ─────────────────────────────────────────────
banner "STEP 2 of 4 — Injecting Fault (DB_HOST → empty string)"

kubectl patch configmap "$CONFIGMAP" -n "$NAMESPACE" \
  --type merge \
  -p '{"data":{"DB_HOST":""}}'

kubectl rollout restart deployment/"$DEPLOYMENT" -n "$NAMESPACE"

echo ""
echo "Fault injected. Watching pod status (Ctrl+C to stop watch)..."
echo ""

# Watch for up to 30s so the crash is visible on screen
kubectl get pods -n "$NAMESPACE" -w &
WATCH_PID=$!
sleep 25
kill "$WATCH_PID" 2>/dev/null || true
wait "$WATCH_PID" 2>/dev/null || true

echo ""
pause "Pod should be in CrashLoopBackOff. Switch to Prometheus — you should see the alert PENDING/FIRING."

# ─────────────────────────────────────────────
# STEP 3 — Triage: inspect logs
# ─────────────────────────────────────────────
banner "STEP 3 of 4 — Triage: Inspect Crash Logs"

CRASH_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep 'tasker' | grep -v 'postgresql' | awk 'NR==1{print $1}')

echo "Inspecting logs for pod: $CRASH_POD"
echo ""
kubectl logs -n "$NAMESPACE" "$CRASH_POD" --tail=25 || \
  kubectl logs -n "$NAMESPACE" "$CRASH_POD" --previous --tail=25 || true

pause "Note the 'No such file or directory' Unix socket error. Now let's recover."

# ─────────────────────────────────────────────
# STEP 4 — Recovery
# ─────────────────────────────────────────────
banner "STEP 4 of 4 — Recovery (Restoring DB_HOST)"

kubectl patch configmap "$CONFIGMAP" -n "$NAMESPACE" \
  --type merge \
  -p '{"data":{"DB_HOST":"tasker-postgresql"}}'

kubectl rollout restart deployment/"$DEPLOYMENT" -n "$NAMESPACE"

echo ""
echo "Waiting for rollout to complete..."
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=90s

echo ""
echo "Final pod state:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "══════════════════════════════════════════════════"
echo "  ✓  DEMO COMPLETE"
echo "  Switch to Prometheus — alert should clear."
echo "  Switch to Tasker app — service should be live."
echo "══════════════════════════════════════════════════"
echo ""
