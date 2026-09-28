#!/usr/bin/env bash
# OS prep for the "Diagnose Config Sync With proxy-status" playground (`ats-016-playground-030-02`).
#
# Environment preparation only — there is no task and no grading. This script:
#   1. puts `istioctl` on the PATH,
#   2. installs the Istio control plane with the `demo` profile,
#   3. applies the module's starting workloads,
#   4. waits until the namespace has settled.
set -euo pipefail

ISTIO_VERSION="1.30.5"
NAMESPACES="proxysync-demo"
EXTRA_MANIFESTS=""

BIN_DIR="/usr/local/bin"
[ -w "$BIN_DIR" ] || BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

# Pin the version rather than accepting whatever istioctl happens to be on the
# machine: a different client installs a different control plane, and the whole
# course is written against ${ISTIO_VERSION}. BIN_DIR goes first on PATH above,
# so the pinned binary wins over any system-wide one.
have_version=""
command -v istioctl >/dev/null 2>&1 && \
  have_version=$(istioctl version --remote=false 2>/dev/null | awk '/client version/{print $3}')
if [ "$have_version" != "$ISTIO_VERSION" ]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  echo "[playground] Downloading Istio ${ISTIO_VERSION}..."
  (cd "$WORK" && curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIO_VERSION" sh -)
  install -m 0755 "$WORK/istio-${ISTIO_VERSION}/bin/istioctl" "$BIN_DIR/istioctl"
fi
istioctl version --remote=false

echo "[playground] Installing the Istio control plane (demo profile)..."
istioctl install --set profile=demo -y
kubectl -n istio-system rollout status deployment/istiod --timeout=300s

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR=""
for candidate in "$SCRIPT_DIR/../manifests" "./manifests" "$SCRIPT_DIR/manifests"; do
  [ -d "$candidate" ] && { MANIFEST_DIR="$candidate"; break; }
done

# lab-start.yaml is also listed under bootstrap.manifests in config.yaml, so it
# may already be applied. kubectl apply is idempotent, and the rollout restart
# below covers pods created before the injection webhook existed.
if [ -n "$MANIFEST_DIR" ] && [ -f "$MANIFEST_DIR/lab-start.yaml" ]; then
  echo "[playground] Applying starting workloads..."
  kubectl apply -f "$MANIFEST_DIR/lab-start.yaml"
fi

for NAMESPACE in $NAMESPACES; do
  kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || {
    echo "[playground] ERROR: namespace $NAMESPACE was never created." >&2
    exit 1
  }
done

for NAMESPACE in $NAMESPACES; do
  echo "[playground] Settling workloads in $NAMESPACE..."
  kubectl -n "$NAMESPACE" rollout restart deployment --all >/dev/null 2>&1 || true
  for d in $(kubectl -n "$NAMESPACE" get deployment -o name); do
    kubectl -n "$NAMESPACE" rollout status "$d" --timeout=300s
  done
done

# Istio custom resources need the control plane's CRDs, so they are applied
# here rather than through bootstrap.manifests.
if [ -n "$MANIFEST_DIR" ]; then
  for m in $EXTRA_MANIFESTS; do
    [ -f "$MANIFEST_DIR/$m" ] || continue
    echo "[playground] Applying $m..."
    kubectl apply -f "$MANIFEST_DIR/$m"
  done
fi

echo "[playground] Ready."
for NAMESPACE in $NAMESPACES; do
  echo "[playground] Namespace $NAMESPACE:"
  kubectl -n "$NAMESPACE" get pods -o wide
done
echo "[playground] Every proxy starts SYNCED — breaking that link yourself is the module's subject."
