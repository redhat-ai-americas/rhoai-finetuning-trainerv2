#!/usr/bin/env bash
# Read-only checks for the OpenShift AI 3.5 Trainer v2 banking demo.
# Does not create, update, or delete cluster resources.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a && source "${REPO_ROOT}/.env" && set +a
fi

DEMO_NAMESPACE="${DEMO_NAMESPACE:-osft-banking-support-demo}"
STORAGE_CLASS="${STORAGE_CLASS:-efs-csi}"

PASS=0
FAIL=0
WARN=0

pass() {
  PASS=$((PASS + 1))
  printf 'PASS  %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL  %s\n' "$1"
}

warn() {
  WARN=$((WARN + 1))
  printf 'WARN  %s\n' "$1"
}

echo "==> OpenShift AI 3.5 banking demo — cluster checks"
echo "    Namespace:     ${DEMO_NAMESPACE}"
echo "    Storage class: ${STORAGE_CLASS}"
echo "    These checks only read the cluster."
echo ""

if command -v oc >/dev/null 2>&1; then
  KUBECTL="$(command -v oc)"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL="$(command -v kubectl)"
else
  fail "oc or kubectl is not on PATH"
  echo ""
  echo "==> ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
  exit 1
fi

if ! "${KUBECTL}" whoami >/dev/null 2>&1; then
  fail "not logged in to the cluster (${KUBECTL} whoami failed)"
  echo ""
  echo "==> ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
  exit 1
fi
pass "logged in as $(${KUBECTL} whoami)"

check_component() {
  local dsc="$1"
  local component="$2"
  local expected="$3"
  local actual
  actual="$("${KUBECTL}" get dsc "${dsc}" -o "jsonpath={.spec.components.${component}.managementState}" 2>/dev/null || true)"
  if [[ "${actual}" == "${expected}" ]]; then
    pass "DataScienceCluster/${dsc} ${component}=${expected}"
  elif [[ -z "${actual}" ]]; then
    fail "DataScienceCluster/${dsc} has no ${component}.managementState (expected ${expected})"
  else
    fail "DataScienceCluster/${dsc} ${component}=${actual} (expected ${expected})"
  fi
}

dsc_names="$("${KUBECTL}" get dsc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
if [[ -z "${dsc_names}" ]]; then
  fail "no DataScienceCluster found"
else
  while IFS= read -r dsc; do
    [[ -z "${dsc}" ]] && continue
    check_component "${dsc}" kueue Unmanaged
    check_component "${dsc}" trainer Managed
    check_component "${dsc}" trainingoperator Managed
    check_component "${dsc}" workbenches Managed
    check_component "${dsc}" kserve Managed
    check_component "${dsc}" mlflowoperator Managed
  done <<< "${dsc_names}"
fi

if "${KUBECTL}" get clustertrainingruntime training-hub >/dev/null 2>&1; then
  pass "ClusterTrainingRuntime/training-hub exists"
else
  fail "ClusterTrainingRuntime/training-hub not found (oc get clustertrainingruntime)"
fi

trainer_ready="$("${KUBECTL}" get deploy -n redhat-ods-applications kubeflow-training-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
if [[ "${trainer_ready}" =~ ^[1-9] ]]; then
  pass "kubeflow-training-operator has ${trainer_ready} ready replica(s)"
else
  fail "kubeflow-training-operator is not ready in redhat-ods-applications"
fi

if "${KUBECTL}" get crd jobsets.jobset.x-k8s.io >/dev/null 2>&1 || "${KUBECTL}" get crd jobsets.jobset.sigs.k8s.io >/dev/null 2>&1; then
  pass "JobSet CRD is installed"
else
  fail "JobSet CRD is missing (install the JobSet Operator; expected jobsets.jobset.x-k8s.io)"
fi

kueue_ns=""
for candidate in openshift-kueue-operator redhat-kueue-operator; do
  if "${KUBECTL}" get ns "${candidate}" >/dev/null 2>&1; then
    kueue_ns="${candidate}"
    break
  fi
done
if [[ -z "${kueue_ns}" ]]; then
  fail "Red Hat build of Kueue namespace not found (expected openshift-kueue-operator)"
else
  kueue_running="$("${KUBECTL}" get pods -n "${kueue_ns}" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [[ "${kueue_running}" =~ ^[1-9] ]]; then
    pass "Kueue pods are running in ${kueue_ns} (${kueue_running})"
  else
    fail "no Running pods in ${kueue_ns}"
  fi
fi

gpu_ns=""
for candidate in nvidia-gpu-operator gpu-operator; do
  if "${KUBECTL}" get ns "${candidate}" >/dev/null 2>&1; then
    gpu_ns="${candidate}"
    break
  fi
done
if [[ -z "${gpu_ns}" ]]; then
  fail "NVIDIA GPU Operator namespace not found (expected nvidia-gpu-operator)"
else
  gpu_running="$("${KUBECTL}" get pods -n "${gpu_ns}" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [[ "${gpu_running}" =~ ^[1-9] ]]; then
    pass "GPU Operator pods are running in ${gpu_ns} (${gpu_running})"
  else
    fail "no Running pods in ${gpu_ns}"
  fi
fi

gpu_nodes=0
other_instance=0
node_rows="$("${KUBECTL}" get nodes -o go-template='{{range .items}}{{.metadata.name}}{{"\t"}}{{range .status.conditions}}{{if eq .type "Ready"}}{{.status}}{{end}}{{end}}{{"\t"}}{{index .status.allocatable "nvidia.com/gpu"}}{{"\t"}}{{index .metadata.labels "node.kubernetes.io/instance-type"}}{{"\n"}}{{end}}' 2>/dev/null || true)"
if [[ -z "${node_rows}" ]]; then
  fail "could not list nodes"
else
    while IFS=$'\t' read -r name ready gpus itype; do
    [[ -z "${name}" ]] && continue
    if [[ "${itype}" == "<no value>" || "${itype}" == "<none>" ]]; then
      itype=""
    fi
    if [[ "${gpus}" == "<no value>" || "${gpus}" == "<none>" ]]; then
      gpus=""
    fi
    if [[ "${ready}" == "True" && "${gpus}" =~ ^[1-9][0-9]*$ ]]; then
      gpu_nodes=$((gpu_nodes + 1))
      printf '      GPU node %s allocatable=%s instance=%s\n' "${name}" "${gpus}" "${itype:-unknown}"
      if [[ -n "${itype}" && "${itype}" != "g6e.2xlarge" ]]; then
        other_instance=$((other_instance + 1))
      fi
    fi
  done <<< "${node_rows}"
  if (( gpu_nodes >= 2 )); then
    pass "${gpu_nodes} Ready nodes advertise at least 1 nvidia.com/gpu"
  else
    fail "need 2 Ready nodes with nvidia.com/gpu >= 1; found ${gpu_nodes}"
  fi
  if (( other_instance > 0 )); then
    warn "one or more GPU nodes are not g6e.2xlarge; this demo requests 1 GPU, 4 CPU, and 32Gi per node"
  fi
fi

hp_resource=""
if "${KUBECTL}" get crd hardwareprofiles.infrastructure.opendatahub.io >/dev/null 2>&1; then
  hp_resource="hardwareprofiles.infrastructure.opendatahub.io"
fi
if [[ -z "${hp_resource}" ]]; then
  fail "HardwareProfile CRD hardwareprofiles.infrastructure.opendatahub.io not found"
else
  hp_rows="$("${KUBECTL}" get "${hp_resource}" -A -o go-template='{{range .items}}{{.metadata.namespace}}/{{.metadata.name}}{{"\t"}}{{range .spec.identifiers}}{{.identifier}}{{","}}{{end}}{{"\n"}}{{end}}' 2>/dev/null || true)"
  gpu_profiles=0
  cpu_profiles=0
  if [[ -z "${hp_rows}" ]]; then
    fail "no HardwareProfile resources found"
  else
    while IFS=$'\t' read -r hp_name identifiers; do
      [[ -z "${hp_name}" ]] && continue
      if [[ "${identifiers}" == *"nvidia.com/gpu"* ]]; then
        gpu_profiles=$((gpu_profiles + 1))
      else
        cpu_profiles=$((cpu_profiles + 1))
      fi
    done <<< "${hp_rows}"
    if (( gpu_profiles >= 1 )); then
      pass "${gpu_profiles} hardware profile(s) request nvidia.com/gpu"
    else
      fail "no hardware profile includes nvidia.com/gpu (needed for the comparison workbench and vLLM)"
    fi
    if (( cpu_profiles >= 1 )); then
      pass "${cpu_profiles} hardware profile(s) do not request a GPU (use one while training)"
    else
      fail "no CPU-only hardware profile found (the workbench must not hold a GPU during training)"
    fi
  fi
fi

if "${KUBECTL}" get storageclass "${STORAGE_CLASS}" >/dev/null 2>&1; then
  provisioner="$("${KUBECTL}" get storageclass "${STORAGE_CLASS}" -o jsonpath='{.provisioner}')"
  case "${provisioner}" in
    *efs*|*nfs*|*cephfs*|*filestore*|*trident*)
      pass "StorageClass/${STORAGE_CLASS} exists (${provisioner})"
      ;;
    *)
      pass "StorageClass/${STORAGE_CLASS} exists (${provisioner})"
      warn "provisioner ${provisioner} is not a known ReadWriteMany type; confirm the PVC can use ReadWriteMany"
      ;;
  esac
else
  fail "StorageClass/${STORAGE_CLASS} not found. Set STORAGE_CLASS in .env to the RWX class from: ${KUBECTL} get storageclass"
fi

if ! "${KUBECTL}" get namespace "${DEMO_NAMESPACE}" >/dev/null 2>&1; then
  warn "namespace ${DEMO_NAMESPACE} does not exist yet; re-run after scripts/setup.sh to check its Kueue LocalQueue"
else
  kueue_managed="$("${KUBECTL}" get namespace "${DEMO_NAMESPACE}" -o jsonpath='{.metadata.labels.kueue\.openshift\.io/managed}' 2>/dev/null || true)"
  if [[ "${kueue_managed}" != "true" ]]; then
    pass "namespace ${DEMO_NAMESPACE} is not Kueue-managed, so the TrainJob is not queued"
  else
    lq_rows="$("${KUBECTL}" get localqueue -n "${DEMO_NAMESPACE}" -o go-template='{{range .items}}{{.metadata.name}}{{"\t"}}{{.spec.clusterQueue}}{{"\n"}}{{end}}' 2>/dev/null || true)"
    if [[ -z "${lq_rows}" ]]; then
      fail "namespace ${DEMO_NAMESPACE} is Kueue-managed but has no LocalQueue"
    else
      admitted=0
      while IFS=$'\t' read -r lq_name cq_name; do
        [[ -z "${lq_name}" || -z "${cq_name}" ]] && continue
        max_quota=0
        quota_rows="$("${KUBECTL}" get clusterqueue "${cq_name}" -o go-template='{{range .spec.resourceGroups}}{{range .flavors}}{{range .resources}}{{if eq .name "nvidia.com/gpu"}}{{.nominalQuota}}{{"\n"}}{{end}}{{end}}{{end}}{{end}}' 2>/dev/null || true)"
        while IFS= read -r quota; do
          [[ "${quota}" =~ ^[0-9]+$ ]] || continue
          if (( quota > max_quota )); then
            max_quota=${quota}
          fi
        done <<< "${quota_rows}"
        if (( max_quota >= 2 )); then
          admitted=1
          pass "LocalQueue/${lq_name} uses ClusterQueue/${cq_name} with nvidia.com/gpu nominalQuota ${max_quota}"
        else
          warn "LocalQueue/${lq_name} -> ClusterQueue/${cq_name} nvidia.com/gpu nominalQuota is ${max_quota}"
        fi
      done <<< "${lq_rows}"
      if (( admitted == 0 )); then
        fail "no LocalQueue in ${DEMO_NAMESPACE} can admit nvidia.com/gpu: 2 at once"
      fi
    fi
  fi
fi

echo ""
echo "==> ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
