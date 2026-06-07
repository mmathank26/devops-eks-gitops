#!/bin/bash
# =============================================================
# ArgoCD Bootstrap Script
# =============================================================
# Run ONCE manually after EKS cluster is provisioned.
# Worker nodes are in PRIVATE subnets.
# ArgoCD and all services are accessed via AWS NLB + ingress-nginx.
# kubectl port-forward is NOT used.
#
# Bootstrap order:
#   1. Apply gp3 StorageClass
#   2. Install ArgoCD via Helm
#   3. Apply root-app (App of Apps)
#   4. ArgoCD deploys ingress-nginx --> AWS provisions NLB
#   5. Configure DNS CNAME --> NLB hostname
#   6. Apply argocd-ingress.yaml
#   7. Access ArgoCD UI via browser
# =============================================================

set -euo pipefail

ARGOCD_VERSION="7.3.11"   # Helm chart version (ArgoCD v2.10.x)
GITOPS_REPO="https://github.com/mmathank26/devops-eks-gitops"
ARGOCD_NAMESPACE="argocd"

# echo "==> [1/6] Verifying kubectl context..."
# kubectl config current-context
# echo ""
# read -p "Is this the correct cluster? (y/n): " confirm
# [[ "$confirm" == "y" ]] || { echo "Aborted."; exit 1; }
# echo ""

echo "==> [2/6] Applying gp3 StorageClass..."
kubectl apply -f ../../infrastructure/storage/gp3-storageclass.yaml
echo ""

echo "==> [3/6] Creating ArgoCD namespace..."
kubectl apply -f namespace.yaml
echo ""

echo "==> [4/6] Adding ArgoCD Helm repo..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
echo ""

echo "==> [5/6] Installing ArgoCD via Helm..."
helm upgrade --install argocd argo/argo-cd \
  --namespace ${ARGOCD_NAMESPACE} \
  --version ${ARGOCD_VERSION} \
  --values values.yaml \
  --wait \
  --timeout 10m
echo ""

echo "==> [6/6] Applying root ArgoCD App (App of Apps)..."
kubectl apply -f ../../argocd-apps/root-app.yaml
echo ""

echo "============================================"
echo "ArgoCD Bootstrap Complete!"
echo "============================================"
echo ""
echo "NOTE: Worker nodes are in private subnets."
echo "ArgoCD is accessed via NGINX Ingress + AWS NLB."
echo ""
echo "==> Waiting for ingress-nginx NLB to be provisioned..."
echo "    ArgoCD root-app will trigger ingress-nginx deployment."
echo ""
echo "    Watch NLB status (run in a separate terminal):"
echo "    kubectl get svc -n ingress-nginx -w"
echo ""
echo "==> Once the NLB EXTERNAL-IP is assigned:"
echo ""
echo "    1. Get the NLB hostname:"
echo "       kubectl get svc -n ingress-nginx ingress-nginx-controller \\"
echo "         -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo ""
echo "    2. Create DNS CNAME records pointing to the NLB hostname:"
echo "       argocd.meghalmathankar.com     -->  <NLB_HOSTNAME>"
echo "       grafana.meghalmathankar.com    -->  <NLB_HOSTNAME>"
echo "       prometheus.meghalmathankar.com -->  <NLB_HOSTNAME>"
echo "       jenkins.meghalmathankar.com    -->  <NLB_HOSTNAME>"
echo ""
echo "    3. Apply the ArgoCD ingress (after ingress-nginx is Running):"
echo "       kubectl apply -f argocd-ingress.yaml"
echo ""
echo "    4. Access ArgoCD UI:"
echo "       http://argocd.meghalmathankar.com"
echo ""
echo "==> Get the initial admin password:"
echo "    kubectl get secret argocd-initial-admin-secret -n argocd \\"
echo "      -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "Next: ArgoCD will GitOps-manage all other components."
echo "Push changes to ${GITOPS_REPO} to trigger deployments."
