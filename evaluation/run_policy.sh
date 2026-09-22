#!/usr/bin/env bash
#
# run_policy.sh — run the trained ACT policy on the real SO-101, and score it.
#
# This is the G2 evaluation: 10 scripted trials of the canonical cube-to-bowl task.
#
#   ./run_policy.sh info     # resolved config: which checkpoint, which cameras, which ports
#   ./run_policy.sh check    # preflight: hardware, calibration, and POLICY/CAMERA KEY MATCH
#   ./run_policy.sh probe    # what does the policy COMMAND right now? Arm never moves
#   ./run_policy.sh dry      # ONE short autonomous run, records nothing. Do this first
#   ./run_policy.sh eval     # the 10 scored trials, recorded to a dataset
#   ./run_policy.sh score    # tally successes into an evaluation log (the Phase-A deliverable)
#
# ================================ SAFETY ===================================
# The follower arm moves BY ITSELF here. The leader is not in the loop and
# pulling it back will not stop anything. Before the first `dry`:
#
#   - Clear the workspace of everything except the cube and the bowl.
#   - Keep a hand on the 12 V supply switch. That is the stop button.
#   - Stand where you can reach it without reaching across the arm.
#   - ACT commits to `n_action_steps` actions per inference and is BLIND for all
#     of them. See N_ACTION_STEPS in CONFIG for the horizon this run uses; `info`
#     prints it in seconds. A bad trajectory will not self-correct inside that
#     window. This is the single most important thing to know before watching it
#     move for the first time.
#
# Ctrl-C leaves the arm wherever it stopped, under torque. `return_to_initial_position`
# (on by default) only runs on a clean shutdown — Esc, not Ctrl-C.
# ===========================================================================
#
# See README.md in this directory for the procedure and the scoring rubric.

set -euo pipefail

# ============================== CONFIG ======================================

VENV=/home/chinmay/lerobot-env

# --- Which policy. Default resolves the training module's best checkpoint by
# eval loss; override with a step number or a Hub repo id:
#   POLICY=100000 ./run_policy.sh eval
#   POLICY=chinmaykurade/act_so101_cube_to_bowl_50 ./run_policy.sh eval
TRAIN_JOB=act_cube_to_bowl
POLICY="${POLICY:-best}"

# --- Arm. Same by-id paths as data_collection/record_episodes.sh — read that
# file's CONFIG comment before changing these. The leader is NOT connected for
# evaluation: the policy drives the follower alone.
FOLLOWER_PORT=/dev/serial/by-id/usb-1a86_USB_Single_Serial_5B3D048536-if00
FOLLOWER_ID=follower_arm

# --- Cameras. THE NAMES ARE LOAD-BEARING. The policy was trained on feature keys
# observation.images.top and observation.images.wrist; these names must produce
# exactly those keys or the policy silently receives the wrong image in the wrong
# slot and behaves like it is broken. `check` verifies this against the checkpoint
# rather than trusting the comment.
CAMERAS=(
  "top=/dev/v4l/by-id/usb-Sonix_Technology_Co.__Ltd._Lenovo_FHD_Webcam_Audio_SN0001-video-index0"
  "wrist=/dev/v4l/by-id/usb-Arducam_Technology_Co.__Ltd._USB_2.0_Camera_SN0001-video-index0"
)
CAM_WIDTH=640
CAM_HEIGHT=480
CAM_FPS=30

# --- The trial. TASK must match the string the dataset was recorded with.
TASK="Pick up the cube and place it in the bowl"
NUM_TRIALS=10
EPISODE_TIME_S=15      # a little longer than recording's 12: a policy may hesitate
RESET_TIME_S=10        # you are replacing the cube by hand between trials
FPS=30

# --- Open-loop horizon. `chunk_size` (100) is ARCHITECTURE: it is baked into the
# checkpoint at training time and cannot be lowered here — the decoder has 100
# action slots. What IS an inference-time knob is how many of those 100 predicted
# actions get executed before the policy looks at the cameras again. Lowering it
# re-plans more often on fresher observations, which is what "more accurate" means
# in practice for ACT; the network is untouched. 20 at 30 fps = re-plan every
# 0.66 s instead of every 3.3 s. Costs one extra forward pass per 20 steps, which
# the 3080 has headroom for at 30 fps.
#
# Must be <= 100 or lerobot refuses to build the config. The tradeoff at the low
# end is chunk-boundary jerk: consecutive chunks disagree slightly and stitching
# them every 0.66 s can visibly stutter. If that shows up, that is exactly what
# TEMPORAL_ENSEMBLE below is for. Leave empty to use the checkpoint's own 100.
N_ACTION_STEPS=60

# --- Temporal ensembling. OFF, matching training. Turning it on queries the policy
# every step and exponentially averages overlapping chunks, which usually smooths
# chunk-boundary jerk at the cost of 100x more inference calls. It is an
# inference-time switch — the SAME checkpoint works either way, so it is worth a
# second pass if the arm twitches at chunk boundaries. n_action_steps MUST be 1
# with it, so it overrides N_ACTION_STEPS above.
TEMPORAL_ENSEMBLE=false

# --- The training dataset. Only `probe` uses it: normalizer stats come from here,
# and they must be the SAME dataset the checkpoint was trained on or the probe's
# numbers are meaningless.
TRAIN_REPO_ID=chinmaykurade/so101_cube_to_bowl_50
TRAIN_DATASET_ROOT_NAME=so101_cube_to_bowl_50

# --- Where the recorded trials land. Kept local; publication is a separate step.
HF_USER=chinmaykurade
EVAL_DATASET_NAME=eval_act_cube_to_bowl

# ============================ END CONFIG ====================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${VENV}/bin"
PY="${BIN}/python"
CKPT_ROOT="${REPO_ROOT}/outputs/train/${TRAIN_JOB}/checkpoints"
EVAL_REPO_ID="${HF_USER}/${EVAL_DATASET_NAME}"
EVAL_ROOT="${REPO_ROOT}/datasets/${EVAL_DATASET_NAME}"
LOG_DIR="${REPO_ROOT}/outputs/logs"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

cameras_json() {
  local out="{" entry name dev first=1
  for entry in "${CAMERAS[@]}"; do
    name="${entry%%=*}"; dev="${entry#*=}"
    [[ ${first} -eq 1 ]] || out+=", "
    out+="${name}: {type: opencv, index_or_path: ${dev}, width: ${CAM_WIDTH}, height: ${CAM_HEIGHT}, fps: ${CAM_FPS}}"
    first=0
  done
  printf '%s}' "${out}"
}

# Resolve POLICY to something --policy.path accepts.
resolve_policy() {
  if [[ "${POLICY}" == */* ]]; then          # a Hub repo id
    echo "${POLICY}"; return
  fi
  local step="${POLICY}"
  if [[ "${POLICY}" == "best" ]]; then
    step="$("${REPO_ROOT}/training/train_act.sh" best --quiet 2>/dev/null)" \
      || die "could not resolve the best checkpoint — run: ../training/train_act.sh best"
    step="$(printf '%06d' "${step}")"
  fi
  local path="${CKPT_ROOT}/${step}/pretrained_model"
  [[ -d "${path}" ]] || die "no checkpoint at ${path}
       available: $(ls "${CKPT_ROOT}" 2>/dev/null | tr '\n' ' ')"
  echo "${path}"
}

# The check that matters. A policy trained on {top, wrist} handed a robot exposing
# {front, side} does not error — lerobot builds the observation dict from whatever
# the robot reports, and missing/renamed keys produce a policy that "just doesn't
# work". Compare the checkpoint's own input_features against CONFIG.
verify_feature_match() {
  local policy_path="$1"
  local names=()
  local entry
  for entry in "${CAMERAS[@]}"; do names+=("${entry%%=*}"); done

  POLICY_PATH="${policy_path}" CAM_NAMES="${names[*]}" "${PY}" - <<'PYEOF'
import json, os, sys
from pathlib import Path

path = Path(os.environ["POLICY_PATH"])
cfg_file = path / "config.json"
if not cfg_file.is_file():
    # A Hub repo id: let lerobot fetch it at run time; we cannot check offline.
    print("  (policy is a Hub repo id — feature match will be checked when it loads)")
    sys.exit(0)

cfg = json.loads(cfg_file.read_text())
want = {k.rsplit(".", 1)[-1] for k in cfg.get("input_features", {}) if k.startswith("observation.images.")}
have = set(os.environ["CAM_NAMES"].split())

print(f"  policy expects cameras : {', '.join(sorted(want)) or '(none)'}")
print(f"  CONFIG provides        : {', '.join(sorted(have)) or '(none)'}")

if want == have:
    print("  MATCH")
    sys.exit(0)

print()
missing, extra = sorted(want - have), sorted(have - want)
if missing:
    print(f"  MISSING: the policy needs {', '.join(missing)} and CONFIG has no camera by that name.")
if extra:
    print(f"  UNUSED: {', '.join(extra)} is configured but the policy never saw it.")
print("  Rename the CAMERAS entries to match the policy. The names, not the devices,")
print("  are what becomes observation.images.<name>.")
sys.exit(1)
PYEOF
}

preflight() {
  [[ -x "${BIN}/lerobot-rollout" ]] || die "lerobot-rollout not found at ${BIN} — check VENV"
  [[ -e "${FOLLOWER_PORT}" ]] || die "follower port missing: ${FOLLOWER_PORT}
       run: ../data_collection/record_episodes.sh doctor"
  local calib="${HOME}/.cache/huggingface/lerobot/calibration/robots/so_follower/${FOLLOWER_ID}.json"
  [[ -e "${calib}" ]] || die "no calibration for '${FOLLOWER_ID}' at ${calib} — see ../calibration/README.md"
  local entry name dev
  for entry in "${CAMERAS[@]}"; do
    name="${entry%%=*}"; dev="${entry#*=}"
    [[ -e "${dev}" ]] || die "camera '${name}' not found: ${dev}
       run: ../data_collection/record_episodes.sh cameras"
  done
}

# Policy flags shared by dry and eval.
policy_args() {
  local path="$1"
  printf '%s\0' "--policy.path=${path}" "--policy.device=cuda"
  if [[ "${TEMPORAL_ENSEMBLE}" == "true" ]]; then
    # Ensembling queries the policy every step, so the horizon knob does not apply.
    printf '%s\0' "--policy.temporal_ensemble_coeff=0.01" "--policy.n_action_steps=1"
  elif [[ -n "${N_ACTION_STEPS}" ]]; then
    printf '%s\0' "--policy.n_action_steps=${N_ACTION_STEPS}"
  fi
}

robot_args() {
  printf '%s\0' \
    "--robot.type=so101_follower" \
    "--robot.port=${FOLLOWER_PORT}" \
    "--robot.id=${FOLLOWER_ID}" \
    "--robot.cameras=$(cameras_json)"
}

# How long the arm is blind between inferences, in the units that matter on the
# bench. Reads the checkpoint's 100 when N_ACTION_STEPS is left empty.
open_loop_desc() {
  if [[ "${TEMPORAL_ENSEMBLE}" == "true" ]]; then
    echo "1 step (temporal ensembling — re-plans every frame)"
    return
  fi
  local n="${N_ACTION_STEPS:-100}"
  printf '%s steps = %.2f s per inference (chunk_size 100)\n' \
    "${n}" "$(${PY} -c "print(${n}/${FPS})")"
}

confirm_arm_will_move() {
  warn "=============================================================="
  warn " The follower arm is about to move ON ITS OWN."
  warn "   - workspace clear except the cube and the bowl?"
  warn "   - hand on the 12 V switch, reachable without leaning over the arm?"
  warn "   - open-loop window: $(open_loop_desc)"
  warn "=============================================================="
  read -r -p "Ready? [y/N] " reply
  [[ "${reply}" == [yY] ]] || die "aborted — nothing ran"
}

cmd="${1:-info}"
shift || true

case "${cmd}" in

  info)
    policy_path="$(resolve_policy)"
    bold "Resolved configuration"
    printf '  %-16s %s\n' \
      "policy"      "${policy_path}" \
      "follower"    "${FOLLOWER_PORT}  id=${FOLLOWER_ID}" \
      "cameras"     "$(cameras_json)" \
      "task"        "${TASK}" \
      "trials"      "${NUM_TRIALS} × ${EPISODE_TIME_S}s (+${RESET_TIME_S}s reset) @ ${FPS} fps" \
      "open-loop"   "$(open_loop_desc)" \
      "ensembling"  "${TEMPORAL_ENSEMBLE}" \
      "records to"  "${EVAL_ROOT}"
    echo
    bold "Policy / camera key match"
    verify_feature_match "${policy_path}" || true
    echo
    bold "Order:  $0 check  →  $0 dry  →  $0 eval  →  $0 score"
    echo "  Arm sitting still during \`dry\`?  $0 probe  (moves nothing)"
    ;;

  check)
    bold "Hardware"
    preflight
    echo "  follower port, calibration and both cameras present"
    echo
    policy_path="$(resolve_policy)"
    bold "Policy — ${policy_path}"
    verify_feature_match "${policy_path}" \
      || die "camera names do not match the policy — fix CAMERAS in CONFIG before running the arm"
    echo
    bold "Preflight passed. The arm has not moved."
    echo "  Next: $0 dry"
    ;;

  probe)
    # Reads the arm and the cameras, runs the policy, prints the commanded goal
    # against the present position, and SENDS NOTHING. Safe with the arm powered.
    preflight
    policy_path="$(resolve_policy)"
    verify_feature_match "${policy_path}" >/dev/null \
      || die "camera names do not match the policy — run '$0 check'"

    bold "Probing the policy against live observations — the arm will NOT move"
    echo
    cam_flags=()
    for entry in "${CAMERAS[@]}"; do cam_flags+=(--camera "${entry}"); done
    frames_dir="${REPO_ROOT}/outputs/probe_frames"

    "${PY}" "${REPO_ROOT}/evaluation/probe_live.py" \
      --policy-path="${policy_path}" \
      --port="${FOLLOWER_PORT}" \
      --robot-id="${FOLLOWER_ID}" \
      "${cam_flags[@]}" \
      --width="${CAM_WIDTH}" --height="${CAM_HEIGHT}" --fps="${CAM_FPS}" \
      --repo-id="${TRAIN_REPO_ID}" \
      --dataset-root="${REPO_ROOT}/datasets/${TRAIN_DATASET_ROOT_NAME}" \
      --task="${TASK}" \
      --save-frames="${frames_dir}" \
      "$@"

    echo
    echo "  Move the arm by hand to a different pose and run this again. The commanded"
    echo "  goal should change with the pose. If it does not, the policy is ignoring"
    echo "  its observations."
    ;;

  dry)
    preflight
    policy_path="$(resolve_policy)"
    verify_feature_match "${policy_path}" >/dev/null \
      || die "camera names do not match the policy — run '$0 check'"
    bold "Dry run — ONE autonomous attempt, ${EPISODE_TIME_S}s, nothing recorded"
    echo "  policy ${policy_path}"
    echo "  Esc stops cleanly and returns the arm to its start pose. Ctrl-C does NOT."
    echo
    confirm_arm_will_move
    mkdir -p "${LOG_DIR}"

    mapfile -d '' -t pargs < <(policy_args "${policy_path}")
    mapfile -d '' -t rargs < <(robot_args)
    "${BIN}/lerobot-rollout" \
      --strategy.type=base \
      "${pargs[@]}" "${rargs[@]}" \
      --task="${TASK}" \
      --fps="${FPS}" \
      --duration="${EPISODE_TIME_S}" \
      --display_data=true \
      "$@" 2>&1 | tee "${LOG_DIR}/eval_dry.log"

    echo
    bold "Watch that back before running 10 of them."
    echo "  Did it reach toward the cube at all? If it moved confidently to the wrong"
    echo "  place, suspect the camera framing has drifted from the recording setup (R4)."
    ;;

  eval)
    preflight
    policy_path="$(resolve_policy)"
    verify_feature_match "${policy_path}" >/dev/null \
      || die "camera names do not match the policy — run '$0 check'"

    [[ -d "${EVAL_ROOT}" ]] && die "${EVAL_ROOT} already exists.
       Move it aside, or change EVAL_DATASET_NAME, so a previous evaluation is not mixed in."

    bold "G2 evaluation — ${NUM_TRIALS} trials, recorded to ${EVAL_ROOT}"
    echo "  policy ${policy_path}"
    echo "  → end a trial early · ← discard and redo it · Esc stop the session"
    echo "  Reset the cube to a DIFFERENT position each trial, within the range you"
    echo "  demonstrated. Same position 10 times measures memorization, not the policy."
    echo
    confirm_arm_will_move
    mkdir -p "${LOG_DIR}"

    mapfile -d '' -t pargs < <(policy_args "${policy_path}")
    mapfile -d '' -t rargs < <(robot_args)
    # push_to_hub defaults to TRUE in lerobot — same trap as recording. Explicit false.
    "${BIN}/lerobot-rollout" \
      --strategy.type=episodic \
      "${pargs[@]}" "${rargs[@]}" \
      --dataset.repo_id="${EVAL_REPO_ID}" \
      --dataset.root="${EVAL_ROOT}" \
      --dataset.single_task="${TASK}" \
      --dataset.num_episodes="${NUM_TRIALS}" \
      --dataset.episode_time_s="${EPISODE_TIME_S}" \
      --dataset.reset_time_s="${RESET_TIME_S}" \
      --dataset.fps="${FPS}" \
      --dataset.push_to_hub=false \
      --fps="${FPS}" \
      --display_data=true \
      "$@" 2>&1 | tee "${LOG_DIR}/eval_trials.log"

    echo
    bold "Now record the verdict:  $0 score"
    ;;

  score)
    # Success is a human judgement — nothing in the recording knows whether the cube
    # ended up in the bowl. This writes the Phase-A evaluation-log deliverable.
    policy_path="$(resolve_policy)"
    out="${REPO_ROOT}/notes/$(date +%Y-%m-%d)-g2-eval.md"
    [[ -e "${out}" ]] && die "${out} already exists — rename it or edit it by hand"

    bold "Scoring ${NUM_TRIALS} trials. For each: s = success, f = failure."
    echo "  Success = cube ends up inside the bowl, unaided, within the episode."
    echo "  A nudge, a re-grasp by hand, or a cube knocked off the table is a failure."
    echo
    declare -a verdicts=() reasons=()
    n=0
    while (( n < NUM_TRIALS )); do
      read -r -p "  trial $((n+1)): [s/f] " v
      case "${v}" in
        s|S) verdicts+=("success"); reasons+=(""); ((n++)) ;;
        f|F) read -r -p "        what failed? " why
             verdicts+=("failure"); reasons+=("${why}"); ((n++)) ;;
        *) echo "        s or f" ;;
      esac
    done

    successes=0
    for v in "${verdicts[@]}"; do [[ "${v}" == "success" ]] && ((successes++)); done

    mkdir -p "${REPO_ROOT}/notes"
    {
      echo "# G2 evaluation — ACT, cube to bowl"
      echo
      echo "- **Date:** $(date +%Y-%m-%d)"
      echo "- **Policy:** \`${policy_path}\`"
      echo "- **Dataset trained on:** 50 episodes, top + wrist"
      echo "- **Temporal ensembling:** ${TEMPORAL_ENSEMBLE}"
      echo "- **Trials recorded to:** \`datasets/${EVAL_DATASET_NAME}\`"
      echo
      echo "## Result: ${successes}/${NUM_TRIALS}"
      echo
      if (( successes >= 8 )); then
        echo "**G2 met** (criterion: >= 8/10)."
      else
        echo "**G2 not met** (criterion: >= 8/10)."
      fi
      echo
      echo "| Trial | Outcome | Notes |"
      echo "|---|---|---|"
      for i in "${!verdicts[@]}"; do
        printf '| %d | %s | %s |\n' "$((i+1))" "${verdicts[$i]}" "${reasons[$i]}"
      done
      echo
      echo "## Observations"
      echo
      echo "_Failure modes, and whether they cluster by cube position. Fill in._"
    } > "${out}"

    echo
    bold "${successes}/${NUM_TRIALS} — $( (( successes >= 8 )) && echo 'G2 MET' || echo 'G2 not met')"
    echo "  written to ${out}"
    echo "  Then: /summary to flip the tracker."
    ;;

  *)
    die "unknown subcommand '${cmd}'. One of: info check probe dry eval score"
    ;;
esac
