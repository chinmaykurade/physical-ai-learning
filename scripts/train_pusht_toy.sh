#!/usr/bin/env bash
# The canonical pusht toy-training job: Diffusion Policy on lerobot/pusht.
#
# This is the Phase-0 exit-criterion run (docs/progress.md), kept in a tracked
# file so the command lives somewhere other than gitignored W&B metadata.
# Runs unchanged on the RTX 3080 workstation and on a RunPod pod -- it detects
# which environment it is in and picks the right venv and output directory.
#
# Usage:
#   bash scripts/train_pusht_toy.sh                 # full 5000-step run
#   bash scripts/train_pusht_toy.sh --steps=200     # smoke test
#   bash scripts/train_pusht_toy.sh --steps=50 --job-name=quickcheck
#   bash scripts/train_pusht_toy.sh --push          # also upload weights to the HF Hub
#   bash scripts/train_pusht_toy.sh --push --private --repo-id=me/my-policy
#
# Pushing is OFF by default so smoke tests never publish anything. The upload
# happens at END of training, and LeRobot writes a generated model card with it.
#
# Reference: the 3080 does the full run in ~18 min. Pod wall-clock is NOT
# directly comparable -- different GPU.

set -euo pipefail

STEPS=5000
JOB_NAME=""
PUSH=0
PRIVATE=0
REPO_ID=""
HF_USER_DEFAULT=chinmaykurade
EXTRA_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --steps=*)    STEPS="${arg#*=}" ;;
    --job-name=*) JOB_NAME="${arg#*=}" ;;
    --push)       PUSH=1 ;;
    --private)    PRIVATE=1 ;;
    --repo-id=*)  REPO_ID="${arg#*=}"; PUSH=1 ;;
    -h|--help)    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            EXTRA_ARGS+=("$arg") ;;   # passed through to lerobot-train
  esac
done

# ------------------------------------------------------------ environment
POD_ENV=/workspace/lerobot-env/env.sh
LOCAL_VENV=/home/chinmay/lerobot-env

if [ -f "$POD_ENV" ]; then
  # shellcheck disable=SC1090
  . "$POD_ENV"
  PYBIN=/workspace/lerobot-env/bin
  OUT_ROOT=/workspace/outputs
  WHERE="runpod"
elif [ -x "$LOCAL_VENV/bin/lerobot-train" ]; then
  PYBIN="$LOCAL_VENV/bin"
  OUT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/outputs"
  WHERE="local"
  # The workstation has a display, but force the headless codepaths anyway so
  # a local smoke test exercises what the pod will actually run.
  export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-dummy}
  export MPLBACKEND=${MPLBACKEND:-Agg}
else
  echo "FAIL: no environment found." >&2
  echo "      pod:   run scripts/runpod_bootstrap.sh first" >&2
  echo "      local: expected a venv at $LOCAL_VENV" >&2
  exit 1
fi

[ -n "$JOB_NAME" ] || JOB_NAME="pusht_diffusion_${WHERE}"
OUT_DIR="$OUT_ROOT/train/$JOB_NAME"

DOTENV="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"
if [ -f "$DOTENV" ] && { [ -z "${WANDB_API_KEY:-}" ] || [ -z "${HF_TOKEN:-}" ]; }; then
  # shellcheck disable=SC1090
  set -a; . "$DOTENV"; set +a
fi
[ -n "${WANDB_API_KEY:-}" ] || { echo "FAIL: WANDB_API_KEY is not set (see .env.example)" >&2; exit 1; }

if [ -d "$OUT_DIR" ]; then
  echo "FAIL: $OUT_DIR already exists." >&2
  echo "      Pass --job-name=<something-else>, or remove that directory." >&2
  exit 1
fi

# ------------------------------------------------------------ hub preflight
# LeRobot pushes at the END of training, so an auth problem would otherwise
# surface only after the full run. Verify write access up front instead.
HUB_ARGS=(--policy.push_to_hub=false)

if [ "$PUSH" -eq 1 ]; then
  [ -n "$REPO_ID" ] || REPO_ID="$HF_USER_DEFAULT/$JOB_NAME"

  "$PYBIN/python" - "$REPO_ID" <<'PY' || exit 1
import sys
from huggingface_hub import HfApi, get_token

repo_id = sys.argv[1]
if get_token() is None:
    sys.exit(
        "FAIL: no Hugging Face token found.\n"
        "      local: run  hf auth login\n"
        "      pod:   set HF_TOKEN as a pod environment variable (write scope)"
    )

api = HfApi()
try:
    who = api.whoami()["name"]
except Exception as exc:
    sys.exit(f"FAIL: Hugging Face token rejected: {exc}")

# create_repo with exist_ok is the cheapest real write test: it proves the
# token has write scope AND that the namespace is usable, without uploading.
try:
    api.create_repo(repo_id=repo_id, repo_type="model", exist_ok=True, private=True)
except Exception as exc:
    sys.exit(
        f"FAIL: cannot write to '{repo_id}' as user '{who}': {exc}\n"
        "      The token needs WRITE scope, and the namespace must be yours."
    )
print(f"    hub: authenticated as {who}, write access to {repo_id} ok")
PY

  HUB_ARGS=(--policy.push_to_hub=true "--policy.repo_id=$REPO_ID")
  [ "$PRIVATE" -eq 1 ] && HUB_ARGS+=(--policy.private=true)
fi
# LeRobot requires output_dir NOT to exist (it refuses to overwrite unless
# resume=true), so the log lives alongside it rather than inside it.
mkdir -p "$OUT_ROOT/logs"
LOG="$OUT_ROOT/logs/${JOB_NAME}.log"

printf '\n\033[1;36m==> %s run: %s steps -> %s\033[0m\n' "$WHERE" "$STEPS" "$OUT_DIR"
if [ "$PUSH" -eq 1 ]; then
  printf '    will push to https://huggingface.co/%s%s\n\n' \
    "$REPO_ID" "$([ "$PRIVATE" -eq 1 ] && echo '  (private)')"
else
  printf '\n'
fi

# ------------------------------------------------------------- the command
# Flags kept explicit rather than relying on LeRobot defaults, so this file is
# a complete record of the job.
#
# --eval.use_async_envs=false is REQUIRED, not a preference: LeRobot 0.6.0
# builds AsyncVectorEnv with context="forkserver" without preloading
# gym_pusht, so the worker processes raise NamespaceNotFound on
# gym_pusht/PushT-v0. This is a library bug and it reproduces on every new
# machine -- do not drop this flag.
#
# --wandb.project=so101-embodied-ai is the canonical project (docs/progress.md).
# Note neural_networks/wandb_quickstart.py uses "physical-ai"; that was a
# one-off from the W&B tutorial, not the convention.
"$PYBIN/lerobot-train" \
  --dataset.repo_id=lerobot/pusht \
  --policy.type=diffusion \
  --policy.device=cuda \
  "${HUB_ARGS[@]}" \
  --env.type=pusht \
  --output_dir="$OUT_DIR" \
  --job_name="$JOB_NAME" \
  --steps="$STEPS" \
  --batch_size=64 \
  --log_freq=100 \
  --save_freq=2500 \
  --env_eval_freq=2500 \
  --eval.n_episodes=10 \
  --eval.batch_size=5 \
  --eval.use_async_envs=false \
  --wandb.enable=true \
  --wandb.project=so101-embodied-ai \
  --wandb.disable_artifact=true \
  "${EXTRA_ARGS[@]}" 2>&1 | tee "$LOG"

printf '\n\033[1;36m==> done\033[0m\n'
printf '    checkpoints  %s/checkpoints/\n' "$OUT_DIR"
printf '    log          %s\n' "$LOG"
[ "$PUSH" -eq 1 ] && printf '    hub          https://huggingface.co/%s\n' "$REPO_ID"
[ "$WHERE" = "runpod" ] && printf '    remember to STOP the pod when finished.\n'
printf '\n'
