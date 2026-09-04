# Tasker — SRE PoC

> **Flask + PostgreSQL microservice deployed on k3s with full SRE observability:**  
> Prometheus · Grafana · Loki · GitHub Actions CI/CD · Helm · Failure simulations · RCA/Postmortems

---

## Architecture

```
                     ┌──────────────────────────────────────────────────┐
                     │         Ubuntu 22.04 EC2 (2 vCPU, 4 GB RAM)     │
                     │              Default VPC · Public IP             │
                     │  SG: TCP 22 (SSH) · TCP 80 (HTTP)               │
                     │                                                  │
   GitHub Actions ──►│  k3s (single-node)                              │
   (build & push)    │  ┌─────────────┐  ┌────────────────────────┐    │
                     │  │  default ns  │  │    monitoring ns        │    │
                     │  │             │  │                        │    │
   ghcr.io ─────────►│  │  Tasker App │  │  kube-prometheus-stack │    │
   (container image) │  │  (Flask)    │  │  ├─ Prometheus         │    │
                     │  │     ▼       │  │  ├─ Grafana            │    │
                     │  │  PostgreSQL │  │  ├─ Alertmanager        │    │
                     │  │  (Bitnami)  │  │  └─ Loki + Promtail    │    │
                     │  └─────────────┘  └────────────────────────┘    │
                     │         Traefik Ingress (built into k3s)         │
                     └──────────────────────────────────────────────────┘
```

**Design decisions & assumptions:**
- Ubuntu 22.04, 2 vCPU, 4 GB RAM, 40 GB storage — AWS default VPC, public IP
- EC2 Security Group: inbound TCP 22 (SSH) + TCP 80 (HTTP) from `0.0.0.0/0` only
- k3s (lightweight Kubernetes) instead of full K8s — justified by single-node constraint
- GHCR (GitHub Container Registry) for image hosting — no external registry account needed
- Traefik ingress (built into k3s) used instead of nginx-ingress — app accessible on port 80
- Secrets stored only in GitHub Actions Secrets (never in repo)
- PostgreSQL running in-cluster via Bitnami Helm chart
- Prometheus/Grafana/Alertmanager accessed via `kubectl port-forward` (not publicly exposed)

---

## Repository Layout

```
.
├── .github/workflows/deploy.yaml   # CI/CD pipeline (build, push, deploy)
├── Dockerfile                      # Multi-stage Flask app image
├── app.py                          # Flask app (REST + frontend)
├── models.py                       # SQLAlchemy models
├── requirements.txt
├── start-portfwd.sh                # Port-forward script (deployed to VM by CI)
├── tasker-chart/                   # Helm chart
│   ├── Chart.yaml                  # Chart with postgresql as dependency
│   ├── values.yaml                 # Resource limits, probes, DB config
│   └── templates/
│       ├── deployment.yaml         # Deployment with liveness/readiness probes
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── configmap.yaml
│       └── secret.yaml
├── grafana/
│   ├── tasker-service-health.json  # Grafana dashboard: app health & request rate
│   └── cluster-health.json         # Grafana dashboard: node CPU, memory, pods
├── tests/
│   ├── demo-crashloop.sh           # Full guided demo: inject crash + observe alert + recover
│   ├── simulate-crashloop.sh       # Bare crash simulation script
│   └── simulate-high-cpu.sh        # CPU busy-loop injection script
└── docs/
    ├── rca-incident-simulations.md  # Combined RCA/postmortem: INC-001 + INC-002
    ├── rca-crashloop.pdf            # Detailed RCA PDF: CrashLoopBackOff
    ├── rca-high-cpu.pdf             # Detailed RCA PDF: High CPU
    └── runbook.md                   # SRE runbook: restart, scale, rollback, failover, etc.
```

---

## Prerequisites — What You Need Before Starting

| Tool       | Version  | Install                                                    |
| :--------- | :------- | :--------------------------------------------------------- |
| k3s        | latest   | `curl -sfL https://get.k3s.io \| sh -`                    |
| kubectl    | latest   | bundled with k3s (`/usr/local/bin/kubectl`)               |
| helm       | 3.x      | `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` |
| Docker     | 24+      | `sudo apt install docker.io -y` (optional; k3s uses containerd) |

---

## Part 1 — Environment Provisioning (VM Setup)

SSH into your EC2 instance, then:

```bash
# 1. Install k3s
curl -sfL https://get.k3s.io | sh -

# 2. Set kubeconfig (add to ~/.bashrc for persistence)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc

# 3. Verify cluster is up
kubectl get nodes

# 4. Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 5. Add the Bitnami chart repo (used by Tasker's postgresql dependency)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# 6. Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set grafana.adminPassword=prom-operator

# 7. Install Loki + Promtail for log aggregation
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install loki-stack grafana/loki-stack \
  -n monitoring \
  --set promtail.enabled=true \
  --set loki.enabled=true
```

---

## Part 2 — GitHub Actions CI/CD

### Required GitHub Secrets

Set these in your repo under **Settings → Secrets and variables → Actions**:

| Secret        | Description                                  |
| :------------ | :------------------------------------------- |
| `EC2_HOST`    | Public IP of your EC2 instance               |
| `EC2_USER`    | SSH user (e.g., `ubuntu`)                    |
| `EC2_KEY`     | Full private SSH key for EC2 access          |
| `DB_PASSWORD` | PostgreSQL password (never stored in repo)   |

### Pipeline Stages

On every push to `main`:

1. **build-and-deploy** — Builds Docker image and pushes to `ghcr.io/<owner>/tasker:<sha>`
2. **Deploy-to-EC2** — SCP Helm chart + scripts to VM, then SSH and runs `helm upgrade --install`

---

## Part 3 — Deploy the Application

Deployment is fully automated via GitHub Actions on push to `main`.  
To manually redeploy from the EC2 instance:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Update Helm dependencies (postgresql)
helm dependency update ~/tasker-chart

# Deploy / upgrade
helm upgrade --install tasker ~/tasker-chart \
  --set image.repository=ghcr.io/melvinfused/tasker \
  --set image.tag=<git-sha> \
  --set-string db.password='<DB_PASSWORD>' \
  --set-string postgresql.auth.postgresPassword='<DB_PASSWORD>' \
  --timeout 2m

# Verify
kubectl get pods -n default
kubectl rollout status deployment/tasker-tasker-chart -n default
```

**Access the app** (via Traefik Ingress):
```
http://<EC2_PUBLIC_IP>
```

---

## Part 4 — Observability

### Start Port-Forwards

```bash
~/start-portfwd.sh
```

Opens:

| Service      | URL                      | Default Credentials   |
| :----------- | :----------------------- | :-------------------- |
| Grafana      | `http://<EC2_IP>:3000`   | admin / prom-operator |
| Prometheus   | `http://<EC2_IP>:9090`   | —                     |
| Alertmanager | `http://<EC2_IP>:9093`   | —                     |

### Import Grafana Dashboards

1. Grafana → **Dashboards → Import**.
2. Upload `grafana/tasker-service-health.json` → **Tasker Service Health**.
3. Upload `grafana/cluster-health.json` → **Cluster Health**.

### Prometheus Alert Rules

Two custom alert rules are deployed via the Helm chart:

| Alert                  | Expression                                                                    | For | Severity |
| :--------------------- | :---------------------------------------------------------------------------- | :-- | :------- |
| `TaskerPodCrashLooping`| `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1`   | 2m  | critical |
| `TaskerHighCPU`        | `rate(container_cpu_usage_seconds_total{container="tasker"}[2m]) / request > 80%` | 5m  | warning  |

View firing alerts at: `http://<EC2_IP>:9090/alerts`

### View Logs in Loki

1. Grafana → **Explore** → datasource: **Loki**.
2. Example LogQL queries:
   ```logql
   {namespace="default"} |= "ERROR"
   {namespace="default"} |= "psycopg2"
   ```

---

## Part 5 — Failure Simulations

### Incident 1 — CrashLoopBackOff (INC-001)

**Guided demo (recommended for recording):**
```bash
bash tests/demo-crashloop.sh
```

**Bare simulation:**
```bash
bash tests/simulate-crashloop.sh
```

**What it does:** Patches `DB_HOST=""` in the ConfigMap → pod crash-loops → `TaskerPodCrashLooping` alert fires after 2 minutes → ConfigMap restored → pod recovers.

**Expected alert:** `TaskerPodCrashLooping` (severity: critical) visible at `http://<EC2_IP>:9090/alerts`

---

### Incident 2 — High CPU Exhaustion (INC-002)

```bash
bash tests/simulate-high-cpu.sh
```

**What it does:** Injects a `timeout 400` CPU busy-loop into the running container → CPU spikes to the 250m cgroup limit → `TaskerHighCPU` fires after 5 minutes of sustained load → killed via `nsenter` from host.

**Expected alert:** `TaskerHighCPU` (severity: warning)

---

### RCA / Postmortems

See [`docs/rca-incident-simulations.md`](docs/rca-incident-simulations.md) for:
- Full 5-Why root cause analysis for both incidents
- Event timelines
- Alert rule configurations
- Recovery commands
- Action items with owners

PDF copies: [`docs/rca-crashloop.pdf`](docs/rca-crashloop.pdf) · [`docs/rca-high-cpu.pdf`](docs/rca-high-cpu.pdf)

---

## Part 6 — SRE Runbook

See [`docs/runbook.md`](docs/runbook.md) for procedures covering:

- Restart a crashing pod
- Scale the deployment up/down
- Fix a broken ConfigMap
- Helm rollback
- Kill a rogue CPU process (minimal container / `nsenter`)
- Diagnose DB connectivity
- Access Grafana / Prometheus / Alertmanager
- Query logs in Loki
- Debug the GitHub Actions pipeline

---

## Security Notes

| Area | Implementation |
| :--- | :--- |
| **Secrets** | `DB_PASSWORD` stored only in GitHub Actions Secrets; never committed to repo. In-cluster secret (`tasker-tasker-chart-secret`) created at deploy time via `--set-string`. |
| **Container image** | Minimal Alpine-based image; no shell utilities (`kill`, `pkill`) to reduce attack surface. |
| **RBAC** | `serviceAccount.create: false` — app runs under the default service account with no elevated cluster permissions. `kubectl exec` access should be restricted via RBAC in production. |
| **Network** | Traefik only exposes port 80/443. Prometheus/Grafana are NOT exposed publicly — accessed via port-forward only. |
| **Image scanning** | Recommend adding `trivy` image scan step to the GitHub Actions workflow before push. |
| **Secrets in repo** | `.env` is in `.gitignore`. The `.env` file in root is for local development only. |

---

## Teardown

```bash
# Remove the Tasker Helm release
helm uninstall tasker -n default

# Remove the monitoring stack
helm uninstall monitoring -n monitoring
helm uninstall loki-stack -n monitoring

# Remove k3s entirely
/usr/local/bin/k3s-uninstall.sh
```

---

## Assumptions & Deviations

| Item | Decision |
| :--- | :--- |
| VM size | 2 vCPU, 4 GB RAM, 40 GB — spec recommended 4 vCPU but 2 vCPU was sufficient for this workload |
| Container registry | GHCR (GitHub Packages) — no external registry account needed |
| Ingress controller | Traefik (built into k3s) instead of nginx-ingress — built-in, no extra install |
| k3s vs. Minikube | k3s used as specified — closer to production than Minikube |
| DB | In-cluster PostgreSQL (Bitnami Helm chart) — no managed DB required |
| Replica count | `replicaCount: 1` — intentional for clear, unambiguous failure visibility in demo |
| Reviewer access | Tasker app on port 80 (public). Prometheus/Grafana require `kubectl port-forward` via SSH — not publicly exposed (SG only opens 22 + 80) |

---

*Submitted: 2026-09-04 · Delivery estimate: Sep 4, 2026 19:00 IST*
