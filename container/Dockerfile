
# Custom workbench image for the RHOAI Banking Support Agent demo.
# Build and push before creating your workbench — see README for instructions.
FROM registry.redhat.io/rhoai/odh-workbench-jupyter-pytorch-cuda-py312-rhel9:v3.4

USER root

RUN pip install --no-cache-dir --upgrade pip

# Hugging Face stack (not included in the base workbench image)
RUN pip install --no-cache-dir \
    "datasets<4.0.0" \
    transformers \
    accelerate \
    openai

# Kubeflow Trainer v2 and OSFT training-hub runtime dependencies
RUN pip install --no-cache-dir \
    kubeflow-trainer-api==2.1.0 \
    kubeflow-katib-api==0.19.0 \
    kubeflow==0.3.0+rhaiv.2 \
    training-hub==0.5.0 \
    --index-url https://console.redhat.com/api/pypi/public-rhai/rhoai/3.4/cuda12.9-ubi9/simple/ \
    --extra-index-url https://pypi.org/simple

USER 1001
