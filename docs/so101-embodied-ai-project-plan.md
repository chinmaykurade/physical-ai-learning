# SO-101 Robot Arm & Embodied AI Learning Rig — Project Plan

**Owner:** Chinmay · **Location:** Kerala, India · **Date:** 24 July 2026 · **Version:** 1.1
**Status:** Ready for procurement · **Stage:** 1 of 2 (Stage 2 = XLeRobot dual-arm mobile robot)
**v1.1 changes:** full BOM with fabrication equipment (Bambu Lab P2S Combo), filament requirements, optional items, and a course curriculum mapped to phases.

---

## 1. Purpose & Introduction

This project builds a complete imitation-learning rig around the open-source SO-101 robot arm: a **follower arm** that executes tasks and a **leader arm** used to teleoperate it and record demonstrations, both driven from an existing RTX 3080 workstation running the LeRobot framework.

The rig serves two purposes at once. First, it is **Stage 1 of a larger build** — a dual-arm mobile household robot (XLeRobot) — and every component purchased here (servos, adapter boards, cameras, printed knowledge) carries forward into that robot without waste. Second, and more importantly, it is a **hands-on curriculum in modern embodied AI**. The explicit learning goals are the method families that define the field today: imitation learning and behavior cloning, large behavior models (LBMs), vision-language-action models (VLAs), and real-world reinforcement learning. Each project phase below is paired with the concepts it teaches and the papers it makes legible, so the outcome is not just a working robot but demonstrable, career-relevant AI engineering skill.

A note on model roles, since this shaped the plan: world foundation models such as NVIDIA Cosmos are *data-generation and simulation* tools used at industrial scale, and their VRAM requirements (26 GB+) exceed consumer hardware. They are not needed here. The models that actually control a robot from instructions are **policy models** — ACT, Diffusion Policy, SmolVLA, GR00T N1.7, π0 — all of which are trainable or at least runnable within this project's hardware and small cloud budget.

## 2. Goals & Success Criteria

| # | Goal | Success criterion |
|---|------|-------------------|
| G1 | Working teleoperation rig | Leader arm drives follower smoothly; calibration passes; 30-minute teleop session without faults |
| G2 | First autonomous policy | ACT policy achieves ≥ 8/10 successes on a pick-and-place task using ~50 self-recorded demonstrations |
| G3 | Data-centric study | Demo-count scaling curve (10/25/50/100 episodes) and camera ablation completed; dataset published to Hugging Face Hub |
| G4 | Language-conditioned control | Fine-tuned SmolVLA executes 3+ distinct tasks selected by natural-language instruction |
| G5 | Frontier VLA fine-tune | GR00T N1.7 or π0 LoRA-fine-tuned on own data in the cloud, running inference locally on the 3080 |
| G6 | Real-world RL | One task trained via HIL-SERL with leader-arm interventions, exceeding the BC baseline success rate |
| G7 | Portfolio output | Short written note or post per phase documenting method, results, and lessons |

## 3. Scope

**In scope (Stage 1):** one follower + one leader SO-101, single 12 V supply, PC-hosted control and training, tabletop manipulation tasks, simulation environments for the same arm, cloud fine-tuning of ≤ 3–4 B parameter models.

**Deferred to Stage 2:** second follower arm, mobile base (XLeRobot dual-wheel or omni), onboard Raspberry Pi, battery power, head camera gimbal, whole-body tasks.

**Out of scope:** custom servo or PCB design, humanoid hardware, training runs requiring multi-GPU clusters, ROS 2 (LeRobot does not need it; revisit only if Stage 2 demands).

## 4. System Overview

Two arms connect to the workstation over USB, each through its own Waveshare serial-bus servo adapter. All 12 servos are the same SKU (Feetech STS3215-C018, 12 V / 30 kg·cm), daisy-chained per arm on a single fused 12 V rail; the leader's servos run torque-disabled as passive encoders. A rigidly clamped 1080p webcam observes the workspace (a wrist camera is added in Phase B). The PC (Ubuntu, RTX 3080 10 GB) runs LeRobot for teleoperation, dataset recording, training, and inference.

**Model stack and where it runs:**

| Model | Role | Train | Inference |
|---|---|---|---|
| ACT | Single-task imitation baseline | Local 3080 (hours) | Local |
| Diffusion Policy | Comparison method / LBM building block | Local 3080 | Local |
| SmolVLA (~450 M) | Language-conditioned multi-task | Local fine-tune | Local |
| GR00T N1.7 (3 B) / π0 | Frontier VLA | Cloud LoRA (rented A100, hours) | Local (bf16/quantized) |
| HIL-SERL | Real-world RL | Local + human interventions | Local |

## 5. Requirements

### 5.1 Bill of Materials

The BOM is split into three parts: **A — robot core** (required to hit G1–G6), **B — fabrication** (3D printer and filament; capital equipment that outlives this project), and **C — optional and upgrade items** (quality-of-life, resilience, and Stage-2 pre-buys).

#### 5.1-A · Robot core (required)

| Item | Qty | Source | Est. cost (₹) |
|---|---|---|---|
| Feetech STS3215-C018 servo (12 V, 30 kg·cm) | 13 (6 follower + 6 leader + 1 spare) | Evelta (in stock at time of writing) | 30,500 |
| Waveshare serial bus servo adapter board | 2 | Amazon.in / Robu | 1,600–2,400 |
| 12 V 5 A PSU (or existing 3S LiPo + XT60→5.5 mm barrel lead) | 1 | Local / drone bench | 0–800 |
| 1080p USB webcam (workspace view) | 1 | Amazon.in | 1,500–2,500 |
| USB endoscope-style wrist camera (Phase B) | 1 | Amazon.in | 800 |
| M3 fastener assortment, zip ties, USB cables | — | Robu / local | 800 |
| **Subtotal A** | | | **≈ 35,200–37,800** |

Sourcing notes: order servos on day 1 — domestic stock of the C018 variant is thin and this project already migrated off one out-of-stock supplier. Verify the variant suffix (C018 = 12 V 30 kg; C001 = 7.4 V 19.5 kg — electrically incompatible on a shared 12 V rail). If domestic stock fails, fallback is a small import (WowRobo / Feetech AliExpress store, ~40 % landed duty on the shortfall only).

#### 5.1-B · Fabrication: 3D printer & filament

| Item | Qty | Source | Est. cost (₹) |
|---|---|---|---|
| Bambu Lab P2S Combo (printer + AMS 2 Pro) | 1 | Robocraze (~₹1,00,000 incl. GST); also 3Ding, Ideal3D, Zee3D, 3D Protofarm | 95,000–1,00,000 |
| — alternative: P2S standalone (no AMS) | 1 | 3Ding / Ideal3D | 71,999 |
| PLA (arm structure, jigs, reprints) | 3 × 1 kg | eSUN / Sunlu / WOL3D / Bambu resellers | 2,100–3,300 |
| PETG (clamps, camera mounts, higher-stress brackets) | 1 kg | same | 900–1,300 |
| TPU 95A (compliant gripper fingertips) | 0.5–1 kg | same | 1,000–1,800 |
| Spare 0.4 mm nozzle + build-plate glue/IPA | — | printer reseller | 800–1,500 |
| **Subtotal B (with Combo)** | | | **≈ 1,00,000–1,08,000** |

Printer notes: the P2S (256 mm³ enclosed CoreXY, servo extruder, auto flow calibration) comfortably exceeds this project's needs — every SO-101/XLeRobot part fits its bed, and the enclosure helps if PETG/ABS enters the picture in Stage 2. Two honest caveats: (1) all robot parts are **single-material prints**, so the AMS 2 Pro adds convenience and multi-color capability for other projects, not capability for this one — the standalone P2S at ₹71,999 saves ~₹28k if the budget is tight; (2) TPU 95A should be fed from the external spool holder, not through the AMS, per Bambu's own guidance for soft filaments. Some Indian resellers list the P2S on 1–2 week backorder — order early or buy the ~1.3 kg of Phase-A parts from a print service (₹2,500–3,500) to avoid blocking assembly.

#### 5.1-C · Optional & upgrade items

| Item | Purpose | Source | Est. cost (₹) |
|---|---|---|---|
| Xbox-style USB/Bluetooth gamepad | Backup teleop; HIL-SERL intervention device alternative (decision D2) | Amazon.in | 1,800–4,500 |
| Official SO-101 leader gear-ratio servo set (mixed 1:191 / 1:147 ratios) | Lighter leader-arm feel if C018 back-drive friction hurts demo quality (decision D1) | WowRobo import | 8,000–10,000 + duty |
| Feetech STS3215 spare gear sets ×2 | Field repair of stripped gears without cannibalizing the spare servo | AliExpress / Robu | 600–1,000 |
| Powered USB 3.0 hub | Stable bandwidth once 2–3 cameras stream simultaneously | Amazon.in | 1,500–2,500 |
| Second 1080p webcam | Multi-view ablations in Phase B | Amazon.in | 1,500–2,500 |
| Inline blade fuse holder + 5 A fuses, illuminated rocker kill-switch | Fused 12 V rail and reachable e-stop (risk R8) | Local auto/electronics shop | 400–700 |
| 12 V→7.4 V buck converter + XT60 pigtails | Only needed if C001-variant servos ever join the bus | Robu / drone bench | 300–600 |
| Digital calipers | Print tolerance tuning, assembly QC | Amazon.in | 800–1,200 |
| Cable spiral wrap + label sheets | Bus hygiene; servo IDs stay legible | Local | 300–500 |
| Raspberry Pi 5 (8 GB) + PSU + microSD | Stage-2 pre-buy; also enables headless rig experiments | Robu / Silverline | 9,000–11,000 |
| **Subtotal C (all options)** | | | **≈ 24,000–34,500** |

Recommended minimum from list C: gamepad, fuse + kill-switch, spare gear sets, calipers (~₹3,600–7,400). Everything else can wait for a demonstrated need.

### 5.2 Software & accounts

Ubuntu 22.04/24.04 native (dual-boot preferred; WSL2 works but USB passthrough via usbipd is a known friction point) · **Python 3.12** environment (corrected from 3.10 on 26 Jul 2026: LeRobot 0.6.0 declares `Requires-Python >=3.12`, so 3.10 cannot install it; the working env is 3.12.3) · LeRobot with Feetech extras, pinned to a known-good release per phase · PyTorch + CUDA matching the pin · MuJoCo / ManiSkill SO-101 environments · Hugging Face account (datasets + model hub) · RunPod or equivalent GPU-rental account with ~₹2,000–3,000 budget for Phase C.

### 5.3 Courses, reading list & prerequisites

Working Python and basic PyTorch are assumed. Electronics, soldering, and battery handling skills transfer directly from prior FPV drone work.

The curriculum below pairs one primary course per phase with the papers that phase makes legible. The deliberate pattern: touch the hardware first, then study the theory — papers read completely differently after debugging your own version of their problems. All primary courses are free.

| Phase | Primary course | Format & cost | Supporting papers |
|---|---|---|---|
| 0–A | **Hugging Face Robotics Course** (huggingface.co/learn/robotics-course) — classical foundations → robot learning → imitation learning, built directly on LeRobot and the Robot Learning Tutorial. Do Units 0 through the IL unit alongside the build. | Self-paced, free | ALOHA / ACT |
| B | **MIT 6.4210 Robotic Manipulation** (Russ Tedrake) — manipulation.csail.mit.edu; free lecture videos + online textbook. Tedrake also leads TRI's LBM effort, so this is the intellectual home of the Phase-B methodology. Selected chapters: perception, grasping, learning-based manipulation. | Self-paced, free | Diffusion Policy; TRI *Large Behavior Models* report |
| C | **HF Robotics Course — foundation-model/VLA units**, plus **NVIDIA DLI self-paced robot-learning courses** (Isaac Sim / Isaac Lab track) for the simulator and GR00T ecosystem. Optional deeper theory: Stanford **CS224R Robot Learning** lecture videos (Chelsea Finn). | Self-paced; free (DLI courses free–low cost) | SmolVLA; π0 / π0.5; GR00T N1.x whitepaper |
| D | **UC Berkeley CS285 Deep RL** (Sergey Levine) — the canonical deep-RL-for-robotics course, full lectures on YouTube. Fast-track alternative: **HF Deep RL Course** (free, hands-on, lighter). Keep **OpenAI Spinning Up** open as a reference throughout. | Self-paced, free | SERL; HIL-SERL |
| Optional | **Modern Robotics** specialization (Northwestern / Kevin Lynch, Coursera) — classical kinematics and dynamics grounding, useful before Stage 2 but not blocking. | Audit free / cert paid | — |

Realistic pacing: one course unit or lecture block per week alongside the build (≈ 3–4 h/week of the §7 time budget). CS285 in particular is a semester course — extract the model-free RL, offline RL, and RL-from-human-feedback lecture blocks rather than completing it linearly.

### 5.4 Workspace

A rigid desk with the camera clamped (never handheld), consistent artificial lighting independent of time of day, taped reference positions for objects, and clear floor space around the arm during autonomous runs.

## 6. Phase Plan

### Phase 0 — Procurement & Preparation (Week 0–1)

*Objective: everything on the desk and the software stack proven before assembly begins.*

Order the full BOM on day 1. While shipping: print all follower and leader parts plus the assembly-alignment jig; install Ubuntu, the Python environment, and LeRobot; run simulated teleoperation and a toy training job end-to-end so the pipeline is verified before hardware exists. **Exit criteria:** all parts received and inspected; simulated teleop + training run completes.

### Phase A — Build & First Autonomous Policy (Weeks 1–4)

*Objective: a calibrated leader/follower rig and a trained ACT policy — the full imitation-learning loop, experienced once.*

Set each servo's bus ID **before** assembly and label every cable. Assemble follower, then leader; wire each to its adapter; run joint calibration. Practice teleoperation until pick-and-place feels fluent. Define one canonical task (cube → bowl), record ~50 short episodes (10–15 s), train ACT overnight on the 3080, and evaluate over 10 scripted trials. **Deliverables:** calibration record, 50-episode dataset, trained checkpoint, evaluation log. **Learning outcomes:** behavior cloning, action chunking and temporal ensembling, dataset hygiene, why demonstration quality dominates architecture. **Study track:** HF Robotics Course, Unit 0 through the imitation-learning unit; read the ACT paper after the first policy runs. **Exit criteria:** G1 and G2 met.

### Phase B — Data-Centric Experiments (Weeks 4–6)

*Objective: learn the experimental methodology behind large behavior models at desk scale.*

Re-record the canonical task at 10/25/50/100 episodes and plot success-rate scaling. Add the wrist camera and ablate it. Train Diffusion Policy on identical data and compare against ACT. Publish the best dataset with documentation to the Hugging Face Hub. **Deliverables:** scaling curve, ablation table, method comparison, public dataset, written note (G3, first G7 installment). **Learning outcomes:** data-centric ML practice, diffusion/flow policies, evaluation discipline, the reasoning behind TRI-style LBMs. **Study track:** MIT 6.4210 selected chapters (perception, grasping, learning-based manipulation); Diffusion Policy paper before the method comparison; TRI LBM report after it.

### Phase C — Vision-Language-Action Models (Weeks 6–9)

*Objective: language-conditioned control, from a small local VLA to a frontier model fine-tuned on own data.*

Record a 3–4 task dataset with language annotations. Fine-tune SmolVLA locally; verify instruction-following ("pick up the red cube" vs "put the sponge in the tray"). Then rent an A100 for a few hours and LoRA-fine-tune GR00T N1.7 or π0 using their SO-101 configs; export and run inference on the 3080. Build a small evaluation harness that scores each instruction separately. **Deliverables:** G4 and G5, plus a written comparison of the three models' data efficiency and failure modes. **Learning outcomes:** VLM backbones, action tokenization vs flow-matching action experts, LoRA fine-tuning economics, local deployment of 3 B-class models. **Study track:** HF Robotics Course foundation-model units; NVIDIA DLI Isaac Lab course before the GR00T fine-tune; SmolVLA → π0 → GR00T papers in that order (smallest to largest).

### Phase D — Reinforcement Learning (Weeks 9–12)

*Objective: RL where it actually works in 2026 — simulation at scale, and sample-efficient human-in-the-loop RL on real hardware.*

Simulation track: train PPO/SAC on the SO-101 MuJoCo/ManiSkill environments, experiment with reward shaping and domain randomization, attempt a sim-to-real transfer and document the gap honestly. Real-world track: set up LeRobot's HIL-SERL with the leader arm as the intervention device; train one contact-rich task (e.g., precise insertion) and compare against its BC baseline. **Deliverables:** G6, sim2real writeup. **Learning outcomes:** reward design, off-policy RL with human corrections, why HIL-SERL succeeds where naive real-world RL fails. **Study track:** CS285 model-free RL and offline-RL lecture blocks (or the HF Deep RL Course end-to-end as the faster path); SERL and HIL-SERL papers before the real-robot run; Spinning Up as the standing reference.

### Phase E — Stage 2 Decision Gate (Month 4+)

*Objective: a deliberate go/no-go on scaling to the XLeRobot.*

Review outcomes against G1–G7, then decide on the upgrade: second follower arm, mobile base (default: the cheaper dual-wheel variant), Raspberry Pi 5, battery, and cart — an incremental ₹30,000–45,000, reusing every Stage 1 component including the leader arm as the bimanual teleop rig. This plan document gets a v2.0 revision at that point.

## 7. Timeline Summary

| Weeks | Phase | Key milestone |
|---|---|---|
| 0–1 | Phase 0 | Parts ordered day 1; sim pipeline verified |
| 1–4 | Phase A | First autonomous ACT policy ≥ 80 % |
| 4–6 | Phase B | Scaling study + public dataset |
| 6–9 | Phase C | Language-conditioned VLA, cloud fine-tune deployed locally |
| 9–12 | Phase D | HIL-SERL task beats BC baseline |
| 16+ | Phase E | Stage 2 go/no-go |

Pacing assumes ~8–10 focused hours per week; phases are sequential but reading and printing parallelize with shipping and training runs.

## 8. Budget Summary

| Category | Est. cost (₹) |
|---|---|
| A · Robot core hardware (§5.1-A) | 35,200–37,800 |
| B · Fabrication — P2S Combo + filament + printer consumables (§5.1-B) | 1,00,000–1,08,000 |
| C · Optional items — recommended minimum / full list (§5.1-C) | 3,600–34,500 |
| Cloud GPU rental (Phase C) | 2,000–3,000 |
| Courses | 0 (all primary courses free) |
| Contingency (~10 % of A + consumables) | 4,000 |
| **Stage 1 total (Combo + recommended options)** | **≈ 1,45,000–1,58,000** |
| **Robot-only cost (excluding printer, a multi-project capital asset)** | **≈ 45,000–53,000** |
| Budget levers | Standalone P2S instead of Combo: −₹28,000 · Print-service Phase-A parts + defer printer: −₹95,000 now |
| Stage 2 delta (deferred, indicative) | 30,000–45,000 |

## 9. Risks & Mitigations

| # | Risk | L / I | Mitigation |
|---|------|-------|------------|
| R1 | C018 servos sell out domestically (thin stock, 15 units seen) | H / H | Order day 1; backup sellers identified (Amazon.in Waveshare listing, DNA Tech bulk email, IndiaMART); import shortfall only |
| R2 | Servo DOA or stripped gear mid-project | M / M | 13th unit as spare; Feetech replacement gear sets are cheap and user-fittable |
| R3 | Print tolerance/quality issues on first prints | M / M | Calibrate printer first; use alignment jig; print service as fallback |
| R4 | Camera or lighting drift silently ruins datasets (commonly misread as a model bug) | H / H | Rigid clamps, taped positions, fixed lighting; never move camera after recording; re-record rather than debug the model first |
| R5 | WSL2 USB instability | M / M | Native Ubuntu dual-boot as primary environment |
| R6 | 10 GB VRAM ceiling blocks large fine-tunes | Certain / M | Planned cloud LoRA budget; quantized local inference; SmolVLA as local-first path |
| R7 | LeRobot API churn breaks tutorials mid-phase | M / M | Pin a release per phase; upgrade only at phase boundaries |
| R8 | Electrical fault (short, reversed polarity, hot-plugging bus) | L / H | Inline fuse on 12 V rail; barrel-jack disconnect as e-stop habit; never hot-plug servo chains; existing LiPo discipline applies |
| R9 | Pinch injury during autonomous runs | L / M | Clear workspace rule; 30 kg·cm is enough to hurt — treat autonomous runs like a spinning prop |
| R10 | Scope creep into Stage 2 before fundamentals land | M / M | Phase E decision gate; exit criteria enforced per phase |
| R11 | Momentum stall in weeks 5–8 | M / M | One shippable milestone per week; public writeups (G7) create accountability |
| R12 | Import fallback triggers duty surprises | M / L | Prefer domestic; if importing, small parcels only; accurate invoice descriptions ("educational robotic servo motors") |
| R13 | P2S backorder (several Indian resellers show 1–2 week lead) blocks Phase A printing | M / M | Order printer with the servos on day 1; if delayed, buy Phase-A parts from a print service (₹2,500–3,500) so assembly is never printer-blocked |

## 10. Open Decisions

**D1 — Leader-arm feel:** the official leader BOM uses lighter gear-ratio servo variants (import-only). Start with the C018-based leader; upgrade only if back-drive friction hurts demo quality. **D2 — Backup teleop device:** keyboard vs gamepad for interventions when the leader is impractical. **D3 — Dataset license** for Hub publication. **D4 — Stage 2 base:** dual-wheel (cheaper, stable) vs omni-wheel (holonomic). **D5 — Stage 2 power:** battery/power-station choice, leveraging existing LiPo experience.

## 11. References

LeRobot documentation, GitHub and LeLab web UI (Hugging Face) · SO-ARM100/101 repository (The Robot Studio) · XLeRobot docs and GitHub (Vector Wang) · Evelta product listings (STS3215-C001 / C018) · Bambu Lab P2S product page; Indian resellers: Robocraze, 3Ding, Ideal3D, Zee3D, 3D Protofarm · Courses: Hugging Face Robotics Course; HF Deep RL Course; MIT 6.4210 Robotic Manipulation (Tedrake); UC Berkeley CS285 (Levine); Stanford CS224R (Finn); NVIDIA DLI Isaac self-paced courses; OpenAI Spinning Up; Modern Robotics (Lynch, Coursera) · Papers: ALOHA/ACT; Diffusion Policy; TRI Large Behavior Models; SmolVLA; π0 / π0.5 (Physical Intelligence); NVIDIA Isaac GR00T N1.x; SERL and HIL-SERL.

## 12. Glossary

**BC** — behavior cloning; supervised learning on demonstrations. **ACT** — Action Chunking Transformer; predicts short action sequences instead of single steps. **Diffusion Policy** — policy that denoises action trajectories; core of LBM-style systems. **LBM** — Large Behavior Model; large multitask visuomotor policy (TRI terminology). **VLA** — Vision-Language-Action model; instruction-following policy built on a VLM backbone. **LoRA** — low-rank adaptation; parameter-efficient fine-tuning. **HIL-SERL** — human-in-the-loop sample-efficient RL; real-robot RL with operator interventions. **Sim2real** — transferring sim-trained policies to hardware. **Teleoperation** — human control of the follower via the leader arm. **DoF** — degrees of freedom (SO-101: 6).