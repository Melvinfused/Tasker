# Tasker SRE Runbook / Playbook

> **Scope:** Common remedial actions for the Tasker service running in k3s (`default` namespace).
> **Stack:** Flask + PostgreSQL (Bitnami) · Prometheus + Grafana + Loki (kube-prometheus-stack + Loki-stack) · k3s · Helm

---

## 0 — Prerequisites

```bash
# Set kubeconfig before running any kubectl command
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

---

## 1 — Restart a Crashing Pod

**When to use:** Pod is in `CrashLoopBackOff`, `Error`, or repeatedly restarting.

```bash
# Confirm the pod state
kubectl get pods -n default -l app.kubernetes.io/instance=tasker

# Check logs from the crashed container
kubectl logs -n default deploy/tasker-tasker-chart --previous

# Rolling restart (zero-downtime when replicas > 1)
kubectl rollout restart deployment/tasker-tasker-chart -n default

# Watch until stable
kubectl rollout status deployment/tasker-tasker-chart -n default --timeout=2m
```

**If the pod keeps crashing after restart:** check for a bad ConfigMap (see §3).

---

## 2 — Scale the Deployment

**When to use:** High load causing latency / CPU saturation, or to scale back down to save resources.

```bash
# Scale up to 3 replicas
kubectl scale deployment/tasker-tasker-chart -n default --replicas=3

# Scale back to 1 replica
kubectl scale deployment/tasker-tasker-chart -n default --replicas=1

# Verify
kubectl get pods -n default -l app.kubernetes.io/instance=tasker
```

> **Note:** `replicaCount` in `tasker-chart/values.yaml` is set to `1`.
> Changes via `kubectl scale` are ephemeral; update `values.yaml` and redeploy via Helm to persist.

---

## 3 — Fix a Broken ConfigMap (DB_HOST / ENV)

**When to use:** Alert `TaskerPodCrashLooping` is firing due to an empty or invalid `DB_HOST`.

```bash
# Inspect current configmap values
kubectl describe configmap tasker-tasker-chart-config -n default

# Patch DB_HOST back to the correct service name
kubectl patch configmap tasker-tasker-chart-config -n default \
  --type merge \
  -p '{"data":{"DB_HOST":"tasker-postgresql"}}'

# Restart the deployment to pick up the change
kubectl rollout restart deployment/tasker-tasker-chart -n default
kubectl rollout status deployment/tasker-tasker-chart -n default --timeout=2m
```

---

## 4 — Rollback a Failed Helm Release

**When to use:** A `helm upgrade` caused the application to break.

```bash
# List Helm release history
helm history tasker -n default

# Rollback to the previous revision
helm rollback tasker -n default

# Or rollback to a specific revision number
helm rollback tasker 3 -n default

# Confirm the app is healthy
kubectl rollout status deployment/tasker-tasker-chart -n default --timeout=2m
kubectl get pods -n default
```

---

## 5 — Kill a Rogue CPU Process (Minimal Container)

**When to use:** Alert `TaskerHighCPU` is firing; a stress process is running inside the container but the image has no `kill`/`pkill`.

```bash
# 1. Find the container ID on the node
sudo crictl ps | grep tasker

# 2. Get the host-level PID of the container init process
sudo crictl inspect <container-id> | grep -i '"pid"' | head -1

# 3. Enter the container PID namespace and list all processes
sudo nsenter -t <host-pid> -p -- ps aux

# 4. Kill ONLY the stress-loop PID (NOT gunicorn PID 1 / PID 7)
sudo nsenter -t <host-pid> -p -- /usr/bin/kill -TERM <stress-pid>

# 5. Confirm CPU has returned to baseline
kubectl top pod -n default
```

---

## 6 — Diagnose DB Connectivity Loss

**When to use:** `/readyz` returns 503; Tasker pod is Running but requests fail.

```bash
# Test DB reachability from inside the Tasker pod
kubectl exec -n default deploy/tasker-tasker-chart -- \
  sh -c 'nc -zv tasker-postgresql 5432 && echo "DB reachable" || echo "DB unreachable"'

# Check PostgreSQL pod health
kubectl get pods -n default -l app.kubernetes.io/name=postgresql
kubectl logs -n default -l app.kubernetes.io/name=postgresql --tail=50

# Force-delete a stuck PostgreSQL pod (StatefulSet will recreate it)
kubectl delete pod -n default -l app.kubernetes.io/name=postgresql
```

---

## 7 — Access Observability UIs (Port-Forward)

```bash
# Run the bundled port-forward script (deployed to ~/start-portfwd.sh by CI)
~/start-portfwd.sh
```

| Service      | URL                             | Credentials           |
| :----------- | :------------------------------ | :-------------------- |
| Grafana      | `http://<EC2_IP>:3000`          | admin / prom-operator |
| Prometheus   | `http://<EC2_IP>:9090`          | —                     |
| Alertmanager | `http://<EC2_IP>:9093`          | —                     |
| Tasker App   | `http://<EC2_IP>` (via Traefik) | —                     |

---

## 8 — Query Logs in Loki (Grafana → Explore)

1. Open Grafana → **Explore** → select datasource **Loki**.
2. Use the log browser or enter a LogQL query:

```logql
# All Tasker app logs
{namespace="default", app="tasker-chart"}

# Filter for errors only
{namespace="default", app="tasker-chart"} |= "ERROR"

# DB connection errors (CrashLoop scenario)
{namespace="default", app="tasker-chart"} |= "psycopg2"

# Monitoring namespace logs
{namespace="monitoring"}
```

---

## 9 — Manually Query Alert Rules

```bash
# List all currently active/pending alerts
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool

# Test the CrashLoopBackOff expression
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}' \
  | python3 -m json.tool

# Test the CPU alert expression
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=(rate(container_cpu_usage_seconds_total{container="tasker",image!=""}[2m]) / kube_pod_container_resource_requests{resource="cpu",container="tasker"}) * 100' \
  | python3 -m json.tool
```

---

## 10 — Debug GitHub Actions Pipeline

If the deploy did not proceed after a push to `main`:

1. Go to your repo's **Actions** tab (`https://github.com/<owner>/<repo>/actions`).
2. Inspect the **CI/CD Pipeline** run — check `build-and-deploy` then `Deploy-to-EC2` steps.

| Failure                             | Fix                                                                              |
| :---------------------------------- | :------------------------------------------------------------------------------- |
| `EC2_HOST` / `EC2_KEY` missing      | Add secrets in repo Settings → Secrets & variables → Actions                    |
| Docker image push 403               | Ensure `GITHUB_TOKEN` has `packages: write` or repo is public                   |
| `helm dependency update` fails      | `helm repo add bitnami https://charts.bitnami.com/bitnami` on EC2               |
| `kubectl get nodes` fails           | `sudo systemctl start k3s` on EC2; verify `KUBECONFIG=/etc/rancher/k3s/k3s.yaml` |

---

*Runbook version 1.0 — 2026-09-04*
