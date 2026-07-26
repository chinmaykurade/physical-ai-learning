# RunPod template settings

Exact values for **Templates → New Template** in the RunPod console. Create the template once;
after that every pod is two clicks. Built from [`Dockerfile`](Dockerfile) via
[`../scripts/build_image.sh`](../scripts/build_image.sh).

---

## Template fields

| Field | Value |
|---|---|
| **Template Name** | `lerobot-so101` |
| **Template Type** | Pod (GPU) |
| **Container Image** | `chinmaykurade/lerobot-so101:0.6.0` |
| **Container Registry Credentials** | *(none — the image is public)* |
| **Container Disk** | `20` GB |
| **Volume Disk** | *(leave at 0 — a network volume is attached at deploy time instead)* |
| **Volume Mount Path** | `/workspace` |
| **Expose HTTP Ports** | *(empty)* |
| **Expose TCP Ports** | `22` |
| **Container Start Command** | *(leave empty — the image's CMD starts sshd via `/start.sh`)* |

### Environment variables

| Key | Value |
|---|---|
| `WANDB_API_KEY` | `{{ RUNPOD_SECRET_wandb_api_key }}` |
| `HF_TOKEN` | `{{ RUNPOD_SECRET_hf_token }}` |

Both reference **Settings → Secrets** entries, so the keys never appear in the template
definition. `HF_TOKEN` is only needed for `train_pusht_toy.sh --push`; the bootstrap warns
rather than fails when it is missing.

Do **not** set `HF_HOME`, `TORCH_HOME`, `UV_CACHE_DIR`, `SDL_VIDEODRIVER` or `MPLBACKEND`
here — the image already sets them, pointing at `/workspace/.cache/…` so downloads survive
across pods.

---

## Deploying from the template

1. **Pods → Deploy**.
2. **Additional filters → CUDA Versions → 13.x.** *Required.* `torch==2.11.0` needs the CUDA 13
   stack, which needs host driver ≥ 580. Without this filter you will land on a 570 host —
   observed in practice on an RTX 4090 — and the bootstrap will abort.
3. Pick the datacenter that holds your network volume, then the GPU
   (**RTX A5000** ~$0.27/hr for plumbing work).
4. Attach the network volume at `/workspace`.
5. Select the `lerobot-so101` template.
6. **Deploy On-Demand**.

---

## First run

```bash
ssh <pod-id>-<hash>@ssh.runpod.io -i ~/.ssh/id_ed25519

cd /workspace
git clone --depth 1 https://github.com/chinmaykurade/physical-ai-learning.git
cd physical-ai-learning

bash scripts/runpod_bootstrap.sh              # seconds — the env is prebaked
bash scripts/train_pusht_toy.sh --steps=200   # smoke test
bash scripts/train_pusht_toy.sh               # full 5000-step run
```

On later pods the repo is already on the volume — `git pull` instead of cloning.

---

## What the image provides

- Venv at **`/opt/lerobot-env`**, not `/workspace`. The network volume mounts over
  `/workspace` at runtime and would hide anything the image put there. Both scripts detect
  the baked venv and skip installing.
- `torch==2.11.0+cu130`, `lerobot==0.6.0`, and the rest of
  [`../env/lerobot-env.lock.txt`](../env/lerobot-env.lock.txt) — verified at build time by
  [`verify.py`](verify.py), which asserts torch 2.11.0 + CUDA 13, a working `cv2.resize`, a
  headless PushT render, and `lerobot-train` on PATH. A broken environment fails the build
  rather than reaching a pod.
- System `ffmpeg`, `libgl1`, `libglib2.0-0` for torchcodec and headless rendering.

Roughly 30 GB uncompressed / ~10–13 GB compressed. The compressed figure is what a pod pulls.

---

## Troubleshooting

**Bootstrap aborts on the driver.** The CUDA filter was not applied at deploy time. Terminate
and redeploy with **Additional filters → CUDA Versions → 13.x**. `/workspace` survives
termination, so nothing is lost. Forward compatibility is not an option — `cuda-compat-13-x`
needs a ≥ 580 base driver itself and is unsupported on GeForce cards.

**Cannot SSH.** Confirm TCP port 22 is exposed on the template and that your public key is in
**Settings → SSH Public Keys**. The proxy form (`ssh …@ssh.runpod.io`) has no scp/sftp; that
needs a pod with a public IP.

**`git clone` prompts for a password.** GitHub dropped password auth for HTTPS. Either make
the repo public or clone with a PAT — see
[`../scripts/README.md`](../scripts/README.md#running).

**Bumping the image.** The tag pins `lerobot==0.6.0`. Per roadmap §8 rule 2, pins change only
at phase gates — rebuild with a new tag then, and point the template at it. Never move the
`0.6.0` tag.
