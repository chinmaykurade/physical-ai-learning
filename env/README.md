# Environment

The Python environment for this project is a **uv-managed virtualenv living outside this
repo** at `/home/chinmay/lerobot-env`, running **Python 3.12.3** — 3.12 is the minimum,
since `lerobot==0.6.0` declares `Requires-Python >=3.12`. It is never committed —
`lerobot-env.lock.txt` in this directory is the only record of it in git. Use `uv pip` for
everything that touches it (never bare `pip`), and regenerate the lock file after any
change with:

```bash
uv pip freeze --python /home/chinmay/lerobot-env/bin/python > env/lerobot-env.lock.txt
```

## Arm calibration

LeRobot reads calibration from `~/.cache/huggingface/lerobot/calibration`, which on this
machine is a **symlink into the repo** at [`calibration/`](../calibration/) — so the files are
versioned rather than living in a cache that any reinstall would clear. Recreate it on a new
machine with:

```bash
ln -s /home/chinmay/physical-ai-learning/calibration ~/.cache/huggingface/lerobot/calibration
```

Servo **IDs** are not covered by this — they live in EEPROM on the motors themselves and are
re-flashed with `lerobot-setup-motors`. See [`calibration/README.md`](../calibration/README.md).

Per roadmap §8 rule 3 (extending project-plan risk R7), the pins in this lock file —
LeRobot release, the CUDA/PyTorch pair, and course-code commits — **change only at phase
gates**, never mid-phase. If something needs a newer version in the middle of a phase,
that is a backlog item, not an upgrade.
