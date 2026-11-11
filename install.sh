#!/usr/bin/env bash
# One-node k3s + Argo CD bootstrap. Run on a fresh Ubuntu 22.04/24.04 VM.
set -Eeuo pipefail
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 0644" sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl apply -n argocd -f bootstrap/root-app.yaml
echo "argocd admin password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
