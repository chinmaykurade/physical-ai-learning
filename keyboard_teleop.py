#!/usr/bin/env python3
"""
Joint-space keyboard teleoperation for an SO-101 follower arm (LeRobot 0.6.0).

Moves one joint at a time by nudging a target position that is sent to the arm
every control tick. No URDF, no IK, no leader arm required -- this is the
minimum viable way to drive the follower and sanity-check servo IDs, joint
directions, and calibration before the leader is wired up.

Prerequisite: calibrate the arm first, or connect() will prompt for it.

    python -m lerobot.calibrate --robot.type=so101_follower \
                                --robot.port=/dev/ttyACM1 \
                                --robot.id=follower_arm

Usage:

    python keyboard_teleop.py --port /dev/ttyACM1 --id follower_arm --step 0.5

Keys:

    q/a   shoulder_pan    -/+          [ ]    step size down / up
    w/s   shoulder_lift   -/+          SPACE  re-sync target to measured pos
    e/d   elbow_flex      -/+          ESC    quit (torque disabled on exit)
    r/f   wrist_flex      -/+
    t/g   wrist_roll      -/+
    y/h   gripper         -/+

Safety: keep a hand near the barrel jack. Start with a small step size and a
clear workspace. 30 kg-cm will happily crush a finger.

If a joint stops responding, check the error column. A servo driven into a
mechanical stop trips a *latched* overload flag and ignores commands until
power is cycled -- restarting this script will not clear it. Start from a
neutral pose so the weight-bearing joints (elbow_flex, wrist_flex) have
headroom in both directions.
"""

import argparse
import curses
import time

from lerobot.robots.so_follower import SO101Follower, SO101FollowerConfig

# key -> (motor, direction)
KEYMAP = {
    "q": ("shoulder_pan", -1),
    "a": ("shoulder_pan", +1),
    "w": ("shoulder_lift", -1),
    "s": ("shoulder_lift", +1),
    "e": ("elbow_flex", -1),
    "d": ("elbow_flex", +1),
    "r": ("wrist_flex", -1),
    "f": ("wrist_flex", +1),
    "t": ("wrist_roll", -1),
    "g": ("wrist_roll", +1),
    "y": ("gripper", -1),
    "h": ("gripper", +1),
}

# LeRobot's normalized calibration range: joints [-100, 100], gripper [0, 100].
LIMITS = {"gripper": (0.0, 100.0)}
DEFAULT_LIMIT = (-100.0, 100.0)


def clamp(motor: str, value: float) -> float:
    lo, hi = LIMITS.get(motor, DEFAULT_LIMIT)
    return max(lo, min(hi, value))


def read_targets(robot) -> dict[str, float]:
    """Snapshot the arm's measured joint positions as {'<motor>.pos': value}.

    Clamped on the way in: a miscalibrated joint can measure outside its
    normalized range (e.g. wrist_flex reading 105.98), and seeding an
    out-of-range target would command the servo into a mechanical stop.
    """
    obs = robot.get_observation()
    return {
        k: clamp(k.removesuffix(".pos"), float(v))
        for k, v in obs.items()
        if k.endswith(".pos")
    }


def loop(stdscr, robot, step: float, fps: float) -> None:
    curses.curs_set(0)
    stdscr.nodelay(True)

    target = read_targets(robot)
    if not target:
        raise RuntimeError("No '.pos' keys in observation -- is the arm connected?")

    period = 1.0 / fps
    last_key = ""

    while True:
        tick = time.perf_counter()

        # Drain every key buffered since the last tick so held keys accumulate.
        ch = stdscr.getch()
        while ch != -1:
            if ch == 27:  # ESC
                return
            key = chr(ch).lower() if 0 <= ch < 256 else ""
            last_key = key
            if key in KEYMAP:
                motor, direction = KEYMAP[key]
                name = f"{motor}.pos"
                if name in target:
                    target[name] = clamp(motor, target[name] + direction * step)
            elif key == "[":
                step = max(0.1, step - 0.1)
            elif key == "]":
                step = min(10.0, step + 0.1)
            elif key == " ":
                target = read_targets(robot)
            ch = stdscr.getch()

        robot.send_action(dict(target))

        # Raw, unclamped -- so a joint reading outside its range stays visible.
        obs = robot.get_observation()
        measured = {k: float(v) for k, v in obs.items() if k.endswith(".pos")}
        stdscr.erase()
        stdscr.addstr(0, 0, f"SO-101 keyboard teleop   step={step:.1f}   last='{last_key}'")
        stdscr.addstr(1, 0, "-" * 58)
        stdscr.addstr(2, 0, f"{'motor':<16}{'target':>10}{'measured':>12}{'error':>10}")
        for row, name in enumerate(sorted(target), start=3):
            tgt = target[name]
            mes = measured.get(name, float("nan"))
            stdscr.addstr(
                row, 0, f"{name.removesuffix('.pos'):<16}{tgt:>10.2f}{mes:>12.2f}{tgt - mes:>10.2f}"
            )
        stdscr.addstr(row + 2, 0, "q/a w/s e/d r/f t/g y/h move  |  [ ] step  |  SPACE resync  |  ESC quit")
        stdscr.refresh()

        sleep = period - (time.perf_counter() - tick)
        if sleep > 0:
            time.sleep(sleep)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="e.g. /dev/ttyACM0")
    parser.add_argument("--id", required=True, help="robot id used for the calibration file")
    parser.add_argument("--step", type=float, default=1.0, help="degrees per keypress")
    parser.add_argument("--fps", type=float, default=30.0, help="control loop rate")
    args = parser.parse_args()

    robot = SO101Follower(SO101FollowerConfig(port=args.port, id=args.id))
    robot.connect()
    try:
        curses.wrapper(loop, robot, args.step, args.fps)
    except KeyboardInterrupt:
        pass
    finally:
        # A latched servo fault (e.g. "Overload error!") makes disconnect() raise
        # *before* it disables torque. Swallowing that would hide the one thing
        # worth knowing, so say it loudly: the motors are still energized and
        # only a power cycle clears the latch.
        try:
            robot.disconnect()
        except Exception as exc:
            print(f"\n!!! DISCONNECT FAILED: {exc}")
            print("!!! TORQUE MAY STILL BE ON -- cut power at the barrel jack,")
            print("!!! supporting the arm so it does not drop.")
        else:
            print("Disconnected, torque off.")


if __name__ == "__main__":
    main()