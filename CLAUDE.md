# CLAUDE.md — SO-101 Embodied AI Rig

**Project identity.** An SO-101 imitation-learning rig: one follower arm and one leader arm
used to teleoperate it and record demonstrations, driven from an RTX 3080 workstation
running LeRobot. This is **Stage 1 of 2** (Stage 2 = XLeRobot dual-arm mobile robot; every
Stage-1 component carries forward). It has a dual purpose that must both be served: a
working robot, *and* a hands-on curriculum in modern embodied AI (BC/IL → LBMs → VLAs →
real-world RL). Owner: **Chinmay**.

## Hardware

- **GPU: RTX 3080, 10 GB.** ~9.4–9.6 GB usable with a desktop session running. This is
  plan risk **R6** and it **binds** — it is a design constraint on every training decision,
  not a caveat. Cloud LoRA (rented A100) is the planned escape hatch for 3B-class
  fine-tunes; local inference is bf16/quantized. *(Measured: 10240 MiB total, ~1.2 GiB
  held by the desktop session, torch sees 9.64 GiB.)*
- **OS: Ubuntu native, dual-boot. Never WSL2** — risk **R5**, USB passthrough via usbipd is
  a known failure mode for the servo buses. Currently native Linux, kernel 7.0.0-28-generic.
- **Servos: Feetech STS3215-C018** (12 V, 30 kg·cm), 13 units (6 follower + 6 leader +
  1 spare), daisy-chained per arm on a **shared, fused 12 V rail**, one Waveshare serial-bus
  adapter per arm. The leader runs torque-disabled as a passive encoder. The C018 suffix is
  load-bearing: C001 is 7.4 V and electrically incompatible on this rail.

## Environment

uv-managed venv at **`/home/chinmay/lerobot-env`** — **outside this repo**, never committed.
Use **`uv pip`**, never bare `pip`. Regenerate the lock after any change:

```bash
uv pip freeze --python /home/chinmay/lerobot-env/bin/python > env/lerobot-env.lock.txt
```

Load-bearing pins (from `env/lerobot-env.lock.txt`): `lerobot==0.6.0` · `torch==2.11.0`
(`+cu130`) / `torchvision==0.26.0` / `torchcodec==0.11.1` · CUDA stack
`cuda-toolkit==13.0.2`, `cuda-bindings==13.3.1`, `nvidia-cudnn-cu13==9.19.0.56`,
`nvidia-cublas==13.1.0.3`, `nvidia-nccl-cu13==2.28.9`, `triton==3.6.0` ·
`transformers==5.5.4` · `diffusers==0.35.2` · `accelerate==1.14.0` ·
`feetech-servo-sdk==1.0.0` (+ `pyserial==3.5`) · `gymnasium==1.3.0` · `gym-pusht==0.1.6`.
Verified on this machine: **torch 2.11.0+cu130, CUDA 13.0, sm_86, bf16 native**.

**Interpreter: Python 3.12.3, and 3.12 is a floor, not a preference** — `lerobot==0.6.0`
declares `Requires-Python >=3.12`, so a 3.10 env cannot install this release at all. Plan
§5.2 originally said 3.10; corrected 26 Jul 2026. Do not "fix" the env down to 3.10.

## Current status — build Phase 0 / study phase L0

Verified done: environment built and the GPU path confirmed end to end (torch/CUDA/bf16 on
sm_86); lock file captured; Ubuntu native, not WSL2.

Still open (plan Phase-0 exit criteria): **all BOM parts received and inspected**; all
follower/leader parts plus the alignment jig **printed**; **simulated teleoperation** run;
**toy training job** completed end to end. Phase 0 does not exit until the sim pipeline is
proven with no hardware in the loop.

**`docs/progress.md` is the live status board — read it at the start of any session that
touches build or study work, and trust it over this paragraph.** It carries the current
phase, every task across Phases 0–F with its status, the goals G1–G7, and decisions D1–D5.

## Progress-tracking process

Three files, three jobs — keep them from drifting:

- **`docs/progress.md`** — task status and *where I am now*. Flip a status the day it
  changes, not at gate time. Statuses: ☐ not started · ◐ in progress · ☑ done · ⤴ moved to
  backlog · ✂ cut (dated reason required).
- **`docs/backlog.md`** — deferred items, the stretch watchlist, and the gate review log.
- **`notes/`** — the Saturday 30-minute log and the G7 writeups. Prose lives here, never in
  the tracker.

When an item slips past its phase exit: set it ⤴ in progress.md **and** write the row into
backlog.md with tag, target and date. The ⤴ is a pointer; backlog.md is the record. Never
edit a depth tag in place — a [Deep]→[Read] demotion is written as a demotion.

At a phase gate: run roadmap §8 rule 5 (core done? backlog groomed? artifact shipped?), fill
the backlog.md gate row, update **Where I am now** in progress.md, then advance.

## Standing rules (roadmap §8 — respect these in every session)

1. **One [Deep] item in flight.** Everything else queues.
2. **Version pins change only at phase gates** (extends plan risk R7 to study code). No
   mid-phase upgrades of LeRobot, the CUDA/PyTorch pair, or course-code commits.
3. **The build never blocks on study, and study never blocks on the build.**
4. **Backlog items are never silently dropped** — deferred work goes to `docs/backlog.md`
   with its depth tag intact; a [Deep]→[Read] demotion is recorded, not overwritten.

## Two roles in this repo: coding agent **and** web research agent

This project runs on fast-moving external material — LeRobot churns (risk R7), courses and
model checkpoints move, and much of the work is "how do I set up X". So:

- **When a question needs current external information, search the web and answer with
  links.** Setup and tooling ("how do I set up W&B / Docker / RunPod / TensorRT"), library
  and CLI usage, course and lecture locations, paper lookups, hardware sourcing and
  pricing, error messages from a specific version — all of these get a search, not a recall.
- **Always include the relevant URLs in the response** — official docs and primary sources
  first, a good tutorial second. A prose answer with no links is an incomplete answer to a
  research question.
- **Do not invent URLs, arXiv IDs, or API signatures.** Roadmap §3 warns that IDs may 404 —
  search by title and first author, which are the durable identifiers.
- **Prefer the pinned version's docs.** This env is `lerobot==0.6.0` / `torch 2.11.0+cu130`
  / Python 3.12; a tutorial written against a different release is a lead, not an answer.
- Pure coding, file, and repo work needs no search — don't pad answers with links that
  aren't load-bearing.

## Where things live

- [docs/progress.md](docs/progress.md) — **owns task status and the current phase**: all
  Phase 0–F tasks, goals G1–G7, decisions D1–D5. The status board.
- [docs/so101-embodied-ai-project-plan.md](docs/so101-embodied-ai-project-plan.md) — **owns
  hardware, BOM, phases 0–E, timeline, budget, risks R1–R13, decisions D1–D5.**
- [docs/physical-ai-learning-roadmap.md](docs/physical-ai-learning-roadmap.md) — **owns
  study scheduling**: the 14 domains, source library, phases L0–L-E and F1–F5, the
  ~65-item reading queue, the LeRobot code-reading plan.
- [docs/backlog.md](docs/backlog.md) — **owns deferred items and gate history**: active
  backlog, stretch watchlist, gate review log, one-in-flight tracker.
- [env/README.md](env/README.md) — environment path and regeneration. `notes/` — weekly
  logs and G7 writeups.

## Maintaining this file

Update CLAUDE.md **only at phase gates, or when a pin or a hardware fact changes.** It is
durable context, not a status board — day-to-day progress belongs in `docs/progress.md`.
