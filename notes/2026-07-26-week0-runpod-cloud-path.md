# Week 0 — proving the cloud training path

**2026-07-26 (Sun)** · build Phase 0 · study L0 · *written same-day rather than at the
Saturday slot: this was day 1 and the whole thing happened in one sitting.*

---

## What I did

Built and proved the RunPod path end to end, ahead of when the plan needs it. Phase C rents an
A100 for a GR00T N1.7 / π0 LoRA fine-tune (₹2,000–3,000); debugging cloud plumbing at A100
rates is the expensive way to learn it. So I ran the same pusht Diffusion Policy job that
already worked locally, on a rented GPU, for roughly $0.30.

Result: pod → prebaked env → training → W&B → Hub push, all working. Weights live at
`chinmaykurade/pusht_diffusion_runpod_01` (private, 1.05 GB), 2000 steps, batch 64, logged to
W&B project `so101-embodied-ai`.

Artifacts: `scripts/runpod_bootstrap.sh`, `scripts/train_pusht_toy.sh`,
`scripts/build_image.sh`, `docker/Dockerfile`, `docker/verify.py`,
`docker/RUNPOD_TEMPLATE.md`.

---

## What I learned

**`torch==2.11.0` is a CUDA-13 build, and that is not negotiable.** Its wheel metadata
hard-requires `cuda-toolkit==13.0.2`, `cuda-bindings>=13.0.3`, `nvidia-cudnn-cu13`,
`nvidia-nccl-cu13`, `triton==3.6.0`. There is no "same torch on cu128". This is why none of
RunPod's PyTorch templates work — the newest torch they ship is 2.9.1. Everything else about
the image design follows from this one fact.

**A container image name says nothing about the host driver.** I deployed a `cu1300` image
and landed an RTX 4090 on driver **570.211.01**. CUDA 13.x needs ≥ 580. The fix is a
deploy-time setting — *Additional filters → CUDA Versions → 13.x* — which **cannot be saved
into a template**, so it is a manual click on every single deploy. This is the thing most
likely to bite me again in Phase C.

Forward compatibility is not an escape hatch either: `cuda-compat-13-x` needs a ≥ 580 base
driver *itself*, and NVIDIA only supports it on Data Center GPUs, not GeForce cards.

**`opencv-python` and `opencv-python-headless` share one `cv2/` directory.** Uninstalling the
GUI build to fix a headless container deletes files the headless build still needs. `cv2` then
*imports fine* and has no attributes — surfacing as `module 'cv2' has no attribute 'resize'`
from deep inside a gym_pusht render. Reinstalling headless afterwards repairs it. The lesson
that generalises: **check a library by attribute, not by import**, when two distributions
overlap on disk.

**Docker layers are additive.** I tried to shrink the image by `pip uninstall`-ing the base
image's unused torch 2.9.1, which does nothing — deleted files still occupy the layer beneath,
and the whiteout markers *add* a little. The only fix is to not start from that image. Moved
`FROM runpod/pytorch:*` → `runpod/base:*-cuda1300-*` (6.9 GB vs 10.5 GB compressed).

**`uv pip freeze` strips the local version tag.** The lock recorded `torch==2.11.0`, not
`torch==2.11.0+cu130`, and carries no index URL. So the lock file alone does not reproduce the
environment — the cu130 index has to be supplied separately. Worth remembering before trusting
any lock file as a complete build input.

**Also:** the lock was 38 packages stale (missing `wandb`, which the training command needs).
`uv pip freeze` after every change is a real instruction, not a nicety.

**The toy training job needs `--eval.use_async_envs=false`.** LeRobot 0.6.0 constructs
`AsyncVectorEnv` with `context="forkserver"` but does not preload `gym_pusht` in the workers, so
each worker starts a fresh interpreter without the env registered and dies on
`NamespaceNotFound`. Disabling async envs sidesteps it. This applies to the local 5000-step run
and any future pusht eval — worth remembering rather than re-diagnosing.

**The R8 fuse and kill-switch parts, for reordering.** Littelfuse ATOF 287 blade fuses
`0287005.PXCN` (5 A, the primary) and `028707.5PXCN` (7.5 A, the step-up if the 5 A nuisance-
trips under stall current), an inline ATO blade fuse holder, and a Daier `KCD3-101N-R`
illuminated rocker (12 V lamp, SPST, 20 A/125 VAC). The fuse sits in series between PSU and
motor driver, so wiring the PSU straight to the driver never displaced the need for it — which
is why the BOM-C cut of this line was reversed the same day it was made.

---

## What surprised me

How much of the difficulty was *packaging*, not machine learning. The training itself was the
easy part — it ran first time. Everything hard was dependency resolution, container layering,
driver compatibility, and auth. That is probably the honest shape of MLOps work and worth
remembering before I assume Phase C's difficulty lies in the model.

The preflight-check discipline paid for itself immediately. Every failure this session was
caught in seconds by a cheap assertion rather than 10 minutes into an install or 2500 steps
into a run. Cost of writing the checks: maybe 20 minutes. Cost of not having them, on an
A100: considerably more.

---

## What moved

Nothing to the backlog. No study items deferred, no depth tags demoted, and the one [Deep]
slot stays empty (L0 has no [Deep] items; Karpathy micrograd is a Deep-*course*, which does
not occupy the slot).

This work does **not** move the Phase-0 gate — the toy-training exit criterion was already met
locally earlier today. This is Phase-C infrastructure arriving early, which is allowed:
roadmap §8 rule 3 says the build never blocks on study and study never blocks on the build,
and this blocked neither.

---

## Next

- **Simulated teleoperation** — the last software Phase-0 exit criterion, and unblocked now.
- Study L0 Core: HF Robotics Course Unit 0, MuJoCo Overview, load the Menagerie SO-ARM100
  model (study exit criterion). Karpathy micrograd continues.
- Everything else in Phase 0 waits on the BOM delivery and the printer.

For Phase C, when the A100 arrives: size the network volume 100–200 GB (not 50), create it in
a datacenter that actually has A100/H100 stock, and remember the CUDA filter.
