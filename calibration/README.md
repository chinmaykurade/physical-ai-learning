# Calibration

Per-joint calibration for the SO-101 arms, kept in git because re-deriving it means
re-sweeping every joint by hand, and because it is provenance for every dataset recorded
against it. A recording is only interpretable next to the calibration that produced it.

## Layout

LeRobot resolves calibration as `HF_LEROBOT_CALIBRATION / {robots|teleoperators} / {class} /
{id}.json` (`lerobot/robots/robot.py`, `lerobot/utils/constants.py`), so this tree mirrors
that shape exactly:

```
calibration/
  robots/so_follower/follower_arm.json      # the follower  (a Robot)
  teleoperators/so_leader/<id>.json         # the leader    (a Teleoperator)
```

Two things that are easy to get wrong:

- The directory is the **class** name — `so_follower` / `so_leader` — not the CLI type
  string, which is `so101_follower` / `so101_leader`.
- The follower is a `Robot` and the leader is a `Teleoperator`. They live under different
  top-level directories and are configured with different CLI flags (`--robot.*` vs
  `--teleop.*`).

## How LeRobot finds this directory

`~/.cache/huggingface/lerobot/calibration` is a **symlink** to this directory:

```bash
ln -s /home/chinmay/physical-ai-learning/calibration ~/.cache/huggingface/lerobot/calibration
```

A symlink rather than an environment variable on purpose: it applies to every entry point —
`lerobot-calibrate`, `lerobot-teleoperate`, `lerobot-record`, and `keyboard_teleop.py` —
with nothing to export and nothing to forget. Had it been `HF_LEROBOT_CALIBRATION`, a shell
that missed the export would not error; LeRobot would silently create an empty directory
under `~/.cache` and prompt for a fresh calibration, quietly orphaning this one.

On a new machine, recreate the symlink (or export `HF_LEROBOT_CALIBRATION` to point here).

## What is *not* in this directory

**Servo IDs are not stored here.** `setup_motor` writes the ID to the servo's control table
— EEPROM on the motor itself (`lerobot/motors/motors_bus.py`). It survives power cycles and
OS reinstalls, and it cannot be committed. The `id` field in the JSON below records the
mapping, but it does not *set* it.

The consequence: swap in a replacement servo and the ID must be re-flashed with
`lerobot-setup-motors` for that joint. The physical mapping from servo to joint lives on
labelled cables, not in git.

## Re-calibrating

```bash
lerobot-calibrate --robot.type=so101_follower --robot.port=/dev/ttyACM1 --robot.id=follower_arm
lerobot-calibrate --teleop.type=so101_leader  --teleop.port=/dev/ttyACM0 --teleop.id=leader_arm
```

Each joint's `range_min` / `range_max` is captured from the sweep you perform, so **drive
every joint through its full travel in both directions**. A short sweep records a narrow
range, and because normalization maps that range onto [-100, 100], the joint will later
report values outside [-100, 100] in ordinary use — which is how a target gets seeded past a
mechanical stop. See `notes/2026-08-05-calibration-and-motor-ids.md`.
