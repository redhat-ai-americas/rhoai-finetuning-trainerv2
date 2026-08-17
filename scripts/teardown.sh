#!/usr/bin/env bash
# Remove demo Kubernetes resources. Does NOT delete trained model data by default.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a && source "${REPO_ROOT}/.env" && set +a
fi

DEMO_NAMESPACE="${DEMO_NAMESPACE:-osft-banking-support-demo}"
DELETE_PVC="${DELETE_PVC:-false}"

KUBECTL="${KUBECTL:-$(command -v oc || command -v kubectl)}"

echo "==> Banking Support Agent — teardown"
echo "    Namespace: ${DEMO_NAMESPACE}"
echo ""

if [[ "${DELETE_PVC}" == "true" ]]; then
  echo "==> Deleting PVC (trained model data will be lost)..."
  "${KUBECTL}" delete pvc shared-support-data -n "${DEMO_NAMESPACE}" --ignore-not-found
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
cp -r "${REPO_ROOT}/manifests/." "${TMP_DIR}/"

if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s/name: osft-banking-support-demo/name: ${DEMO_NAMESPACE}/g" "${TMP_DIR}"/*.yaml
  sed -i '' "s/namespace: osft-banking-support-demo/namespace: ${DEMO_NAMESPACE}/g" "${TMP_DIR}"/*.yaml
else
  sed -i "s/name: osft-banking-support-demo/name: ${DEMO_NAMESPACE}/g" "${TMP_DIR}"/*.yaml
  sed -i "s/namespace: osft-banking-support-demo/namespace: ${DEMO_NAMESPACE}/g" "${TMP_DIR}"/*.yaml
fi

echo "==> Deleting demo manifests..."
"${KUBECTL}" delete -k "${TMP_DIR}" --ignore-not-found

echo ""
echo "==> Teardown complete."
echo ""
echo "Note: This script does not remove:"
echo "  - RHOAI Data Science Projects or workbenches (delete via RHOAI UI)"
echo "  - Deployed vLLM models (delete via RHOAI UI -> Models)"
echo "  - Kubeflow training jobs (delete via RHOAI UI -> Distributed workloads)"
echo "  - The PVC and checkpoint data (set DELETE_PVC=true to remove)"
echo ""
