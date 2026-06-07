# devops-eks-gitops

Production-grade GitOps repository for EKS platform management via ArgoCD.

> **Network Design:** Worker nodes run in **private subnets**. All services are exposed
> externally via an AWS Network Load Balancer (NLB) provisioned by ingress-nginx.
> `kubectl port-forward` is not used.

---

## Repository Structure

```
devops-eks-gitops/
│
├── bootstrap/
│   └── argocd/
│       ├── namespace.yaml        # ArgoCD namespace
│       ├── values.yaml           # ArgoCD Helm values
│       ├── argocd-ingress.yaml   # ArgoCD ingress (applied after NLB is ready)
│       └── install.sh            # One-time bootstrap script
│
├── argocd-apps/                  # App of Apps - ArgoCD manages these
│   ├── root-app.yaml             # Master app (points to this folder)
│   ├── ingress-nginx.yaml        # Ingress controller app  [wave 1]
│   ├── monitoring.yaml           # Prometheus + Grafana app [wave 2]
│   └── jenkins.yaml              # Jenkins CI/CD app        [wave 3]
│
├── infrastructure/
│   ├── ingress-nginx/
│   │   └── values.yaml           # NGINX ingress Helm values (NLB config)
│   ├── monitoring/
│   │   └── values.yaml           # kube-prometheus-stack Helm values
│   └── storage/
│       └── gp3-storageclass.yaml # EBS gp3 StorageClass (cluster default)
│
├── applications/
│   └── jenkins/
│       └── values.yaml           # Jenkins Helm values
│
└── README.md
```

---

## Architecture

```
GitHub (Source of Truth)
        |
        | GitOps sync (every 3 min or webhook)
        v
     ArgoCD
     (root-app)
        |
        |--- [wave 1] ingress-nginx  --> AWS NLB (internet-facing, public subnets)
        |--- [wave 2] monitoring     --> Prometheus + Grafana
        |--- [wave 3] jenkins        --> Jenkins CI/CD
```


### Create Sceret for Redis

Generate a strong random password

```
REDIS_PASSWORD=$(openssl rand -base64 32)
```

Create the secret with the password :
```
kubectl create secret generic argocd-redis \
  --namespace argocd \
  --from-literal=auth="$REDIS_PASSWORD"
```

### Traffic Flow

```
Browser
  |
  | DNS CNAME
  v
AWS NLB (internet-facing, public subnets)
  |
  | Routes to pod IPs (NLB IP target mode)
  v
ingress-nginx (pods in private subnets)
  |
  | Ingress rules by hostname
  v
Service (ArgoCD / Grafana / Prometheus / Jenkins)
```

---

## Prerequisites

Before running bootstrap, ensure the following are in place on your EKS cluster:

- `kubectl` configured and pointing to the correct cluster
- `helm` v3.x installed locally
- EBS CSI Driver add-on enabled on the cluster
- Metrics Server add-on enabled on the cluster
- VPC configured with public and private subnets (tagged correctly for NLB)
- AWS Load Balancer Controller **not** required — NLB is provisioned via legacy service annotations

---

## Before You Start — Replace Placeholders

Search the repo for these two placeholders and replace them:

| Placeholder | Replace With |
|---|---|
| `<YOUR_GITHUB_ORG>` | Your GitHub username or org |
| `meghalmathankar.com` | Your domain (e.g. `example.com`) |

Files containing placeholders:

```
bootstrap/argocd/values.yaml
bootstrap/argocd/argocd-ingress.yaml
argocd-apps/root-app.yaml
argocd-apps/ingress-nginx.yaml
argocd-apps/monitoring.yaml
argocd-apps/jenkins.yaml
infrastructure/monitoring/values.yaml
applications/jenkins/values.yaml
```

---

## Bootstrap (One-Time Setup)

```bash
cd bootstrap/argocd
chmod +x install.sh
./install.sh
```

The script performs these steps in order:

| Step | Action |
|------|--------|
| 1 | Verify kubectl context (prompts for confirmation) |
| 2 | Apply gp3 StorageClass |
| 3 | Create argocd namespace |
| 4 | Add ArgoCD Helm repo |
| 5 | Install ArgoCD via Helm |
| 6 | Apply root-app (App of Apps) |

After the script completes, ArgoCD begins syncing. It deploys ingress-nginx first
(sync-wave 1), which causes AWS to provision a Network Load Balancer.

---

## Post-Bootstrap: Expose ArgoCD via NLB

Once the script finishes, follow these steps to make ArgoCD accessible:

**Step 1 — Watch for the NLB to be provisioned:**
```bash
kubectl get svc -n ingress-nginx -w
# Wait until EXTERNAL-IP changes from <pending> to an AWS hostname
```

**Step 2 — Get the NLB hostname:**
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**Step 3 — Create DNS CNAME records** (in Route53, Cloudflare, etc.):
```
argocd.meghalmathankar.com     -->  <NLB_HOSTNAME>
grafana.meghalmathankar.com    -->  <NLB_HOSTNAME>
prometheus.meghalmathankar.com -->  <NLB_HOSTNAME>
jenkins.meghalmathankar.com    -->  <NLB_HOSTNAME>
```

**Step 4 — Apply the ArgoCD ingress:**
```bash
kubectl apply -f bootstrap/argocd/argocd-ingress.yaml
```

**Step 5 — Access ArgoCD UI:**
```
http://argocd.meghalmathankar.com
```

**Step 6 — Get the initial admin password:**
```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

---

## GitOps Workflow

```
Edit values.yaml or add a new ArgoCD Application
         |
         | git push to main
         v
      GitHub
         |
         | ArgoCD polls / webhook triggers
         v
      ArgoCD detects drift
         |
         | Auto-sync (prune + selfHeal enabled)
         v
      Kubernetes updated
```

To make any change to a deployed component — edit the relevant `values.yaml` and push to `main`.
ArgoCD will reconcile automatically.

---

## Namespaces

| Namespace     | Component            | Managed By        |
|---------------|----------------------|-------------------|
| argocd        | ArgoCD               | Helm (bootstrap)  |
| ingress-nginx | NGINX Ingress + NLB  | ArgoCD (wave 1)   |
| monitoring    | Prometheus + Grafana | ArgoCD (wave 2)   |
| jenkins       | Jenkins CI/CD        | ArgoCD (wave 3)   |
| applications  | Future workloads     | ArgoCD            |

---

## Service URLs

| Service    | URL                              | Default Credentials |
|------------|----------------------------------|---------------------|
| ArgoCD     | http://argocd.meghalmathankar.com     | admin / (secret)    |
| Grafana    | http://grafana.meghalmathankar.com    | admin / changeme    |
| Prometheus | http://prometheus.meghalmathankar.com | none                |
| Jenkins    | http://jenkins.meghalmathankar.com    | admin / changeme    |

> Change default passwords before going to production. Use External Secrets Operator
> with AWS Secrets Manager for production credential management.

---

## Helm Chart Versions

| Component             | Chart                                          | Version |
|-----------------------|------------------------------------------------|---------|
| ArgoCD                | argo/argo-cd                                   | 7.3.11  |
| ingress-nginx         | ingress-nginx/ingress-nginx                    | 4.10.1  |
| kube-prometheus-stack | prometheus-community/kube-prometheus-stack     | 61.7.1  |
| Jenkins               | jenkins/jenkins                                | 5.3.3   |

---

## Adding a New Application

1. Create `applications/<app-name>/values.yaml`
2. Create `argocd-apps/<app-name>.yaml` (ArgoCD Application manifest)
3. Push to `main` — ArgoCD auto-deploys

---

## Future Enhancements

- [ ] External Secrets Operator + AWS Secrets Manager
- [ ] cert-manager (automated TLS certificates)
- [ ] Cluster Autoscaler / Karpenter
- [ ] Loki + Promtail (log aggregation)
- [ ] SonarQube (code quality)
- [ ] Horizontal Pod Autoscaler configs
- [ ] Multi-environment promotion (dev → staging → prod)
- [ ] Service Mesh (Istio / Linkerd)
