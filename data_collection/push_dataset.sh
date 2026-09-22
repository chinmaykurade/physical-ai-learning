#!/usr/bin/env bash
#
# push_dataset.sh — publish a recorded SO-101 dataset to the Hugging Face Hub.
#
# Separate from record_episodes.sh on purpose: recording runs with
# PUSH_TO_HUB=false so a finished session never uploads itself, and publication
# is a deliberate, reviewed step (plan goal G3, decision D3). Keep it that way.
#
#   ./push_dataset.sh info      # resolved config + local dataset summary + Hub status
#   ./push_dataset.sh check     # preflight only: auth, identity, local integrity. Uploads nothing
#   ./push_dataset.sh push      # the real upload (asks to confirm; -y skips)
#   ./push_dataset.sh verify    # compare the local file tree against what landed on the Hub
#   ./push_dataset.sh card      # re-push ONLY the dataset card (license/tag edits, no re-upload)
#
# PUBLIC IS IRREVERSIBLE IN PRACTICE. Deleting the repo later does not un-publish
# what has already been cloned or indexed. Everything the cameras saw is in those
# videos — check the frames for anything you would not put on the open internet
# (faces, screens, mail, keys) BEFORE the first push, not after.
#
# See README.md in this directory for the recording procedure that produces the input.

set -euo pipefail

# ============================== CONFIG ======================================

VENV=/home/chinmay/lerobot-env

# --- What to publish. Must match the CONFIG block in record_episodes.sh.
HF_USER=chinmaykurade
DATASET_NAME=so101_cube_to_bowl_50_trimmed

# --- Visibility. false = public. There is no undo; see the warning above.
PRIVATE=false

# --- License for the dataset card. This is project decision D3.
#
# Hub identifiers, not free text — see
# https://huggingface.co/docs/hub/repositories-licenses
#   cc-by-4.0    — a data license: attribution required, reuse allowed. Conventional
#                  for datasets, and what most LeRobot community datasets carry.
#   apache-2.0   — a software license. lerobot's push_to_hub default, which is why
#                  it must be set explicitly here rather than left to fall through.
#
# Env override, so the choice can be tried without editing the file:
#   LICENSE=apache-2.0 ./push_dataset.sh push
LICENSE="${LICENSE:-cc-by-4.0}"

# --- Dataset card tags (discovery on the Hub, not metadata the loader reads).
TAGS=(lerobot so101 robotics imitation-learning teleoperation)

# --- Upload the videos/ directory. false uploads state/action parquet only, which
# makes the dataset unusable for visual policies — it is for metadata-only fixups.
PUSH_VIDEOS=true

# --- Tag the pushed revision with the codebase version (v3.0). Leave true: the
# loader resolves datasets by this tag, so an untagged repo fails to load by repo_id.
TAG_VERSION=true

# --- Where the dataset is on disk. Mirrors record_episodes.sh's DATASET_ROOT.
DATASET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/datasets/${DATASET_NAME}"

# ============================ END CONFIG ====================================

REPO_ID="${HF_USER}/${DATASET_NAME}"
BIN="${VENV}/bin"
PY="${BIN}/python"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

export REPO_ID DATASET_ROOT LICENSE PRIVATE PUSH_VIDEOS TAG_VERSION
export TAGS_STR="${TAGS[*]}"

# Local structure. Catches the mistakes that produce a broken public repo:
# a half-finalized recording, or the smoke dataset pushed by accident.
preflight_local() {
  [[ -x "${PY}" ]] || die "no python at ${PY} — check VENV in CONFIG"
  [[ -d "${DATASET_ROOT}" ]] || die "no dataset at ${DATASET_ROOT} — record it first, or fix DATASET_NAME"

  local info="${DATASET_ROOT}/meta/info.json"
  [[ -f "${info}" ]] || die "missing ${info} — this is not a v3.0 LeRobot dataset root"
  [[ -f "${DATASET_ROOT}/meta/stats.json" ]] \
    || die "missing meta/stats.json — recording did not finalize. Re-run 'record_episodes.sh resume' to completion; pushing now publishes a dataset that will not train"
  [[ -d "${DATASET_ROOT}/data" ]] || die "missing data/ — nothing to publish"

  if [[ "${PUSH_VIDEOS}" == "true" && ! -d "${DATASET_ROOT}/videos" ]]; then
    die "PUSH_VIDEOS=true but ${DATASET_ROOT}/videos does not exist"
  fi

  case "${DATASET_NAME}" in
    *smoke*|*test*|*throwaway*)
      warn "DATASET_NAME='${DATASET_NAME}' looks like a throwaway run."
      warn "Publishing a smoke dataset publicly is almost certainly not what you want."
      ;;
  esac
}

# Identity. A token belonging to a different account fails with 403 only after
# the upload has been attempted, so check it up front.
preflight_auth() {
  "${PY}" - <<'PYEOF'
import os, sys
from huggingface_hub import HfApi, get_token

if not get_token():
    sys.exit("error: not logged in to the Hub — run: hf auth login")

me = HfApi().whoami()
name = me.get("name")
owner = os.environ["REPO_ID"].split("/")[0]
orgs = {o.get("name") for o in me.get("orgs", [])}

if owner != name and owner not in orgs:
    sys.exit(
        f"error: token belongs to '{name}' but REPO_ID targets '{owner}/...'.\n"
        f"       Fix HF_USER in CONFIG, or log in as '{owner}'."
    )
print(f"  authenticated as {name}, may write to {owner}/*")
PYEOF
}

# Read-only summary of the local dataset and the current state of the Hub repo.
summarize() {
  "${PY}" - <<'PYEOF'
import json, os
from pathlib import Path
from huggingface_hub import HfApi

root = Path(os.environ["DATASET_ROOT"])
repo_id = os.environ["REPO_ID"]
info = json.loads((root / "meta" / "info.json").read_text())

print("Local dataset")
for k in ("codebase_version", "robot_type", "fps", "total_episodes", "total_frames", "total_tasks"):
    print(f"  {k:<18} {info.get(k)}")
cams = [k for k in info.get("features", {}) if k.startswith("observation.images.")]
print(f"  {'cameras':<18} {', '.join(c.rsplit('.', 1)[-1] for c in cams) or '(none)'}")

nbytes = sum(f.stat().st_size for f in root.rglob("*") if f.is_file())
print(f"  {'on-disk size':<18} {nbytes / 1e6:.1f} MB")

api = HfApi()
print(f"\nHub repo  {repo_id}")
if api.repo_exists(repo_id, repo_type="dataset"):
    d = api.dataset_info(repo_id)
    n = len(api.list_repo_files(repo_id, repo_type="dataset"))
    print(f"  EXISTS — private={d.private}, {n} files, last modified {d.last_modified}")
    print("  A push updates it in place; matching files are skipped.")
else:
    print("  does not exist yet — the push will create it")
print(f"  https://huggingface.co/datasets/{repo_id}")
PYEOF
}

do_push() {
  "${PY}" - <<'PYEOF'
import os
from lerobot.datasets.lerobot_dataset import LeRobotDataset

root = os.environ["DATASET_ROOT"]
repo_id = os.environ["REPO_ID"]
private = os.environ["PRIVATE"] == "true"
tags = os.environ["TAGS_STR"].split()

# root= loads straight from disk; nothing is fetched from the Hub.
ds = LeRobotDataset(repo_id, root=root)
print(f"loaded {ds.meta.total_episodes} episodes / {ds.meta.total_frames} frames from {root}")
print(f"uploading to {repo_id} (private={private}, license={os.environ['LICENSE']}) ...")

# upload_large_folder is deprecated in huggingface_hub 1.x — upload_folder, which
# push_to_hub uses when upload_large_folder=False, is multi-commit and resumable.
ds.push_to_hub(
    tags=tags,
    license=os.environ["LICENSE"],
    private=private,
    push_videos=os.environ["PUSH_VIDEOS"] == "true",
    tag_version=os.environ["TAG_VERSION"] == "true",
    upload_large_folder=False,
)
print(f"\ndone → https://huggingface.co/datasets/{repo_id}")
PYEOF
}

cmd="${1:-info}"
shift || true

ASSUME_YES=false
for arg in "$@"; do
  case "${arg}" in
    -y|--yes) ASSUME_YES=true ;;
    *) die "unknown option '${arg}'" ;;
  esac
done

case "${cmd}" in

  info)
    bold "Resolved configuration"
    printf '  %-14s %s\n' \
      "repo_id"     "${REPO_ID}" \
      "root"        "${DATASET_ROOT}" \
      "visibility"  "$([[ "${PRIVATE}" == "true" ]] && echo private || echo 'PUBLIC')" \
      "license"     "${LICENSE}  (decision D3)" \
      "tags"        "${TAGS[*]}" \
      "push_videos" "${PUSH_VIDEOS}" \
      "tag_version" "${TAG_VERSION}"
    echo
    preflight_local
    summarize
    echo
    bold "Next:  $0 check   then   $0 push"
    ;;

  check)
    bold "Local dataset"
    preflight_local
    echo "  ${DATASET_ROOT} — structure OK (meta/info.json, meta/stats.json, data/)"
    echo
    bold "Hub authentication"
    preflight_auth
    echo
    summarize
    echo
    bold "Preflight passed. Nothing was uploaded."
    ;;

  push)
    preflight_local
    preflight_auth
    echo

    if [[ "${PRIVATE}" != "true" ]]; then
      warn "=============================================================="
      warn " This uploads a PUBLIC dataset. It cannot be un-published."
      warn "   repo:    ${REPO_ID}"
      warn "   license: ${LICENSE}"
      warn "   videos:  ${PUSH_VIDEOS}  (every frame both cameras recorded)"
      warn "=============================================================="
      echo
    fi

    if [[ "${ASSUME_YES}" != "true" ]]; then
      read -r -p "Publish ${REPO_ID} as $([[ "${PRIVATE}" == "true" ]] && echo private || echo PUBLIC)? [y/N] " reply
      [[ "${reply}" == [yY] ]] || die "aborted — nothing uploaded"
      echo
    fi

    do_push
    echo
    bold "Now run:  $0 verify"
    ;;

  verify)
    preflight_local
    "${PY}" - <<'PYEOF'
import os, sys
from pathlib import Path
from huggingface_hub import HfApi

root = Path(os.environ["DATASET_ROOT"])
repo_id = os.environ["REPO_ID"]
push_videos = os.environ["PUSH_VIDEOS"] == "true"

api = HfApi()
if not api.repo_exists(repo_id, repo_type="dataset"):
    sys.exit(f"error: {repo_id} does not exist on the Hub — push has not run")

remote = set(api.list_repo_files(repo_id, repo_type="dataset"))

# Mirror push_to_hub's own exclusions, plus repo-side files with no local twin.
def skip(rel: str) -> bool:
    return (
        rel.startswith("images/")
        or ".cache/" in rel
        or (not push_videos and rel.startswith("videos/"))
    )

local = {
    str(f.relative_to(root)) for f in root.rglob("*")
    if f.is_file() and not skip(str(f.relative_to(root)))
}

missing = sorted(local - remote)
extra = sorted(r for r in remote - local if r not in {"README.md", ".gitattributes"})

print(f"local files to publish : {len(local)}")
print(f"files on the Hub       : {len(remote)}")

if missing:
    print(f"\nMISSING on the Hub ({len(missing)}):")
    for m in missing[:20]:
        print(f"  {m}")
    if len(missing) > 20:
        print(f"  ... and {len(missing) - 20} more")
    print("\nRe-run push — it skips what already matches.")
else:
    print("\nAll local files are present on the Hub.")

if extra:
    print(f"\nOn the Hub with no local counterpart ({len(extra)}):")
    for e in extra[:10]:
        print(f"  {e}")

d = api.dataset_info(repo_id)
refs = api.list_repo_refs(repo_id, repo_type="dataset")
tags = [t.name for t in refs.tags]
print(f"\nprivate : {d.private}")
print(f"tags    : {', '.join(tags) or '(none)'}")
if "v3.0" not in tags:
    print("  WARNING: no v3.0 tag — loading by repo_id will fail. Re-push with TAG_VERSION=true.")
print(f"card    : README.md {'present' if 'README.md' in remote else 'MISSING'}")
print(f"\nhttps://huggingface.co/datasets/{repo_id}")

sys.exit(1 if missing else 0)
PYEOF
    ;;

  card)
    preflight_local
    preflight_auth
    bold "Re-pushing the dataset card only — no data is re-uploaded."
    echo "  license=${LICENSE}  tags=${TAGS[*]}"
    echo
    "${PY}" - <<'PYEOF'
import os
from huggingface_hub import HfApi
from lerobot.datasets.lerobot_dataset import LeRobotDataset
from lerobot.datasets.utils import create_lerobot_dataset_card

repo_id = os.environ["REPO_ID"]
if not HfApi().repo_exists(repo_id, repo_type="dataset"):
    raise SystemExit(f"error: {repo_id} does not exist on the Hub — run 'push' first")

ds = LeRobotDataset(repo_id, root=os.environ["DATASET_ROOT"])
card = create_lerobot_dataset_card(
    tags=os.environ["TAGS_STR"].split(),
    dataset_info=ds.meta.info,
    license=os.environ["LICENSE"],
    repo_id=repo_id,
)
card.push_to_hub(repo_id=repo_id, repo_type="dataset")
print(f"card updated → https://huggingface.co/datasets/{repo_id}")
PYEOF
    ;;

  *)
    die "unknown subcommand '${cmd}'. One of: info check push verify card"
    ;;
esac
