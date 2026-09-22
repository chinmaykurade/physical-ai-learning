#!/usr/bin/env bash
#
# train_act.sh — train ACT on the recorded SO-101 dataset, both cameras.
#
# Edit the CONFIG block below, then run a subcommand. Nothing outside CONFIG
# should need changing between runs.
#
#   ./train_act.sh info     # resolved config + the features ACT will infer from the dataset
#   ./train_act.sh check    # preflight: venv, GPU, dataset, W&B, free output dir. Trains nothing
#   ./train_act.sh smoke    # 500 throwaway steps; measures it/s and peak VRAM, estimates the full run
#   ./train_act.sh train    # the real overnight run
#   ./train_act.sh resume   # continue the last run from its newest checkpoint
#   ./train_act.sh best     # rank the checkpoints by held-out eval loss and name the winner
#   ./train_act.sh push     # upload a chosen checkpoint to the Hub (deliberate, like push_dataset.sh)
#                           #   ./train_act.sh push best   resolves the winner automatically
#
# ACT reads its input features FROM THE DATASET: every observation.images.* key
# present becomes a camera stream with its own ResNet18 backbone. This dataset has
# `top` and `wrist`, so both cameras are used with no flag — `check` prints exactly
# what will be consumed so a silently-missing camera cannot go unnoticed. The
# single-camera Phase-B ablation is the variant that needs extra work; see README.md.
#
# Run the overnight job under tmux — a dropped SSH session or a closed terminal
# otherwise kills ~7 hours of training:
#   tmux new -s act ; ./train_act.sh train ; (detach Ctrl-b d, reattach `tmux attach -t act`)
#
# See README.md in this directory for the reasoning behind every number below.

set -euo pipefail

# ============================== CONFIG ======================================

VENV=/home/chinmay/lerobot-env

# --- Which dataset. Must match the CONFIG block in ../data_collection/record_episodes.sh.
HF_USER=chinmaykurade
DATASET_NAME=so101_cube_to_bowl_50

# --- Job identity. JOB_NAME names the output dir, the log, and the W&B run, so
# changing it is how you keep two experiments apart (lerobot REFUSES to reuse an
# existing output_dir unless resuming).
JOB_NAME=act_cube_to_bowl

# --- Training length. lerobot's default is 100k. With 50 episodes / ~18k frames
# that is ~45 epochs; ACT on a dataset this size is typically converged well before
# the end, which is what SAVE_FREQ + the held-out eval loss are for — you pick the
# checkpoint afterwards rather than trusting the last one.
STEPS=100000

# --- Batch size. Leave at 8 for the first run: ACT's lr preset (1e-5, in
# configuration_act.py) is tuned for it, and this is a 10 GB card with a desktop
# session on it (plan risk R6). Raising this changes the effective learning rate.
BATCH_SIZE=8

# --- Dataloader. The videos are AV1 and torchcodec decodes them ON THE CPU inside
# the worker processes (CUDA cannot be initialized in a worker), so this was the
# suspected bottleneck. Measured 2026-09-21 on 16 cores: 0.002 s/step of decode
# against 0.152 s/step of GPU — GPU-bound with room to spare. `smoke` re-checks.
NUM_WORKERS=8

# --- uint8 frames over the dataloader IPC boundary instead of float32: 4x less to
# copy per batch, converted on the GPU side. Turn this on if `smoke` says the run
# is dataloader-bound.
RETURN_UINT8=false

# --- Held-out episodes for an offline eval loss, as a fraction (0.1 = the last 5
# of 50). There is no simulator for this task, so the eval loss is the ONLY
# quantitative signal before the 10-trial real-robot eval (G2). It costs 5 training
# episodes; read README.md before changing it — a BC eval loss tracks overfitting
# well and task success only loosely.
EVAL_SPLIT=0.1
EVAL_STEPS=2000

SAVE_FREQ=10000
LOG_FREQ=200
SEED=1000

# --- W&B. so101-embodied-ai is the project convention (docs/progress.md).
WANDB_ENABLE=true
WANDB_PROJECT=so101-embodied-ai

# --- Publication. Training NEVER pushes: the upload happens at the end of a run,
# where a bad token wastes the whole night, and publishing is a reviewed step in
# this repo (see push_dataset.sh). Use `./train_act.sh push` instead.
POLICY_REPO_ID="${HF_USER}/act_${DATASET_NAME}"
POLICY_PRIVATE=false

# --- Smoke run length. 500 steps is enough for the timing average to settle.
SMOKE_STEPS=500

# ============================ END CONFIG ====================================

REPO_ID="${HF_USER}/${DATASET_NAME}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATASET_ROOT="${REPO_ROOT}/datasets/${DATASET_NAME}"

BIN="${VENV}/bin"
PY="${BIN}/python"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- environment
# Same local/pod split as scripts/train_pusht_toy.sh, so this job runs unchanged
# on a rented GPU in Phase C. On a pod the dataset is not on disk, so it is
# pulled from the Hub by repo_id — which works because it was published.
POD_ENV=""
for candidate in /opt/lerobot-env/env.sh /workspace/lerobot-env/env.sh; do
  [[ -f "${candidate}" ]] && { POD_ENV="${candidate}"; break; }
done

if [[ -n "${POD_ENV}" ]]; then
  # shellcheck disable=SC1090
  . "${POD_ENV}"
  BIN="$(dirname "${POD_ENV}")/bin"
  PY="${BIN}/python"
  OUT_ROOT=/workspace/outputs
  WHERE=runpod
else
  OUT_ROOT="${REPO_ROOT}/outputs"
  WHERE=local
fi

OUT_DIR="${OUT_ROOT}/train/${JOB_NAME}"
SMOKE_DIR="${OUT_ROOT}/train/${JOB_NAME}_smoke"
LOG_DIR="${OUT_ROOT}/logs"

# The dataset arg pair: a local tree if there is one, otherwise the Hub copy.
DATASET_ARGS=(--dataset.repo_id="${REPO_ID}")
DATASET_SOURCE="Hub: ${REPO_ID}  (not on local disk)"
if [[ -d "${DATASET_ROOT}" ]]; then
  DATASET_ARGS+=(--dataset.root="${DATASET_ROOT}")
  DATASET_SOURCE="local: ${DATASET_ROOT}"
fi

load_dotenv() {
  local dotenv="${REPO_ROOT}/.env"
  if [[ -f "${dotenv}" && ( -z "${WANDB_API_KEY:-}" || -z "${HF_TOKEN:-}" ) ]]; then
    # shellcheck disable=SC1090
    set -a; . "${dotenv}"; set +a
  fi
}

# --------------------------------------------------------------- preflight
preflight_env() {
  [[ -x "${BIN}/lerobot-train" ]] || die "lerobot-train not found at ${BIN} — check VENV in CONFIG"

  if [[ ! -d "${DATASET_ROOT}" ]]; then
    warn "no local dataset at ${DATASET_ROOT} — will download ${REPO_ID} from the Hub"
  else
    [[ -f "${DATASET_ROOT}/meta/info.json" ]] \
      || die "${DATASET_ROOT} exists but has no meta/info.json — not a v3.0 LeRobot dataset"
    [[ -f "${DATASET_ROOT}/meta/stats.json" ]] \
      || die "${DATASET_ROOT}/meta/stats.json missing — the recording never finalized. Training would use uninitialized normalization statistics"
  fi

  if [[ "${WANDB_ENABLE}" == "true" ]]; then
    load_dotenv
    [[ -n "${WANDB_API_KEY:-}" ]] \
      || die "WANDB_ENABLE=true but WANDB_API_KEY is unset (see ../.env.example), or set WANDB_ENABLE=false"
  fi
}

preflight_gpu() {
  command -v nvidia-smi >/dev/null || die "nvidia-smi not found — no GPU driver?"
  local total used free
  read -r total used < <(nvidia-smi --query-gpu=memory.total,memory.used --format=csv,noheader,nounits | head -1 | tr -d ',')
  free=$(( total - used ))
  printf '  GPU %s MiB total, %s MiB in use by other processes, %s MiB free\n' "${total}" "${used}" "${free}"
  if (( free < 6000 )); then
    warn "  only ${free} MiB free. ACT with two cameras at batch ${BATCH_SIZE} wants ~5-7 GB."
    warn "  Close browsers/other CUDA processes, or log into a console session, before the overnight run."
  fi
}

# What ACT will actually build, read off the dataset rather than assumed. This is
# the guard against training a one-camera policy by accident and only finding out
# at eval time.
describe_features() {
  local root_arg="${1:-}"
  [[ -n "${root_arg}" ]] || { echo "  (dataset not on disk — run 'check' after it downloads)"; return; }
  INFO_PATH="${root_arg}/meta/info.json" "${PY}" - <<'PYEOF'
import json, os
info = json.loads(open(os.environ["INFO_PATH"]).read())
feats = info["features"]
cams = {k: v for k, v in feats.items() if k.startswith("observation.images.")}
print(f"  episodes/frames   {info['total_episodes']} / {info['total_frames']}  @ {info['fps']} fps")
print(f"  observation.state {feats['observation.state']['shape'][0]} dims")
print(f"  action            {feats['action']['shape'][0]} dims")
print(f"  cameras           {len(cams)}  -> {len(cams)} ResNet18 backbone(s)")
for k, v in cams.items():
    h, w, _ = v["shape"]
    print(f"    {k:<28} {w}x{h}  codec={v['info']['video.codec']}")
if len(cams) < 2:
    print("  WARNING: fewer than 2 cameras — this is not the both-cameras run.")
PYEOF
}

# Rank the written checkpoints by their held-out eval loss, parsed out of the run
# log. lerobot has NO best-checkpoint tracking of its own — grep the train script
# for "best" and nothing comes back — so picking one is a post-hoc job, and this is
# it. SAVE_FREQ is a multiple of EVAL_STEPS, so every checkpoint step also has an
# eval point; the resume path appends to the same log, so later lines win.
#
# Prints a table. With QUIET=1 it prints only the winning step, for `push best`.
rank_checkpoints() {
  LOG_FILE="${LOG_DIR}/${JOB_NAME}.log" CKPT_DIR="${OUT_DIR}/checkpoints" \
  QUIET="${QUIET:-0}" "${PY}" - <<'PYEOF'
import os, re, sys
from pathlib import Path

log = Path(os.environ["LOG_FILE"])
ckpt_dir = Path(os.environ["CKPT_DIR"])
quiet = os.environ["QUIET"] == "1"

if not ckpt_dir.is_dir():
    sys.exit(f"error: no checkpoints at {ckpt_dir} — has the run finished a save step?")

steps = sorted(int(d.name) for d in ckpt_dir.iterdir() if d.is_dir() and d.name.isdigit())
if not steps:
    sys.exit(f"error: no numbered checkpoints in {ckpt_dir}")

losses = {}
if log.is_file():
    for m in re.finditer(r"step (\d+): eval_loss=([0-9.]+)", log.read_text(errors="replace")):
        losses[int(m.group(1))] = float(m.group(2))   # later lines win, so a resume overrides

scored = [(st, losses[st]) for st in steps if st in losses]
if not scored:
    sys.exit(
        f"error: no eval_loss for any checkpoint in {log}.\n"
        "       EVAL_SPLIT=0.0 disables the held-out loss, and without it there is no\n"
        "       basis to rank checkpoints — pick by hand, or re-run with a split."
    )

best_step, best_loss = min(scored, key=lambda x: x[1])

if quiet:
    print(best_step)
    sys.exit(0)

print(f"  {'step':>8}  {'eval_loss':>10}")
for st, ls in scored:
    mark = "  <- best" if st == best_step else ""
    print(f"  {st:>8}  {ls:>10.4f}{mark}")

missing = [st for st in steps if st not in losses]
if missing:
    print(f"\n  no eval point for: {', '.join(str(m) for m in missing)}")

last_step, last_loss = scored[-1]
print(f"\n  best   step {best_step}, eval_loss {best_loss:.4f}")
if best_step != last_step:
    print(f"  final  step {last_step}, eval_loss {last_loss:.4f}  ({last_loss - best_loss:+.4f}) — overfitting past {best_step}")
else:
    print("  the last checkpoint is also the best — the run had not started overfitting.")
print("\n  Eval loss picks the checkpoint; the 10 real trials decide G2. For behaviour")
print("  cloning the two agree only loosely, so evaluate the runner-up if the best disappoints.")
PYEOF
}

# ------------------------------------------------------------- the command
# Flags kept explicit rather than inherited from lerobot defaults, so this file is
# a complete record of the job. Anything not listed here is an ACT preset from
# configuration_act.py (chunk_size=100, n_action_steps=100, kl_weight=10,
# lr=1e-5, resnet18 + ImageNet weights, VAE on).
train_cmd() {
  local out_dir="$1" job="$2" steps="$3"; shift 3
  "${BIN}/lerobot-train" \
    "${DATASET_ARGS[@]}" \
    --dataset.eval_split="${EVAL_SPLIT}" \
    --dataset.return_uint8="${RETURN_UINT8}" \
    --policy.type=act \
    --policy.device=cuda \
    --policy.push_to_hub=false \
    --output_dir="${out_dir}" \
    --job_name="${job}" \
    --steps="${steps}" \
    --batch_size="${BATCH_SIZE}" \
    --num_workers="${NUM_WORKERS}" \
    --seed="${SEED}" \
    --log_freq="${LOG_FREQ}" \
    --eval_steps="${EVAL_STEPS}" \
    --env_eval_freq=0 \
    "$@"
}

# Re-exec a long-running subcommand under a sleep/shutdown inhibitor. Scoped to the
# job — nothing about the system's power configuration changes permanently, and the
# block disappears when the run exits. GNOME's automatic suspend is already 'nothing'
# on AC here (checked 2026-09-21), so this guards a manual suspend, a GNOME
# power-menu shutdown, or that setting being changed later and forgotten.
# Verify it took, from another terminal:  systemd-inhibit --list | grep train_act
inhibit_reexec() {
  local sub="$1"; shift
  [[ -n "${_ACT_INHIBITED:-}" ]] && return 0
  [[ "${WHERE}" == "local" ]] || return 0
  command -v systemd-inhibit >/dev/null || return 0
  exec env _ACT_INHIBITED=1 systemd-inhibit \
    --what=sleep:idle:shutdown \
    --who="train_act.sh" \
    --why="ACT training: ${JOB_NAME}" \
    --mode=block \
    "$0" "${sub}" "$@"
}

cmd="${1:-info}"
shift || true

case "${cmd}" in

  info)
    bold "Resolved configuration  (${WHERE})"
    printf '  %-18s %s\n' \
      "dataset"      "${DATASET_SOURCE}" \
      "job_name"     "${JOB_NAME}" \
      "output_dir"   "${OUT_DIR}" \
      "steps"        "${STEPS}" \
      "batch_size"   "${BATCH_SIZE}" \
      "num_workers"  "${NUM_WORKERS}  (return_uint8=${RETURN_UINT8})" \
      "eval_split"   "${EVAL_SPLIT}  every ${EVAL_STEPS} steps" \
      "save_freq"    "${SAVE_FREQ}" \
      "wandb"        "${WANDB_ENABLE}  project=${WANDB_PROJECT}" \
      "push"         "never during training — use '$0 push'"
    echo
    bold "What ACT will build from this dataset"
    describe_features "$([[ -d "${DATASET_ROOT}" ]] && echo "${DATASET_ROOT}")"
    echo
    bold "Next:  $0 check   then   $0 smoke   then   $0 train"
    ;;

  check)
    bold "Environment"
    preflight_env
    echo "  lerobot-train at ${BIN}"
    echo
    bold "GPU"
    preflight_gpu
    echo
    bold "Dataset — ${DATASET_SOURCE}"
    describe_features "$([[ -d "${DATASET_ROOT}" ]] && echo "${DATASET_ROOT}")"
    echo
    bold "Output"
    if [[ -d "${OUT_DIR}" ]]; then
      warn "  ${OUT_DIR} already exists."
      warn "  lerobot refuses to overwrite it. Either '$0 resume', or change JOB_NAME in CONFIG."
    else
      echo "  ${OUT_DIR} is free"
    fi
    echo
    bold "Preflight passed. Nothing was trained."
    ;;

  smoke)
    preflight_env
    preflight_gpu
    echo
    bold "Smoke run — ${SMOKE_STEPS} steps, no checkpoints, no W&B. Output is thrown away."
    rm -rf "${SMOKE_DIR}"
    mkdir -p "${LOG_DIR}"
    smoke_log="${LOG_DIR}/${JOB_NAME}_smoke.log"

    train_cmd "${SMOKE_DIR}" "${JOB_NAME}_smoke" "${SMOKE_STEPS}" \
      --save_checkpoint=false \
      --wandb.enable=false 2>&1 | tee "${smoke_log}"

    echo
    bold "Measured"
    SMOKE_LOG="${smoke_log}" STEPS="${STEPS}" "${PY}" - <<'PYEOF'
import os, re
text = open(os.environ["SMOKE_LOG"], errors="replace").read()

def last(metric):
    hits = re.findall(rf"{re.escape(metric)}:\s*([0-9.]+)", text)
    return float(hits[-1]) if hits else None

updt, data, mem, smp = last("updt_s"), last("data_s"), last("mem_gb"), last("smp/s")
if updt is None:
    raise SystemExit("  could not parse the log — read it directly")

step_s = updt + (data or 0.0)
print(f"  update      {updt:.3f} s/step (GPU)")
print(f"  dataloading {data:.3f} s/step (CPU, AV1 decode)" if data is not None else "")
print(f"  throughput  {1 / step_s:.2f} steps/s" + (f", {smp:.0f} samples/s" if smp else ""))
if mem:
    print(f"  peak VRAM   {mem:.2f} GB of ~9.6 GB usable")

hours = int(os.environ["STEPS"]) * step_s / 3600
print(f"\n  full run    {os.environ['STEPS']} steps -> ~{hours:.1f} h")

print()
if data is not None and data > updt:
    print("  DATALOADER-BOUND: the GPU is waiting on AV1 decode more than it computes.")
    print("  Raise NUM_WORKERS, then set RETURN_UINT8=true, and re-run smoke.")
else:
    print("  GPU-bound — the dataloader is keeping up. Nothing to tune.")
if mem and mem < 6.0:
    print(f"  {mem:.2f} GB peak leaves headroom; batch 16 would fit, but it also")
    print("  doubles the effective step size ACT's 1e-5 preset was tuned for. See README.md.")
PYEOF
    rm -rf "${SMOKE_DIR}"
    echo
    bold "Smoke output deleted. Next:  $0 train"
    ;;

  train)
    inhibit_reexec train "$@"
    preflight_env
    preflight_gpu
    echo
    [[ -n "${_ACT_INHIBITED:-}" ]] && echo "  sleep/shutdown inhibited for the duration of this run"

    [[ -d "${OUT_DIR}" ]] && die "${OUT_DIR} already exists — '$0 resume', or change JOB_NAME in CONFIG"
    mkdir -p "${LOG_DIR}"
    log="${LOG_DIR}/${JOB_NAME}.log"

    if [[ -z "${TMUX:-}" && "${WHERE}" == "local" ]]; then
      warn "not inside tmux — closing this terminal will kill the run."
      warn "  tmux new -s act    then re-run.  Ctrl-C now if you want that."
      sleep 5
    fi

    bold "Training ACT — ${STEPS} steps -> ${OUT_DIR}"
    echo "  dataset ${DATASET_SOURCE}"
    echo "  log     ${log}"
    echo
    train_cmd "${OUT_DIR}" "${JOB_NAME}" "${STEPS}" \
      --save_freq="${SAVE_FREQ}" \
      --wandb.enable="${WANDB_ENABLE}" \
      --wandb.project="${WANDB_PROJECT}" \
      --wandb.disable_artifact=true \
      "$@" 2>&1 | tee "${log}"

    echo
    bold "done"
    printf '  checkpoints  %s/checkpoints/\n' "${OUT_DIR}"
    printf '  log          %s\n' "${log}"
    printf '  next         pick a checkpoint on the eval loss, then  %s push\n' "$0"
    [[ "${WHERE}" == "runpod" ]] && printf '  remember to STOP the pod.\n'
    ;;

  resume)
    # Resume is exactly the case where an unattended machine must not sleep, so it
    # gets the same inhibitor the first run had.
    inhibit_reexec resume "$@"
    preflight_env
    cfg="${OUT_DIR}/checkpoints/last/pretrained_model/train_config.json"
    [[ -f "${cfg}" ]] || die "no checkpoint at ${cfg} — nothing to resume
       Checkpoints are written every ${SAVE_FREQ} steps; a run that died before the
       first one has nothing to resume from and must be restarted."
    mkdir -p "${LOG_DIR}"

    # Say how much work the interruption actually cost, before spending hours redoing it.
    STEP_JSON="${OUT_DIR}/checkpoints/last/training_state/training_step.json" \
    TOTAL_STEPS="${STEPS}" "${PY}" - <<'PYEOF' || true
import json, os
try:
    step = json.load(open(os.environ["STEP_JSON"]))["step"]
except Exception:
    raise SystemExit
total = int(os.environ["TOTAL_STEPS"])
print(f"  resuming at step {step} of {total} — {100 * step / total:.0f}% done, {total - step} steps left")
print(f"  at ~6.5 steps/s that is ~{(total - step) / 6.5 / 3600:.1f} h remaining")
PYEOF

    bold "Resuming ${JOB_NAME} from ${OUT_DIR}/checkpoints/last"
    echo "  restores the step counter, optimizer, LR scheduler, RNG state and data order"
    echo "  W&B continues the SAME run (the run id is stored in the checkpoint), not a new one"
    warn "  the checkpoint's config wins — CONFIG edits since the first run are ignored"
    warn "  unless passed as flags here."
    echo
    "${BIN}/lerobot-train" --config_path="${cfg}" --resume=true "$@" \
      2>&1 | tee -a "${LOG_DIR}/${JOB_NAME}.log"
    ;;

  best)
    bold "Checkpoints ranked by held-out eval loss"
    rank_checkpoints
    echo
    bold "Publish it with:  $0 push best"
    ;;

  push)
    load_dotenv
    ckpt="${1:-last}"
    if [[ "${ckpt}" == "best" ]]; then
      ckpt="$(QUIET=1 rank_checkpoints)" || die "could not resolve the best checkpoint — run '$0 best'"
      echo "  best checkpoint by eval loss: step ${ckpt}"
    fi
    src="${OUT_DIR}/checkpoints/${ckpt}/pretrained_model"
    [[ -d "${src}" ]] || die "no checkpoint '${ckpt}' at ${src}
       available: $(ls "${OUT_DIR}/checkpoints" 2>/dev/null | tr '\n' ' ')"

    bold "Publishing a trained policy"
    printf '  %-12s %s\n' "checkpoint" "${src}" "repo" "${POLICY_REPO_ID}" \
      "visibility" "$([[ "${POLICY_PRIVATE}" == "true" ]] && echo private || echo PUBLIC)"
    echo
    read -r -p "Upload? [y/N] " reply
    [[ "${reply}" == [yY] ]] || die "aborted — nothing uploaded"

    "${BIN}/hf" upload "${POLICY_REPO_ID}" "${src}" \
      --repo-type=model $([[ "${POLICY_PRIVATE}" == "true" ]] && echo --private)
    echo
    bold "https://huggingface.co/${POLICY_REPO_ID}"
    ;;

  *)
    die "unknown subcommand '${cmd}'. One of: info check smoke train resume best push"
    ;;
esac
