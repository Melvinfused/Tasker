# Tasker SRE Observability — Incident Simulation RCA Summary

> **Exercise:** Controlled failure simulation to validate Prometheus alerting, Kubernetes observability, and SRE response procedures for the Tasker web service running in Kubernetes (`default` namespace).

---

## At a Glance

| Field | INC-001 · CrashLoopBackOff | INC-002 · High CPU Exhaustion |
| :--- | :--- | :--- |
| **Alert** | `TaskerPodCrashLooping` | `TaskerHighCPU` |
| **Severity** | Critical | Warning |
| **Status** | Resolved | Resolved |
| **Root Cause** | Empty `DB_HOST` → Unix socket fallback | Injected CPU busy-loop |
| **Application Impact** | Pod crash + restart loop | Degraded compute, no crash |
| **Detection Window** | 2 minutes | 5 minutes |
| **Recovery** | Patch ConfigMap, rollout restart | `nsenter` process kill on host |

---

## INC-001 — CrashLoopBackOff (`TaskerPodCrashLooping`)

### Summary

The `DB_HOST` environment variable in the `tasker-tasker-chart-config` ConfigMap was patched to an empty string (`""`). On the next pod startup, the Flask application's `db.create_all()` call constructed a PostgreSQL connection URI with an empty host segment. `libpq`/`psycopg2` interprets an empty host as a request for a **local Unix domain socket** (`/var/run/postgresql/.s.PGSQL.5432`), which does not exist in the Tasker container (PostgreSQL runs in a separate pod). The Gunicorn worker exited with code 3, the master process shut down, and Kubelet entered a restart loop — escalating to `CrashLoopBackOff`.

### Timeline

| Timestamp (UTC) | Phase | Event |
| :--- | :--- | :--- |
| ~11:41:5x | Trigger | `DB_HOST` patched to `""`; deployment rollout restarted |
| 11:42:01 | Boot | New pod `tasker-tasker-chart-767bd45c98-lhjn4` started |
| 11:42:03 | Failure | Worker raised `psycopg2.OperationalError`; exited (code 3); Gunicorn master shut down |
| 11:42:03+ | Escalation | Kubelet restarted container; 4 restarts within ~3 minutes |
| ~11:44–11:47 | Detection | `TaskerPodCrashLooping` fired after 2-minute evaluation window |
| 17:12 | Investigation | `kubectl logs` confirmed Unix-socket-fallback error |
| 17:12 | Mitigation | `DB_HOST` patched back to `tasker-postgresql`; deployment restarted |
| 17:13 | Recovery | New pod `tasker-tasker-chart-79df9b776d-2fgvp` reached `1/1 Running`, 0 restarts |

### Root Cause (5 Whys)

1. **Why** did the pod enter `CrashLoopBackOff`? → Application crashed during startup.
2. **Why** did the application crash? → `db.create_all()` raised an unhandled `psycopg2.OperationalError`.
3. **Why** did psycopg2 fail to connect? → It targeted a local Unix socket that does not exist in the container.
4. **Why** was it using a local socket? → Empty host in the DB URI triggers Unix-socket mode in `libpq`.
5. **Why** was the host empty? → `DB_HOST` was patched to `""` in the ConfigMap as part of this simulation.

**Root cause:** No startup-time validation for missing/invalid `DB_HOST`; an empty value is silently accepted and only fails downstream during the DB connection attempt.

### Alert Rule

```yaml
- alert: TaskerPodCrashLooping
  expr: >
    rate(kube_pod_container_status_restarts_total{container="tasker"}[5m]) * 60 > 0
    or kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1
  for: 2m
  labels:
    severity: critical
```

### Recovery Commands

```bash
# Restore correct DB_HOST
kubectl patch configmap tasker-tasker-chart-config -n default \
  --type merge \
  -p '{"data":{"DB_HOST":"tasker-postgresql"}}'

kubectl rollout restart deployment/tasker-tasker-chart -n default
```

### Action Items

| Category | Action | Target | Owner |
| :--- | :--- | :--- | :--- |
| Preventative | Add startup validation in `app.py` asserting `DB_HOST` is non-empty | Application | Dev |
| Preventative | Add `values.schema.json` Helm schema validation to disallow empty `db.host` | Helm Chart | DevOps |
| Detective | Maintain 2-minute `TaskerPodCrashLooping` alert threshold | Monitoring | SRE |
| Operational | Document recovery patch in SRE runbooks | Runbooks | SRE |

---

## INC-002 — High CPU Exhaustion (`TaskerHighCPU`)

### Summary

A bounded CPU busy-loop (`timeout 400 sh -c "while true; do :; done"`) was injected into the running Tasker container via `kubectl exec`. CPU utilization surged from near-idle (~1m) to the container's cgroup hard limit (~250m), far exceeding the alert threshold of 80m (80% of the 100m CPU request). The Gunicorn application process continued serving requests throughout — no crash or restart occurred. After the 5-minute sustained evaluation window, Prometheus transitioned `TaskerHighCPU` to **FIRING**. Because the container image lacks `kill`/`pkill` binaries, the stress process was terminated from the host using `nsenter` (targeting only the stress-loop PIDs), leaving Gunicorn untouched. CPU returned to baseline (~1m) immediately.

### Resource Configuration

| Parameter | Value |
| :--- | :--- |
| CPU Request | `100m` |
| CPU Limit | `250m` |
| Memory Request | `128Mi` |
| Memory Limit | `256Mi` |
| Alert Threshold | `80m` (80% of request) |
| Observed Peak | `~250m` (at cgroup limit) |

### Timeline

| Phase | Event |
| :--- | :--- |
| Trigger | `simulate-high-cpu.sh` executed; CPU busy-loop injected via `kubectl exec` |
| Impact | CPU rose from ~1m to ~250m (cgroup limit) |
| Sustained Load | Elevated CPU persisted for the full 5-minute alert evaluation window |
| Detection | `TaskerHighCPU` transitioned to **FIRING** (severity: warning) |
| Investigation | `kubectl get pods` + `kubectl top pod` confirmed `1/1 Running`, 0 restarts; stress loop identified in process list |
| Mitigation | `nsenter` used from host to `SIGTERM` stress-loop PIDs (15, 16); Gunicorn PIDs (1, 7) untouched |
| Recovery | CPU dropped to ~1m; pod remained `1/1 Running` throughout |
| Resolution | `TaskerHighCPU` cleared to **INACTIVE** once CPU stayed below 80m threshold |

### Root Cause (5 Whys)

1. **Why** did Prometheus raise `TaskerHighCPU`? → CPU exceeded 80m continuously for >5 minutes.
2. **Why** was CPU elevated? → A non-yielding shell busy-loop was executing inside the container.
3. **Why** was the loop running? → Deliberately injected via `kubectl exec` as a controlled simulation.
4. **Why** did the application keep serving? → The cgroup throttled the stress process without killing it; Gunicorn retained its CPU share independently.
5. **Why** was `nsenter` required for resolution? → The production container image intentionally omits `kill`/`pkill`, requiring host-level PID namespace access.

**Root cause:** A deliberately injected CPU-bound process consumed container compute up to the configured limit. This is the intended simulation outcome — it validates that Prometheus correctly detects sustained resource pressure that does not crash the application.

### Alert Rule

```yaml
- alert: TaskerHighCPU
  expr: >
    (
      rate(container_cpu_usage_seconds_total{container="tasker", image!=""}[2m])
      /
      kube_pod_container_resource_requests{resource="cpu", container="tasker"}
    ) * 100 > 80
  for: 5m
  labels:
    severity: warning
```

### Recovery Commands

```bash
# 1. Find the container's host PID via the container runtime
crictl ps  # filter to Tasker pod
crictl inspect <container-id>  # retrieve host PID

# 2. Enter the container's PID namespace and terminate ONLY the stress-loop PIDs
sudo nsenter -t 71259 -p -- /usr/bin/kill -TERM 15 16
# NOTE: Gunicorn PIDs (1, 7) were deliberately excluded
```

### Action Items

| Category | Action | Target | Owner |
| :--- | :--- | :--- | :--- |
| Detective | Keep `TaskerHighCPU` at 80% of request with 5m window — correctly caught sustained pressure without false alarms | Prometheus | SRE |
| Architectural | Evaluate HPA targeting ~80% CPU to auto-scale under genuine sustained load | Kubernetes | DevOps |
| Security | Restrict `kubectl exec` RBAC privileges in production to prevent unauthorized process injection | RBAC / Cluster | SecOps |
| Operational | Document `nsenter`/`crictl` procedure in SRE runbook for zero-downtime rogue-process termination on minimal container images | Runbooks | SRE |

---

## Key Observations & Lessons Learned

| Observation | Incident |
| :--- | :--- |
| Prometheus alerting caught **both** failure modes without manual intervention | INC-001 & INC-002 |
| CrashLoopBackOff detection (2 min window) is correctly tuned — fast enough to catch rapid cycling | INC-001 |
| High CPU detection (5 min window) avoids false positives from transient bursts while still catching sustained pressure | INC-002 |
| PostgreSQL pod remained healthy throughout both incidents — isolation between DB and app layer worked as expected | INC-001 & INC-002 |
| Minimal container images (no `kill`/`pkill`) improve security posture but require documented host-level mitigation procedures | INC-002 |
| An empty `DB_HOST` silently causes a Unix-socket fallback instead of failing loudly — startup validation is a critical gap | INC-001 |

---

*Generated from RCA PDFs: `rca-high-cpu.pdf` · `rca-crashloop.pdf`*  
*Date: 2026-09-04*
