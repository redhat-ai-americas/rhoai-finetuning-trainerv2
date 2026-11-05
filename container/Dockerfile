# Optional workbench image. The documented path uses the default PyTorch image
# and Cell 5 of the notebook. Build this only to skip that pip install.
# OSFT still runs in the cluster training-hub runtime.
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
