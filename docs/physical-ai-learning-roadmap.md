# Physical AI Engineer — Learning Roadmap

**Owner:** Chinmay · **Location:** Kerala, India · **Date:** 25 July 2026 · **Version:** 1.0
**Companion to:** *SO-101 Robot Arm & Embodied AI Learning Rig — Project Plan v1.1*
**Status:** Approved through Stage 3 (concepts → sources → plan)
**Goal:** demonstrable, career-relevant Physical AI / robot-learning engineering skill, built on top of the SO-101 rig.

---

## 0. How to Use This Document

This roadmap overlays a **study track** onto the build phases of the project plan (Phases 0–E), then continues past the build with a depth-and-role-readiness phase (Phase F). The build plan answers *"what do I do with the hardware this week"*; this document answers *"what do I learn, read, and practice this week, and why."*

Three structural ideas run through everything:

1. **Two spines, many bolt-ons.** The *practice spine* is the Hugging Face Robotics Course plus the LeRobot library itself. The *theory spine* is ETH Zürich's **Robot Learning: From Fundamentals to Foundation Models** (Spring 2026, Oier Mees — public lectures and homework). Every other course is a specialist bolt-on scheduled at the moment it pays off.
2. **Hardware first, theory second.** Papers are read *after* debugging your own version of their problem wherever possible (the pattern already in the project plan). The schedule enforces this ordering.
3. **Depth tags are contracts.** Every resource carries one of four tags, and the tag is a commitment about time:
   - **[Deep]** — work through fully; implement or annotate; you should be able to whiteboard it.
   - **[Read]** — one careful pass with notes; you can summarize the method and its claim.
   - **[Skim]** — extract the core idea and one figure in ≤ 45 minutes.
   - **[Aware]** — know it exists, what it claims, and when you'd reach for it. Minutes, not hours.

Rules of engagement: refresh math **on demand only** (no standalone math phase); only **one [Deep] item in flight** at a time; anything that misses its phase window moves to the Phase-F backlog rather than blocking the build; pin LeRobot and course-code versions per phase (project-plan risk R7 applies to study code too).

---

## 1. Time Budget & Shape of the Year

Honest accounting first. The full inventory below is roughly **330–370 hours of study**. The project plan budgets 8–10 h/week total with ~3–4 h/week of that as study during the build. That is enough to cover the *core* study items during Phases 0–E, but not the whole inventory — which is why Phase F exists.

| Period | Calendar | Build load | Study load | Study focus |
|---|---|---|---|---|
| Phases L0–L-E | Weeks 0–16 | 5–6 h/wk | 3–5 h/wk (~60–80 h total) | Core items only — everything needed to *understand what you are building as you build it* |
| Phase F | Months 5–9 (~20 weeks) | none (Stage-2 gate deferred or parallel) | 8–10 h/wk (~160–200 h) | Depth passes, full courses, perception, deployment, the three modules, portfolio, interview prep |
| Buffer | Months 10–12 | — | as needed | Spillover, Stage-2 XLeRobot build if go, job search |

**Two pacing tracks.** *Standard*: as tabled above — role-ready in ~9–10 months, 12 with buffer. *Intensive*: 12–14 h/week combined from the start compresses Phase F into months 4–7 — role-ready in ~7–8 months. The schedule in §4 is written for Standard; Intensive simply pulls Phase-F blocks forward.

Every phase in §4 lists **Core** (fits the budget, do not skip) and **Stretch** (do if time allows, else auto-moves to the Phase-F backlog). This keeps the build unblocked — the same principle as project-plan risk R10.

---

## 2. Concept Map — 14 Domains

The approved inventory, condensed. Full sources per domain are in §3; scheduling is in §4.

| # | Domain | Core concepts (abridged) | Target depth | Main phase(s) |
|---|---|---|---|---|
| D1 | Math foundations | Linear algebra for robotics, rotations/SE(3), probability (Bayes, Gaussians, KL, ELBO), optimization, numerical integration | Refresh on demand | throughout |
| D2 | Classical robotics | FK/IK, Jacobians & singularities, rigid-body dynamics, actuator models, PID → impedance → MPC, trajectory generation, planning (RRT/PRM), grasping theory, Kalman basics | Working | L-A, L-D, F2 |
| D3 | Perception & 3D vision | Camera models, calibration + hand-eye calibration, depth/point clouds, 6-DoF pose, ViT/CLIP/SigLIP/DINOv2, SAM, exposure & rolling-shutter discipline | Working (calibration), literate (rest) | L-B, F2 |
| D4 | Deep learning core | Backprop, optimizers, transformer internals (attention, RoPE, KV cache), tokenization, CNNs, bf16, DDP, training diagnostics, experiment discipline | Deep | L0–L-B |
| D5 | Generative modeling | VAE/CVAE, DDPM, score matching, DDIM, CFG, **flow matching**, DiT, energy-based models (Implicit BC) | Deep | L-B, L-C |
| D6 | LLMs & VLMs | Pretraining, scaling laws, SFT, RLHF/DPO, **LoRA/QLoRA**, quantization, VLM recipe (LLaVA), PaliGemma/SmolVLM/Eagle backbones | Deep on PEFT, literate elsewhere | L-C |
| D7 | Imitation learning & LBMs | BC failure modes, DAgger, **ACT** internals, **Diffusion Policy** internals, action multimodality, LBM methodology & evaluation statistics, data scaling, MimicGen | Deep | L-A, L-B, L-E |
| D8 | VLA models | RT-1→RT-2→OXE→Octo→OpenVLA lineage; action representations (bins / FAST tokens / flow experts); dual-system (S1/S2) designs; π0/π0.5, GR00T N1.x, SmolVLA, Gemini Robotics; knowledge insulation; real-time chunking; LIBERO/eval | Deep | L-C, L-E |
| D9 | Reinforcement learning | MDPs → PPO → SAC, GAE, reward design, **offline RL**, RLPD, SERL/**HIL-SERL**, parallel sim RL, domain randomization, sim2real analysis, RL-post-training of VLAs | Deep on HIL-SERL path | L-D, F1 |
| D10 | World models & WAMs | Dreamer line, JEPA (V-JEPA 2), Genie, Cosmos platform, DreamGen synthetic data, World-Action Models, world-model-based evaluation | Conceptual (+1 optional experiment) | L-E, F1 |
| D11 | Simulation & synthetic data | Physics-engine fundamentals (contact, integrators), MuJoCo/MJX/Playground, Isaac Sim vs Isaac Lab, OpenUSD, Newton, Genesis/ManiSkill3, LIBERO/robosuite, URDF/MJCF/USD, domain randomization | Working (MuJoCo, Isaac Lab basics), aware (rest) | L0, L-D, L-E |
| D12 | Data engineering | Teleop system families, LeRobotDataset internals, curation & filtering, normalization stats, language annotation, dataset cards/licensing, OXE/DROID/Bridge literacy | Working | L-A, L-B |
| D13 | Systems & deployment | Control-loop hierarchy (500–1000 Hz low-level vs 30–60 Hz policy), latency budgets, async inference & chunk execution, quantization, ONNX/TensorRT, profiling, safety engineering, eval statistics | Working | L-E, F3 |
| D14 | SWE & ecosystem | Docker, W&B, Git hygiene, LeRobot codebase internals, paper-reading workflow, OSS contribution, community & conference literacy | Working | throughout, F5 |
| M1 | ROS 2 module | Nodes/topics/services/actions, `ros2_control` concept | Awareness (~8 h, timeboxed) | F4 |
| M2 | C++ module | Read robotics C++ (servo SDKs, sim internals) without fear | Reading level (~12 h, timeboxed) | F4 |
| M3 | Humanoid module | Whole-body control stack, VLA-over-controller architecture, Helix/GR00T workflows | Awareness (~4 h, timeboxed) | F4 |

**Explicit exclusions** (from Stage 1 approval): humanoid whole-body *implementation*, SLAM/navigation (Stage 2 of the build), CUDA kernel writing, multi-GPU pretraining, formal control theory (Lyapunov et al.), tactile hardware, PCB/mechanical design.

**One correction to the project plan carried forward:** plan §1 states world-foundation models are purely industrial data-generation tools and "not needed here." As of mid-2026 that is only half true — the World-Action Model wave (video/world-model backbones fine-tuned *into* policies, e.g. Cosmos Policy, DreamZero) and world-model-based policy *evaluation* make D10 a required conceptual unit, and DreamGen-style synthetic data is a feasible optional cloud experiment. The plan's practical conclusion (don't run Cosmos locally; policy models are what you train) still stands.

---

## 3. Source Library

Per domain: **Spine** (primary), **Support**, **Papers** in reading order with depth tags, **Hands-on**. All primary picks are free. arXiv IDs are given where verified; if an ID ever 404s, search by title — titles and first authors are the durable identifiers.

### D1 · Math foundations
- **Spine:** 3Blue1Brown *Essence of Linear Algebra* (YouTube, ~3 h refresh).
- **Support:** *Mathematics for Machine Learning* (Deisenroth, Faisal, Ong — free PDF), probability chapter as reference; ODE/SDE background arrives packaged inside the 6.S184 lecture notes; rotations/SE(3) are learned inside Modern Robotics Ch. 3.
- **Rule:** no standalone math block. Refresh the moment a course assumes something you've lost.

### D2 · Classical robotics
- **Spine:** **Modern Robotics** (Lynch & Park) — free book PDF + full YouTube lecture series + Coursera specialization (audit free). Required: Ch. 2–6 (config space, rigid-body motions, FK, velocity kinematics/Jacobians, IK), Ch. 8 (dynamics), Ch. 9 (trajectory generation), Ch. 11 (robot control). [Read]-level: Ch. 10 (motion planning), Ch. 12 (grasping & manipulation).
- **Support:** MIT 6.4210 *Robotic Manipulation* (Tedrake, manipulation.csail.mit.edu) — already in the project plan; scope to the geometric perception, grasping, and learning-based manipulation chapters. Brian Douglas control-systems videos (YouTube) for PID/feedback intuition. *Kalman and Bayesian Filters in Python* (Labbe, free Jupyter book, github.com/rlabbe) — Kalman chapters only. LaValle *Planning Algorithms* (free online) as shelf reference.
- **Hands-on:** implement FK + a Jacobian-based IK solver for the SO-101's 6 DoF in NumPy against the MJCF model; verify against MuJoCo. Compute the gravity-compensation torques for the leader arm and connect the result to decision D1 (leader-arm feel).

### D3 · Perception & 3D vision
- **Spine:** **First Principles of Computer Vision** (Shree Nayar, Columbia — YouTube): image formation, camera calibration, and binocular stereo playlists [Deep].
- **Support:** OpenCV camera-calibration tutorial + `calibrateHandEye` documentation; Open3D tutorials (when point clouds appear).
- **Papers:** ViT (2010.11929) [Read] → CLIP (2103.00020) [Read] → SigLIP (2303.15343) [Skim] → DINOv2 (2304.07193) [Skim] → SAM (2304.02643) / SAM-2 [Skim] → FoundationPose [Aware].
- **Hands-on:** calibrate your actual workspace webcam (intrinsics) with a printed checkerboard; then perform hand-eye calibration for the wrist camera in Phase B. Lock exposure/white balance and document the procedure (converts risk R4 from rule into understanding).

### D4 · Deep learning core
- **Spine:** **Karpathy, *Neural Networks: Zero to Hero*** (karpathy.ai/zero-to-hero.html) — micrograd → makemore → *build GPT from scratch* [Deep].
- **Support:** CS231n notes (cs231n.github.io) for CNNs and training practicalities [Read]; 3Blue1Brown attention/transformer videos as visual pre-pass; Stanford **CS336 *Language Modeling from Scratch*** (public lectures, 2025 + 2026 editions) — Lectures 1–3 (tokenization; PyTorch & resource accounting; architectures & hyperparameters), 9 (scaling laws), 10 (inference) only [Read].
- **Papers:** *Attention Is All You Need* (1706.03762) [Deep, alongside the Karpathy GPT video]; RoPE (2104.09864) [Skim].
- **Hands-on:** train Karpathy's nanoGPT-scale model on the 3080; instrument it with W&B; deliberately break it (bad LR, no normalization) and diagnose from curves.

### D5 · Generative modeling
- **Spine:** **MIT 6.S184 *Flow Matching and Diffusion Models*** (diffusion.csail.mit.edu — 2026 edition: lectures, self-contained notes, labs building a toy diffusion/flow model from scratch) [Deep]. This is the single most load-bearing theory course in the roadmap: it is literally the mathematics inside Diffusion Policy and π0's action expert.
- **Support:** Lilian Weng's *What are Diffusion Models?* and VAE blog posts (pre-reading); Yang Song's score-based generative modeling blog [Read]; *Flow Matching Guide and Code* (Lipman et al., 2412.06264) as the standing reference.
- **Papers:** VAE (1312.6114) [Skim] → CVAE (Sohn et al., NeurIPS 2015) [Skim — this is ACT's z-variable] → DDPM (2006.11239) [Read] → DDIM (2010.02502) [Skim] → classifier-free guidance (2207.12598) [Skim] → Flow Matching (2210.02747) [Read] → DiT (2212.09748) [Skim — GR00T's action head and video models] → Implicit BC (2109.00137) [Read — bridges into D7].
- **Hands-on:** the 6.S184 labs; then, as a capstone bridge, swap the diffusion objective in your lab code for flow matching and compare sample quality/steps.

### D6 · LLMs & VLMs
- **Spine:** carried by D4 (Karpathy + CS336 selections); add the Hugging Face LLM course fine-tuning chapters for practical PEFT.
- **Papers:** scaling laws — Kaplan (2001.08361) → Chinchilla (2203.15556) [Skim] → **LoRA (2106.09685) [Deep]** → QLoRA (2305.14314) [Skim] → InstructGPT (2203.02155) [Skim] → DPO (2305.18290) [Skim] → LLaVA (2304.08485) [Read — *the* VLM recipe] → PaliGemma (2407.07726) [Read — π0's backbone] → SmolVLM report [Skim — SmolVLA's backbone] → AWQ/GPTQ [Aware].
- **Hands-on:** LoRA-fine-tune a small VLM (e.g., SmolVLM) on the 3080 on a toy captioning set *before* Phase C touches robots — so the first robot VLA fine-tune is your second LoRA run, not your first.

### D7 · Imitation learning & LBMs
- **Spine:** HF Robotics Course IL unit + ETH Robot Learning lectures (IL and generative-policy blocks).
- **Papers:** DAgger (1011.0686) [Read] → **ACT (2304.13705) [Deep — after your first policy runs]** → **Diffusion Policy (2303.04137) [Deep]** → Implicit BC (2109.00137) [Read — why multimodality breaks naive BC] → *What Matters in Learning from Offline Human Demonstrations* (RoboMimic study, 2108.03298) [Read — directly informs Phase B design] → *Data Scaling Laws in Imitation Learning for Robotic Manipulation* (2410.18647) [Read — before the scaling study] → MimicGen (2310.17596) [Skim] → **TRI *Large Behavior Models* report (lbm.tri.global) [Deep — the evaluation-methodology bible]** → VQ-BeT [Aware — it ships in LeRobot].
- **Hands-on:** line-by-line read of LeRobot's ACT and Diffusion Policy implementations against the papers (file list in §6); reproduce the temporal-ensembling ablation on your own Phase-A checkpoint.

### D8 · VLA models
- **Spine:** ETH course VLA block + HF Robotics Course foundation-model units. Use *A Survey on VLA Models: An Action Tokenization Perspective* and its companion repo (github.com/Psi-Robot/Awesome-VLA-Papers) as the territory map, not cover-to-cover reading.
- **Papers (strict order — the lineage is the lesson):** RT-1 (2212.06817) [Skim] → RT-2 (2307.15818) [Read] → Open X-Embodiment (2310.08864) [Skim] → Octo (2405.12213) [Skim] → OpenVLA (2406.09246) [Read] → OpenVLA-OFT (2502.19645) [Skim] → **π0 (2410.24164) [Deep]** → FAST action tokenizer [Read] → π0.5 (2504.16054) [Read] → *Knowledge Insulating VLAs* [Read] → *Real-Time Chunking* [Read — deployment-critical] → **GR00T N1 (2503.14734) [Deep]** + the GR00T N1.6 sim-to-real blog [Read] → **SmolVLA (2506.01844) [Deep — you will fine-tune it]** → Gemini Robotics (2503.20020) [Skim] → LIBERO (2306.03310) [Skim — eval literacy] → ECoT (2407.08693), RDT-1B, Helix blog, GR-3 [Aware].
- **Hands-on:** SmolVLA fine-tune (Phase C, per project plan); read the SO-101 fine-tuning configs in **openpi** (github.com/Physical-Intelligence/openpi) and **Isaac-GR00T** (github.com/NVIDIA/Isaac-GR00T) before renting the A100. Note version churn: N1.5 is what LeRobot integrates, N1.6/N1.7 are current upstream — pin one per the plan's R7 rule and prefer the latest checkpoint the tooling supports.

### D9 · Reinforcement learning
- **Spine:** **CS285** (Levine, Berkeley — full lectures on YouTube) selected blocks: policy gradients → actor-critic → Q-learning → advanced policy gradients (PPO) → SAC → **both offline-RL lectures**. Faster alternative: HF Deep RL Course end-to-end. *Spinning Up* (spinningup.openai.com) as standing reference; Sutton & Barto on the shelf.
- **Papers:** PPO (1707.06347) [Read] → SAC (1801.01290) [Read] → GAE (1506.02438) [Skim] → Levine et al. offline-RL tutorial (2005.01643) [Read, §§1–4] → CQL (2006.04779) + IQL (2110.06169) [Skim] → **RLPD (2302.02948) [Read — HIL-SERL's foundation]** → SERL (2401.16013) [Read] → **HIL-SERL (2410.21845) [Deep]** → domain randomization (Tobin, 1703.06907) [Skim].
- **RL-post-training of VLAs:** survey when Phase D arrives — the space moves monthly; the ETH course and the awesome-lists will carry current anchors.
- **Hands-on:** PPO on a MuJoCo/ManiSkill SO-101 task; the ManiSkill **lerobot-sim2real** workflow for a real transfer attempt; then HIL-SERL per the project plan.

### D10 · World models & WAMs
- **Orientation first:** NVIDIA's blog *Pretrained to Imagine, Fine-Tuned to Act: The Rise of World-Action Models* [Read] — the cleanest taxonomy of action-conditioned world models, video world models, and WAMs.
- **Papers:** World Models (Ha & Schmidhuber, 1803.10122) [Skim] → DreamerV3 (2301.04104) [Skim] → Genie (2402.15391) + Genie 3 blog [Skim] → V-JEPA 2 [Read] → Cosmos platform report [Skim] → **DreamGen (2505.12705) [Read — synthetic trajectories from video models; feeds GR00T]** → Cosmos Policy (2601.16163) [Skim].
- **Maps:** github.com/OpenMOSS/Awesome-WAM and github.com/NTUMARS/Awesome-World-Model-for-Robotics-Policy.
- **Depth:** conceptual only, with **one optional cloud experiment slot** (Phase F): a DreamGen-style synthetic-data augmentation of your own task, budget-permitting.

### D11 · Simulation & synthetic data
- **MuJoCo:** official docs — Overview → Modeling → **Computation** chapter (this *is* your physics-engine-fundamentals unit: integrators, soft contact, solver parameters) [Read]; **MuJoCo Menagerie** (includes the SO-ARM100 model); **MuJoCo Playground** site + colabs [Hands-on].
- **Isaac:** NVIDIA **Physical AI Learning path** (docs.nvidia.com/learning/physical-ai/) — specifically the **SO-101 sim-to-real course** (configure/calibrate, record demos, post-train GR00T, evaluate in Isaac Lab, deploy to hardware with four gap-closing strategies; 6–10 h) [Deep] + the Isaac Lab introduction course; OpenUSD free learning path [Aware].
- **Ecosystem literacy:** the practical division of labor — MuJoCo for contact-rich manipulation accuracy and VLA eval harnesses; Isaac Lab for massively parallel training. Newton physics engine (MuJoCo-Warp; the DeepMind/NVIDIA convergence) [Aware]; Genesis, ManiSkill3/SAPIEN (2410.00425) [Aware]; LIBERO repo for standardized eval; robosuite/RoboCasa [Aware]; URDF↔MJCF↔USD conversion [Hands-on when needed].

### D12 · Data engineering
- **Spine:** LeRobot dataset documentation + built-in tools (episode delete/split/merge, feature add/remove) + LeLab browser recording UI.
- **Papers:** RoboMimic study (re-read data-quality sections during Phase B) → OXE (2310.08864) [Skim] → DROID [Skim] → BridgeData v2 (2308.12952), AgiBot World, UMI, GELLO [Aware].
- **Hands-on:** publish the Phase-B dataset with a proper dataset card; settle decision D3 there (the real choice is CC-BY-4.0 vs Apache-2.0 — CC-BY-4.0 is the common default for robot demo datasets).

### D13 · Systems, deployment & real-time
- **Docs/papers:** *Real-Time Chunking* + LeRobot async-inference docs [Read]; CS336 Lecture 10 (inference) [Read]; ONNX + TensorRT getting-started guides; torch.compile + PyTorch profiler docs [Hands-on].
- **Framing:** the standard control hierarchy — embedded loops at 500–1000 Hz beneath learned policies at 30–60 Hz. Locate your rig honestly: USB serial-bus servos give you a *soft* ~30–60 Hz single-loop system with no hard-real-time layer; know what that costs and what EtherCAT-class systems buy.
- **Evaluation statistics:** LBM-report methodology sections [Deep] + binomial confidence intervals (Wilson interval — any stats reference). From Phase L-E on, every success rate you report carries an interval.
- **Safety:** ISO 10218 / ISO TS 15066 (collaborative robots) [Aware]; your risk-R8/R9 practices, written up as a one-page safety case.

### D14 · SWE & ecosystem
- Docker getting-started + Weights & Biases quickstart [Hands-on, week 0–1]; Git hygiene assumed.
- **LeRobot codebase reading plan** — §6 of this document.
- Keshav, *How to Read a Paper* (10 min) + a reference manager (Zotero) from week 0.
- Community: LeRobot Discord; skim CoRL/RSS/ICRA accepted-paper lists each cycle; follow the LeRobot/Physical Intelligence/NVIDIA-robotics accounts.

### M1 · ROS 2 awareness module (~8 h, timeboxed — Phase F4)
Official ROS 2 tutorials: CLI tools + "writing your first node (Python)" only; then the **Articulated Robotics** *Getting Ready to Build Robots with ROS* series at 1.5×. Exit: you can converse fluently about nodes/topics/services/actions, parameters, and what `ros2_control` is — and explain *why* LeRobot doesn't need ROS.

### M2 · C++ reading-level module (~12 h, timeboxed — Phase F4)
learncpp.com fundamentals chapters (types, references, classes, templates-lite; skip most exercises), then two structured *reading* exercises with annotation goals: (1) the Feetech/SCServo servo SDK your bus adapter speaks, (2) one MuJoCo source file (e.g., a solver or actuator file). Exit: you can read robotics C++ without fear; you write none.

### M3 · Humanoid/whole-body awareness module (~4 h, timeboxed — Phase F4)
The GR00T N1.6 whole-body sim-to-real blog (Isaac-Lab-trained low-level controller beneath a high-level VLA); Figure's Helix blog post; one sim-to-real overview piece for the control-hierarchy picture. Exit: you can whiteboard the humanoid stack — VLA reasoning layer → whole-body controller → joint-level control — in an interview, and locate the SO-101 rig relative to it.

---

## 4. The Phased Schedule

Study phases are named after the build phases they accompany (L0 pairs with build Phase 0, L-A with Phase A, …). Each phase lists **Core** (protected — fits the 3–5 h/week study budget) and **Stretch** (auto-moves to the Phase-F backlog if squeezed). Hours are study-only; build hours live in the project plan.

**Standing weekly rhythm (all phases):** Sunday — pick the week's one [Deep] item and one shippable output; midweek — papers/lectures ride along with prints, shipping waits, and training runs (the plan's parallelization rule); Saturday — 30 min log: what was learned, what moved to backlog. One public artifact per phase minimum (G7).

### Phase L0 — Weeks 0–1 · with build Phase 0 (procurement & prep)

| Wk | Build context | Study — Core | ~h |
|---|---|---|---|
| 0 | Orders placed day 1; printing begins | Docker getting-started + W&B quickstart; Zotero set up + Keshav *How to Read a Paper*; HF Robotics Course Unit 0 | 3 |
| 1 | Ubuntu + LeRobot installed; sim teleop + toy training verified | 3Blue1Brown linear-algebra refresh (selected); Karpathy #1 (micrograd); MuJoCo docs Overview + load the Menagerie SO-ARM100 model and poke it | 5–6 |

**Exit:** experiment tooling live; you have run a MuJoCo model of your own arm before the real one exists. **Stretch:** MuJoCo Modeling chapter.

### Phase L-A — Weeks 1–4 · with build Phase A (build & first ACT policy)

| Wk | Build context | Study — Core | ~h |
|---|---|---|---|
| 1–2 | Servo IDs, assembly, wiring, calibration | HF Robotics Course classical-foundations units; Modern Robotics Ch. 2–3 (videos + notes) — config space, rotations, SE(3) | 6–7 |
| 3 | Teleop fluency; record ~50 episodes | HF Robotics Course imitation-learning unit; DAgger [Read]; Karpathy #2–3 (makemore/backprop fluency) | 4–5 |
| 4 | ACT trained overnight; 10-trial eval (G1, G2) | *After the policy runs:* Weng VAE blog + CVAE [Skim] as pre-reads, then **ACT [Deep]**; LeRobot ACT code-read part 1 (§6 list) | 4–5 |

**Exit:** you can explain every block of the ACT architecture against your own training curves. **Stretch:** MR Ch. 4 (FK) + NumPy FK for the SO-101.

### Phase L-B — Weeks 4–6 · with build Phase B (data-centric experiments)

| Wk | Build context | Study — Core | ~h |
|---|---|---|---|
| 5 | Scaling re-records (10/25/50/100); wrist cam added | 6.S184 Lectures 1–2 + Weng diffusion blog; camera intrinsics calibration (OpenCV) + **hand-eye calibration** of the wrist cam (Nayar calibration videos as needed); Diffusion Policy first pass | 5–6 |
| 6 | DP-vs-ACT comparison; dataset published to Hub (G3) | 6.S184 Lectures 3–4 + Lab 1; **Diffusion Policy [Deep]** + LeRobot code-read part 2; Implicit BC [Read]; RoboMimic *What Matters* [Read]; *Data Scaling Laws in IL* [Read]; dataset card + settle license (D3) | 6–7 |

**Exit:** scaling curve and ablation exist *and* you can say why DP handles multimodal actions where naive BC can't. **Stretch:** full Nayar image-formation playlist → F2.

### Phase L-C — Weeks 6–9 (allow spill to 10) · with build Phase C (VLAs)

The heaviest study block; training runs are passive time — read while GPUs burn.

| Wk | Build context | Study — Core | ~h |
|---|---|---|---|
| 6–7 | Language-annotated 3–4-task dataset recorded | 6.S184 flow-matching lectures + Lab 3 (**finish the course**); Karpathy *build GPT* + *Attention Is All You Need* [Deep] | 6–7 |
| 7–8 | SmolVLA local fine-tune; instruction-following checks (G4) | **LoRA [Deep]** + toy VLM LoRA on the 3080 (non-robot warm-up); LLaVA → PaliGemma [Read] → SmolVLM [Skim]; **SmolVLA [Deep]** + code-read part 3; lineage skims: RT-1, OXE, Octo (+ RT-2, OpenVLA [Read]); ETH VLA lecture 1 | 7–8 |
| 8–9 | A100 rented; GR00T/π0 LoRA fine-tune; local bf16/quantized inference (G5) | **π0 [Deep]** + FAST [Read] + π0.5 [Read]; **GR00T N1 [Deep]** + N1.6 blog; read the SO-101 configs in openpi and Isaac-GR00T *before* renting; ETH VLA lecture 2 | 6–7 |
| 9(–10) | Per-instruction eval harness; three-model comparison note (G7) | *Knowledge Insulation* [Read]; *Real-Time Chunking* [Read]; Gemini Robotics [Skim]; QLoRA [Skim] | 3–4 |

**Exit:** you can whiteboard the design axes — action tokenization vs flow expert, single- vs dual-system — and place all three of your fine-tuned models on them. **Stretch:** OpenVLA-OFT, ECoT, RDT-1B → F1 backlog.

### Phase L-D — Weeks 10–13 · with build Phase D (RL, sim + HIL-SERL)

| Wk | Build context | Study — Core | ~h |
|---|---|---|---|
| 10 | Sim envs stood up | CS285 policy-gradient + actor-critic blocks (1.5×); PPO [Read]; MuJoCo **Computation** chapter; a MuJoCo Playground colab | 5–6 |
| 11 | PPO/SAC training on SO-101 sim task; reward shaping, domain randomization | CS285 Q-learning + advanced-PG blocks; SAC [Read]; Tobin domain-randomization [Skim]; GAE [Skim] | 5 |
| 12 | Sim-to-real transfer attempt; document the gap | CS285 **offline-RL lectures (both)**; Levine offline-RL tutorial §§1–4; CQL + IQL [Skim]; **RLPD [Read]** | 5 |
| 13 | HIL-SERL: reward classifier, leader-arm interventions; beat BC baseline (G6) | SERL [Read] → **HIL-SERL [Deep]** *before* the run; sim2real writeup | 4–5 |

**Exit:** G6 met and you can explain *why* HIL-SERL works where naive real-world RL fails (off-policy + demos + interventions + classifier rewards). **Stretch:** MR Ch. 8 & 11 (dynamics/control) → F2.

### Phase L-E — Weeks 14–16 · consolidation (build load light; Phase-E gate at month 4)

| Wk | Focus | Study — Core | ~h |
|---|---|---|---|
| 14 | The sim-first workflow, properly | **NVIDIA SO-101 sim-to-real course** part 1 (Isaac Lab + GR00T post-training); *Pretrained to Imagine…* WAM blog [Read]; V-JEPA 2 [Read] | 6 |
| 15 | Finish sim course; world-model unit | NVIDIA course part 2 (Isaac Lab eval → real deploy, four gap strategies) + Isaac Lab intro course; DreamGen [Read]; Ha/Dreamer/Genie/Cosmos [Skims] | 6 |
| 16 | Deployment + evaluation rigor sprint | Export your best policy to ONNX → TensorRT, benchmark latency vs PyTorch; LeRobot async-inference docs [Read] + enable it; **LBM report [Deep]**; re-report every success rate with Wilson CIs; one-page safety case | 6–7 |

**Exit:** one policy running through an optimized inference path with honest confidence intervals; Phase-E go/no-go memo written with real evidence.

### Phase F — Months 5–9 · depth & role-readiness (study becomes primary: 8–10 h/wk)

| Block | Weeks | Content | Output |
|---|---|---|---|
| **F1 · Theory consolidation** | 17–24 | **ETH Robot Learning full pass** (lectures end-to-end; homeworks selectively — its repo has graded exercises); clear the paper backlog accumulated in L-phases; CS285 leftovers if any; *optional* DreamGen-style synthetic-data cloud experiment on your own task (~₹1,500–2,500) | Backlog cleared; one "what I misunderstood the first time" post |
| **F2 · Classical + perception depth** | 25–29 | Modern Robotics completion — Ch. 4–6 deep if deferred, Ch. 8, 9, 11 [Deep], Ch. 10, 12 [Read]; capstone: NumPy FK + Jacobian-IK + gravity-compensation for the SO-101, verified in MuJoCo; MIT 6.4210 selected chapters (geometric perception, grasping, learning-based manipulation); Nayar playlists completed; FoundationPose [Aware] | The kinematics capstone repo — a standard interview artifact |
| **F3 · Deployment & efficiency** | 30–32 | CS336 Lectures 1–3, 9, 10; quantization mini-project: int8/4-bit SmolVLA on the rig, **success-rate-vs-latency curve** (a genuinely uncommon portfolio piece); TensorRT pass on a second policy | Quantization study post |
| **F4 · The three modules** | 33–34 | M1 ROS 2 (~8 h) · M2 C++ reading (~12 h) · M3 humanoid awareness (~4 h) | One-page cheat sheets for each |
| **F5 · Portfolio & interview** | 35–38 | Capstone writeup ("a year of embodied AI on a desktop arm"); consolidate all G7 posts; LeRobot OSS contribution ladder (docs fix → bug fix → small feature); interview-prep checklist (§7) drilled; demo reel + résumé | Public portfolio; first applications out |

**Months 10–12:** buffer — spillover, Stage-2 XLeRobot build if the Phase-E gate said go, interview cycles. This document gets a v2.0 at the same time the project plan does.

---

## 5. Master Reading Queue

The complete paper queue in reading order. IDs are arXiv numbers where verified; entries without IDs are unambiguous by title. ~55 items: 10 [Deep], ~20 [Read], the rest [Skim]/[Aware] — roughly 120–140 h of reading across the year, already accounted for in §4's budgets.

| # | Paper / report | ID | Depth | Phase | Why |
|---|---|---|---|---|---|
| 1 | Keshav — *How to Read a Paper* | — | Read | L0 | The protocol used for everything below |
| 2 | Ross et al. — DAgger | 1011.0686 | Read | L-A | Names the covariate-shift problem BC has |
| 3 | Kingma & Welling — VAE | 1312.6114 | Skim | L-A | ELBO; the z in ACT |
| 4 | Sohn et al. — CVAE (NeurIPS 2015) | — | Skim | L-A | ACT is a conditional VAE |
| 5 | Zhao et al. — **ACT / ALOHA** | 2304.13705 | **Deep** | L-A | Your Phase-A policy, block by block |
| 6 | Ho et al. — DDPM | 2006.11239 | Read | L-B | Diffusion, from first principles |
| 7 | Song et al. — DDIM | 2010.02502 | Skim | L-B | Fast sampling — why DP is deployable |
| 8 | Ho & Salimans — Classifier-free guidance | 2207.12598 | Skim | L-B | Conditioning mechanism everywhere |
| 9 | Chi et al. — **Diffusion Policy** | 2303.04137 | **Deep** | L-B | Your Phase-B comparison method |
| 10 | Florence et al. — Implicit BC | 2109.00137 | Read | L-B | Why multimodal actions break MSE-BC |
| 11 | Mandlekar et al. — *What Matters in Learning from Offline Human Demos* | 2108.03298 | Read | L-B | Design manual for your scaling study |
| 12 | Lin et al. — *Data Scaling Laws in Imitation Learning* | 2410.18647 | Read | L-B | The curve you are about to plot |
| 13 | Mandlekar et al. — MimicGen | 2310.17596 | Skim | L-B | Synthetic demo augmentation |
| 14 | Vaswani et al. — *Attention Is All You Need* | 1706.03762 | **Deep** | L-C | With the Karpathy GPT build |
| 15 | Su et al. — RoPE | 2104.09864 | Skim | L-C | Modern positional encoding |
| 16 | Dosovitskiy et al. — ViT | 2010.11929 | Read | L-C | The vision tokenizer of everything |
| 17 | Radford et al. — CLIP | 2103.00020 | Read | L-C | Vision-language alignment |
| 18 | Kaplan et al. — Scaling laws | 2001.08361 | Skim | L-C | Why scale works |
| 19 | Hoffmann et al. — Chinchilla | 2203.15556 | Skim | L-C | Compute-optimal correction |
| 20 | Hu et al. — **LoRA** | 2106.09685 | **Deep** | L-C | You will live inside this method |
| 21 | Dettmers et al. — QLoRA | 2305.14314 | Skim | L-C | Fine-tuning under VRAM ceilings |
| 22 | Liu et al. — LLaVA | 2304.08485 | Read | L-C | The canonical VLM recipe |
| 23 | Beyer et al. — PaliGemma | 2407.07726 | Read | L-C | π0's backbone |
| 24 | SmolVLM report | — | Skim | L-C | SmolVLA's backbone |
| 25 | Lipman et al. — Flow Matching | 2210.02747 | Read | L-C | π0's action expert, mathematically |
| 26 | Peebles & Xie — DiT | 2212.09748 | Skim | L-C | GR00T's action head; video models |
| 27 | Brohan et al. — RT-1 | 2212.06817 | Skim | L-C | Where VLAs started |
| 28 | Brohan et al. — RT-2 | 2307.15818 | Read | L-C | VLM-to-VLA transfer, the founding claim |
| 29 | Open X-Embodiment | 2310.08864 | Skim | L-C | Cross-embodiment data at scale |
| 30 | Octo Model Team — Octo | 2405.12213 | Skim | L-C | Open generalist policy, pre-VLM era |
| 31 | Kim et al. — OpenVLA | 2406.09246 | Read | L-C | The open reference VLA |
| 32 | OpenVLA-OFT | 2502.19645 | Skim | L-C | Fine-tuning speed/success recipe |
| 33 | Black et al. — **π0** | 2410.24164 | **Deep** | L-C | Flow-matching VLA — your G5 candidate |
| 34 | Pertsch et al. — FAST tokenizer | — | Read | L-C | The tokenization alternative to flow |
| 35 | Physical Intelligence — π0.5 | 2504.16054 | Read | L-C | Open-world generalization recipe |
| 36 | NVIDIA — **GR00T N1** | 2503.14734 | **Deep** | L-C | Dual-system VLA — your G5 candidate |
| 37 | GR00T N1.6 technical blog | — | Read | L-C | Current sim-first whole-body workflow |
| 38 | Shukor et al. — **SmolVLA** | 2506.01844 | **Deep** | L-C | You fine-tune it locally (G4) |
| 39 | Driess et al. — Knowledge Insulation | — | Read | L-C | Train fast / run fast / generalize |
| 40 | Physical Intelligence — Real-Time Chunking | — | Read | L-C | Deployment of chunked policies |
| 41 | Gemini Robotics report | 2503.20020 | Skim | L-C | The closed-lab frontier |
| 42 | Liu et al. — LIBERO | 2306.03310 | Skim | L-C | Benchmark literacy |
| 43 | Schulman et al. — PPO | 1707.06347 | Read | L-D | Workhorse of sim RL |
| 44 | Haarnoja et al. — SAC | 1801.01290 | Read | L-D | Off-policy workhorse |
| 45 | Schulman et al. — GAE | 1506.02438 | Skim | L-D | Advantage estimation |
| 46 | Levine et al. — Offline RL tutorial | 2005.01643 | Read | L-D | The bridge to HIL-SERL |
| 47 | Kumar et al. — CQL | 2006.04779 | Skim | L-D | Conservatism idea |
| 48 | Kostrikov et al. — IQL | 2110.06169 | Skim | L-D | Implicit constraint idea |
| 49 | Ball et al. — RLPD | 2302.02948 | Read | L-D | RL + prior data — HIL-SERL's engine |
| 50 | Luo et al. — SERL | 2401.16013 | Read | L-D | The software stack you'll run |
| 51 | Luo et al. — **HIL-SERL** | 2410.21845 | **Deep** | L-D | Your G6 method |
| 52 | Tobin et al. — Domain randomization | 1703.06907 | Skim | L-D | Sim2real's founding trick |
| 53 | NVIDIA blog — *Pretrained to Imagine, Fine-Tuned to Act* | — | Read | L-E | The WAM taxonomy in one read |
| 54 | Assran et al. — V-JEPA 2 | — | Read | L-E | Video SSL → prediction → planning |
| 55 | Jang et al. — DreamGen | 2505.12705 | Read | L-E | Synthetic trajectories from video models |
| 56 | Ha & Schmidhuber — World Models | 1803.10122 | Skim | L-E | The origin |
| 57 | Hafner et al. — DreamerV3 | 2301.04104 | Skim | L-E | Latent world-model RL |
| 58 | Bruce et al. — Genie (+ Genie 3 blog) | 2402.15391 | Skim | L-E | Interactive generative environments |
| 59 | NVIDIA — Cosmos platform report (+ Cosmos Policy skim) | — | Skim | L-E | WFM platform; video-model-as-policy |
| 60 | TRI — **Large Behavior Models report** | lbm.tri.global | **Deep** | L-E | Evaluation methodology bible |
| 61 | Zhai et al. — SigLIP | 2303.15343 | Skim | F2 | Modern contrastive pretraining |
| 62 | Oquab et al. — DINOv2 | 2304.07193 | Skim | F2 | Self-supervised features |
| 63 | Kirillov et al. — SAM / SAM-2 | 2304.02643 | Skim | F2 | Promptable segmentation |
| 64 | FoundationPose | — | Aware | F2 | 6-DoF pose SOTA |
| 65 | ECoT · RDT-1B · Helix blog · GR-3 · VQ-BeT · UMI · GELLO · AgiBot World | — | Aware | F1 | Field literacy, minutes each |

**Backlog rule:** anything unread at phase exit moves to F1 with its tag intact; [Deep] items may be demoted to [Read] there, never silently dropped.

---

## 6. LeRobot Code-Reading Plan (and friends)

The highest-leverage code study available to you: read the implementations of the exact policies you train, against their papers. **Protocol:** paper in one window, source in the other; annotate a fork; produce one hand-drawn dataflow diagram per policy (tensor shapes on every arrow). Exact file paths churn between releases (plan risk R7) — pin your phase's release and locate modules by name with grep; the *capabilities* below are stable.

1. **Dataset layer (Phase L-A/L-B):** the `LeRobotDataset` class — episode/frame indexing, video decoding, delta-timestamp windowing, normalization statistics. Then the dataset tools (split/merge/filter) you'll use in Phase B.
2. **Motors & robot layer (L-A):** the Feetech bus driver (packet protocol, sync read/write, torque enable) and the SO-101 follower/leader classes + calibration routines. This is where software meets your servos.
3. **Teleop & recording (L-A):** the `lerobot-teleoperate` / `lerobot-record` entry points — the control loop's actual Hz, where observations are timestamped, where your R4 camera discipline matters.
4. **ACT (L-A):** `modeling_act` — CVAE encoder, transformer decoder, chunking, temporal ensembling. Diagram it.
5. **Diffusion Policy (L-B):** `modeling_diffusion` — noise scheduler, U-Net/transformer denoiser, observation conditioning, inference-step count. Compare sampling cost vs ACT empirically.
6. **Training loop (L-B):** the train script + config system — where optimizer, EMA, eval, and checkpointing live; wire in your W&B habits.
7. **SmolVLA (L-C):** VLM backbone integration, action-expert head, language conditioning path — trace one instruction from string to torque.
8. **Async inference / policy server (L-E):** the client-server split, action-chunk buffering — read alongside the Real-Time Chunking paper.
9. **HIL-SERL stack (L-D):** actor/learner processes, reward classifier, intervention plumbing from the leader arm.
10. **Friends (L-C):** the SO-101 fine-tuning configs in **openpi** and **Isaac-GR00T** — read the config before renting the A100; know every hyperparameter you're paying for.

---

## 7. Portfolio & Role-Readiness

**Target titles:** Robot Learning Engineer · Research Engineer, Robot Foundation Models · Embodied / Physical AI Engineer · Robotics ML Engineer. The portfolio below is built to answer their screens.

**Public artifacts (G7, expanded)** — one per phase, cumulative:
1. L-A: *"From kit to policy: 50 demos to 80% autonomous"* (build + first ACT results).
2. L-B: *"How many demos is enough?"* (scaling curve + camera ablation + the published dataset).
3. L-C: *"ACT vs SmolVLA vs a 3B VLA on the same desk"* (data efficiency + failure modes).
4. L-D: *"RL that actually worked: HIL-SERL vs my BC baseline"* (+ honest sim2real gap note).
5. L-E: *"Making it fast: quantization, TensorRT, and async inference on a hobby arm"* (or hold for F3's fuller version).
6. F2: the kinematics capstone repo (FK/IK/gravity-comp, verified in MuJoCo).
7. F3: the success-rate-vs-latency quantization study — rare in portfolios, memorable in interviews.
8. F5: the year-in-review capstone + demo reel.

**OSS ladder (F5, start earlier if natural):** docs fix → reproduce-and-triage a bug → small feature or new-robot config PR to LeRobot. One merged PR outweighs a certificate.

**Interview-prep checklist (drill in F5):**

| Area | Be ready to… |
|---|---|
| Kinematics | Derive a Jacobian; explain singularities and damped-least-squares IK; whiteboard SE(3) composition |
| Control | Explain PID vs impedance control; gravity compensation; where MPC fits; your rig's control hierarchy vs a 1 kHz EtherCAT system |
| IL internals | Whiteboard ACT (why a CVAE? why chunk? why ensemble?) and Diffusion Policy (why denoise actions?); when BC fails |
| Generative | DDPM objective from scratch; diffusion vs flow matching trade-offs; why π0 chose flow |
| VLA design | The axes: tokenized vs continuous actions, single vs dual system, knowledge insulation, cross-embodiment; place π0/GR00T/SmolVLA on them |
| RL | PPO vs SAC; why offline RL is hard; why HIL-SERL works; reward-shaping war stories from your Phase D |
| Sim2real | The four gap sources you actually fought (dynamics, visuals, latency, contact) and what closed them; domain randomization limits |
| Data | Your scaling curve; curation rules; what ruined an early dataset (R4 story); dataset licensing |
| Systems | Latency budget of your inference path before/after TensorRT; async chunk execution; what breaks at 30 Hz |
| Evaluation | Success rates with CIs; blind A/B per the LBM report; why 10 trials is not enough |
| Behavioral | The project narrative: constraint-driven decisions (D1–D5), risk table hits, what you'd redo |

---

## 8. Operating Rules & Tracking

1. **One [Deep] in flight.** Everything else queues.
2. **Backlog file** (`backlog.md` beside this doc): every deferred item with its tag; reviewed at each phase gate.
3. **Version pinning:** LeRobot release, CUDA/PyTorch pair, and course-code commits pinned per phase; upgrade only at gates (extends plan R7).
4. **Triage rule:** two weeks behind → cut Stretch, protect the build, demote one [Deep] to [Read]. The build never blocks on the study track, and vice versa.
5. **Phase gates:** at each build-phase exit, 30 minutes against this doc — core done? backlog groomed? one public artifact shipped? Then advance.
6. **Versioning:** this doc revs with the project plan (v2.0 at the Stage-2 decision, Phase E).

---

## 9. Consolidated References

**Courses & lecture series:** Hugging Face Robotics Course (huggingface.co/learn/robotics-course) · ETH *Robot Learning: From Fundamentals to Foundation Models*, Spring 2026 (cvg.ethz.ch/lectures/Robot-Learning; homework: github.com/mees-robot-learning-course/ethz-course-2026) · MIT 6.S184 *Flow Matching and Diffusion Models*, 2026 ed. (diffusion.csail.mit.edu) · Modern Robotics, Lynch & Park (book PDF + videos; Coursera audit) · MIT 6.4210 *Robotic Manipulation*, Tedrake (manipulation.csail.mit.edu) · UC Berkeley CS285, Levine (YouTube) · Stanford CS336 *Language Modeling from Scratch* (YouTube, 2025/2026) · Karpathy *Neural Networks: Zero to Hero* (karpathy.ai/zero-to-hero.html) · CS231n notes (cs231n.github.io) · First Principles of Computer Vision, Nayar (YouTube) · NVIDIA Physical AI Learning path incl. the SO-101 sim-to-real course (docs.nvidia.com/learning/physical-ai/) · HF Deep RL Course · HF LLM course · OpenAI Spinning Up (spinningup.openai.com) · Stanford CS224R, Finn (optional) · Articulated Robotics ROS series · learncpp.com · 3Blue1Brown.

**Books (free):** *Modern Robotics* · *Kalman and Bayesian Filters in Python* (Labbe) · *Mathematics for Machine Learning* (Deisenroth et al.) · Sutton & Barto *RL* · LaValle *Planning Algorithms* · 6.S184 lecture notes · *Flow Matching Guide and Code* (arXiv 2412.06264).

**Repos & tools:** github.com/huggingface/lerobot (+ docs, LeLab) · huggingface/robotics-course · Physical-Intelligence/openpi · NVIDIA/Isaac-GR00T · google-deepmind/mujoco + mujoco_menagerie (SO-ARM100) · MuJoCo Playground · Isaac Lab · ManiSkill3 / lerobot-sim2real · LIBERO · Psi-Robot/Awesome-VLA-Papers · OpenMOSS/Awesome-WAM · NTUMARS/Awesome-World-Model-for-Robotics-Policy · rlabbe/Kalman-and-Bayesian-Filters-in-Python · OpenCV · Open3D · Weights & Biases · Zotero.

**Blogs & standing references:** Lilian Weng (VAE, diffusion) · Yang Song (score-based models) · NVIDIA Technical Blog (*Pretrained to Imagine…*; GR00T N1.6 workflow) · TRI LBM (lbm.tri.global) · techinterview.net Physical-AI roadmap & Figure-interview posts (the role framing this document answers).

---

*End of Learning Roadmap v1.0 — companion to Project Plan v1.1. Next revision: Phase-E gate.*