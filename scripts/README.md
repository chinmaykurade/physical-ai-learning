# scripts/ — cloud training on RunPod

Automation for running LeRobot training jobs on a rented GPU. Two scripts:

| Script | Job |
|---|---|
| `runpod_bootstrap.sh` | Builds the pinned environment on the pod's network volume. Idempotent — safe and fast to re-run. |
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
git clone https://github.com/chinmaykurade/physical-ai-learning.git
cd physical-ai-learning

bash scripts/runpod_bootstrap.sh              # ~6-8 min first boot, ~5 s after
bash scripts/train_pusht_toy.sh --steps=200   # smoke test, ~1 min
bash scripts/train_pusht_toy.sh               # full 5000-step run
```

For a long run, use `tmux` so a dropped SSH session doesn't kill training:

```bash
tmux new -s train
bash scripts/train_pusht_toy.sh
# detach with Ctrl-b d ; reattach later with: tmux attach -t train
```

The script also tees to `/workspace/outputs/logs/<job-name>.log` either way.

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

**Driver requirement.** CUDA 13.x needs host driver **≥ 580**. RunPod hosts running the
`cu1300` images have been observed at 580.126.09, so this normally passes, but the image name
constrains the container and not the host — there is still no `--min-cuda-version` filter
([runpodctl#253](https://github.com/runpod/runpodctl/issues/253)). The bootstrap asserts it in
the first few seconds and aborts with instructions rather than failing deep inside an install.

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
