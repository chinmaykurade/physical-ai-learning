# Prebuilt LeRobot environment for RunPod.
#
# Bakes the ~4.7 GB torch + CUDA 13 stack into an image layer so a fresh pod
# pulls it from the registry (parallel, resumable, edge-cached) instead of
# resolving and downloading it from PyPI at boot.
#
# Build and push (see scripts/build_image.sh):
#   docker build --platform=linux/amd64 -t <user>/lerobot-so101:0.6.0 docker/
#   docker push <user>/lerobot-so101:0.6.0
#
# RunPod requires linux/amd64. The venv is baked at /opt/lerobot-env -- NOT on
# /workspace, which is replaced by the network volume mount at runtime.

FROM runpod/pytorch:1.1.0-cu1300-torch291-ubuntu2404

# torchcodec links against system FFmpeg; libgl1/libglib2.0-0 keep opencv and
# pygame importable in a headless container.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg libgl1 libglib2.0-0 git && \
    rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

ENV VENV=/opt/lerobot-env
ENV UV_LINK_MODE=copy

# Three sequenced passes, matching scripts/runpod_bootstrap.sh. Kept as
# separate layers so an edit to the lock file does not re-download torch.
#
# 1. torch/torchvision from the cu130 index. A single --extra-index-url call
#    would let uv prefer the plain-PyPI torch, silently swapping the CUDA stack.
RUN uv venv --python 3.12 "$VENV" && \
    uv pip install --python "$VENV/bin/python" \
        --index-url https://download.pytorch.org/whl/cu130 \
        torch==2.11.0 torchvision==0.26.0

# 2. cuda-bindings is absent from the cu130 index (pytorch/pytorch#172926), so
#    torch's own dependency has to come from PyPI.
RUN uv pip install --python "$VENV/bin/python" \
        cuda-bindings==13.3.1 cuda-toolkit==13.0.2

# 3. Everything else, with torch filtered out so pass 1 is not clobbered by the
#    untagged `torch==2.11.0` line (uv pip freeze strips the +cu130 tag).
COPY lerobot-env.lock.txt /tmp/lock.txt
RUN grep -viE '^(torch|torchvision)==' /tmp/lock.txt > /tmp/req.txt && \
    uv pip install --python "$VENV/bin/python" -r /tmp/req.txt && \
    rm -f /tmp/req.txt

# The GUI opencv build comes from gymnasium[other]; LeRobot pins only the
# headless one. Removing it avoids a libGL import failure at eval time.
#
# Both distributions share a single cv2/ directory, so uninstalling one DELETES
# files the other still needs -- cv2 then imports but has no attributes
# ("module 'cv2' has no attribute 'resize'"). The --reinstall repairs it.
RUN set -eux; \
    HEADLESS="$(grep -iE '^opencv-python-headless==' /tmp/lock.txt || true)"; \
    [ -n "$HEADLESS" ] || HEADLESS=opencv-python-headless==4.13.0.92; \
    uv pip uninstall --python "$VENV/bin/python" opencv-python || true; \
    uv pip install --python "$VENV/bin/python" --reinstall "$HEADLESS"; \
    rm -f /tmp/lock.txt

# Caches point at /workspace at runtime (the network volume), so downloaded
# datasets and the ResNet18 backbone persist across pods.
ENV HF_HOME=/workspace/.cache/huggingface \
    TORCH_HOME=/workspace/.cache/torch \
    UV_CACHE_DIR=/workspace/.cache/uv \
    SDL_VIDEODRIVER=dummy \
    MPLBACKEND=Agg \
    PATH="/opt/lerobot-env/bin:$PATH"

# Fail the build rather than ship a broken image: assert the CUDA 13 build
# landed and that PushT renders headless. Neither needs a GPU at build time.
COPY verify.py /tmp/verify.py
RUN "$VENV/bin/python" /tmp/verify.py && rm -f /tmp/verify.py

WORKDIR /workspace
CMD ["/start.sh"]
