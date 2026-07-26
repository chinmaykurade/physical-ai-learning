---
name: summary
description: Status briefing for the SO-101 embodied-AI project — reads docs/progress.md, docs/backlog.md, and the build plan + learning roadmap, then reports the current phase and the build and study tasks due now. Also applies updates when Chinmay reports tasks done, in progress, skipped, or cut, editing progress.md and backlog.md per the project's tracking rules. Use for "/summary", "where am I", "what's next", "what should I work on", and for "I finished X" / "I'm skipping Y".
---

# /summary — status briefing and tracker update

Two jobs, in one loop: **brief** (what phase am I in, what do I do now) and **update**
(record what got done, deferred, or cut). A `/summary` invocation always briefs first;
if the invocation already reports completions, apply the updates first and brief against
the updated state.

## Source of truth

| File | Owns | May this skill edit it? |
|---|---|---|
| [docs/progress.md](../../../docs/progress.md) | task status, current phase, goals G1–G7, decisions D1–D5 | **yes** |
| [docs/backlog.md](../../../docs/backlog.md) | deferred items, stretch watchlist, gate log, one-in-flight tracker | **yes** |
| [docs/so101-embodied-ai-project-plan.md](../../../docs/so101-embodied-ai-project-plan.md) | hardware, BOM, phases 0–E, timeline, budget, risks R1–R13 | read-only |
| [docs/physical-ai-learning-roadmap.md](../../../docs/physical-ai-learning-roadmap.md) | 14 domains, sources, phases L0–F5, reading queue, code-read plan | read-only |
| `notes/` | weekly log prose, G7 writeups | only when asked |
| Notion mirror pages | nothing — a read-only copy of the two trackers | **push-only**, see `sync-notion` |

The plan and roadmap are specifications — they get revised at a phase gate by explicit
request (plan §11 / Phase E), never as a side effect of a status update. progress.md wins
over CLAUDE.md when they disagree about status.

The Notion mirror owns nothing. It is a convenience copy for reading the board away from the
workstation, refreshed by the `sync-notion` skill after this one edits a tracker. Never read a
status from Notion, and never let it inform a briefing — if Notion and the repo disagree, the
repo is right and the mirror is stale.

## Briefing

Read progress.md in full and backlog.md in full. Pull from the plan/roadmap only to fill in
detail progress.md compresses — the week-by-week study table (roadmap §4), a task's
rationale, a risk ID, a BOM line. Get today's date with `date +%F` so week/pacing claims are
real.

Report, in this order and no longer than it needs to be:

1. **Where I am now** — build phase + study phase, week number, current [Deep] in flight,
   next gate, and whether `Last updated` is stale relative to today.
2. **Build — do now.** Everything ◐, then the ☐ items that are actually unblocked. Flag
   ordering constraints the plan imposes (e.g. servo bus IDs are set *before* assembly;
   never hot-plug the servo chain, risk R8) and note which items are phase **exit criteria**.
3. **Study — do now.** This week's Core row from roadmap §4, plus any reading-queue items
   whose gating condition is met (several say *after the policy runs* / *before the run* —
   respect that). Name the depth tag on each; tags are time contracts.
4. **Blocked / waiting** — tasks that cannot start yet, with what unblocks them. Keep the
   two tracks separate: the build never blocks on study, and study never blocks on the build
   (roadmap §8 rule 3).
5. **Gate status** — what still stands between here and the next phase exit: remaining exit
   criteria, remaining Core, whether the G7 artifact for this phase is shipped.
6. **Flags**, only when they fire: a second [Deep] item in flight (violates rule 1); the
   study track two weeks or more behind (triage rule — cut Stretch, protect the build,
   demote one [Deep]); an item now past its phase exit with no ⤴/backlog row; a ✂ with no
   dated reason; goals or decisions whose underlying tasks are done but whose row is stale.
7. **The checklist** — always last, always present. See below.

Link every task back to its file (`docs/progress.md:NN`) so rows are one click away. Do not
reprint whole tables — the point is the short list of what to do next, not a re-dump of the
tracker. When a task is a "how do I set up X" question, CLAUDE.md's research rule applies:
search and answer with links rather than from memory.

### The checklist (always ends the response)

Every briefing — and every update that changes what to do next — **ends with a plain bullet
checklist of the open items in the current phase**. This is the part Chinmay actually works
from, so it comes last, reads standalone, and carries no prose, no rationale, no links.

Three groups, in this order, dropping any that is empty:

- **Build — now**, for what is actionable today with nothing in the way
- **Build — blocked on `<the specific thing>`**, named for the real blocker (parts delivery,
  printer, assembly) rather than a generic "later"
- **Study**

Rules for it:

- One line per task, phrased as an action, short enough to scan.
- Mark exit criteria inline with `← *exit criterion*` (or `← *study exit criterion*`). Nothing
  else gets annotation.
- Mark in-flight work `*(in progress)*`.
- Mark genuinely optional or not-yet-needed items `(optional — …)` with the reason in a few
  words.
- Only the **current** phase. Never list future phases here.
- Close with a single line naming what was completed recently, so progress is visible.

Do not restate items 2–5 in it — those explain, this one is the worklist. When the response
is an update rather than a full briefing, the compact diff comes first and the checklist still
ends the message.

## Updating

Triggered by Chinmay reporting state: "done X", "finished X", "started X", "skipping X",
"dropping X", "X slipped". Handle it in the same conversation — no re-invocation needed.

**Match first.** Find the row(s) in progress.md the report refers to. If the description is
ambiguous between rows, or spans several, list the candidates and ask before editing. Never
guess at a row that would change a goal or a gate.

**Then apply, per the status legend:**

- **☑ done** — flip the status. Add a short evidence note in the Notes column when there is
  one (a version, a measurement, a checkpoint path). Prose belongs in `notes/`, not here.
- **◐ in progress** — flip on "started". If the item is [Deep], it must become the *Current
  [Deep] in flight* in both progress.md and the backlog's one-in-flight tracker; if another
  [Deep] is already in flight, say so and ask which one holds the slot before editing.
- **⤴ deferred** — the default reading of "skipped" for an item that is being *postponed*.
  This is two edits, always: set ⤴ in progress.md **and** write the row into
  `backlog.md § Active backlog` with its tag, source/ID, the phase it was deferred from, its
  target phase, today's date, and a reason. The ⤴ is a pointer; the backlog row is the
  record. Default target is F1 — F2 for classical robotics and perception, F3 for deployment
  and efficiency (backlog rule 4). If the item is on the Stretch watchlist, it moves off the
  watchlist into the Active backlog on the day it actually slips.
- **✂ cut** — only when Chinmay says the item is genuinely abandoned, not postponed. Requires
  a dated reason in the Notes column, and a row in the backlog recording it as abandoned.

When "skipped" could mean either deferred or abandoned, ask — ⤴ and ✂ are different
promises and the project's first rule is that nothing is silently dropped.

**Depth tags are never edited in place.** A [Deep]→[Read] demotion is written as a demotion:
the Tag column becomes `[Read] (was [Deep])` and the Notes column gets
`[Deep]→[Read] on YYYY-MM-DD, reason`.

**Propagate.** After any status edit, check whether these need to move too:

- `Where I am now` — current [Deep] in flight, next gate. Always refresh `Last updated` to
  today's date (`date +%F`).
- **Goals G1–G7** — flip when the criterion is met, not when the task is merely done. G7 is
  a counter: `☐ 0 of 8 shipped`.
- **Decisions D1–D5** — a decision settled by the completed work gets its row closed with
  what was decided.
- **Backlog one-in-flight tracker** — Current [Deep], Next [Deep], the queue behind it.
- **Version pins** — pins change only at phase gates (roadmap §8 rule 2). If a completion
  report implies a mid-phase upgrade of LeRobot, the CUDA/PyTorch pair, or a course-code
  commit, flag it rather than recording it silently.

**At a phase gate** — when the last exit criterion for the current phase goes ☑, run
roadmap §8 rule 5 rather than just advancing: core done? backlog groomed? artifact shipped?
Tick the three gate checkboxes in progress.md, fill the phase's row in
`backlog.md § Gate review log` (date, core complete, items added, items cleared, artifact),
update `Where I am now` to the next phase and its next [Deep], and only then report the
advance. CLAUDE.md's status paragraph and pins get updated at gates too — offer that edit,
it is the one time this skill touches CLAUDE.md.

**Sync the Notion mirror.** After any edit to progress.md or backlog.md, push the read-only
Notion mirror by following the `sync-notion` skill. This runs on *updates only* — a pure
briefing that changed no file has nothing to sync, so skip it there.

The mirror is push-only (repo → Notion) and Notion is never authoritative: do not read a
status back from Notion, and never let it inform the briefing. If the Notion connector is
unavailable — common in headless, cron, or non-interactive runs — note
"Notion not synced — connector unavailable" in the report and carry on. **A failed sync never
fails the briefing**; the trackers in git are the deliverable.

**Report back** a compact diff: which rows changed and to what, which backlog rows were
added, whether the Notion mirror was synced, and anything that was flagged rather than
edited. Then re-brief if the phase or the next actions changed — and end with **the
checklist**, per the Briefing section. An update that closes or opens a task always ends with
the refreshed checklist, even when the rest of the briefing is skipped.
