# physical-ai-learning

Planning and study repo for the **SO-101 imitation-learning rig** — a leader/follower
robot arm pair driven from an RTX 3080 workstation with LeRobot — and the embodied-AI
curriculum built on top of it. Stage 1 of 2 (Stage 2 is the XLeRobot dual-arm mobile
robot). Owner: Chinmay.

Mostly documents: the build plan, the study roadmap, the deferred-work backlog, and the
lock file for the environment that lives outside it — plus the scripts that run training
jobs locally and on rented cloud GPUs.

| Path | What it owns |
|---|---|
| [docs/so101-embodied-ai-project-plan.md](docs/so101-embodied-ai-project-plan.md) | The build: hardware, BOM, phases 0–E, budget, risks, open decisions |
| [docs/physical-ai-learning-roadmap.md](docs/physical-ai-learning-roadmap.md) | The study track: 14 domains, source library, phased schedule L0–F5, reading queue |
| [docs/progress.md](docs/progress.md) | Status board: current phase, every task across Phases 0–F, goals and decisions |
| [docs/backlog.md](docs/backlog.md) | Deferred items, the stretch watchlist, and gate-review history |
| [env/README.md](env/README.md) | The uv-managed venv at `/home/chinmay/lerobot-env` and how to regenerate its lock |
| [scripts/README.md](scripts/README.md) | Training jobs and cloud runs: RunPod pod setup, the environment bootstrap, the canonical pusht job |
| [notes/](notes/) | Weekly logs and G7 phase writeups |
| [CLAUDE.md](CLAUDE.md) | Durable project context for Claude Code sessions |
