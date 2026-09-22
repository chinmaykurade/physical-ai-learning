#!/usr/bin/env bash
#
# trim_dataset.sh — build a copy of the recorded dataset with the idle frames at the
# head of every episode removed.
#
# Edit the CONFIG block below, then run a subcommand.
#
#   ./trim_dataset.sh info      # resolved config + the train command that matches it
#   ./trim_dataset.sh profile   # how many idle frames per episode, at each threshold. Writes nothing
#   ./trim_dataset.sh smoke     # same pipeline over 3 episodes into a throwaway dataset
#   ./trim_dataset.sh build     # write the trimmed dataset, then verify it
#   ./trim_dataset.sh verify    # re-check an already-built dataset against the source
#
# WHY. Every one of the 50 demonstrations opens with the operator settling their hand
# on the leader before teleoperating — median 34 frames, 1.1 s of the arm sitting
# still. ACT learned that pause, and under action chunking it is an ABSORBING STATE:
# a rollout at n_action_steps=20 executes half the pause, the arm does not move, the
# observation does not change, and the next chunk prescribes the same pause. The arm
# never starts. Full write-up in notes/learnings.md (L1).
#
# THE SOURCE DATASET IS NEVER MODIFIED. It is the published D3 artifact; this writes a
# new one beside it. Nothing here touches the Hub either — publication stays a separate,
# deliberate step (push_dataset.sh), which is also why the push_to_hub trap that bites
# lerobot-record and lerobot-rollout does not apply: the authoring API has no such flag.
#
# See README.md in this directory for the procedure and the numbers.

set -euo pipefail

# ============================== CONFIG ======================================

VENV=/home/chinmay/lerobot-env

# --- Source. Must match the CONFIG block in record_episodes.sh.
HF_USER=chinmaykurade
SRC_NAME=so101_cube_to_bowl_50

# --- Destination. A NEW name: lerobot refuses to create into an existing root, which
# is the guardrail that keeps the published dataset safe.
DST_NAME=so101_cube_to_bowl_50_trimmed

# --- Episodes in a `smoke` run. Enough to exercise create/add_frame/save_episode/
# finalize and the verify pass end to end; far too few to train on.
SMOKE_EPISODES=3

# --- Motion threshold, in degrees of commanded travel from the episode's own starting
# pose. The onset is the first frame that exceeds it.
#
# 2.0 is the working value: servo read noise on this rig is ~0.1°, and a deliberate
# reach passes 2° within a frame or two of starting, so this sits in the wide gap
# between them. `profile` prints the whole curve — it is flat between 1° and 5°
# (median 28 → 36 frames), which is what "the threshold is not critical" looks like.
#
# Raise it if the retrained policy is STILL flat through k=20 in the chunk profile:
# that means real motion is still being counted as part of the pause.
THRESHOLD=2.0

# --- Frames kept in front of the onset. The policy should see "arm at rest, move now",
# not "arm already mid-reach" — a dataset whose every episode opens mid-motion has no
# examples of starting from a standstill, which is exactly the state a rollout begins
# in. 3 frames = 0.1 s, enough to anchor the start pose and far short of the 1.1 s that
# caused the deadlock.
MARGIN=3

# ============================ END CONFIG ====================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${VENV}/bin"
PY="${BIN}/python"
SCRIPT="${REPO_ROOT}/data_collection/trim_idle_frames.py"

SRC_REPO_ID="${HF_USER}/${SRC_NAME}"
DST_REPO_ID="${HF_USER}/${DST_NAME}"
SRC_ROOT="${REPO_ROOT}/datasets/${SRC_NAME}"
DST_ROOT="${REPO_ROOT}/datasets/${DST_NAME}"
SMOKE_NAME="${DST_NAME}_smoke"
SMOKE_REPO_ID="${HF_USER}/${SMOKE_NAME}"
SMOKE_ROOT="${REPO_ROOT}/datasets/${SMOKE_NAME}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

preflight() {
  [[ -x "${PY}" ]] || die "python not found at ${PY} — check VENV in CONFIG"
  [[ -d "${SRC_ROOT}" ]] || die "source dataset not found at ${SRC_ROOT}"
  [[ -f "${SCRIPT}" ]] || die "trim_idle_frames.py missing at ${SCRIPT}"
}

common_args=(
  --src-repo-id="${SRC_REPO_ID}"
  --src-root="${SRC_ROOT}"
  --dst-repo-id="${DST_REPO_ID}"
  --dst-root="${DST_ROOT}"
  --threshold="${THRESHOLD}"
  --margin="${MARGIN}"
)

cmd="${1:-info}"
shift || true

case "${cmd}" in
  profile)
    preflight
    bold "Idle-frame profile of ${SRC_REPO_ID} — nothing is written"
    "${PY}" "${SCRIPT}" "${common_args[@]}" --mode=profile "$@"
    ;;

  smoke)
    preflight
    [[ -d "${SMOKE_ROOT}" ]] && { warn "removing previous smoke dataset ${SMOKE_ROOT}"; rm -rf "${SMOKE_ROOT}"; }
    bold "Smoke: trimming ${SMOKE_EPISODES} episodes into ${SMOKE_REPO_ID}"
    echo "Throwaway. It proves the round trip — decode, permute, re-encode, verify —"
    echo "before committing an hour of wall clock to all 50."
    echo
    "${PY}" "${SCRIPT}" \
      --src-repo-id="${SRC_REPO_ID}" --src-root="${SRC_ROOT}" \
      --dst-repo-id="${SMOKE_REPO_ID}" --dst-root="${SMOKE_ROOT}" \
      --threshold="${THRESHOLD}" --margin="${MARGIN}" \
      --mode=build --episodes="${SMOKE_EPISODES}" "$@"
    ;;

  build)
    preflight
    [[ -d "${DST_ROOT}" ]] && die "${DST_ROOT} already exists — move it aside or change DST_NAME"
    bold "Building ${DST_REPO_ID}"
    echo "  source      ${SRC_ROOT}  (read-only)"
    echo "  destination ${DST_ROOT}"
    echo "  threshold ${THRESHOLD}°   margin ${MARGIN} frames"
    echo
    echo "Every frame is decoded and re-encoded, so this takes tens of minutes and"
    echo "needs ~250 MB of scratch per episode for the intermediate PNGs. Run it under"
    echo "tmux if the terminal might go away."
    echo
    "${PY}" "${SCRIPT}" "${common_args[@]}" --mode=build "$@"
    echo
    bold "Next: retrain on it"
    echo "  Set DATASET_NAME=${DST_NAME} and a fresh JOB_NAME in ../training/train_act.sh,"
    echo "  then ./train_act.sh check && ./train_act.sh train"
    ;;

  verify)
    preflight
    [[ -d "${DST_ROOT}" ]] || die "${DST_ROOT} does not exist — run '$0 build' first"
    bold "Verifying ${DST_REPO_ID} against ${SRC_REPO_ID}"
    "${PY}" "${SCRIPT}" "${common_args[@]}" --mode=verify "$@"
    ;;

  info)
    bold "Resolved configuration"
    printf '  %-16s %s\n' \
      "source"      "${SRC_REPO_ID}" \
      "source root" "${SRC_ROOT}" \
      "dest"        "${DST_REPO_ID}" \
      "dest root"   "${DST_ROOT}$([[ -d "${DST_ROOT}" ]] && echo '  (exists)')" \
      "threshold"   "${THRESHOLD}°" \
      "margin"      "${MARGIN} frames ($(awk "BEGIN{printf \"%.2f\", ${MARGIN}/30}")s @ 30 fps)"
    echo
    bold "Train ACT on the trimmed dataset"
    cat <<EOF
  In ../training/train_act.sh CONFIG:
    DATASET_NAME=${DST_NAME}
    JOB_NAME=act_cube_to_bowl_trimmed     # a new name, or lerobot refuses the output dir

  Then:
    cd ../training && ./train_act.sh check && tmux new -s act -- ./train_act.sh train

  And afterwards, in ../evaluation/run_policy.sh CONFIG:
    TRAIN_JOB=act_cube_to_bowl_trimmed
    TRAIN_REPO_ID=${DST_REPO_ID}
    TRAIN_DATASET_ROOT_NAME=${DST_NAME}
    N_ACTION_STEPS=20                     # the value the trim is meant to make safe

  The probe's normalizer stats MUST come from the dataset the checkpoint was
  trained on, or its numbers mean nothing.
EOF
    ;;

  *)
    die "unknown subcommand '${cmd}'. One of: profile smoke build verify info"
    ;;
esac
