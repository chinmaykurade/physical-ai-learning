#!/usr/bin/env bash
# Idempotent RunPod environment bootstrap for the SO-101 project.
#
# Builds the pinned LeRobot environment on the /workspace network volume so it
# survives pod stop/restart. Safe to re-run: on a provisioned pod it exits in
# seconds after re-verifying, and installs nothing.
#
# Usage:  bash scripts/runpod_bootstrap.sh
# See scripts/README.md for the console setup this assumes.

set -euo pipefail

WORKSPACE=/workspace
VENV="$WORKSPACE/lerobot-env"
UV_BIN="$WORKSPACE/.local/bin/uv"
ENV_SH="$VENV/env.sh"
STAMP="$VENV/.bootstrap-complete"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$REPO_ROOT/env/lerobot-env.lock.txt"

# torch 2.11.0 hard-requires the CUDA 13 stack (cuda-toolkit==13.0.2,
# nvidia-cudnn-cu13, nvidia-nccl-cu13, triton==3.6.0), so cu130 is not a
# preference here — it is what this wheel is. CUDA 13.x needs driver >= 580.
CUDA_INDEX="https://download.pytorch.org/whl/cu130"
MIN_DRIVER=580

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[0;32mok\033[0m  %s\n' "$*"; }
die()  { printf '\n\033[1;31mFAIL: %s\033[0m\n' "$1" >&2
         [ $# -gt 1 ] && printf '      fix: %s\n' "$2" >&2
         exit 1; }

# ---------------------------------------------------------------- A. preflight
# Everything that can fail should fail here, in seconds, with a fix attached --
# not 10 minutes into an install or 2500 steps into a training run.
say "Preflight"

[ -d "$WORKSPACE" ] || die "$WORKSPACE does not exist." \
  "Attach a network volume with mount path $WORKSPACE when creating the pod."

# A volume that is not a mount point means the container filesystem is being
# used: everything below would silently vanish on pod stop.
if ! mountpoint -q "$WORKSPACE" 2>/dev/null; then
  printf '\033[1;33m    WARNING: %s is not a mount point.\033[0m\n' "$WORKSPACE"
  printf '             The venv and checkpoints will NOT survive a pod restart.\n'
  printf '             Attach a network volume unless this is deliberate.\n'
  printf '             Continuing in 10s -- Ctrl-C to abort.\n'
  sleep 10
else
  ok "$WORKSPACE is a network volume mount"
fi

command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi not found." \
  "This pod has no GPU runtime. Recreate it with a GPU type selected."

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
DRIVER_MAJOR=${DRIVER%%.*}
ok "GPU: $GPU_NAME"
ok "driver: $DRIVER"

if [ "$DRIVER_MAJOR" -lt "$MIN_DRIVER" ]; then
  die "driver $DRIVER is too old for CUDA 13 (need >= $MIN_DRIVER)." \
"torch==2.11.0 requires the CUDA 13 stack, and this HOST driver cannot run it.
      The cu1300 image does not guarantee the host driver -- you must filter for it.

      Terminate this pod, then redeploy with:
        Deploy -> Additional filters -> CUDA Versions -> select 13.x
      That schedules you onto a host with driver >= $MIN_DRIVER.

      /workspace survives termination, so the repo and any cached env persist.
      (Forward compatibility is not an option here: cuda-compat-13-x itself
      needs a >= 580 base driver, and it is unsupported on GeForce cards.)"
fi
ok "driver supports CUDA 13"

[ -n "${WANDB_API_KEY:-}" ] || die "WANDB_API_KEY is not set." \
"Add it as a pod environment variable:
        WANDB_API_KEY = {{ RUNPOD_SECRET_wandb_api_key }}
      after creating the secret under Settings -> Secrets."
ok "WANDB_API_KEY is set"

[ -f "$LOCK" ] || die "lock file not found at $LOCK" \
  "Run this script from inside the cloned repo."

# Optional: only needed for --push runs. Warn rather than abort, so a pod that
# is only training does not fail on a missing token it will never use.
if [ -n "${HF_TOKEN:-}" ]; then
  ok "HF_TOKEN is set (Hub pushes available)"
else
  printf '    \033[0;33m--\033[0m  HF_TOKEN not set -- `train_pusht_toy.sh --push` will fail.\n'
  printf '        Add a WRITE-scope token as a pod env var if you want Hub uploads:\n'
  printf '        HF_TOKEN = {{ RUNPOD_SECRET_hf_token }}\n'
fi

AVAIL_KB=$(df -Pk "$WORKSPACE" | awk 'NR==2 {print $4}')
if [ "$AVAIL_KB" -lt 15000000 ]; then
  die "only $((AVAIL_KB/1024/1024)) GB free on $WORKSPACE (need ~15 GB)." \
    "Create a larger network volume, or clear $WORKSPACE/.cache."
fi
ok "$((AVAIL_KB/1024/1024)) GB free on $WORKSPACE"

# ------------------------------------------------------- B. idempotence gate
# The stamp records the lock hash it was built from, so a changed lock file
# correctly forces a rebuild instead of silently running a stale environment.
LOCK_HASH=$(sha256sum "$LOCK" | cut -d' ' -f1)

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$LOCK_HASH" ]; then
  say "Environment already provisioned -- skipping install"
  ok "lock hash matches $STAMP"
  SKIP_INSTALL=1
else
  [ -f "$STAMP" ] && say "Lock file changed since last bootstrap -- reinstalling"
  SKIP_INSTALL=0
fi

if [ "$SKIP_INSTALL" -eq 0 ]; then
  # ------------------------------------------------------------- C. install
  say "Installing uv and creating the venv"
  if [ ! -x "$UV_BIN" ]; then
    # Keep uv on the volume too, so a restarted pod does not re-download it.
    export UV_INSTALL_DIR="$WORKSPACE/.local/bin"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  export PATH="$WORKSPACE/.local/bin:$PATH"
  export UV_CACHE_DIR="$WORKSPACE/.cache/uv"
  ok "uv $("$UV_BIN" --version | awk '{print $2}')"

  [ -d "$VENV" ] || "$UV_BIN" venv --python 3.12 "$VENV"
  ok "venv at $VENV"

  # Three sequenced passes, deliberately not one --extra-index-url resolve:
  # with an extra index uv may prefer the plain-PyPI torch==2.11.0 over the
  # cu130 build, which is exactly the silent stack swap we are avoiding.
  say "1/3  torch + torchvision from the cu130 index"
  "$UV_BIN" pip install --python "$VENV/bin/python" \
    --index-url "$CUDA_INDEX" \
    torch==2.11.0 torchvision==0.26.0

  # cuda-bindings is absent from the cu130 index (pytorch/pytorch#172926), so
  # torch's own dependency has to come from PyPI in a separate pass.
  say "2/3  CUDA deps the cu130 index is missing (from PyPI)"
  "$UV_BIN" pip install --python "$VENV/bin/python" \
    cuda-bindings==13.3.1 cuda-toolkit==13.0.2

  say "3/3  everything else from the lock file"
  # torch/torchvision are filtered out so pass 1 is not clobbered by the
  # untagged `torch==2.11.0` line in the lock (uv pip freeze strips +cu130).
  TMP_REQ=$(mktemp)
  grep -viE '^(torch|torchvision)==' "$LOCK" > "$TMP_REQ"
  "$UV_BIN" pip install --python "$VENV/bin/python" -r "$TMP_REQ"
  rm -f "$TMP_REQ"

  # ------------------------------------------------------ D. headless fixes
  say "Applying headless-container fixes"
  # The GUI opencv build comes from gymnasium[other], not LeRobot (which pins
  # only opencv-python-headless). Removing it avoids the libGL/X11 import
  # failure without touching anything LeRobot depends on.
  if "$VENV/bin/python" -c "import importlib.metadata as m; m.version('opencv-python')" 2>/dev/null; then
    "$UV_BIN" pip uninstall --python "$VENV/bin/python" opencv-python
    ok "removed GUI opencv-python (kept opencv-python-headless)"
  fi

  # torchcodec links against system FFmpeg; without these the video backend
  # dies at the first dataloader batch, before step 1.
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      ffmpeg libgl1 libglib2.0-0 >/dev/null
    ok "ffmpeg + libgl1 + libglib2.0-0"
  fi
fi

# ------------------------------------------------- E. caches on the volume
say "Writing $ENV_SH"
mkdir -p "$WORKSPACE/.cache"
cat > "$ENV_SH" <<EOF
# Sourced by the training scripts and by interactive shells on this pod.
export PATH="$WORKSPACE/.local/bin:\$PATH"
export VIRTUAL_ENV="$VENV"
export PATH="$VENV/bin:\$PATH"

# Caches on the network volume: without TORCH_HOME the ResNet18 backbone is
# re-downloaded on every pod restart.
export HF_HOME="$WORKSPACE/.cache/huggingface"
export TORCH_HOME="$WORKSPACE/.cache/torch"
export UV_CACHE_DIR="$WORKSPACE/.cache/uv"

# pygame renders PushT eval frames with no display attached.
export SDL_VIDEODRIVER=dummy
export MPLBACKEND=Agg
EOF
ok "$ENV_SH"

# Make interactive shells pick it up too, so an ssh session behaves the same
# as the training script without the user having to remember to source it.
if ! grep -q "lerobot-env/env.sh" /root/.bashrc 2>/dev/null; then
  echo "[ -f $ENV_SH ] && . $ENV_SH" >> /root/.bashrc
  ok "sourced from /root/.bashrc"
fi

# --------------------------------------------------------- F. verify + stamp
say "Verifying"
# shellcheck disable=SC1090
. "$ENV_SH"

"$VENV/bin/python" - <<'PY'
import sys
import torch

print(f"    torch          {torch.__version__}")
print(f"    torch.cuda     {torch.version.cuda}")
print(f"    is_available   {torch.cuda.is_available()}")

if not torch.cuda.is_available():
    sys.exit("torch cannot see the GPU -- driver/CUDA mismatch")

major, minor = torch.cuda.get_device_capability()
print(f"    device         {torch.cuda.get_device_name(0)} (sm_{major}{minor})")
print(f"    bf16           {torch.cuda.is_bf16_supported()}")

if not torch.__version__.startswith("2.11.0"):
    sys.exit(f"expected torch 2.11.0, got {torch.__version__}")
if not (torch.version.cuda or "").startswith("13"):
    sys.exit(f"expected a CUDA 13 build, got cuda={torch.version.cuda}")
PY
ok "torch sees the GPU with the expected CUDA 13 build"

# Exercise the exact headless pygame path that would otherwise crash at the
# first eval, 2500 steps in. Five seconds here beats ten minutes there.
"$VENV/bin/python" - <<'PY'
import gymnasium as gym
import gym_pusht  # noqa: F401  (registers gym_pusht/PushT-v0)

env = gym.make("gym_pusht/PushT-v0", obs_type="pixels_agent_pos", render_mode="rgb_array")
obs, _ = env.reset(seed=0)
frame = env.render()
env.close()
print(f"    PushT reset ok, obs keys {sorted(obs)}, frame {frame.shape}")
PY
ok "headless PushT renders"

"$VENV/bin/python" -c "import lerobot; print('    lerobot       ', lerobot.__version__)" 2>/dev/null \
  || ok "lerobot importable (no __version__ attribute)"

# Only stamp after every check has passed -- a failed bootstrap must never
# mark itself complete, or the next run would skip straight past the problem.
echo "$LOCK_HASH" > "$STAMP"

N_PKGS=$("$UV_BIN" pip freeze --python "$VENV/bin/python" 2>/dev/null | wc -l)
say "Bootstrap complete -- $N_PKGS packages"
printf '    next: bash scripts/train_pusht_toy.sh --steps=200   # smoke test\n'
printf '          bash scripts/train_pusht_toy.sh               # full run\n\n'
