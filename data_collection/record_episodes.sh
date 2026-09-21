#!/usr/bin/env bash
#
# record_episodes.sh — SO-101 demonstration recording for the canonical task.
#
# Edit the CONFIG block below, then run a subcommand. Nothing outside CONFIG
# should need changing for day-to-day recording.
#
#   ./record_episodes.sh doctor    # USB power/topology audit — run FIRST if anything drops
#   ./record_episodes.sh cameras   # which camera is which — capture sample images
#   ./record_episodes.sh check     # teleop + live view, records nothing. Tape the mounts here
#   ./record_episodes.sh smoke     # 2 throwaway episodes; confirm fps is stable
#   ./record_episodes.sh record    # the real run
#   ./record_episodes.sh resume    # continue an interrupted run
#   ./record_episodes.sh view      # open the recorded dataset in the visualizer
#   ./record_episodes.sh info      # print resolved config + the train command that matches it
#
# Controls while recording:  → end episode early · ← discard and re-record · Esc stop
# On Wayland, keep the TERMINAL focused (not the Rerun window) or the keys are missed.
#
# See README.md in this directory for the full procedure and the reasoning.

set -euo pipefail

# ============================== CONFIG ======================================

VENV=/home/chinmay/lerobot-env

# --- Arms.
# Use /dev/serial/by-id/ paths, NOT /dev/ttyACM*. The ttyACM numbers are handed out
# in enumeration order and have already swapped on this rig; a swap makes the script
# command the torque-disabled leader as the follower (risk R8). The by-id path embeds
# the adapter's serial number and never changes.
#
# Mapping below was read off the bus on 2026-09-20, when ttyACM0 (=5B3D048536)
# connected as the follower. VERIFY IT ONCE: unplug the follower, run
# `./record_episodes.sh doctor`, and confirm the follower line goes MISSING.
# IDs must match the filenames under calibration/ (follower_arm.json, leader_arm.json).
FOLLOWER_PORT=/dev/serial/by-id/usb-1a86_USB_Single_Serial_5B3D048536-if00
FOLLOWER_ID=follower_arm
LEADER_PORT=/dev/serial/by-id/usb-1a86_USB_Single_Serial_5B79019104-if00
LEADER_ID=leader_arm

# --- Cameras: "name=device". The name becomes the dataset feature key
# (observation.images.<name>), so renaming one here makes a NEW, incompatible
# feature — keep names stable once recording starts.
#
# Always use /dev/v4l/by-id/ paths, never integer indices: indices renumber
# across reboots and replugs, by-id paths do not. Use the -video-index0 node.
# Comment out a line to record without that camera.
CAMERAS=(
  "top=/dev/v4l/by-id/usb-Sonix_Technology_Co.__Ltd._Lenovo_FHD_Webcam_Audio_SN0001-video-index0"
  "wrist=/dev/v4l/by-id/usb-Arducam_Technology_Co.__Ltd._USB_2.0_Camera_SN0001-video-index0"
)
CAM_WIDTH=640
CAM_HEIGHT=480
CAM_FPS=30

# --- Dataset
HF_USER=chinmaykurade
DATASET_NAME=so101_cube_to_bowl_50
TASK="Pick up the cube and place it in the bowl"
NUM_EPISODES=50
EPISODE_TIME_S=12      # lerobot default is 60 — far too long for a 10-15 s task
RESET_TIME_S=7        # lerobot default is 60
FPS=30

# Keep false until decision D3 (dataset license) is settled — see docs/progress.md.
# lerobot's own default is TRUE, which would upload the moment recording ends.
PUSH_TO_HUB=false

# Where the dataset is written. Empty string = lerobot's default
# ($HF_LEROBOT_HOME/<repo_id>, i.e. ~/.cache/huggingface/lerobot/).
# Set here to keep recordings beside the repo that documents them; `datasets/`
# is gitignored. If you change this, `train` and `view` need the same root —
# `info` prints commands that already carry it.
DATASET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/datasets/${DATASET_NAME}"

# ============================ END CONFIG ====================================

REPO_ID="${HF_USER}/${DATASET_NAME}"
SMOKE_NAME="${DATASET_NAME}_smoke"
SMOKE_REPO_ID="${HF_USER}/${SMOKE_NAME}"
SMOKE_ROOT="${DATASET_ROOT:+$(dirname "${DATASET_ROOT}")/${SMOKE_NAME}}"

BIN="${VENV}/bin"
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

preflight() {
  [[ -x "${BIN}/lerobot-record" ]] || die "lerobot not found at ${BIN} — check VENV in CONFIG"

  local calib="${HOME}/.cache/huggingface/lerobot/calibration"
  [[ -e "${calib}/robots/so_follower/${FOLLOWER_ID}.json" ]] \
    || die "no calibration for robot id '${FOLLOWER_ID}' under ${calib} — see calibration/README.md"
  [[ -e "${calib}/teleoperators/so_leader/${LEADER_ID}.json" ]] \
    || die "no calibration for teleop id '${LEADER_ID}' under ${calib} — see calibration/README.md"

  [[ -e "${FOLLOWER_PORT}" ]] || die "follower port ${FOLLOWER_PORT} missing — run '$0 doctor'"
  [[ -e "${LEADER_PORT}"   ]] || die "leader port ${LEADER_PORT} missing — run '$0 doctor'"
  [[ "${FOLLOWER_PORT}" != "${LEADER_PORT}" ]] || die "follower and leader are on the same port"

  [[ ${#CAMERAS[@]} -gt 0 ]] || die "no cameras configured"
  local entry name dev
  for entry in "${CAMERAS[@]}"; do
    name="${entry%%=*}"; dev="${entry#*=}"
    [[ -n "${name}" && -n "${dev}" && "${name}" != "${dev}" ]] || die "malformed CAMERAS entry: '${entry}' (want name=device)"
    [[ -e "${dev}" ]] || die "camera '${name}' device not found: ${dev}  (run: $0 cameras)"
  done
}

# Warn loudly if the bus looks unstable, but let the operator decide.
preflight_bus() {
  if ! doctor >/dev/null 2>&1; then
    echo
    warn "=============================================================="
    warn " 'doctor' reports USB problems. Run '$0 doctor' for detail."
    warn " Recording on an unstable bus loses the session, and a servo"
    warn " adapter dropping mid-run drops an arm under load (R8)."
    warn "=============================================================="
    echo
    read -r -p "Continue anyway? [y/N] " reply
    [[ "${reply}" == [yY] ]] || die "aborted — fix the wiring first"
  fi
}

# Build the draccus dict literal lerobot expects for --robot.cameras
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

# Flags shared by teleoperate and record
arm_args() {
  printf '%s\0' \
    "--robot.type=so101_follower" \
    "--robot.port=${FOLLOWER_PORT}" \
    "--robot.id=${FOLLOWER_ID}" \
    "--robot.cameras=$(cameras_json)" \
    "--teleop.type=so101_leader" \
    "--teleop.port=${LEADER_PORT}" \
    "--teleop.id=${LEADER_ID}"
}

run() {
  bold "→ $1"; shift
  printf '  %q \\\n' "$@"
  echo
  "$@"
}

do_record() {
  local repo_id="$1" root="$2" episodes="$3" resume="$4"
  local -a args=()
  while IFS= read -r -d '' a; do args+=("$a"); done < <(arm_args)
  args+=(
    "--dataset.repo_id=${repo_id}"
    "--dataset.single_task=${TASK}"
    "--dataset.num_episodes=${episodes}"
    "--dataset.episode_time_s=${EPISODE_TIME_S}"
    "--dataset.reset_time_s=${RESET_TIME_S}"
    "--dataset.fps=${FPS}"
    "--dataset.push_to_hub=${PUSH_TO_HUB}"
    "--dataset.streaming_encoding=true"
    "--dataset.encoder_threads=2"
    "--display_data=true"
  )
  [[ -n "${root}" ]] && { mkdir -p "$(dirname "${root}")"; args+=("--dataset.root=${root}"); }
  [[ "${resume}" == "true" ]] && args+=("--resume=true")

  echo
  bold "Controls:  → end episode early   ← discard + re-record   Esc stop"
  warn  "Wayland: keep THIS terminal focused, not the Rerun window."
  echo
  run "lerobot-record" "${BIN}/lerobot-record" "${args[@]}"
}

# Resolve a /dev node to the sysfs directory of the USB device behind it
usb_dev_dir() {
  local real sys
  real="$(readlink -f "$1" 2>/dev/null)" || return 1
  case "${real}" in
    /dev/video*) sys="/sys/class/video4linux/$(basename "${real}")/device" ;;
    /dev/tty*)   sys="/sys/class/tty/$(basename "${real}")/device" ;;
    *) return 1 ;;
  esac
  sys="$(readlink -f "${sys}" 2>/dev/null)" || return 1
  while [[ -n "${sys}" && "${sys}" != "/" ]]; do
    [[ -r "${sys}/bMaxPower" ]] && { printf '%s' "${sys}"; return 0; }
    sys="$(dirname "${sys}")"
  done
  return 1
}

# USB power / topology audit. Catches the failure that killed the first `check`
# run on 2026-09-20: a bus-powered hub carrying 776mA of downstream demand on a
# 500mA port, which dropped the wrist camera and, earlier, both servo adapters.
doctor() {
  local -a nodes=() labels=()
  local entry
  for entry in "${CAMERAS[@]}"; do
    nodes+=("${entry#*=}"); labels+=("camera:${entry%%=*}")
  done
  nodes+=("${FOLLOWER_PORT}" "${LEADER_PORT}")
  labels+=("arm:follower" "arm:leader")

  local -A hub_load=() hub_kids=()
  local i dir parent name power missing=0 problems=0

  bold "Devices"
  for i in "${!nodes[@]}"; do
    if [[ ! -e "${nodes[$i]}" ]]; then
      printf '  \033[31m%-15s MISSING   %s\033[0m\n' "${labels[$i]}" "${nodes[$i]}"
      missing=1; continue
    fi
    dir="$(usb_dev_dir "${nodes[$i]}" || true)"
    if [[ -z "${dir}" ]]; then
      printf '  %-15s %s\n' "${labels[$i]}" "$(readlink -f "${nodes[$i]}")"
      continue
    fi
    name="$(basename "${dir}")"
    power="$(cat "${dir}/bMaxPower" 2>/dev/null || echo '?')"
    parent="$(basename "$(dirname "${dir}")")"
    printf '  %-15s %-8s %-7s on %-8s -> %s\n' \
      "${labels[$i]}" "${name}" "${power}" "${parent}" "$(readlink -f "${nodes[$i]}")"
    hub_load["${parent}"]=$(( ${hub_load["${parent}"]:-0} + ${power%mA} ))
    hub_kids["${parent}"]="${hub_kids[${parent}]:-}${labels[$i]} "
  done

  echo
  bold "Shared-hub power budget"
  local hub load kids hubpower
  if [[ ${#hub_load[@]} -eq 0 ]]; then
    echo "  (nothing resolved)"
  fi
  for hub in "${!hub_load[@]}"; do
    load="${hub_load[$hub]}"; kids="${hub_kids[$hub]}"
    if [[ "${hub}" == usb* ]]; then
      printf '  %-9s root controller, %smA — %s\n' "${hub}" "${load}" "${kids}"
      continue
    fi
    hubpower="$(cat "/sys/bus/usb/devices/${hub}/bMaxPower" 2>/dev/null || echo '?')"
    printf '  %-9s hub, %smA downstream (hub itself %s) — %s\n' "${hub}" "${load}" "${hubpower}" "${kids}"
    if (( load > 500 )); then
      warn "            ^ over the 500mA a USB 2.0 port supplies. Unless this hub has its"
      warn "              external power adapter connected, devices WILL drop mid-session."
      problems=1
    fi
    if [[ "${kids}" == *camera:* && "${kids}" == *arm:* ]]; then
      warn "            ^ cameras share this hub with servo adapters. A brown-out here drops"
      warn "              an arm under load, not just a video stream (risk R8)."
      problems=1
    fi
  done

  echo
  bold "Recent USB faults (kernel log)"
  local log
  log="$( { dmesg 2>/dev/null || journalctl -k -b --no-pager 2>/dev/null; } \
          | grep -iE "USB disconnect|connect-debounce failed|Cannot enable|unable to enumerate" \
          | tail -8 )"
  if [[ -n "${log}" ]]; then
    echo "${log}" | sed 's/^/  /'
    warn "  Faults during a run mean the bus is unstable. Fix the wiring before recording."
    problems=1
  else
    echo "  none since boot — clean"
  fi

  echo
  bold "Root controllers (spread the load across these)"
  lsusb -t 2>/dev/null | grep -E "^/:" | sed 's/^/  /'

  echo
  if (( missing )); then
    warn "A configured device is missing. Replug it, then re-run doctor."
    return 1
  elif (( problems )); then
    warn "doctor found problems — recording on an unstable bus wastes the session."
    return 1
  fi
  bold "No problems found."
  return 0
}

cmd="${1:-info}"
case "${cmd}" in

  doctor)
    doctor
    ;;

  cameras)
    bold "Capturing sample images from every detected camera..."
    echo "Devices currently present under /dev/v4l/by-id/:"
    ls -1 /dev/v4l/by-id/ 2>/dev/null | sed 's/^/  /' || echo "  (none)"
    echo
    "${BIN}/lerobot-find-cameras" opencv
    echo
    bold "Match each saved image to a camera, then set CAMERAS in this script."
    echo "Use the -video-index0 node of each device (index1 is metadata, not capture)."
    ;;

  check)
    preflight
    preflight_bus
    bold "Teleoperation with live view. Nothing is recorded."
    echo "Run the full cube → bowl motion and confirm:"
    echo "  · top sees the cube's whole start zone, the bowl, and the arm at full extension"
    echo "  · wrist still sees the cube at the moment of grasp"
    echo "Then TAPE BOTH MOUNTS and do not move them again (risk R4)."
    echo
    local_args=()
    while IFS= read -r -d '' a; do local_args+=("$a"); done < <(arm_args)
    run "lerobot-teleoperate" "${BIN}/lerobot-teleoperate" "${local_args[@]}" "--display_data=true"
    ;;

  smoke)
    preflight
    preflight_bus
    bold "Smoke test — 2 throwaway episodes into '${SMOKE_REPO_ID}'."
    echo "Watch the reported fps: it should hold a stable ${FPS}."
    echo "If it is unstable, raise --dataset.num_image_writer_threads_per_camera,"
    echo "or add --dataset.num_image_writer_processes=1."
    do_record "${SMOKE_REPO_ID}" "${SMOKE_ROOT}" 2 false
    ;;

  record)
    preflight
    preflight_bus
    bold "Recording ${NUM_EPISODES} episodes → ${REPO_ID}"
    [[ -n "${DATASET_ROOT}" ]] && echo "Local root: ${DATASET_ROOT}"
    [[ "${PUSH_TO_HUB}" == "true" ]] && warn "push_to_hub=true — this WILL upload to the Hub. D3 settled?"
    echo "Estimated wall clock: ~$(( NUM_EPISODES * (EPISODE_TIME_S + RESET_TIME_S) / 60 )) min plus re-records."
    do_record "${REPO_ID}" "${DATASET_ROOT}" "${NUM_EPISODES}" false
    ;;

  resume)
    preflight
    preflight_bus
    bold "Resuming ${REPO_ID} up to ${NUM_EPISODES} episodes"
    do_record "${REPO_ID}" "${DATASET_ROOT}" "${NUM_EPISODES}" true
    ;;

  view)
    local_args=("--repo-id=${REPO_ID}")
    [[ -n "${DATASET_ROOT}" ]] && local_args+=("--root=${DATASET_ROOT}")
    run "lerobot-dataset-viz" "${BIN}/lerobot-dataset-viz" "${local_args[@]}"
    ;;

  info)
    bold "Resolved configuration"
    printf '  %-16s %s\n' \
      "follower" "${FOLLOWER_PORT}  id=${FOLLOWER_ID}" \
      "leader"   "${LEADER_PORT}  id=${LEADER_ID}" \
      "cameras"  "$(cameras_json)" \
      "repo_id"  "${REPO_ID}" \
      "root"     "${DATASET_ROOT:-<lerobot default: ~/.cache/huggingface/lerobot/${REPO_ID}>}" \
      "task"     "${TASK}" \
      "episodes" "${NUM_EPISODES} × ${EPISODE_TIME_S}s (+${RESET_TIME_S}s reset) @ ${FPS} fps" \
      "push_to_hub" "${PUSH_TO_HUB}"
    echo
    bold "Train ACT on this dataset (top camera only — the Phase-A G2 baseline)"
    cat <<EOF
  ${BIN}/lerobot-train \\
    --dataset.repo_id=${REPO_ID} \\${DATASET_ROOT:+
    --dataset.root=${DATASET_ROOT} \\}
    --policy.type=act \\
    --policy.device=cuda \\
    --output_dir=outputs/train/act_cube_to_bowl \\
    --job_name=act_cube_to_bowl \\
    --wandb.enable=true

  Both cameras are recorded, but ACT infers its inputs from the dataset and would
  use both. To hold the planned single-camera baseline, either set
  --policy.input_features explicitly, or fork a wrist-free copy first:

  ${BIN}/lerobot-edit-dataset \\
    --repo_id=${REPO_ID} \\${DATASET_ROOT:+
    --root=${DATASET_ROOT} \\}
    --new_repo_id=${REPO_ID}_toponly \\
    --operation.type=remove_feature \\
    --operation.feature_names='[observation.images.wrist]'

  --new_repo_id is NOT optional here: without it edit-dataset rewrites the
  dataset IN PLACE and the wrist stream is gone for good, taking Phase B's
  ablation with it.
EOF
    ;;

  *)
    die "unknown subcommand '${cmd}'. One of: doctor cameras check smoke record resume view info"
    ;;
esac
