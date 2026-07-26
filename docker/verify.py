"""Build-time checks for the prebuilt image.

Runs inside `docker build`, so it must not need a GPU. Its job is to make a
broken environment fail the build instead of shipping and failing on a pod.

Kept as a file rather than an inline `RUN python -c` because the escaping in a
multi-line one-liner hides which assertion actually failed.
"""

import sys


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


# --- torch: the whole point of the image is the cu130 stack -----------------
import torch

print(f"torch {torch.__version__}  cuda {torch.version.cuda}")
if not torch.__version__.startswith("2.11.0"):
    fail(f"expected torch 2.11.0, got {torch.__version__}")
if not (torch.version.cuda or "").startswith("13"):
    fail(f"expected a CUDA 13 build, got cuda={torch.version.cuda}")

# torch.cuda.is_available() is deliberately NOT checked: the build host has no
# GPU. That check belongs in runpod_bootstrap.sh, which runs on the pod.

# --- cv2: opencv-python and -headless share one cv2/ directory --------------
# Uninstalling the GUI build deletes files the headless build still needs, and
# the result is an importable-but-empty module. Check an attribute, not just
# the import, or this failure reaches the pod disguised as a gym_pusht error.
import cv2

if not hasattr(cv2, "resize"):
    fail(
        "cv2 imports but has no `resize` -- the opencv-python uninstall "
        "gutted the shared cv2/ directory. Reinstall opencv-python-headless."
    )
print(f"cv2 {cv2.__version__} (headless)")

# --- pygame + gym_pusht render with no display ------------------------------
# This is the exact path that would otherwise crash at the first eval, 2500
# steps into a training run.
import gymnasium as gym
import gym_pusht  # noqa: F401  (registers gym_pusht/PushT-v0)

env = gym.make(
    "gym_pusht/PushT-v0", obs_type="pixels_agent_pos", render_mode="rgb_array"
)
obs, _ = env.reset(seed=0)
frame = env.render()
env.close()
if frame is None or frame.shape[2] != 3:
    fail(f"unexpected render output: {None if frame is None else frame.shape}")
print(f"headless PushT ok  obs={sorted(obs)}  frame={frame.shape}")

# --- lerobot entry points ---------------------------------------------------
import shutil

if shutil.which("lerobot-train") is None:
    fail("lerobot-train is not on PATH")
print("lerobot-train on PATH")

print("\nall build checks passed")
