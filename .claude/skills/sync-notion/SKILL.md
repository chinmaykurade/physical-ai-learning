---
name: sync-notion
description: Push docs/progress.md and docs/backlog.md to their read-only Notion mirror pages. Use for "/sync-notion", "sync Notion", "update the Notion mirror", or after any tracker edit that should show up on the phone. Git is the source of truth; this is push-only and never reads status back from Notion.
---

# /sync-notion — push the tracker mirror to Notion

One job: overwrite the two Notion mirror pages with the current contents of
[docs/progress.md](../../../docs/progress.md) and [docs/backlog.md](../../../docs/backlog.md).

**Direction is fixed: repo → Notion.** Never the reverse. `docs/progress.md` is the source of
truth for task status (CLAUDE.md, and the `/summary` skill's own source-of-truth table). Notion
is a convenience mirror for reading the board away from the workstation — on a phone at the
workbench, or away from the desk. Nothing in Notion is ever authoritative, and this skill never
copies a status from Notion into the repo. If the two disagree, the repo is right and the
mirror is stale.

## The pages

| Doc | Notion page | Page ID |
|---|---|---|
| parent | [SO-101 Embodied AI](https://app.notion.com/p/3a9c6576670181b2a66deb8035f097d2) | `3a9c6576-6701-81b2-a66d-eb8035f097d2` |
| `docs/progress.md` | [Progress Tracker](https://app.notion.com/p/3a9c657667018121a797dda10eec5ce9) | `3a9c6576-6701-8121-a797-dda10eec5ce9` |
| `docs/backlog.md` | [Backlog](https://app.notion.com/p/3a9c657667018119a2a5ee863bde5d45) | `3a9c6576-6701-8119-a2a5-ee863bde5d45` |

These IDs are stable. Reuse them — do **not** create new pages. Creating a second "Progress
Tracker" is the main failure mode to avoid, because then the phone view and the repo diverge
silently with no way to tell which page is live.

## How to run it

1. **Build the payloads.** From the repo root:

   ```bash
   scripts/notion_sync_payload.sh /tmp/notion-sync
   ```

   It prints `sha=`, `date=`, and the two payload paths. The converter
   ([scripts/md_to_notion.py](../../../scripts/md_to_notion.py)) turns GitHub pipe tables into
   Notion `<table>` XML — Notion's markdown does not accept pipe tables — and prepends a
   read-only provenance callout naming the source file, the commit, and the sync date.

   If `sha=` carries `(uncommitted local edits)`, the trackers have uncommitted changes. That is
   fine and worth syncing, but say so in the report — the provenance line will name a commit that
   does not contain what the mirror shows.

2. **Read each payload file**, then push it with the Notion `update-page` tool using
   `command: "replace_content"` and the page ID from the table above. Replace wholesale rather
   than patching: the mirror is disposable, and a full replace is the only way to guarantee it
   matches the file. Pass `allow_deleting_content: true` — the mirror pages have no child pages
   to lose.

3. **Verify** by fetching one page back and confirming the provenance callout shows today's date
   and that tables rendered as tables, not as escaped text.

4. **Report**: which pages were pushed, the commit and date stamped on them, and anything the
   conversion could not carry (see below).

## Known conversion limits

State these when they bite rather than silently shipping a lossy mirror:

- **Relative markdown links do not resolve.** `[backlog.md](backlog.md)` and
  `docs/progress.md:NN` line references are repo-relative and dead in Notion. The mirror is for
  reading status, not for navigation. Cross-references between the two mirror pages should be
  rewritten as prose ("the Backlog page") rather than left as broken links.
- **Notion auto-escapes `[`, `]` and `~` on ingest.** `\[Deep\]` in the fetched text is normal
  and renders correctly as `[Deep]`. Not a bug, do not try to fix it.
- **A `+` after an inline-code span gets eaten.** Notion reads `` `foo` + bar `` as list markup
  and renders the `+` as a bullet, corrupting notes like ``  `model.safetensors` + config  ``.
  The converter escapes this case (`PLUS_AFTER_CODE`). If a new variant appears, fix it in the
  converter, not by hand-editing Notion.
- **`update_content` search-and-replace is unreliable against stored text** whose whitespace
  Notion normalised on ingest. This is why step 2 uses `replace_content`, not targeted patches.
- The emoji status legend (`☐ ◐ ☑ ⤴ ✂`) survives as plain text and reads fine.

## When the connector is missing

The Notion MCP connector is interactively authenticated, so it may be **absent in headless,
cron, or non-interactive runs**. If the Notion tools are unavailable:

- Do **not** fail the caller, and never fail a `/summary` briefing over it.
- Say plainly: "Notion not synced — connector unavailable in this session."
- The repo is unaffected. The mirror is simply stale until the next interactive run.

Never ask for tokens, auth codes, or callback URLs. Authorisation happens in the user's
claude.ai connector settings, not here.
