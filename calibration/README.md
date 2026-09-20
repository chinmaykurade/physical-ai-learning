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

## Finding the serial ports

Every command below needs a port. On this machine the two Waveshare adapters currently
enumerate as:

| Arm | Class | Port |
|---|---|---|
| Follower | `so101_follower` (Robot) | `/dev/ttyACM1` |
| Leader | `so101_leader` (Teleoperator) | `/dev/ttyACM0` |

**`ttyACM0`/`ttyACM1` is enumeration order, not identity.** It is assigned in the order the
kernel sees the adapters, so it can swap on reboot or on a replug — and swapping it silently
points the follower's calibration at the leader's servos. Re-check after any replug rather
than trusting the table.

To identify a port, unplug/replug one adapter and let LeRobot diff the device list:

```bash
lerobot-find-port
```

It snapshots `/dev/tty*`, waits for you to pull the USB cable, snapshots again, and prints
the one entry that disappeared (`lerobot/scripts/lerobot_find_port.py`). Run it once per
adapter, with **only that adapter unplugged** — it raises if the diff is not exactly one
port. Plain `ls /dev/ttyACM*` before and after works identically if you prefer.

For a name that survives reboots, use the persistent symlinks the kernel creates:

```bash
ls -l /dev/serial/by-id/    # by adapter serial number — stable across USB sockets
ls -l /dev/serial/by-path/  # by physical USB socket — stable if the cables stay put
```

Either path can be passed straight to `--robot.port` / `--teleop.port`. Prefer `by-id` when
the adapters report distinct serial numbers; several Waveshare boards do not, in which case
their `by-id` names collide and `by-path` (keep each arm in its own USB socket) is the one
that actually disambiguates.

Serial access needs the `dialout` group — already granted here (`id -nG`). On a new machine:
`sudo usermod -aG dialout $USER`, then log out and back in.

## Re-calibrating

The CLI entry points live in the venv, which is **not** on `PATH` by default:

```bash
source /home/chinmay/lerobot-env/bin/activate    # or call /home/chinmay/lerobot-env/bin/lerobot-* directly
```

```bash
lerobot-calibrate --robot.type=so101_follower --robot.port=/dev/ttyACM1 --robot.id=follower_arm
lerobot-calibrate --teleop.type=so101_leader  --teleop.port=/dev/ttyACM0 --teleop.id=leader_arm
```

Each joint's `range_min` / `range_max` is captured from the sweep you perform, so **drive
every joint through its full travel in both directions**. A short sweep records a narrow
range, and because normalization maps that range onto [-100, 100], the joint will later
report values outside [-100, 100] in ordinary use — which is how a target gets seeded past a
mechanical stop. See `notes/2026-08-05-calibration-and-motor-ids.md`.

## Teleoperation

Leader → follower. Both arms must already be calibrated under the ids below, or `connect()`
prompts for a fresh sweep mid-session:

```bash
lerobot-teleoperate \
  --robot.type=so101_follower  --robot.port=/dev/ttyACM1 --robot.id=follower_arm \
  --teleop.type=so101_leader   --teleop.port=/dev/ttyACM0 --teleop.id=leader_arm \
  --fps=30
```

`Ctrl-C` stops it — the `KeyboardInterrupt` is caught and both arms are disconnected, which
disables follower torque (`disable_torque_on_disconnect` defaults to true). The loop prints
its achieved rate; `--fps` defaults to 60, which the servo bus will not sustain with six
joints, so 30 is the honest starting point.

**Before the first tick, match the two arms' poses by hand.** The loop reads the leader and
sends that pose to the follower immediately, with no ramp and no interpolation — a follower
parked far from the leader's pose slews there at full speed. For an unfamiliar setup, cap the
per-tick motion:

```bash
--robot.max_relative_target=5
```

That clamps the magnitude of each relative target (`SOFollowerConfig.max_relative_target`,
default `None` = unclamped). It turns a bad first tick into a slow crawl instead of a swing.
Drop it once the pairing is known-good; it also damps legitimate fast motion.

`--display_data=true` streams observations to Rerun, but **`rerun-sdk` is not installed in
this env** — the flag will fail until it is added, and adding it is a pin change, so it waits
for a phase gate (roadmap §8 rule 2). Without cameras there is little to see anyway; the
per-joint table the loop prints is enough for a first bring-up.

### Keyboard-only fallback

`keyboard_teleop.py` at the repo root drives the follower with no leader arm — useful for
checking servo IDs, joint directions and calibration in isolation:

```bash
python keyboard_teleop.py --port /dev/ttyACM1 --id follower_arm --step 0.5
```

### A units caveat worth knowing

Both arms default to `use_degrees=True`, so the five body joints are normalized as
**degrees**, not the `[-100, 100]` range (`so_follower.py:50`, `so_leader.py:42`); only the
gripper is `RANGE_0_100`. This matters for reading the numbers: the `wrist_flex` value of
105.98 recorded in the notes is not necessarily out of range under this default, and
`keyboard_teleop.py`'s `[-100, 100]` clamp will truncate legitimate travel on a joint whose
range exceeds ±100°. Re-check that clamp before trusting it as a safety limit.
