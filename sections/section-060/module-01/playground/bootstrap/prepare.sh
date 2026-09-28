#!/usr/bin/env bash
# OS prep for the "Troubleshoot With Kiali" playground (`ats-016-playground-060-01`).
#
# Environment preparation only — there is no task and no grading. This script:
#   1. puts `istioctl` on the PATH,
#   2. installs the Istio control plane with the `demo` profile,
#   3. installs the Prometheus and Kiali addons, because Kiali is useless
#      without both,
#   4. applies the module's starting workloads.
#
# No traffic is generated and no fault is injected — an empty graph is the
# starting point the module works from.
set -euo pipefail

ISTIO_VERSION="1.30.5"
ISTIO_BRANCH="release-1.30"
NAMESPACE="kiali-demo"
ADDON_BASE="https://raw.githubusercontent.com/istio/istio/${ISTIO_BRANCH}/samples/addons"

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

echo "[playground] Installing the Prometheus and Kiali addons..."
kubectl apply -f "${ADDON_BASE}/prometheus.yaml"
kubectl apply -f "${ADDON_BASE}/kiali.yaml"
kubectl -n istio-system rollout status deployment/prometheus --timeout=300s
kubectl -n istio-system rollout status deployment/kiali --timeout=300s

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR=""
for candidate in "$SCRIPT_DIR/../manifests" "./manifests" "$SCRIPT_DIR/manifests"; do
  [ -d "$candidate" ] && { MANIFEST_DIR="$candidate"; break; }
done

if [ -n "$MANIFEST_DIR" ] && [ -f "$MANIFEST_DIR/lab-start.yaml" ]; then
  echo "[playground] Applying starting workloads..."
  kubectl apply -f "$MANIFEST_DIR/lab-start.yaml"
fi

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || {
  echo "[playground] ERROR: namespace $NAMESPACE was never created." >&2
  exit 1
}

echo "[playground] Settling workloads in $NAMESPACE..."
kubectl -n "$NAMESPACE" rollout restart deployment --all >/dev/null 2>&1 || true
for d in $(kubectl -n "$NAMESPACE" get deployment -o name); do
  kubectl -n "$NAMESPACE" rollout status "$d" --timeout=300s
done

echo "[playground] Ready."
kubectl -n "$NAMESPACE" get pods -o wide
kubectl -n istio-system get pods -l app=kiali
echo "[playground] No traffic is flowing yet, so the Kiali graph starts empty — that is expected."
