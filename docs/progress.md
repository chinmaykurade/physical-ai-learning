# Progress Tracker

The status board for this project: every task across every phase, what state it is in, and
where I am right now. Derived from [so101-embodied-ai-project-plan.md](so101-embodied-ai-project-plan.md)
(build) and [physical-ai-learning-roadmap.md](physical-ai-learning-roadmap.md) (study).
Deferred items and gate history live in [backlog.md](backlog.md) — this file points at them,
it does not duplicate them.

---

## Where I am now

| | |
|---|---|
| **Current build phase** | **Phase 0 — Procurement & Preparation** (weeks 0–1) |
| **Current study phase** | **L0** (weeks 0–1) |
| **Current [Deep] in flight** | none — L0 has no [Deep] items. Deep-*course* underway: Karpathy #1 (micrograd) |
| **Next [Deep]** | ACT / ALOHA (2304.13705), L-A week 4 |
| **Pacing track** | Standard (5–6 h/wk build + 3–5 h/wk study) |
| **Next gate** | L0 exit — sim pipeline proven, tooling live |
| **Last updated** | 2026-07-26 (Notes columns trimmed to the one-line budget; detail moved to `notes/`) |

**Status legend:** ☐ not started · ◐ in progress · ☑ done · ⤴ moved to [backlog.md](backlog.md)
· ✂ cut (recorded, never silent)

**Week numbering:** build weeks follow plan §7, study weeks follow roadmap §4. They agree
everywhere except Phase D (plan: weeks 9–12; roadmap L-D: weeks 10–13) — both are shown below.

**Weekly rhythm (roadmap §4):** Sunday — pick the week's one [Deep] item and one shippable
output. Midweek — papers and lectures ride along with prints, shipping waits, and training
runs. Saturday — 30-minute log into `notes/`: what was learned, what moved to backlog.

---

## Goals (plan §2)

| Goal | Criterion | Phase | Status |
|---|---|---|---|
| G1 | Leader drives follower smoothly; calibration passes; 30-min teleop session without faults | A | ☐ |
| G2 | ACT ≥ 8/10 on pick-and-place from ~50 demos | A | ☐ |
| G3 | Scaling curve + camera ablation done; dataset published to HF Hub | B | ☐ |
| G4 | Fine-tuned SmolVLA executes 3+ tasks by language instruction | C | ☐ |
| G5 | GR00T N1.7 or π0 LoRA-fine-tuned in cloud, inference local on the 3080 | C | ☐ |
| G6 | One HIL-SERL task beats its BC baseline | D | ☐ |
| G7 | Written note/post per phase | all | ☐ 0 of 8 shipped |

## Open decisions (plan §10)

| # | Decision | Settle by | Status |
|---|---|---|---|
| D1 | Leader-arm feel — stay on C018 vs import lighter gear-ratio servos | A (after teleop practice) | ☐ open |
| D2 | Backup teleop / intervention device — keyboard vs gamepad | D (HIL-SERL setup) | ☐ open — PS5 controller already on hand, so the gamepad option costs nothing to try |
| D3 | Dataset license for Hub publication (CC-BY-4.0 vs Apache-2.0) | B | ☐ open |
| D4 | Stage-2 base — dual-wheel vs omni | E | ☐ open |
| D5 | Stage-2 power — battery / power-station choice | E | ☐ open |

---

## Phase 0 / L0 — Procurement & Preparation · weeks 0–1

**Build exit criteria:** all parts received and inspected; simulated teleop + training run completes.
**Study exit:** experiment tooling live; a MuJoCo model of the arm run before the real one exists.

### Build

| Task | Status | Notes |
|---|---|---|
| Order BOM-A: 13× STS3215-C018, 2× Waveshare adapter, 12 V 5 A PSU, workspace webcam, wrist cam, fasteners | ☑ | Ordered 2026-07-26. Verify C018 suffix on arrival (R1) |
| Order BOM-B: Bambu Lab P2S (Combo or standalone) + PLA ×3 kg, PETG 1 kg, TPU 0.5–1 kg, spare nozzle | ☑ | Ordered 2026-07-26 (R13 watch until it ships) |
| Order BOM-C recommended minimum: gamepad, inline fuse + kill-switch, spare gear sets ×2, calipers | ☑ | Ordered 2026-07-26; gamepad = existing PS5 controller. Spare gear sets **✂ cut 2026-07-26**, no SKU exists (see [backlog.md](backlog.md)). R8 part numbers in [notes](../notes/2026-07-26-week0-runpod-cloud-path.md) |
| Receive and inspect all parts | ☐ | Build exit criterion |
| Calibrate the printer | ☐ | Risk R3 |
| Print all follower parts | ☐ | Print-service fallback if printer slips (R13) |
| Print all leader parts | ☐ | |
| Print the assembly-alignment jig | ☐ | |
| Install Ubuntu native dual-boot | ☑ | Native Linux confirmed, kernel 7.0.0-28-generic. Never WSL2 (R5) |
| Create the Python environment | ☑ | uv venv at `/home/chinmay/lerobot-env`, Python 3.12.3 |
| Install LeRobot + Feetech extras, pinned | ☑ | `lerobot==0.6.0`; 18 `lerobot-*` CLI entry points present |
| Verify GPU path (torch/CUDA/bf16) | ☑ | torch 2.11.0+cu130, CUDA 13.0, sm_86, bf16 native |
| Capture the env lock file | ☑ | `env/lerobot-env.lock.txt`. Regenerated 2026-07-26: 116 → 154 pkgs, no version changed (not a rule-2 pin change) |
| Run simulated teleoperation | ☐ | Build exit criterion |
| Run a toy training job end to end | ☑ | **Exit criterion met 2026-07-26.** DP on `lerobot/pusht`, 5000 steps, ~18 min on the 3080 → `outputs/train/pusht_diffusion_toy/`. [notes](../notes/2026-07-26-week0-runpod-cloud-path.md) |
| Set up HF account (datasets + hub) | ☑ | 2026-07-26, account `chinmaykurade`. Model push verified local + pod → `chinmaykurade/pusht_diffusion_runpod_01`. Plan §5.2 |
| Set up RunPod (or equivalent) account, ₹2,000–3,000 budget | ☑ | Account 2026-07-26. **Cloud path proven end to end**; automation in `scripts/` + `docker/`, see `docker/RUNPOD_TEMPLATE.md` and [notes](../notes/2026-07-26-week0-runpod-cloud-path.md). Phase-C A100 spend still ahead |
| Set up the workspace: rigid desk, clamped camera, fixed lighting, taped positions | ☐ | Plan §5.4 — this is risk R4 prevention |

### Study — Core

| Task | Wk | Tag | Status | Notes |
|---|---|---|---|---|
| Docker getting-started | 0 | Hands-on | ☑ | 2026-07-26. D14 |
| Weights & Biases quickstart | 0 | Hands-on | ☑ | 2026-07-26 → `neural_networks/wandb_quickstart.py`. D14 |
| Zotero set up | 0 | Hands-on | ☑ | 2026-07-26. D14 |
| Keshav — *How to Read a Paper* | 0 | Read | ☑ | 2026-07-26. §5 #1; the protocol for everything after |
| HF Robotics Course Unit 0 | 0 | — | ☐ | Practice spine |
| 3Blue1Brown *Essence of Linear Algebra* (selected) | 1 | — | ☐ | D1; on-demand refresh only |
| Karpathy *Zero to Hero* #1 — micrograd | 1 | Deep-course | ◐ | Started 2026-07-26 → `neural_networks/micrograd_from_scratch.ipynb`. D4 spine |
| MuJoCo docs — Overview chapter | 1 | Read | ☐ | D11 |
| Load the Menagerie SO-ARM100 model and poke it | 1 | Hands-on | ☐ | Study exit criterion |

### Study — Stretch

| Task | Tag | Likely target | Status |
|---|---|---|---|
| MuJoCo docs — Modeling chapter | [Read] | F1 | ☐ |

### L0 gate

☐ Core done? ☐ Backlog groomed? ☐ Artifact — none due (G7 starts at L-A). Record in
[backlog.md § Gate review log](backlog.md#gate-review-log).

---

## Phase A / L-A — Build & First Autonomous Policy · weeks 1–4

**Exit criteria:** G1 and G2 met. **Study exit:** explain every block of ACT against your own training curves.

### Build

| Task | Status | Notes |
|---|---|---|
| Set every servo's bus ID **before** assembly | ☐ | 12 servos; do not skip the ordering |
| Label every cable | ☐ | Bus hygiene |
| Assemble the follower arm | ☐ | |
| Assemble the leader arm | ☐ | |
| Wire each arm to its adapter; fused 12 V rail + kill switch | ☐ | Risk R8 — never hot-plug the servo chain |
| Run joint calibration on both arms | ☐ | Deliverable: calibration record |
| Practice teleoperation to fluency; 30-min fault-free session | ☐ | **G1** |
| Define the canonical task (cube → bowl) | ☐ | |
| Record ~50 episodes, 10–15 s each | ☐ | Deliverable: 50-episode dataset |
| Train ACT overnight on the 3080 | ☐ | Deliverable: trained checkpoint |
| Evaluate over 10 scripted trials | ☐ | **G2** ≥ 8/10. Deliverable: evaluation log |
| Settle decision D1 (leader-arm feel) | ☐ | After teleop practice |
| Ship G7 #1 — *"From kit to policy: 50 demos to 80% autonomous"* | ☐ | → `notes/` |

### Study — Core

| Task | Wk | Tag | Status |
|---|---|---|---|
| HF Robotics Course — classical-foundations units | 1–2 | — | ☐ |
| Modern Robotics Ch. 2–3 — config space, rotations, SE(3) | 1–2 | Working | ☐ |
| HF Robotics Course — imitation-learning unit | 3 | — | ☐ |
| Karpathy #2–3 — makemore / backprop fluency | 3 | Deep-course | ☐ |
| Weng VAE blog (pre-read) | 4 | — | ☐ |
| LeRobot code-read 1 — `LeRobotDataset` (indexing, video decode, delta-timestamps, norm stats) | 1–4 | Hands-on | ☐ |
| LeRobot code-read 2 — Feetech bus driver + SO-101 follower/leader classes + calibration | 1–4 | Hands-on | ☐ |
| LeRobot code-read 3 — `lerobot-teleoperate` / `lerobot-record` control loop | 1–4 | Hands-on | ☐ |
| LeRobot code-read 4 — `modeling_act`; diagram it (tensor shapes on every arrow) | 4 | Hands-on | ☐ |

### Study — Reading queue (roadmap §5)

| # | Paper | ID | Tag | Status |
|---|---|---|---|---|
| 2 | Ross et al. — DAgger | 1011.0686 | Read | ☐ |
| 3 | Kingma & Welling — VAE | 1312.6114 | Skim | ☐ |
| 4 | Sohn et al. — CVAE | NeurIPS 2015 | Skim | ☐ |
| 5 | Zhao et al. — **ACT / ALOHA** | 2304.13705 | **Deep** | ☐ *after the policy runs* |

### Study — Stretch

| Task | Tag | Likely target | Status |
|---|---|---|---|
| Modern Robotics Ch. 4 (FK) + NumPy FK for the SO-101 | [Deep] | F2 | ☐ |

### L-A gate
☐ Core done? ☐ Backlog groomed? ☐ G7 #1 shipped?

---

## Phase B / L-B — Data-Centric Experiments · weeks 4–6

**Deliverables:** scaling curve, ablation table, method comparison, public dataset, written note (G3).
**Study exit:** the curve and ablation exist *and* you can say why DP handles multimodal actions where naive BC can't.

### Build

| Task | Status | Notes |
|---|---|---|
| Re-record the canonical task at 10 / 25 / 50 / 100 episodes | ☐ | Camera must not move between runs (R4) |
| Plot the success-rate scaling curve | ☐ | Deliverable |
| Mount and calibrate the wrist camera | ☐ | |
| Run the wrist-camera ablation | ☐ | Deliverable: ablation table |
| Train Diffusion Policy on identical data | ☐ | |
| Compare DP vs ACT (success + sampling cost) | ☐ | Deliverable: method comparison |
| Write the dataset card; settle decision D3 (license) | ☐ | CC-BY-4.0 vs Apache-2.0 |
| Publish the best dataset to the HF Hub | ☐ | **G3** |
| Ship G7 #2 — *"How many demos is enough?"* | ☐ | → `notes/` |

### Study — Core

| Task | Wk | Tag | Status |
|---|---|---|---|
| MIT 6.S184 Lectures 1–2 + Weng diffusion blog | 5 | Deep-course | ☐ |
| Camera intrinsics calibration with a printed checkerboard (OpenCV) | 5 | Hands-on | ☐ |
| **Hand-eye calibration** of the wrist camera | 5 | Hands-on | ☐ |
| Nayar calibration videos (as needed) | 5 | Deep | ☐ |
| 6.S184 Lectures 3–4 + Lab 1 | 6 | Deep-course | ☐ |
| LeRobot code-read 5 — `modeling_diffusion`; compare sampling cost vs ACT | 6 | Hands-on | ☐ |
| LeRobot code-read 6 — train script + config system; wire in W&B | 6 | Hands-on | ☐ |
| LeRobot dataset tools — split / merge / filter | 5–6 | Hands-on | ☐ |

### Study — Reading queue

| # | Paper | ID | Tag | Status |
|---|---|---|---|---|
| 6 | Ho et al. — DDPM | 2006.11239 | Read | ☐ |
| 7 | Song et al. — DDIM | 2010.02502 | Skim | ☐ |
| 8 | Ho & Salimans — Classifier-free guidance | 2207.12598 | Skim | ☐ |
| 9 | Chi et al. — **Diffusion Policy** | 2303.04137 | **Deep** | ☐ |
| 10 | Florence et al. — Implicit BC | 2109.00137 | Read | ☐ |
| 11 | Mandlekar et al. — *What Matters in Learning from Offline Human Demos* | 2108.03298 | Read | ☐ |
| 12 | Lin et al. — *Data Scaling Laws in IL* | 2410.18647 | Read | ☐ *before the scaling study* |
| 13 | Mandlekar et al. — MimicGen | 2310.17596 | Skim | ☐ |

### Study — Stretch

| Task | Tag | Likely target | Status |
|---|---|---|---|
| Nayar — full image-formation playlist | [Deep] | F2 | ☐ |

### L-B gate
☐ Core done? ☐ Backlog groomed? ☐ G7 #2 shipped?

---

## Phase C / L-C — Vision-Language-Action Models · weeks 6–9 (spill to 10)

The heaviest study block. Training runs are passive time — read while GPUs burn.
**Study exit:** whiteboard the design axes (tokenization vs flow expert, single vs dual system) and place all three fine-tuned models on them.

### Build

| Task | Status | Notes |
|---|---|---|
| Record a 3–4 task dataset with language annotations | ☐ | |
| Fine-tune SmolVLA locally on the 3080 | ☐ | |
| Verify instruction-following across the tasks | ☐ | **G4** |
| Read the SO-101 configs in openpi and Isaac-GR00T **before** renting | ☐ | Know every hyperparameter you pay for |
| Rent an A100 (RunPod); LoRA fine-tune GR00T N1.7 or π0 | ☐ | ₹2,000–3,000 budget |
| Export and run inference locally, bf16/quantized | ☐ | **G5** — R6 binds here |
| Build a per-instruction evaluation harness | ☐ | Scores each instruction separately |
| Ship G7 #3 — *"ACT vs SmolVLA vs a 3B VLA on the same desk"* | ☐ | Data efficiency + failure modes |

### Study — Core

| Task | Wk | Tag | Status |
|---|---|---|---|
| 6.S184 flow-matching lectures + Lab 3 — **finish the course** | 6–7 | Deep-course | ☐ |
| Karpathy — *build GPT from scratch* | 6–7 | Deep-course | ☐ |
| Toy VLM LoRA on the 3080 (non-robot warm-up) | 7–8 | Hands-on | ☐ |
| LeRobot code-read 7 — SmolVLA: backbone integration, action expert, language path | 7–8 | Hands-on | ☐ |
| ETH Robot Learning — VLA lecture 1 | 7–8 | — | ☐ |
| ETH Robot Learning — VLA lecture 2 | 8–9 | — | ☐ |
| NVIDIA DLI Isaac Lab course (plan §5.3) before the GR00T fine-tune | 8–9 | — | ☐ |
| Code-read 10 — openpi + Isaac-GR00T SO-101 fine-tuning configs | 8–9 | Hands-on | ☐ |

### Study — Reading queue

| # | Paper | ID | Tag | Status |
|---|---|---|---|---|
| 14 | Vaswani et al. — *Attention Is All You Need* | 1706.03762 | **Deep** | ☐ |
| 15 | Su et al. — RoPE | 2104.09864 | Skim | ☐ |
| 16 | Dosovitskiy et al. — ViT | 2010.11929 | Read | ☐ |
| 17 | Radford et al. — CLIP | 2103.00020 | Read | ☐ |
| 18 | Kaplan et al. — Scaling laws | 2001.08361 | Skim | ☐ |
| 19 | Hoffmann et al. — Chinchilla | 2203.15556 | Skim | ☐ |
| 20 | Hu et al. — **LoRA** | 2106.09685 | **Deep** | ☐ |
| 21 | Dettmers et al. — QLoRA | 2305.14314 | Skim | ☐ |
| 22 | Liu et al. — LLaVA | 2304.08485 | Read | ☐ |
| 23 | Beyer et al. — PaliGemma | 2407.07726 | Read | ☐ |
| 24 | SmolVLM report | — | Skim | ☐ |
| 25 | Lipman et al. — Flow Matching | 2210.02747 | Read | ☐ |
| 26 | Peebles & Xie — DiT | 2212.09748 | Skim | ☐ |
| 27 | Brohan et al. — RT-1 | 2212.06817 | Skim | ☐ |
| 28 | Brohan et al. — RT-2 | 2307.15818 | Read | ☐ |
| 29 | Open X-Embodiment | 2310.08864 | Skim | ☐ |
| 30 | Octo | 2405.12213 | Skim | ☐ |
| 31 | Kim et al. — OpenVLA | 2406.09246 | Read | ☐ |
| 33 | Black et al. — **π0** | 2410.24164 | **Deep** | ☐ |
| 34 | Pertsch et al. — FAST tokenizer | — | Read | ☐ |
| 35 | π0.5 | 2504.16054 | Read | ☐ |
| 36 | NVIDIA — **GR00T N1** | 2503.14734 | **Deep** | ☐ |
| 37 | GR00T N1.6 technical blog | — | Read | ☐ |
| 38 | Shukor et al. — **SmolVLA** | 2506.01844 | **Deep** | ☐ |
| 39 | Driess et al. — Knowledge Insulation | — | Read | ☐ |
| 40 | PI — Real-Time Chunking | — | Read | ☐ |
| 41 | Gemini Robotics report | 2503.20020 | Skim | ☐ |
| 42 | Liu et al. — LIBERO | 2306.03310 | Skim | ☐ |

Strict order matters here — the VLA lineage *is* the lesson (roadmap §3, D8).

### Study — Stretch

| Task | ID | Tag | Likely target | Status |
|---|---|---|---|---|
| OpenVLA-OFT | 2502.19645 | [Skim] | F1 | ☐ |
| ECoT | 2407.08693 | [Aware] | F1 | ☐ |
| RDT-1B | — | [Aware] | F1 | ☐ |

### L-C gate
☐ Core done? ☐ Backlog groomed? ☐ G7 #3 shipped?

---

## Phase D / L-D — Reinforcement Learning · build weeks 9–12 · study weeks 10–13

**Exit:** G6 met, and you can explain *why* HIL-SERL works where naive real-world RL fails.

### Build

| Task | Status | Notes |
|---|---|---|
| Stand up the SO-101 MuJoCo / ManiSkill environments | ☐ | |
| Train PPO/SAC on a sim task | ☐ | |
| Experiment with reward shaping | ☐ | |
| Apply domain randomization | ☐ | |
| Attempt sim-to-real transfer; document the gap honestly | ☐ | Four gap sources: dynamics, visuals, latency, contact |
| Set up LeRobot HIL-SERL with the leader arm as intervention device | ☐ | Settle D2 if the leader is impractical |
| Train one contact-rich task (e.g. precise insertion) | ☐ | |
| Beat the BC baseline on that task | ☐ | **G6** |
| Ship G7 #4 — *"RL that actually worked: HIL-SERL vs my BC baseline"* + sim2real note | ☐ | |

### Study — Core

| Task | Wk | Tag | Status |
|---|---|---|---|
| CS285 — policy-gradient + actor-critic blocks (1.5×) | 10 | — | ☐ |
| MuJoCo docs — **Computation** chapter (physics-engine fundamentals) | 10 | Read | ☐ |
| A MuJoCo Playground colab | 10 | Hands-on | ☐ |
| CS285 — Q-learning + advanced policy-gradient blocks | 11 | — | ☐ |
| CS285 — **both offline-RL lectures** | 12 | — | ☐ |
| Levine et al. offline-RL tutorial §§1–4 | 12 | Read | ☐ |
| LeRobot code-read 9 — HIL-SERL stack: actor/learner, reward classifier, intervention plumbing | 13 | Hands-on | ☐ |
| ManiSkill **lerobot-sim2real** workflow | 12 | Hands-on | ☐ |

### Study — Reading queue

| # | Paper | ID | Tag | Status |
|---|---|---|---|---|
| 43 | Schulman et al. — PPO | 1707.06347 | Read | ☐ |
| 44 | Haarnoja et al. — SAC | 1801.01290 | Read | ☐ |
| 45 | Schulman et al. — GAE | 1506.02438 | Skim | ☐ |
| 46 | Levine et al. — Offline RL tutorial | 2005.01643 | Read | ☐ |
| 47 | Kumar et al. — CQL | 2006.04779 | Skim | ☐ |
| 48 | Kostrikov et al. — IQL | 2110.06169 | Skim | ☐ |
| 49 | Ball et al. — RLPD | 2302.02948 | Read | ☐ |
| 50 | Luo et al. — SERL | 2401.16013 | Read | ☐ |
| 51 | Luo et al. — **HIL-SERL** | 2410.21845 | **Deep** | ☐ *before the run* |
| 52 | Tobin et al. — Domain randomization | 1703.06907 | Skim | ☐ |

### Study — Stretch

| Task | Tag | Likely target | Status |
|---|---|---|---|
| Modern Robotics Ch. 8 & 11 (dynamics / control) | [Deep] | F2 | ☐ |

### L-D gate
☐ Core done? ☐ Backlog groomed? ☐ G7 #4 shipped?

---

## Phase E / L-E — Consolidation & Stage-2 Gate · study weeks 14–16 · build gate month 4+

**Exit:** one policy running through an optimized inference path with honest confidence intervals; the Phase-E go/no-go memo written with real evidence.

### Build / engineering

| Task | Status | Notes |
|---|---|---|
| Export the best policy ONNX → TensorRT | ☐ | |
| Benchmark latency vs PyTorch | ☐ | |
| Enable LeRobot async inference | ☐ | |
| Re-report every success rate with Wilson confidence intervals | ☐ | From here on, always |
| Write the one-page safety case | ☐ | Risks R8 / R9 written up |
| Review outcomes against G1–G7 | ☐ | |
| Stage-2 go/no-go memo: 2nd arm, base (D4), Pi 5, battery (D5), cart — ₹30,000–45,000 | ☐ | |
| Revise the project plan to v2.0 and the roadmap to v2.0 | ☐ | Both docs rev together |
| Ship G7 #5 — *"Making it fast: quantization, TensorRT, async inference"* | ☐ | Or hold for F3's fuller version |

### Study — Core

| Task | Wk | Tag | Status |
|---|---|---|---|
| NVIDIA SO-101 sim-to-real course part 1 (Isaac Lab + GR00T post-training) | 14 | **Deep** | ☐ |
| NVIDIA course part 2 (Isaac Lab eval → real deploy, four gap strategies) | 15 | **Deep** | ☐ |
| Isaac Lab introduction course | 15 | — | ☐ |
| LeRobot async-inference docs | 16 | Read | ☐ |
| LeRobot code-read 8 — async inference / policy server, chunk buffering | 16 | Hands-on | ☐ |

### Study — Reading queue

| # | Paper | ID | Tag | Status |
|---|---|---|---|---|
| 53 | NVIDIA — *Pretrained to Imagine, Fine-Tuned to Act* | — | Read | ☐ |
| 54 | Assran et al. — V-JEPA 2 | — | Read | ☐ |
| 55 | Jang et al. — DreamGen | 2505.12705 | Read | ☐ |
| 56 | Ha & Schmidhuber — World Models | 1803.10122 | Skim | ☐ |
| 57 | Hafner et al. — DreamerV3 | 2301.04104 | Skim | ☐ |
| 58 | Bruce et al. — Genie (+ Genie 3 blog) | 2402.15391 | Skim | ☐ |
| 59 | NVIDIA — Cosmos platform report (+ Cosmos Policy) | — | Skim | ☐ |
| 60 | TRI — **Large Behavior Models report** | lbm.tri.global | **Deep** | ☐ |

No Stretch items — L-E is all Core.

### L-E gate
☐ Core done? ☐ Backlog groomed? ☐ G7 #5 shipped?

---

## Phase F — Depth & Role-Readiness · months 5–9 (study becomes primary, 8–10 h/wk)

### F1 · Theory consolidation — weeks 17–24

| Task | Status |
|---|---|
| ETH *Robot Learning* full pass — lectures end to end | ☐ |
| ETH homeworks, selectively (graded exercises in its repo) | ☐ |
| Clear the paper backlog accumulated in the L-phases | ☐ → see [backlog.md](backlog.md) |
| CS285 leftovers, if any | ☐ |
| §5 #65 field-literacy batch: ECoT · RDT-1B · Helix blog · GR-3 · VQ-BeT · UMI · GELLO · AgiBot World [Aware] | ☐ |
| *Optional* DreamGen-style synthetic-data cloud experiment (~₹1,500–2,500) | ☐ |
| Output: one *"what I misunderstood the first time"* post | ☐ |

### F2 · Classical + perception depth — weeks 25–29

| Task | Status |
|---|---|
| Modern Robotics Ch. 4–6 deep (if deferred from L-A) | ☐ |
| Modern Robotics Ch. 8, 9, 11 [Deep] | ☐ |
| Modern Robotics Ch. 10, 12 [Read] | ☐ |
| **Kinematics capstone:** NumPy FK + Jacobian-IK + gravity compensation, verified in MuJoCo | ☐ |
| MIT 6.4210 selected chapters — geometric perception, grasping, learning-based manipulation | ☐ |
| Nayar playlists completed | ☐ |
| SigLIP (2303.15343) [Skim] · DINOv2 (2304.07193) [Skim] · SAM/SAM-2 (2304.02643) [Skim] · FoundationPose [Aware] | ☐ |
| Output: the kinematics capstone repo (G7 #6) | ☐ |

### F3 · Deployment & efficiency — weeks 30–32

| Task | Status |
|---|---|
| CS336 Lectures 1–3, 9, 10 | ☐ |
| Quantization mini-project: int8 / 4-bit SmolVLA on the rig | ☐ |
| **Success-rate-vs-latency curve** | ☐ |
| TensorRT pass on a second policy | ☐ |
| Output: quantization study post (G7 #7) | ☐ |

### F4 · The three modules — weeks 33–34

| Task | Budget | Status |
|---|---|---|
| M1 — ROS 2 awareness (CLI + first node; Articulated Robotics series at 1.5×) | ~8 h timeboxed | ☐ |
| M2 — C++ reading level (learncpp fundamentals; read the Feetech SDK + one MuJoCo source file) | ~12 h timeboxed | ☐ |
| M3 — Humanoid/whole-body awareness (GR00T N1.6 blog, Helix, one sim2real overview) | ~4 h timeboxed | ☐ |
| Output: one-page cheat sheet per module | | ☐ |

### F5 · Portfolio & interview — weeks 35–38

| Task | Status |
|---|---|
| Capstone writeup — *"a year of embodied AI on a desktop arm"* | ☐ |
| Consolidate all G7 posts | ☐ |
| OSS ladder: LeRobot docs fix → reproduce-and-triage a bug → small feature / new-robot config PR | ☐ |
| Drill the interview-prep checklist (roadmap §7, 11 areas) | ☐ |
| Demo reel + résumé | ☐ |
| Output: public portfolio; first applications out (G7 #8) | ☐ |

**Months 10–12 — buffer:** spillover · Stage-2 XLeRobot build if the Phase-E gate said go · interview cycles.

---

## How to update this file

- Flip a status the day it changes; don't batch it to gate day.
- When an item slips past its phase exit, set it to ⤴ **and** write the row into
  [backlog.md](backlog.md) with its tag, target and date. The ⤴ here is a pointer, not the record.
- ✂ (cut) requires a dated reason in the Notes column. Nothing disappears silently.
- Update **Where I am now** at every phase gate — current phase, [Deep] in flight, next gate.
- Weekly log prose goes in `notes/`, not here. This file holds status only.
- **Notes cells are one line — ~15 words, two clauses at most.** They carry only what cannot be
  recomputed: a date, a version, a measurement, an identifier, a path, a risk ID, an
  exit-criterion marker. Reasons, error text, diagnoses and narrative go to `notes/`; the cell
  gets a pointer to the file. A cell that restates a notes file is duplication that will drift.
