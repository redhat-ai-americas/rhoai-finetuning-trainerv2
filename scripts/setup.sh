#!/usr/bin/env bash
# Deploy demo namespace, ServiceAccounts, RBAC, and optionally the RWX PVC.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a && source "${REPO_ROOT}/.env" && set +a
fi

DEMO_NAMESPACE="${DEMO_NAMESPACE:-osft-banking-support-demo}"
STORAGE_CLASS="${STORAGE_CLASS:-efs-csi}"
PVC_SIZE="${PVC_SIZE:-50Gi}"
DEMO_PVC_NAME="${DEMO_PVC_NAME:-shared-support-data}"
DEMO_WORKBENCH_SA="${DEMO_WORKBENCH_SA:-jupyterhub}"

echo "==> Banking Support Agent — infrastructure setup"
echo "    Namespace:       ${DEMO_NAMESPACE}"
echo "    Workbench SA:    ${DEMO_WORKBENCH_SA}"
echo "    Storage class:   ${STORAGE_CLASS}"
echo "    PVC name/size:   ${DEMO_PVC_NAME} / ${PVC_SIZE}"
echo ""

if ! command -v oc &>/dev/null && ! command -v kubectl &>/dev/null; then
  echo "ERROR: oc or kubectl is required." >&2
  exit 1
fi

KUBECTL="${KUBECTL:-$(command -v oc || command -v kubectl)}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
cp -r "${REPO_ROOT}/manifests/." "${TMP_DIR}/"

apply_sed() {
  local expression="$1"
  local target="$2"
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "${expression}" "${target}"
  else
    sed -i "${expression}" "${target}"
  fi
}

for file in "${TMP_DIR}"/*.yaml; do
  apply_sed "s/osft-banking-support-demo/${DEMO_NAMESPACE}/g" "${file}"
  apply_sed "s/workbench-sa-placeholder/${DEMO_WORKBENCH_SA}/g" "${file}"
done

apply_sed "s/storageClassName: efs-csi/storageClassName: ${STORAGE_CLASS}/g" "${TMP_DIR}/pvc.yaml"
apply_sed "s/storage: 50Gi/storage: ${PVC_SIZE}/g" "${TMP_DIR}/pvc.yaml"
apply_sed "s/name: shared-support-data/name: ${DEMO_PVC_NAME}/g" "${TMP_DIR}/pvc.yaml"

echo "==> Applying namespace, ServiceAccount, and RBAC..."
"${KUBECTL}" apply -k "${TMP_DIR}"

if "${KUBECTL}" get namespace kubeflow-system &>/dev/null; then
  echo "==> Applying optional kubeflow-system trainer RBAC..."
  OPTIONAL_FILE="${TMP_DIR}/optional/rbac-trainer-kubeflow-system.yaml"
  if [[ -f "${OPTIONAL_FILE}" ]]; then
    apply_sed "s/osft-banking-support-demo/${DEMO_NAMESPACE}/g" "${OPTIONAL_FILE}"
    apply_sed "s/workbench-sa-placeholder/${DEMO_WORKBENCH_SA}/g" "${OPTIONAL_FILE}"
    "${KUBECTL}" apply -f "${OPTIONAL_FILE}"
  fi
else
  echo "==> kubeflow-system namespace not found — skipping optional trainer version RBAC."
  echo "    (Harmless; Cell 5 may show a version info warning but training still works.)"
fi

if "${KUBECTL}" get pvc "${DEMO_PVC_NAME}" -n "${DEMO_NAMESPACE}" &>/dev/null; then
  echo ""
  echo "==> PVC '${DEMO_PVC_NAME}' already exists — skipping PVC create/update."
  echo "    (Existing PVCs cannot be resized if the StorageClass does not support it.)"
else
  echo ""
  echo "==> Creating PVC '${DEMO_PVC_NAME}'..."
  "${KUBECTL}" apply -f "${TMP_DIR}/pvc.yaml"
fi

echo ""
echo "==> Setup complete. Next steps:"
echo ""
echo "  1. Confirm DEMO_WORKBENCH_SA matches your workbench ServiceAccount:"
echo "       oc get pod -n ${DEMO_NAMESPACE} -l opendatahub.io/dashboard=true \\"
echo "         -o jsonpath='{.items[0].spec.serviceAccountName}{\"\\n\"}'"
echo ""
echo "  2. If the SA name differs, update .env and re-run: ./scripts/setup.sh"
echo ""
echo "  3. Restart the workbench pod so it picks up new RBAC (stop/start in RHOAI UI)."
echo ""
echo "  4. Open notebooks/osft-banking-demo.ipynb and run from Cell 1."
echo ""
