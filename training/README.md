# training/ — ACT on the 50-episode dataset

The Phase-A policy run: train ACT on `so101_cube_to_bowl_50` using **both cameras**, pick a
checkpoint, and hand it to the 10-trial real-robot evaluation that settles **G2**
([`docs/progress.md`](../docs/progress.md)).

| Script | Job |
|---|---|
| `train_act.sh` | The whole run — preflight, throughput smoke test, overnight training, resume, publish. |

```bash
cd training
./train_act.sh info      # resolved config + what ACT will build from the dataset
./train_act.sh check     # venv, GPU headroom, dataset integrity, W&B, free output dir
./train_act.sh smoke     # 500 throwaway steps; measures it/s + peak VRAM, estimates the run
tmux new -s act
./train_act.sh train     # the real run
```

Everything tunable is in the `CONFIG` block at the top of the script. This file explains
*why* those values are what they are.

---

## Both cameras is the default, not a flag

ACT derives `input_features` from the dataset. Every `observation.images.*` key present
becomes a camera view with **its own ResNet18 backbone**, whose feature map is flattened into
the transformer encoder's token sequence. This dataset carries `top` and `wrist`, so a plain
`lerobot-train --policy.type=act` already trains the two-camera policy. There is nothing to
add.

The failure mode runs the other way: a camera that silently *didn't* make it into the dataset
produces a quietly worse policy that you only discover at evaluation. So `info` and `check`
print the camera keys, resolutions and codec read straight out of `meta/info.json`, and warn
if fewer than two are found. Read that block before starting a 7-hour run.

The **single-camera** variant is the one that takes work — it is the Phase-B ablation, and it
needs a forked copy of the dataset with the wrist stream removed
(`lerobot-edit-dataset --operation.type=remove_feature`, with `--new_repo_id` so the edit is
not in place). `../data_collection/record_episodes.sh info` prints that command.

---

## What is actually being trained

Nothing in the script overrides ACT's architecture. Those come from
`configuration_act.py` in the pinned `lerobot==0.6.0`, and they are the ALOHA-paper defaults:

| | |
|---|---|
| `chunk_size` / `n_action_steps` | 100 / 100 — the policy predicts 100 actions and executes all 100 (3.3 s at 30 fps) |
| `vision_backbone` | `resnet18`, ImageNet-pretrained, **one per camera** |
| `dim_model` / `n_heads` | 512 / 8, 4 encoder layers, 1 decoder layer |
| `use_vae` / `kl_weight` | true / 10.0 — the CVAE objective the paper's "style variable" comes from |
| `temporal_ensemble_coeff` | `None` — temporal ensembling **off** |
| optimizer | AdamW, lr 1e-5, backbone lr 1e-5, weight decay 1e-4 |

Two of those are worth knowing before you read the ACT paper in week 4:

**Temporal ensembling is off by default.** The paper's ensembling — querying the policy every
step and exponentially averaging overlapping chunks — is an *inference-time* choice, and
LeRobot disables it because it requires `n_action_steps=1`. It costs nothing at training time,
so the same checkpoint can be evaluated both ways. If the arm is jerky at chunk boundaries
during the G2 trials, that is the first thing to try.

**Only 1 decoder layer.** Not a LeRobot simplification — the original ACT implementation has a
bug where only the first of its 7 decoder layers is used
([tonyzhaozh/act#25](https://github.com/tonyzhaozh/act/issues/25)), and LeRobot matches the
behaviour rather than the config. Worth having in hand when the paper says seven.

---

## The numbers in CONFIG

**`STEPS=100000`** — LeRobot's default, and the community norm for ~50 SO-101 episodes.
At 17,953 frames and batch 8 that is ~45 epochs. ACT on a dataset this size usually converges
well before the end, which is why `SAVE_FREQ=10000` keeps ten checkpoints: you choose one
afterwards rather than trusting the last.

**`BATCH_SIZE=8`** — leave it for the first run. ACT's `lr=1e-5` preset is tuned for batch 8,
so raising the batch silently changes the effective step size, and the result stops being
comparable to every published SO-101 ACT baseline. The 3080 has room (`smoke` reports peak
VRAM), but "it fits" is not a reason — spend the headroom only if a later run is
throughput-bound *and* you adjust the learning rate deliberately.

**`NUM_WORKERS=8`** — the dataset's videos are **AV1** (`video.codec: av1` in
`meta/info.json`), and LeRobot decodes them with torchcodec **on the CPU** inside the dataloader
workers: the decoder cannot use the GPU there, since initializing CUDA in a worker process
breaks. Each step needs 8 random frames × 2 cameras seeked out of AV1, which is more expensive
than the H.264 most tutorials assume, so this was the suspected bottleneck. **Measured, it is
not** — see below. LeRobot's default of 4 workers may also be fine; 8 is what was measured on
this 16-core box and there is no reason to go lower.

If a future run *does* come out dataloader-bound (`smoke` says so explicitly), raise
`NUM_WORKERS`, then set **`RETURN_UINT8=true`**, which ships frames over the worker→trainer IPC
boundary as uint8 instead of float32 — 4× less to copy, converted on the GPU.

**`EVAL_SPLIT=0.1` + `EVAL_STEPS=2000`** — holds out the last 5 of 50 episodes and computes a
loss on them every 2000 steps. This is a real trade: 45 training episodes instead of 50, on a
dataset that is already small.

It is worth it here because **there is no simulator for this task**. `--env_eval_freq` is
pinned to 0 in the script for exactly that reason — there is no gym env to roll out in, so
without a held-out split the *only* number the overnight run produces is a training loss,
which falls monotonically and tells you nothing about when to stop. The held-out loss is what
turns "ten checkpoints" into "this checkpoint".

Do not over-read it: for behaviour cloning, validation loss tracks overfitting well and task
success only loosely — a policy can improve on the real robot while the eval loss is flat.
It picks the checkpoint; the 10 real trials decide G2.

**`--policy.push_to_hub=false`, always.** LeRobot uploads at the *end* of training, so a bad
token turns a 7-hour run into a 7-hour run with no artifact. Publication is a separate,
confirmed step here — same reasoning as
[`../data_collection/push_dataset.sh`](../data_collection/push_dataset.sh):

```bash
./train_act.sh push            # the 'last' checkpoint
./train_act.sh push 050000     # a specific one
```

---

## Measured on this machine — 2026-09-21

500-step smoke run, batch 8, both cameras, `NUM_WORKERS=8`, RTX 3080 with a desktop session:

| | |
|---|---|
| update (GPU) | 0.152 s/step |
| dataloading (CPU, AV1 decode) | **0.002 s/step** |
| throughput | 6.5 steps/s · 52 samples/s |
| peak VRAM | **3.73 GB** of ~9.6 GB usable |
| model | 51.6 M learnable parameters |
| split | 45 train / 5 eval episodes, 16,155 training frames |
| **100k steps** | **~4.3 h** |

Two things to take from this. **It is GPU-bound, not data-bound** — AV1 decode costs ~1% of
step time with 8 workers, so the concern above is handled and `RETURN_UINT8` is not needed.
And **R6 does not bind here**: 3.73 GB peak on a 10 GB card is comfortable, which makes ACT
the cheapest thing this project will train. The 3B-class VLAs in Phase C are where the cloud
escape hatch earns its keep.

4.3 hours is a long evening rather than a full night, so the run can start after dinner and be
read over breakfast. Re-run `smoke` after any CONFIG change rather than trusting these numbers.

---

## Running it overnight

`lerobot-train` refuses to reuse an existing `output_dir`, which is a feature: it makes an
accidental overwrite of a finished run impossible. To run a second experiment, change
`JOB_NAME` in CONFIG — that renames the output dir, the log and the W&B run together.

Use tmux. The script warns and pauses 5 seconds if it is not inside one, because a closed
terminal or a dropped SSH session kills the run:

```bash
tmux new -s act
./train_act.sh train
# Ctrl-b d to detach; tmux attach -t act to come back
```

### Keeping the machine up

Checked on this workstation, 2026-09-21 — **it is already safe**, and the script does not
change any of it permanently:

| | |
|---|---|
| `sleep-inactive-ac-type` | `'nothing'` — GNOME automatic suspend is **off** on AC |
| chassis | desktop (DMI type 3, MSI MS-7B85) — no lid, no battery, so every `lid-close-*` and `*-battery-*` setting is inert |
| `Unattended-Upgrade::Automatic-Reboot` | not set — no overnight reboot |
| `idle-delay` / screen lock | 300 s / on — **harmless**, and mildly helpful |

The screen blanking and locking after 5 minutes does **not** touch training. Leave it on: a
blanked screen is a slightly idler desktop compositor, which gives the run back a little of the
~0.9 GB of VRAM GNOME holds. There is no reason to run this with the display awake.

`train` still re-execs itself under a scoped inhibitor:

```
systemd-inhibit --what=sleep:idle:shutdown --mode=block
```

That is belt-and-braces, not a fix for a broken setting — it guards against a manual suspend, a
GNOME power-menu shutdown while the run is going, and against `sleep-inactive-ac-type` being
changed months from now and forgotten. It lasts exactly as long as the job. Confirm it took,
from another terminal:

```bash
systemd-inhibit --list | grep train_act
# train_act.sh  1000 chinmay ... shutdown:sleep:idle  ACT training: act_cube_to_bowl, ~4-5 h  block
```

Note it blocks *logind-mediated* shutdown — the GNOME menu, `systemctl poweroff` as your user.
A root `systemctl poweroff --force`, a power cut, or a kernel panic still wins; that is what
`SAVE_FREQ` and `./train_act.sh resume` are for.

Two things the inhibitor does not cover. `apt-daily-upgrade.timer` fires **06:03** daily — a
4.3 h run started in the evening is long finished, but an early-morning start could have
packages installed underneath it, and an NVIDIA driver update mid-run breaks CUDA for the
already-running process. And on a pod (`WHERE=runpod`) the inhibitor is skipped entirely, since
there is no logind session to inhibit and RunPod stops the pod on its own schedule.

Output lands in gitignored `../outputs/`:

```
outputs/train/act_cube_to_bowl/checkpoints/{010000,...,last}/pretrained_model/
outputs/logs/act_cube_to_bowl.log
```

### If it dies partway

**There is no W&B checkpoint to restart from, and there is not meant to be.** `train` passes
`--wandb.disable_artifact=true`, so `WandBLogger.log_policy` returns before it builds an
artifact and nothing is ever uploaded. W&B holds metrics here, not weights. Resume reads from
local disk:

```bash
./train_act.sh resume
```

It reports the step it is picking up from and the time remaining before it starts, so an
interruption's real cost is visible before you spend hours redoing it.

What `checkpoints/<step>/` actually holds, and what resume restores from it:

| | |
|---|---|
| `pretrained_model/` | weights, policy config, **`train_config.json`** (the resume entry point) |
| `training_state/` | optimizer state, LR scheduler state, **RNG state**, step counter |
| restored | step, optimizer, scheduler, RNG, and the data order — LeRobot recomputes the dataloader offset from the saved `num_processes × batch_size`, so the resume is *sample-exact*, not just "same weights" |
| `checkpoints/last` | a symlink to the newest one, so it costs no disk |

**W&B continues the same run, it does not fork a new one.** `wandb.init` is called with
`resume="must"` and the run id recovered from `cfg.wandb.run_id` in the checkpoint's
`train_config.json` (falling back to globbing `<output_dir>/wandb/latest-run/`). The loss curve
carries on across the gap rather than restarting at step 0 in a second run.

That strictness is also the one trap: `resume="must"` means wandb **raises** if the id cannot
be resolved — a W&B run deleted server-side, or a first run made with `WANDB_ENABLE=false`,
fails the resume at startup rather than quietly opening a new run. Re-run with
`--wandb.enable=false` to get training back without it.

**Worst case you lose `SAVE_FREQ` steps** — 10,000 at ~6.5 steps/s is about **26 minutes** of
the 4.3 h run. Each ACT checkpoint is roughly 620 MB (206 MB of fp32 weights plus AdamW's two
moments), so all ten cost ~6 GB against 330 GB free. Halve `SAVE_FREQ` if you would rather
trade disk for a shorter redo.

Resume deliberately gets the **same `systemd-inhibit` wrapper** as `train` — picking a run back
up is precisely when the machine is unattended.

One asymmetry to know: on resume the **checkpoint's** config wins over CONFIG. Editing
`BATCH_SIZE` or `STEPS` in the script and then resuming changes nothing; flags passed after
`resume` are the only override.

### Checkpoints that survive the machine

Resume protects against a crash, not against losing the disk. If you want that — and you will
in Phase C, where the GPU is rented and the pod is temporary — LeRobot can push every
checkpoint as it is written:

```bash
./train_act.sh train --save_checkpoint_to_hub=true --policy.repo_id=chinmaykurade/act_cube_to_bowl
```

Then `lerobot-train --config_path=chinmaykurade/act_cube_to_bowl --resume=true` resumes from the
Hub copy on *any* machine. It is off by default here because it uploads ~206 MB per checkpoint
from a workstation whose disk is not going anywhere, and because each pushed checkpoint is
public unless `--policy.private=true` — which is the kind of thing this repo makes a deliberate
step rather than a default.

---

## Running it on a rented GPU

`train_act.sh` uses the same local/pod detection as
[`../scripts/train_pusht_toy.sh`](../scripts/train_pusht_toy.sh), so it runs unchanged on a
RunPod pod after `scripts/runpod_bootstrap.sh` — see [`../scripts/README.md`](../scripts/README.md).
On a pod the dataset is not on disk, so it is pulled from the Hub by `repo_id`, which works
because the 50-episode dataset was published. Outputs go to `/workspace/outputs` instead.

This is not needed for ACT — it is a ~50M-parameter model and the 3080 handles it overnight.
It is here so Phase C's VLA fine-tune inherits a job that already works.

---

## Reference

- LeRobot — [Imitation Learning on Real-World Robots](https://huggingface.co/docs/lerobot/il_robots)
  (the `lerobot-train` walkthrough, checkpoint upload, and `lerobot-rollout` for evaluation)
- Zhao et al. — *Learning Fine-Grained Bimanual Manipulation with Low-Cost Hardware* (ACT/ALOHA),
  [arXiv:2304.13705](https://arxiv.org/abs/2304.13705) — the L-A week-4 [Deep] item
- `lerobot==0.6.0` sources: `lerobot/policies/act/configuration_act.py` (every default above),
  `modeling_act.py` (the LeRobot code-read 4 target), `configs/train.py` (the flags)
