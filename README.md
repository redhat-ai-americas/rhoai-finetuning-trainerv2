# RHOAI Banking Support Agent Demo

Enterprise demo for Red Hat Solutions Architects showcasing **Intelligent Customer Support Routing** on Red Hat OpenShift AI (RHOAI) 3.4.

A base LLM hallucinates conversational filler when asked to route banking complaints. By fine-tuning with **Orthogonal Subspace Fine-Tuning (OSFT)** via Kubeflow Trainer v2, the model learns to output strict JSON routing decisions mapped to 77 banking intents from the [PolyAI Banking77](https://github.com/PolyAI-LDN/task-specific-datasets) dataset.

**Repository:** [redhat-ai-americas/rhoai-finetuning-trainerv2](https://github.com/redhat-ai-americas/rhoai-finetuning-trainerv2)

---

## Architecture

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  Jupyter         │     │  Kubeflow Trainer v2  │     │  MLflow         │
│  Workbench       │────▶│  (training-hub OSFT)  │────▶│  (metrics)      │
│  (this notebook) │     │  2 nodes × 2 GPUs     │     │                 │
└────────┬────────┘     └──────────┬───────────┘     └─────────────────┘
         │                         │
         │              ┌──────────▼───────────┐
         └─────────────▶│  RWX PVC             │
                        │  shared-support-data │
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │  vLLM (KServe)       │
                        │  RHOAI UI deploy     │
                        └──────────────────────┘
```

---

## Prerequisites

This repo assumes you already have a working OpenShift cluster with RHOAI 3.4. **Do not use this repo to install OpenShift or RHOAI** — use the guides below first.

### 1. OpenShift cluster

- OpenShift **4.19+** with `cluster-admin` or sufficient permissions
- `oc` CLI logged in (`oc whoami`)

### 2. GPU nodes and RWX storage

Follow the [openshift-infra](https://github.com/dandawg/openshift-infra) repository:

| Step | Command / Action |
|------|------------------|
| Bootstrap GitOps | `./bootstrap.sh` |
| Deploy GPU nodes | `openshift-infra-machineset-aws --instance-type g6.2xlarge` |
| Deploy RWX storage | `openshift-infra-efs-aws` (creates `efs-csi` StorageClass on AWS) |

**Minimum hardware for this demo:**

| Resource | Requirement |
|----------|-------------|
| Training | 2 GPU nodes, 2 GPUs per node (`nnodes=2`, `nproc_per_node=2`) |
| Workbench inference cell | 1 GPU on the workbench pod |
| Storage | RWX PVC, 50 Gi recommended (`shared-support-data`) |

### 3. RHOAI 3.4 platform

Follow [rhoai-maas-guide](https://github.com/rh-aiservices-bu/rhoai-maas-guide) **Phases 1–4** to install and configure RHOAI:

- Operator subscriptions (RHOAI, cert-manager, LWS)
- DataScienceCluster and DSCInitialization
- Dashboard settings

> **Note:** You do not need MaaS Phases 5–7 for this demo. Model serving is done directly via the RHOAI Single-model serving UI (KServe + vLLM), not through the MaaS API gateway.

### 4. RHOAI components required

Confirm these are enabled in your DataScienceCluster:

- [x] **Training Operator** with `training-hub` runtime (v0.5.0)
- [x] **MLflow** tracking server
- [x] **Model serving** (KServe) with vLLM ServingRuntime available
- [x] **Workbench** with GPU quota in your namespace

---

## Quick Start

### Step 1: Clone and configure

```bash
git clone https://github.com/redhat-ai-americas/rhoai-finetuning-trainerv2.git
cd rhoai-finetuning-trainerv2
cp .env.example .env
```

Edit `.env` for your cluster:

```bash
DEMO_NAMESPACE=osft-banking-support-demo   # Must match your Data Science Project namespace
STORAGE_CLASS=efs-csi                      # Your RWX StorageClass name
CUSTOM_IMAGE=quay.io/YOUR_ORG/banking-demo-base:latest
VLLM_MODEL_NAME=banking-routing-model
```

### Step 2: Deploy demo infrastructure

```bash
chmod +x scripts/setup.sh scripts/teardown.sh
./scripts/setup.sh
```

This creates:

- Namespace `osft-banking-support-demo`
- ServiceAccount `osft-dist-banking-demo` with MLflow RBAC
- RWX PVC `shared-support-data`

### Step 3: Build the custom workbench image

The custom image pre-installs all Python dependencies so live demos do not require `pip install` waits.

```bash
cd container

# Build (requires access to registry.redhat.io/rhoai and the RHOAI PyPI index)
podman build -t quay.io/YOUR_ORG/banking-demo-base:latest .

# Push to your registry
podman login quay.io
podman push quay.io/YOUR_ORG/banking-demo-base:latest
```

On OpenShift, you can also build via a `BuildConfig` or connect the image to your namespace's image pull secrets.

### Step 4: Create the RHOAI Data Science Project and workbench

1. In the RHOAI Dashboard, create a **Data Science Project** linked to namespace `osft-banking-support-demo`.
2. Create a **Workbench** with these settings:

| Setting | Value |
|---------|-------|
| Image | `quay.io/YOUR_ORG/banking-demo-base:latest` (custom image) |
| GPU | Assign a GPU hardware profile |
| Storage | Mount PVC `shared-support-data` at `/opt/app-root/src/shared` |
| Environment variable | Add `opendatahub.io/mlflow-instance` annotation (via workbench settings / YAML) so MLflow env vars are injected |

3. Clone or upload this repository into the workbench.
4. Open `notebooks/osft-banking-demo.ipynb`.

### Step 5: Run the demo notebook

Execute cells in order. Expected runtime:

| Phase | Cells | Time |
|-------|-------|------|
| Data preparation | 1–3 | ~2 min |
| Submit training | 4–6 | ~1 min |
| Stream training logs | 7 | ~60–90 min |
| Checkpoint + inference comparison | 8–9 | ~10 min |
| vLLM config cleanup | 10 | ~1 min |
| Deploy model (UI) | markdown cell | ~5–10 min |
| Test vLLM endpoint | 11 | ~1 min |

---

## Deploy Model via RHOAI UI

After training completes and Cell 10 sanitizes the tokenizer config:

1. Go to your Data Science Project → **Models** → **Deploy model**.
2. Select **Single-model serving** platform.
3. Configure:

| Field | Value |
|-------|-------|
| Model name | `banking-routing-model` |
| Serving runtime | `vLLM ServingRuntime` |
| Model framework | `vLLM` |
| Model location | Existing data connection → PVC path from Cell 8 output |

Example PVC-relative path:

```
support-checkpoints/hf_format/samples_30009.0
```

4. Wait for the green checkmark, then run Cell 11.

The endpoint URL is derived automatically:

```
http://banking-routing-model-predictor.<namespace>.svc.cluster.local/v1
```

---

## Demo Narrative (Customer-Facing)

| Cell | Talking Point |
|------|---------------|
| 3 | "We start with 10,000 real banking complaints across 77 intent categories." |
| 6–7 | "RHOAI distributes OSFT training across multiple GPUs, logging metrics to MLflow." |
| 9 | "Watch the base model hallucinate JSON format — wrong keys, wrong types. The fine-tuned model outputs strict routing JSON." |
| UI deploy | "We serve the fine-tuned weights directly from shared storage via vLLM — no export step." |
| 11 | "Production-grade inference: same JSON schema, sub-second latency, API-ready." |

---

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `DEMO_NAMESPACE` | `osft-banking-support-demo` | Kubernetes / DSP namespace |
| `STORAGE_CLASS` | `efs-csi` | RWX StorageClass for the PVC |
| `DEMO_PVC_NAME` | `shared-support-data` | Shared PVC name |
| `DEMO_SA_NAME` | `osft-dist-banking-demo` | Training worker ServiceAccount |
| `VLLM_MODEL_NAME` | `banking-routing-model` | Model name in RHOAI UI and inference cell |
| `CUSTOM_IMAGE` | — | Custom workbench image URI |
| `K8S_VERIFY_SSL` | `true` | Set `false` only for sandbox clusters with self-signed certs |

See also `config/demo-config.yaml` for a YAML reference of all settings.

---

## Troubleshooting

### `'training-hub' runtime not found`

Ensure the RHOAI Training Operator is installed and the `training-hub` ClusterTrainingRuntime (v0.5.0) is available. Check **Administration → Training Runtimes** in the RHOAI dashboard.

### MLflow URI not found in Cell 2

Add the `opendatahub.io/mlflow-instance` annotation to your workbench. See [RHOAI MLflow documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/monitoring_and_tracing_models/index).

### Training job fails with RBAC errors

Confirm `scripts/setup.sh` was run and training workers use ServiceAccount `osft-dist-banking-demo`. The MLflow RoleBinding is in `manifests/rbac-mlflow.yaml`.

### vLLM deployment fails after training

Run Cell 10 before deploying. OSFT occasionally writes a `quantization_config` block that vLLM rejects.

### PVC stays Pending

Verify your cluster has a **ReadWriteMany** StorageClass. On AWS, deploy EFS via [openshift-infra](https://github.com/dandawg/openshift-infra). Update `STORAGE_CLASS` in `.env` before running `setup.sh`.

### Cell 5 fails with `403 Forbidden` on `trainingruntimes` or `kubeflow-trainer-public`

The Jupyter workbench ServiceAccount needs RBAC to talk to Kubeflow Trainer v2. This is **not** an `.env` misconfiguration — it means `DEMO_WORKBENCH_SA` in `.env` does not match your workbench pod's SA, or `setup.sh` has not been run since adding the trainer RBAC manifests.

1. Find your workbench ServiceAccount:

```bash
oc get pod -n osft-baning-support-demo -l opendatahub.io/dashboard=true \
  -o jsonpath='{.items[0].spec.serviceAccountName}{"\n"}'
```

2. Set `DEMO_WORKBENCH_SA=<result>` in `.env` and re-run `./scripts/setup.sh`

3. **Restart the workbench** (stop/start in RHOAI UI) so the pod picks up new RoleBindings

4. Re-run Cell 5

### Harmless Cell 5 warning about `kubeflow-trainer-public`

On RHOAI 3.4, the `kubeflow-system` namespace often does not exist. You may see a warning when connecting to the Trainer client — this is **cosmetic only** and does not affect training. No action required.

### PVC error during `setup.sh` on an existing cluster

If you see `persistentvolumeclaims ... is forbidden: only dynamically provisioned pvc can be resized`, your PVC already exists — that is fine. The updated `setup.sh` skips PVC updates automatically. Namespace, SA, and RBAC still apply successfully.

### Workbench cannot submit training jobs

Ensure `DEMO_WORKBENCH_SA` is set correctly and `./scripts/setup.sh` has been applied. The workbench SA needs the trainer RBAC in `manifests/rbac-trainer-workbench.yaml`.

---

## Teardown

```bash
# Remove namespace resources (keeps PVC data by default)
./scripts/teardown.sh

# Also delete trained model data on the PVC
DELETE_PVC=true ./scripts/teardown.sh
```

Also manually delete via the RHOAI UI:

- Deployed vLLM models (**Models** page)
- Kubeflow training jobs (**Distributed workloads**)
- Workbench instance

---

## Repository Structure

```
rhoai-finetuning-trainerv2/
├── README.md
├── .env.example
├── config/
│   └── demo-config.yaml
├── container/
│   └── Dockerfile              # Custom workbench image
├── notebooks/
│   └── osft-banking-demo.ipynb # Main demo workflow
├── manifests/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── serviceaccount.yaml
│   ├── rbac-mlflow.yaml
│   └── pvc.yaml
└── scripts/
    ├── setup.sh
    └── teardown.sh
```

---

## Related Resources

- [RHOAI 3.4 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4)
- [rhoai-maas-guide](https://github.com/rh-aiservices-bu/rhoai-maas-guide) — RHOAI platform setup
- [openshift-infra](https://github.com/dandawg/openshift-infra) — GPU nodes and RWX storage
- [PolyAI Banking77 Dataset](https://github.com/PolyAI-LDN/task-specific-datasets)
- [Qwen2.5-1.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct) — Base model
