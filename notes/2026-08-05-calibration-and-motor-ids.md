# Motor IDs vs calibration — two kinds of state, one of them uncommittable

*2026-08-05 · build Phase A, week 1*

The follower arm is assembled, wired, calibrated and driving under `keyboard_teleop.py`.
Getting there turned up a distinction that the LeRobot docs never state outright, and a
calibration bug that would have quietly poisoned the first dataset.

## The rig's configuration lives in two places, not one

Setting up an arm writes state to two completely different kinds of storage, and only one of
them is a file.

**Servo IDs live in EEPROM on the servos.** `lerobot-setup-motors` calls `setup_motor`, which
writes to control-table address `ID` on the motor itself (`lerobot/motors/motors_bus.py:588`).
Non-volatile, on the hardware. It survives power cycles, venv rebuilds, and reinstalling the
OS. It cannot be backed up, committed, or restored from git. The only durable record of which
physical servo is which joint is a labelled cable.

**Calibration lives in a JSON file.** `HF_LEROBOT_CALIBRATION / {robots|teleoperators} /
{class} / {id}.json` — per joint, a `homing_offset`, a `range_min` / `range_max`, a
`drive_mode`, and the `id`. This one is committable, and now is.

The `id` field in that JSON is what makes the split confusing: the calibration file *records*
the ID mapping but does not *set* it. Restoring the JSON onto a fresh servo does nothing —
the servo still answers to whatever ID is burned into it. The two have to be reconciled by
hand whenever a motor is replaced, and the spare servo in BOM-A means that will happen.

## Why setup-motors is per-arm, and why it is one motor at a time

Every STS3215 ships as ID 1. `setup_motor` addresses a servo at its *current* ID in order to
write the new one, so six unconfigured servos on one bus all answer to 1 and the write is
ambiguous. Hence the prompt-per-motor loop in `so_leader.py:139`, which asks you to connect
exactly one motor at a time and walks the chain in reverse (gripper first).

It also means the leader needs its own full pass — a separate bus, six more servos, all
shipping as ID 1. Nothing about having done the follower carries over.

The leader is a **Teleoperator**, not a Robot: `--teleop.type=so101_leader`, and its
calibration lands under `calibration/teleoperators/so_leader/`. `SetupConfig` raises if you
pass both `--robot` and `--teleop`.

A naming trap worth writing down: the on-disk directory is the *class* name (`so_follower`,
`so_leader`) while the CLI type string is `so101_follower` / `so101_leader`. They do not
match, and the mismatch is invisible until you go looking for the file.

## The calibration bug: a short sweep reads as an out-of-range joint

While writing `keyboard_teleop.py` I found `wrist_flex` measuring **105.98** — outside the
normalized [-100, 100] range that LeRobot's calibration is supposed to guarantee. I clamped
the seed values in `read_targets` to stop an out-of-range measurement from being turned into
a commanded target, which is the right defensive fix but not the cause.

The cause is in the calibration file. `wrist_flex` recorded:

```
range_min: 160, range_max: 2573
```

against `wrist_roll`'s clean `0`–`4095`. Normalization maps the recorded range onto
[-100, 100], so any travel beyond `range_max` reads above 100. The joint was simply never
driven through its full travel during the calibration sweep — a short sweep does not fail, it
silently records a narrow range and every later reading is scaled against it.

This is worth catching before recording episodes, not after. It compounds badly:

- Seeding a target from an out-of-range measurement commands the servo into a mechanical
  stop, which trips a **latched** overload flag. Latched means it ignores commands until
  power is cycled — restarting the script does not clear it. `keyboard_teleop.py` now says
  so loudly on disconnect failure rather than swallowing the exception, because the failure
  mode is "torque is still on and the arm will drop when you cut power".
- Every recorded episode is normalized against the calibration in force at record time. Fix
  the calibration after recording 50 episodes and the old episodes are scaled differently
  from the new ones, in a way nothing in the dataset makes visible.

That second point is the real reason calibration now lives in git: it is provenance for a
dataset, not just a convenience.

## What changed in the repo

- `calibration/` now holds the real files; `~/.cache/huggingface/lerobot/calibration` is a
  symlink to it. Symlink rather than `HF_LEROBOT_CALIBRATION` because a missed export does
  not error — LeRobot would create an empty directory and prompt for a fresh calibration,
  orphaning the committed one.
- `calibration/README.md` documents the layout and the ID/calibration split.

## Open

- Re-calibrate `wrist_flex` (full travel, both directions) before recording begins. Worth
  re-sweeping all six while the arm is on the bench.
- Leader arm: bus IDs, assembly, wiring, calibration — all still to do.
