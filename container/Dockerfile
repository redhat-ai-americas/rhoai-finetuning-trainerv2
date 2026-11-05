# Custom workbench image for the RHOAI Banking Support Agent demo.
# Build and push before creating your workbench — see README for instructions.
# OSFT runs in the cluster training-hub runtime. This image only needs the
# Kubeflow SDK (to submit TrainJobs) plus the notebook's data and inference libs.
FROM registry.redhat.io/rhoai/odh-workbench-jupyter-pytorch-cuda-py312-rhel9:v3.5

USER root

RUN pip install --no-cache-dir --upgrade pip

RUN pip install --no-cache-dir \
    pandas \
    transformers \
    accelerate \
    openai \
    "kubeflow==0.3.0+rhaiv.3" \
    --index-url https://packages.redhat.com/api/pypi/public-rhai/rhoai/3.5/cuda13.0-ubi9/simple/

USER 1001
