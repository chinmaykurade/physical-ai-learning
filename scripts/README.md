# scripts/ — cloud training on RunPod

Automation for running LeRobot training jobs on a rented GPU. Two scripts:

| Script | Job |
|---|---|
| `runpod_bootstrap.sh` | Prepares the environment on the pod. Idempotent — safe and fast to re-run. |
| `build_image.sh` | Builds and pushes the prebuilt image (see [Prebuilt image](#prebuilt-image-faster-cold-starts)). |
| `train_pusht_toy.sh` | The canonical pusht Diffusion-Policy job. Runs unchanged on the workstation *and* on a pod. Optional `--push` uploads weights to the HF Hub. |

The intended loop is: **ssh in → `runpod_bootstrap.sh` → `train_pusht_toy.sh` → stop the pod.**
No manual package installs, no debugging on the pod. Anything that can fail is checked in the
bootstrap's preflight, which takes seconds.

---

## Why this exists

Phase C rents an A100 for a GR00T N1.7 / π0 LoRA fine-tune ([`docs/progress.md`](../docs/progress.md)).
Debugging cloud plumbing at A100 rates is the expensive way to learn it, so this proves the
whole path — env → dataset → training → W&B → checkpoints on persistent storage → teardown —
on a ~$0.30 test run using a job that already works locally.

---

## One-time account setup

Do all three **before** creating a pod. Two of them cannot be added to a running pod without
recreating it.

**1. SSH key.** If you don't already have one:

```bash
ssh-keygen -t ed25519 -C "chinmayk202@gmail.com"
cat ~/.ssh/id_ed25519.pub
```

Paste the public key into **Settings → SSH Public Keys**.

**2. W&B secret.** **Settings → Secrets → Create Secret**, name it `wandb_api_key`, value is
the key from your local [`.env`](../.env.example). Storing it as a secret rather than a plain
env var keeps it out of the template definition.

**2b. HF token secret** (only if you want `--push`). Create a **write-scope** token at
[huggingface.co/settings/tokens](https://huggingface.co/settings/tokens), then add it as a
second secret named `hf_token`. See [Pushing weights to the Hub](#pushing-weights-to-the-hub).

**3. Network volume.** **Storage → Network Volume → Create**. 50 GB is ample for this test —
it holds the venv (~8 GB), the HF dataset cache, and checkpoints.

> **Note the datacenter it lands in.** A network volume is pinned to one datacenter, and pods
> must be created there. This constrains which GPUs you can rent. For Phase C, create the
> volume in a datacenter that actually has A100/H100 stock, and size it 100–200 GB for a
> 3B-class LoRA.

---

## Creating the pod

**Pods → Deploy**, then:

| Field | Value |
|---|---|
| Datacenter | The one holding your network volume |
| **CUDA filter** | **Additional filters → CUDA Versions → 13.x.** Required — see below |
| GPU | **RTX A5000** (~$0.27/hr) for plumbing tests |
| Container image | `runpod/pytorch:1.1.0-cu1300-torch291-ubuntu2404` |
| Network volume | Attach it — mount path `/workspace` |
| Container disk | 20 GB (everything persistent lives on the volume) |
| Environment variable | `WANDB_API_KEY` = `{{ RUNPOD_SECRET_wandb_api_key }}` |
| Environment variable | `HF_TOKEN` = `{{ RUNPOD_SECRET_hf_token }}` — only needed for `--push` |
| Container start command | Leave empty — the image's own sshd entrypoint is what we want |

Then **Deploy On-Demand**.

The image is entered as a **custom image**, not chosen from the template list — click
**Change Template** and type it into the *Container Image* field. See
[Choosing the image](#choosing-the-image) for why none of the listed templates work.

**GPU choice.** Avoid the RTX 2000 Ada: it is *slower than the RTX 3080* you already own, so
it proves nothing you can't prove at home. Use an A5000 for plumbing, or a 4090 (~$0.69/hr) if
you want a number roughly comparable to the 3080.

---

## Running

Connect via the pod's **Connect** button:

```bash
ssh <pod-id>-<hash>@ssh.runpod.io -i ~/.ssh/id_ed25519
```

This proxied form has no scp/sftp. That needs a pod with a public IP
(`ssh root@<ip> -p <port> -i ~/.ssh/id_ed25519`) — but we don't need file transfer, since the
repo arrives by `git clone`.

```bash
cd /workspace
# Already cloned (the volume survives pod termination)? Just update:
#   cd /workspace/physical-ai-learning && git pull
git clone --depth 1 https://github.com/chinmaykurade/physical-ai-learning.git
cd physical-ai-learning

bash scripts/runpod_bootstrap.sh              # ~6-8 min first boot, ~5 s after
bash scripts/train_pusht_toy.sh --steps=200   # smoke test, ~1 min
bash scripts/train_pusht_toy.sh               # full 5000-step run
```

> **Cloning a private repo.** GitHub dropped password auth for HTTPS, so a plain
> `git clone` of a private repo prompts and fails on the pod. Either make the repo public
> (it holds no secrets — `.env` is gitignored), or add a `repo`-scoped GitHub PAT as a RunPod
> secret and clone with it:
> ```bash
> git clone --depth 1 https://$GITHUB_PAT@github.com/chinmaykurade/physical-ai-learning.git
> ```
> with pod env var `GITHUB_PAT = {{ RUNPOD_SECRET_github_pat }}`, which keeps the token out of
> shell history. The repo is <1 MB, so clone time is never the bottleneck — auth is.

For a long run, use `tmux` so a dropped SSH session doesn't kill training:

```bash
tmux new -s train
bash scripts/train_pusht_toy.sh
# detach with Ctrl-b d ; reattach later with: tmux attach -t train
```

The script also tees to `/workspace/outputs/logs/<job-name>.log` either way.

---

## Prebuilt image (faster cold starts)

The slow part of a first boot is not the repo clone — it is downloading the
**~4.7 GB** torch + CUDA 13 stack from PyPI (`nvidia/cu13` alone is 1.8 GB, torch 1.2 GB,
triton 0.7 GB). [`docker/Dockerfile`](../docker/Dockerfile) bakes that into an image so a
fresh pod pulls it from the registry instead — parallel, resumable, and edge-cached, which is
substantially faster than a serial pip resolve.

```bash
bash scripts/build_image.sh <dockerhub-user>      # ~10-15 min once, then push
```

Then create the template once: **Templates → New Template**, container image
`<dockerhub-user>/lerobot-so101:0.6.0`, volume mount path `/workspace`, and the same two env
vars. Deploy from that template (still with the CUDA 13.x filter).

The bootstrap detects the baked venv at `/opt/lerobot-env` and skips installing entirely —
it just verifies and writes `env.sh`. Same command either way:

```bash
bash scripts/runpod_bootstrap.sh    # prebaked: seconds. volume-built: ~6-8 min.
```

**Cost: nothing.** RunPod templates are free, and Docker Hub allows unlimited *public*
repositories on the free tier (public also means RunPod needs no registry credentials). You
pay only for GPU time and storage as before.

**Caveat.** This does not make the gigabytes vanish — it moves them from boot-time to
build-time and swaps a slow protocol for a fast one. Expect a cold pull of a few minutes
rather than ~6–8 minutes of installing. The bigger wins are that the install becomes
*deterministic* (it either worked at build time or the build failed) and that the image
build asserts torch 2.11.0 + CUDA 13 and a headless PushT render, so a broken environment
cannot ship.

Note the venv is baked at `/opt/lerobot-env`, **not** `/workspace` — the network volume is
mounted over `/workspace` at runtime and would hide anything the image put there.

---

## Pushing weights to the Hub

Pushing is **opt-in** — a smoke test should never publish anything. Add `--push`:

```bash
bash scripts/train_pusht_toy.sh --push                              # -> chinmaykurade/<job-name>
bash scripts/train_pusht_toy.sh --push --private                    # private repo
bash scripts/train_pusht_toy.sh --repo-id=chinmaykurade/my-policy   # explicit name (implies --push)
```

The upload happens **at the end of training**, and LeRobot writes a generated model card
alongside the weights. Uploaded for this policy: `model.safetensors`, `config.json`,
`train_config.json`, both pre/post-processor files, and `README.md` — **~1.05 GB total**,
which takes roughly **2 minutes**. On a rented pod that is billable dead time at the end of
every pushed run, so don't push smoke tests.

Because a failed upload after a long run is the expensive failure mode, the script does a
**hub preflight before training starts**: it verifies a token exists, that the Hub accepts it,
and that you can actually create the target repo. A bad namespace or a read-only token fails
in about two seconds.

### Locally

Authenticate once — no `HF_TOKEN` needed, the CLI caches a token:

```bash
hf auth login          # paste a WRITE-scope token
```

Then try it end to end cheaply, and delete the repo afterwards:

```bash
bash scripts/train_pusht_toy.sh --steps=50 --job-name=hubtest --private \
  --repo-id=chinmaykurade/pusht-diffusion-hubtest
```

### On the pod

A pod has no cached login, so the token **must** come from the environment. Set
`HF_TOKEN = {{ RUNPOD_SECRET_hf_token }}` when creating the pod (see
[Creating the pod](#creating-the-pod)); the bootstrap warns if it is missing rather than
failing, since training without `--push` doesn't need it.

```bash
bash scripts/train_pusht_toy.sh --push --private \
  --repo-id=chinmaykurade/pusht-diffusion-runpod
```

Pushing from the pod is also the practical way to **get weights off a pod you are about to
terminate** — the network volume survives termination, but the Hub copy is what survives
deleting the volume too.

> The token needs **write** scope. A read-scope token authenticates fine and then fails at
> upload — which is exactly why the preflight tries `create_repo` rather than just `whoami`.

---

## Teardown

1. Confirm the W&B run finished in project `so101-embodied-ai`.
2. Confirm checkpoints exist under `/workspace/outputs/train/<job-name>/checkpoints/`.
3. If you pushed, confirm the repo at `https://huggingface.co/<repo-id>` has
   `model.safetensors` — that copy is what survives deleting the volume.
4. **Stop** (square icon) keeps the pod and its volume; **Terminate** (trash icon) deletes the
   pod. The network volume survives both.

GPU billing stops when the pod stops. **The network volume keeps billing** at its hourly rate
whether or not a pod is attached — terminate the volume too when you're done with it entirely.

---

## Choosing the image

The console's default **PyTorch 2.8 / cu128** template is the wrong base, and so is every
other listed template. The reason is a hard constraint, not a preference:

- `lerobot==0.6.0` requires Python ≥ 3.12 and this project pins `torch==2.11.0`.
- That wheel's own metadata hard-requires the **CUDA 13** stack: `cuda-toolkit==13.0.2`,
  `cuda-bindings>=13.0.3`, `nvidia-cudnn-cu13`, `nvidia-nccl-cu13`, `triton==3.6.0`. For this
  LeRobot/Python combination, torch 2.11.0 *is* a CUDA-13 build — there is no "same torch on
  cu128".
- The newest torch RunPod ships in any image is **2.9.1**, so no template reaches 2.11.0.

So we take a `cu1300` image for its CUDA 13 system libraries, Ubuntu 24.04, Python 3.12 and
preconfigured SSH — and **ignore its preinstalled torch**, building our own venv on
`/workspace` from [`env/lerobot-env.lock.txt`](../env/lerobot-env.lock.txt). That is also the
point of the exercise: the lock file is the artifact under test. Building on a template's
torch would make the run pass while telling you nothing about whether your environment
reproduces.

Template names don't guarantee the torch inside them anyway —
[runpod/containers#114](https://github.com/runpod/containers/issues/114) documents a
"PyTorch 2.8.0 cu128" template that shipped torch 2.4.1.

**Driver requirement — set the CUDA filter, or the pod will fail.** CUDA 13.x needs host
driver **≥ 580**. The image name constrains the *container*, not the *host*: a `cu1300` image
lands on driver-570 hosts routinely, and then nothing CUDA-13 can run.

Fix it at deploy time: **Deploy → Additional filters → CUDA Versions → 13.x**. That schedules
you onto a host with a new enough driver. (The equivalent CLI flag still doesn't exist —
[runpodctl#253](https://github.com/runpod/runpodctl/issues/253) — but the console filter
works.)

Observed in practice: an unfiltered deploy landed an RTX 4090 on driver **570.211.01**, and
the bootstrap aborted in ~3 seconds. Terminate and redeploy with the filter set; `/workspace`
survives termination, so nothing is lost.

**Forward compatibility is not a workaround here.** `cuda-compat-13-x` requires a base driver
of ≥ 580 itself, and NVIDIA supports forward compatibility only on Data Center GPUs — not on
GeForce cards like the 4090/A5000. There is no way to run CUDA 13 on a 570 host.

---

## What the bootstrap does

1. **Preflight** — `/workspace` is a real mount; `nvidia-smi` works; driver ≥ 580;
   `WANDB_API_KEY` set; enough free space. Every failure prints a fix.
2. **Idempotence gate** — a stamp file records the lock-file hash it was built from. Matching
   hash ⇒ skip straight to verification. Changed lock ⇒ rebuild. No flags to remember.
3. **Install, in three sequenced passes** — torch/torchvision from the cu130 index; then
   `cuda-bindings` + `cuda-toolkit` from PyPI (they are *missing* from the cu130 index,
   [pytorch#172926](https://github.com/pytorch/pytorch/issues/172926)); then everything else
   from the lock file with torch filtered out. One `--extra-index-url` call would let uv
   silently prefer the plain-PyPI torch, which is the exact stack swap being avoided.
4. **Headless fixes** — removes the GUI `opencv-python` (LeRobot pins only
   `opencv-python-headless`; the GUI build comes from `gymnasium[other]` and wants libGL);
   installs `ffmpeg`, `libgl1`, `libglib2.0-0` for torchcodec's shared libraries.
5. **Caches on the volume** — `HF_HOME`, `TORCH_HOME`, `UV_CACHE_DIR`, `SDL_VIDEODRIVER=dummy`
   written to `/workspace/lerobot-env/env.sh`. `TORCH_HOME` is what stops the ResNet18
   backbone being re-downloaded after every restart.
6. **Verify, then stamp** — asserts torch 2.11.0 + CUDA 13 + a visible GPU, then builds a
   headless `PushT-v0` and renders one frame. That last check exercises the pygame path that
   would otherwise crash at the first eval, 2500 steps in. The stamp is written *only* after
   everything passes.

---

## Gotchas worth knowing

**`--eval.use_async_envs=false` is required, not optional.** LeRobot 0.6.0 builds
`AsyncVectorEnv` with `context="forkserver"` without preloading `gym_pusht`, so worker
processes raise `NamespaceNotFound` on `gym_pusht/PushT-v0`. It is a library bug and it
reproduces on every new machine. Don't drop the flag.

**LeRobot refuses to reuse an output directory.** `train_pusht_toy.sh` checks for this up
front and tells you to pass `--job-name=`, rather than letting you hit the traceback after the
dataset has downloaded.

**Wall-clock is not comparable across GPUs.** The 3080 does the full 5000-step run in ~18 min.
A pod number is informational only.

**W&B project is `so101-embodied-ai`.** Note that
[`neural_networks/wandb_quickstart.py`](../neural_networks/wandb_quickstart.py) uses
`physical-ai` — that was a one-off from the W&B tutorial, not the project convention.

---

## Extending to Phase C

The scaffolding transfers unchanged: CUDA 13 supports Ampere (A100, sm_80) and Hopper
(H100, sm_90) — it dropped only Maxwell, Pascal and Volta. Same image, same wheels, same
bootstrap, same volume layout, same secret wiring. What changes is the GPU dropdown and the
training script.

It does **not** pre-validate GR00T or π0 themselves — `openpi` and `Isaac-GR00T` have their
own dependency stacks that may pin torch differently from `lerobot==0.6.0`. Phase C's task
"read the SO-101 configs in openpi and Isaac-GR00T **before** renting" still stands.
