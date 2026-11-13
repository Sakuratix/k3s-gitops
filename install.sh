#!/usr/bin/env bash
# One-node k3s + Argo CD bootstrap. Run on a fresh Ubuntu 22.04/24.04 VM.
# Safe to re-run: every step checks what is already there.
#
# Versions are pinned so the same commit always builds the same cluster;
# bump them here (and in a PR) instead of getting whatever "stable" is today.
set -Eeuo pipefail

K3S_VERSION="${K3S_VERSION:-v1.31.4+k3s1}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.3}"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd "$(dirname "$0")"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root: sudo ./install.sh"
for bin in curl base64; do command -v "$bin" >/dev/null || die "$bin is required"; done
mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
(( mem_mb >= 3500 )) || die "need at least 4 GB RAM for k3s + monitoring, have ${mem_mb} MB"

if command -v k3s >/dev/null && k3s --version | grep -qF "${K3S_VERSION%%+*}"; then
  log "k3s ${K3S_VERSION} already installed"
else
  log "installing k3s ${K3S_VERSION}"
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" \
    INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 0644" sh -
fi
log "waiting for the node to be Ready"
until kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 2; done

log "installing Argo CD ${ARGOCD_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl wait --for condition=established --timeout=120s crd/applications.argoproj.io crd/appprojects.argoproj.io
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s

log "handing the cluster over to git (bootstrap/)"
kubectl apply -n argocd -f bootstrap/

if kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  pass=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
  log "Argo CD admin password: $pass"
  log "change it, then: kubectl -n argocd delete secret argocd-initial-admin-secret"
fi
log "done. Watch the sync: kubectl -n argocd get applications -w"
