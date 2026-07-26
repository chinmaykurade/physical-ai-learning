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

# Flag uncommitted tracker edits: the mirror would then reflect working-tree
# state that no commit records, which makes the provenance line misleading.
dirty=""
if ! git diff --quiet -- docs/progress.md docs/backlog.md 2>/dev/null; then
	dirty=" (uncommitted local edits)"
fi

for doc in progress backlog; do
	header="Read-only mirror. Do not edit — overwritten on next sync. Source: \`docs/${doc}.md\` at commit \`${sha}\`${dirty} · synced ${today}."
	python3 scripts/md_to_notion.py "docs/${doc}.md" --header "$header" \
		> "${outdir}/${doc}.notion.md"
done

echo "sha=${sha}${dirty}"
echo "date=${today}"
echo "progress=${outdir}/progress.notion.md"
echo "backlog=${outdir}/backlog.notion.md"
