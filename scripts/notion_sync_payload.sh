#!/usr/bin/env bash
# Build the Notion-flavored payloads for the read-only tracker mirror.
#
# Read-only mirror: git is the source of truth. This only ever converts
# repo -> Notion, never the reverse. Writes two files the `sync-notion` skill
# then pushes with the Notion MCP update-page tool.
#
# Usage:  scripts/notion_sync_payload.sh [outdir]
# Default outdir is a mktemp dir; the paths are printed on stdout.

set -euo pipefail

repo="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
cd "$repo"

outdir="${1:-$(mktemp -d)}"
mkdir -p "$outdir"

sha="$(git rev-parse --short HEAD)"
today="$(date +%F)"

# The four mirrored docs: output basename -> source file. The trackers are the
# live status board; the plan and roadmap are specifications, mirrored purely for
# reference away from the workstation.
declare -A DOCS=(
	[progress]="docs/progress.md"
	[backlog]="docs/backlog.md"
	[plan]="docs/so101-embodied-ai-project-plan.md"
	[roadmap]="docs/physical-ai-learning-roadmap.md"
)

# Flag uncommitted edits: the mirror would then reflect working-tree state that no
# commit records, which makes the provenance line misleading.
dirty=""
if ! git diff --quiet -- "${DOCS[@]}" 2>/dev/null; then
	dirty=" (uncommitted local edits)"
fi

echo "sha=${sha}${dirty}"
echo "date=${today}"

for name in progress backlog plan roadmap; do
	src="${DOCS[$name]}"
	spec=""
	if [[ $name == plan || $name == roadmap ]]; then
		spec=" This is a specification — revised only at a phase gate, never as a side effect of a status update."
	fi
	header="Read-only mirror. Do not edit — overwritten on next sync. Source: \`${src}\` at commit \`${sha}\`${dirty} · synced ${today}.${spec}"
	python3 scripts/md_to_notion.py "$src" --header "$header" \
		> "${outdir}/${name}.notion.md"
	echo "${name}=${outdir}/${name}.notion.md"
done
