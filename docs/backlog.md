# Study Backlog

Companion to [physical-ai-learning-roadmap.md](physical-ai-learning-roadmap.md) (§5 Backlog
rule; §8 rules 1, 2 and 4) and [so101-embodied-ai-project-plan.md](so101-embodied-ai-project-plan.md).
This file is the single record of everything **either track** deferred or cut, why, and where
it went — the study backlog below, and the build track in
[§ Build track — deferred and cut](#build-track--deferred-and-cut).
Reviewed at every phase gate. Live task status and the current phase live in
[progress.md](progress.md) — an item marked ⤴ or ✂ there must have a row here.

---

## Rules

1. **Nothing is silently dropped.** Anything unread at phase exit moves to the Phase-F
   backlog — it does not evaporate. If an item is genuinely being abandoned, it is written
   here as abandoned, with a date and a reason (§5 Backlog rule).
2. **Depth tags travel with the item.** An item arrives in the backlog carrying the tag it
   had in the roadmap ([Deep] / [Read] / [Skim] / [Aware]). Tags are contracts about time,
   not labels — see roadmap §0.
3. **A [Deep]→[Read] demotion is recorded, never overwritten.** [Deep] items *may* be
   demoted to [Read] when they reach the backlog, but the demotion is written into the
   Notes column as `[Deep]→[Read] on YYYY-MM-DD, reason`. The original tag stays visible in
   the Tag column as `[Read] (was [Deep])`. Never edit a tag in place.
4. **Default target is F1.** Deferred items land in Phase F1 (theory consolidation) unless
   they belong to:
   - **F2** — classical robotics and perception (Modern Robotics chapters, Nayar, 6.4210,
     kinematics capstone, pose/segmentation papers);
   - **F3** — deployment and efficiency (CS336 inference, quantization, TensorRT,
     latency work).
5. **Triage rule (§8 rule 4):** when the study track is **two weeks behind**, cut Stretch,
   protect the build, and demote one [Deep] to [Read]. The build never blocks on study, and
   study never blocks on the build.
6. **One [Deep] in flight (§8 rule 1).** Everything else queues — see the tracker at the
   bottom of this file.
7. **Build items are carried here too.** Rules 1 and 3 are study-track mechanics (depth tags,
   Phase-F targets) and do not apply to build work, so build deferrals and cuts get their own
   table with build-shaped columns: the BOM or plan line, the risk it mitigated, and what now
   covers that risk. A build ✂ must name the **residual risk** it leaves behind — that is the
   whole point of recording it rather than deleting the row.

---

## Active backlog

Empty by design. The first entries arrive at the **L0 gate** — nothing is deferred before a
gate has judged it deferred.

| Item | Source/ID | Tag | Deferred from | Target | Date added | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

---

## Stretch watchlist

Every item roadmap §4 marks as **Stretch**. These are **not deferred** and do not belong in
the Active backlog — they are simply the items most likely to slip if a phase runs tight.
An item moves to the Active backlog only when it actually slips past its phase exit, at
which point it is written there with its date and target.

| Item | Phase | Tag | Likely target | Note |
|---|---|---|---|---|
| MuJoCo docs — Modeling chapter | L0 | [Read] | F1 | D11 spine; Computation chapter is separately scheduled as Core in L-D wk 10 |
| Modern Robotics Ch. 4 (FK) + NumPy FK for the SO-101 | L-A | [Deep] | F2 | F2 explicitly covers "Ch. 4–6 deep if deferred"; feeds the kinematics capstone |
| Nayar *First Principles of Computer Vision* — full image-formation playlist | L-B | [Deep] | F2 | Roadmap names F2 as the target; L-B Core only needs the calibration subset |
| OpenVLA-OFT (2502.19645) | L-C | [Skim] | F1 | Roadmap names F1 as the target |
| ECoT (2407.08693) | L-C | [Aware] | F1 | Grouped with the §5 #65 field-literacy batch |
| RDT-1B | L-C | [Aware] | F1 | Grouped with the §5 #65 field-literacy batch |
| Modern Robotics Ch. 8 & 11 (dynamics / control) | L-D | [Deep] | F2 | Roadmap names F2 as the target; F2 lists Ch. 8, 9, 11 as [Deep] |

L-E lists no Stretch items — its three weeks are all Core.

---

## Build track — deferred and cut

Build-side items dropped or postponed against [so101-embodied-ai-project-plan.md](so101-embodied-ai-project-plan.md).
Per rule 7, every ✂ names the residual risk. Reviewed at each gate alongside the study backlog.

| Item | Plan line | Status | Risk it mitigated | Phase | Date | Residual risk / what covers it now |
|---|---|---|---|---|---|---|
| Feetech STS3215 spare gear sets ×2 | plan §6 BOM-C (`plan.md:91`) | ✂ cut | R2 — servo DOA or stripped gear | 0 | 2026-07-26 | No standalone 1:345 SKU found at Robu, AliExpress or the Feetech resellers; TheRobotStudio SO-101 README documents no gear-replacement path. **Covered by the 13th spare servo in BOM-A** — a stripped gear now costs a whole servo instead of a gear set, and the spare is single-use |

**Reversed, kept for the record:** inline fuse + kill-switch (plan §6 BOM-C, `plan.md:94`) was
cut on 2026-07-26 on the grounds that the PSU would be wired directly to the motor driver, and
reinstated the same day — a fuse sits in series between PSU and driver, so the wiring choice
never displaced it. The fused 12 V rail is architecture, not just a BOM line (`plan.md:39`).

---

## Gate review log

One row per gate. 30 minutes at each build-phase exit against the roadmap: core done?
backlog groomed? artifact shipped? Then advance (§8 rule 5). The artifact column carries the
G7 installment that gate owes, per roadmap §7.

| Date | Gate | Core complete? | Items added | Items cleared | Artifact shipped |
|---|---|---|---|---|---|
| | L0 exit | | | | — (no G7 due; first artifact is at L-A) |
| | L-A exit | | | | G7 #1 — *"From kit to policy: 50 demos to 80% autonomous"* |
| | L-B exit | | | | G7 #2 — *"How many demos is enough?"* (scaling curve + ablation + published dataset) |
| | L-C exit | | | | G7 #3 — *"ACT vs SmolVLA vs a 3B VLA on the same desk"* |
| | L-D exit | | | | G7 #4 — *"RL that actually worked: HIL-SERL vs my BC baseline"* |
| | L-E exit | | | | G7 #5 — *"Making it fast: quantization, TensorRT, and async inference on a hobby arm"* (or held for F3's fuller version) |

---

## One-in-flight tracker

Roadmap §8 rule 1: **one [Deep] item in flight at a time.** Everything else queues.

- **Current [Deep]:** none — Phase L0 has no [Deep] items. L0 Core is tooling setup
  (Docker ☑, W&B ☑, Zotero ☑, Keshav ☑, HF Course Unit 0 ☑ — all of week 0 closed), the
  3Blue1Brown linear-algebra refresh, Karpathy #1 (micrograd — ◐ in flight as a Deep-*course*,
  which does not occupy the [Deep] slot), and MuJoCo Overview + the Menagerie SO-ARM100 model.
- **Next [Deep]:** **ACT / ALOHA — 2304.13705**, roadmap §5 #5, scheduled **L-A week 4**,
  read *after* the first policy runs.
- **Queued behind it:** Diffusion Policy (2303.04137, L-B) → *Attention Is All You Need*
  (1706.03762, L-C) → LoRA (2106.09685, L-C) → π0 (2410.24164, L-C) → GR00T N1
  (2503.14734, L-C) → SmolVLA (2506.01844, L-C) → HIL-SERL (2410.21845, L-D) → TRI LBM
  report (L-E). Plus the two [Deep] courses that run across phases: MIT 6.S184 (L-B/L-C)
  and the NVIDIA SO-101 sim-to-real course (L-E).
