#!/bin/bash
#
# demo-crashloop.sh
# ─────────────────────────────────────────────────────────────────
# INC-001: CrashLoopBackOff — Interactive Demo Script
#
# SCENARIO:
#   Simulates a real-world misconfiguration where the database hostname
#   (DB_HOST) is accidentally wiped from the Kubernetes ConfigMap.
#   Without a valid host, psycopg2 falls back to a local Unix socket
#   that does not exist inside the container, causing the Gunicorn worker
#   to crash on every boot — triggering CrashLoopBackOff.
#
# WHAT THIS SCRIPT DEMONSTRATES:
#   1. Baseline cluster health (pods running, DB_HOST correctly set)
#   2. Fault injection  — ConfigMap patched to DB_HOST=""
#   3. Crash triage     — psycopg2 Unix socket error in pod logs
#   4. Recovery         — ConfigMap restored, pod stabilises
#
# ALERT BEING VALIDATED:
#   Name     : TaskerPodCrashLooping
#   Severity : critical
#   Rule     : kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1
#   Window   : fires after 2 minutes of continuous crashing
#
# USAGE:
#   bash tests/demo-crashloop.sh
#
# NOTE:
#   Press [ENTER] at each pause to advance — this gives you time to
#   switch to Prometheus/Grafana in the browser between steps.
# ─────────────────────────────────────────────────────────────────

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

info() {
  echo "  ℹ  $1"
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
info "Confirming both the Tasker web pod and PostgreSQL are Running with 0 restarts."
info "Also verifying DB_HOST is correctly set to 'tasker-postgresql' in the ConfigMap."
echo ""

echo "Pods:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "Current DB_HOST value in ConfigMap '$CONFIGMAP':"
kubectl get configmap "$CONFIGMAP" -n "$NAMESPACE" \
  -o jsonpath='{.data.DB_HOST}'; echo ""

pause "Baseline looks healthy. Switch to Prometheus/Grafana to show green/inactive alerts, then come back."

# ─────────────────────────────────────────────
# STEP 2 — Inject the fault
# ─────────────────────────────────────────────
banner "STEP 2 of 4 — Injecting Fault (DB_HOST → empty string)"
info "Patching ConfigMap to set DB_HOST=\"\" (empty)."
info "With an empty host, psycopg2/libpq falls back to a local Unix domain socket:"
info "  /var/run/postgresql/.s.PGSQL.5432"
info "That socket does not exist — PostgreSQL runs in a separate pod."
info "The Gunicorn worker will raise psycopg2.OperationalError and exit immediately."
info "Kubelet will restart the container repeatedly → CrashLoopBackOff."
echo ""

kubectl patch configmap "$CONFIGMAP" -n "$NAMESPACE" \
  --type merge \
  -p '{"data":{"DB_HOST":""}}'

kubectl rollout restart deployment/"$DEPLOYMENT" -n "$NAMESPACE"

echo ""
info "Fault injected. Watching pod status for 25s — observe the pod cycling through Error → CrashLoopBackOff."
echo ""

# Watch for up to 25s so the crash is visible on screen
kubectl get pods -n "$NAMESPACE" -w &
WATCH_PID=$!
sleep 25
kill "$WATCH_PID" 2>/dev/null || true
wait "$WATCH_PID" 2>/dev/null || true

echo ""
pause "Pod should be in CrashLoopBackOff. Switch to Prometheus — the 'TaskerPodCrashLooping' alert should be PENDING or FIRING."

# ─────────────────────────────────────────────
# STEP 3 — Triage: inspect logs
# ─────────────────────────────────────────────
banner "STEP 3 of 4 — Triage: Inspect Crash Logs"
info "Fetching logs from the crashing Tasker pod."
info "Key line to look for:"
info "  psycopg2.OperationalError: connection to server on socket"
info "  \"/var/run/postgresql/.s.PGSQL.5432\" failed: No such file or directory"
info "This confirms libpq is using Unix socket mode (triggered by empty DB_HOST),"
info "NOT a network/DNS failure — the PostgreSQL pod itself is perfectly healthy."
echo ""

CRASH_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep 'tasker' | grep -v 'postgresql' | awk 'NR==1{print $1}')

echo "Inspecting logs for pod: $CRASH_POD"
echo ""
kubectl logs -n "$NAMESPACE" "$CRASH_POD" --tail=25 || \
  kubectl logs -n "$NAMESPACE" "$CRASH_POD" --previous --tail=25 || true

pause "Root cause confirmed. DB_HOST was empty → Unix socket fallback → crash. Now let's recover."

# ─────────────────────────────────────────────
# STEP 4 — Recovery
# ─────────────────────────────────────────────
banner "STEP 4 of 4 — Recovery (Restoring DB_HOST)"
info "Patching ConfigMap to restore DB_HOST=tasker-postgresql."
info "This is the Kubernetes Service name that resolves to the PostgreSQL pod via cluster DNS."
info "A new pod will boot, db.create_all() will connect successfully, and 1/1 Running will be restored."
echo ""

kubectl patch configmap "$CONFIGMAP" -n "$NAMESPACE" \
  --type merge \
  -p '{"data":{"DB_HOST":"tasker-postgresql"}}'

kubectl rollout restart deployment/"$DEPLOYMENT" -n "$NAMESPACE"

echo ""
info "Rollout initiated. Waiting for new pod to reach Running state..."
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=90s

echo ""
echo "Final pod state:"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "══════════════════════════════════════════════════"
echo "  ✓  DEMO COMPLETE"
echo "  → Switch to Prometheus — 'TaskerPodCrashLooping' alert should clear to INACTIVE."
echo "  → Switch to Tasker app  — service should be live and accepting requests."
echo "══════════════════════════════════════════════════"
echo ""
