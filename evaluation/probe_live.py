"""probe_live.py — what does the policy actually command, right now, on this arm?

Read ONE live observation (both cameras + all six joints), run the policy on it,
and print the commanded goal next to the present position. NOTHING IS SENT TO THE
MOTORS — the arm does not move, and this is safe to run with the workspace as-is.

It answers the one question `dry` cannot: when the arm sits still, is the policy
commanding it to sit still, or is it commanding motion that never arrives?

    |delta| ~ 0 on every joint      the policy wants to stay put. The observation
                                    is out of distribution — almost always camera
                                    framing or lighting drift from the recording
                                    setup (plan risk R4). Compare the saved frames
                                    against the dataset.
    |delta| large, arm still        the policy is fine and the command is not
                                    reaching the motors. Bus, power, or torque.

It also prints the CHUNK PROFILE: how far the commanded position has moved away
from the arm's current pose by step k of the chunk. A chunk is only executed up
to step N, so N decides how much of that motion ever reaches the arm.

READ IT AGAINST THE RIGHT REFERENCE. The 50 recorded demos each open with the
operator sitting still — median 40 frames, 1.33 s, before the arm first moves
10 deg. The policy learned that pause faithfully, so a chunk predicted AT THE
START POSE is flat for ~30 steps and only then ramps. A chunk predicted mid-reach
climbs immediately. Both profiles are printed below; compare against the one
matching the pose the arm is actually in.

This is why n_action_steps below ~40 deadlocks at the start of a rollout: the arm
only ever executes the pause, so the observation never changes, so the next chunk
prescribes the same pause. Nothing is wrong with the policy — it is reproducing
the idle time in the demonstrations.

Run it with the arm in a few different poses — start pose, mid-reach, near the
cube. A policy that outputs the same goal regardless of where the arm is has
collapsed to the dataset mean and the observation is not informing it at all.

Invoked by `run_policy.sh probe`; the arguments come from that file's CONFIG.
"""

import argparse
import numpy as np
import torch

from lerobot.cameras.opencv.configuration_opencv import OpenCVCameraConfig
from lerobot.configs.policies import PreTrainedConfig
from lerobot.policies.factory import make_policy, make_pre_post_processors
from lerobot.datasets.lerobot_dataset import LeRobotDatasetMetadata
from lerobot.robots.so_follower.config_so_follower import SOFollowerRobotConfig
from lerobot.robots.so_follower.so_follower import SOFollower


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--policy-path", required=True)
    ap.add_argument("--port", required=True)
    ap.add_argument("--robot-id", required=True)
    ap.add_argument("--camera", action="append", default=[], metavar="NAME=DEVICE")
    ap.add_argument("--width", type=int, default=640)
    ap.add_argument("--height", type=int, default=480)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--dataset-root", required=True)
    ap.add_argument("--repo-id", required=True)
    ap.add_argument("--task", default="")
    ap.add_argument("--samples", type=int, default=5,
                    help="consecutive observations to probe; the arm is static, so "
                         "the spread across them is the policy's own jitter")
    ap.add_argument("--save-frames", metavar="DIR",
                    help="write the camera frames here to eyeball against the dataset")
    args = ap.parse_args()

    cams = {}
    for spec in args.camera:
        name, dev = spec.split("=", 1)
        cams[name] = OpenCVCameraConfig(index_or_path=dev, fps=args.fps,
                                        width=args.width, height=args.height)

    meta = LeRobotDatasetMetadata(args.repo_id, root=args.dataset_root)
    cfg = PreTrainedConfig.from_pretrained(args.policy_path)
    cfg.pretrained_path = args.policy_path
    policy = make_policy(cfg, ds_meta=meta).eval()
    pre, post = make_pre_post_processors(cfg, pretrained_path=args.policy_path,
                                         dataset_stats=meta.stats)
    print(f"policy      {args.policy_path}")
    print(f"            chunk_size={cfg.chunk_size} n_action_steps={cfg.n_action_steps}\n")

    robot = SOFollower(SOFollowerRobotConfig(
        port=args.port, id=args.robot_id, cameras=cams))
    robot.connect()
    try:
        joints = [f"{m}.pos" for m in robot.bus.motors]
        rows = []
        for i in range(args.samples):
            obs = robot.get_observation()
            state = np.array([obs[j] for j in joints], dtype=np.float32)
            batch = {"observation.state": torch.from_numpy(state), "task": args.task}
            for name in cams:
                img = obs[name]
                batch[f"observation.images.{name}"] = (
                    torch.from_numpy(img).permute(2, 0, 1).float() / 255.0)
                if args.save_frames and i == 0:
                    import imageio.v3 as iio
                    from pathlib import Path
                    Path(args.save_frames).mkdir(parents=True, exist_ok=True)
                    iio.imwrite(f"{args.save_frames}/{name}.png", img)

            policy.reset(); pre.reset(); post.reset()
            with torch.inference_mode():
                chunk = post(policy.predict_action_chunk(pre(batch)))
            chunk = chunk.squeeze(0).float().cpu().numpy()
            rows.append((state, chunk[0], chunk))

        state, goal, chunk = rows[-1]
        spread = np.array([g for _, g, _ in rows]).std(axis=0)
        print(f"{'joint':<18} {'present':>9} {'commanded':>10} {'delta':>9} {'jitter':>8}")
        print("-" * 58)
        for k, j in enumerate(joints):
            print(f"{j:<18} {state[k]:>9.2f} {goal[k]:>10.2f} "
                  f"{goal[k] - state[k]:>+9.2f} {spread[k]:>8.3f}")

        d = np.abs(goal - state)
        print("-" * 58)
        print(f"max |delta| {d.max():.2f}   mean |delta| {d.mean():.2f}")

        # The profile. n_action_steps=N executes the chunk only up to step N, so
        # the row at k=N is the largest position error the servo is ever asked for
        # before the next observation re-anchors the whole thing back to `state`.
        # Measured on this dataset with checkpoint 100000. The start column is the
        # one to use when the arm is parked at its home pose.
        REF_START = {1: 1.5, 5: 1.4, 10: 1.5, 20: 1.5, 30: 3.3, 50: 32.9, 70: 100.5, 100: 140.7}
        REF_MID = {1: 6.3, 5: 10.4, 10: 17.9, 20: 31.8, 30: 41.8, 50: 55.9, 70: 72.2, 100: 86.9}
        print("\n\nChunk profile — commanded position error vs the arm's CURRENT pose")
        print("Training reference in the last two columns: a chunk predicted at an")
        print("episode START (flat, then ramps after the ~1.3 s demo pause) and one")
        print("predicted MID-REACH (climbs immediately).\n")
        print(f"{'k':>5} {'time':>8} {'live':>9} {'ref start':>11} {'ref mid':>9}")
        print("-" * 46)
        for k in (1, 5, 10, 20, 30, 50, 70, 100):
            if k <= chunk.shape[0]:
                print(f"{k:>5} {k / args.fps:>7.2f}s "
                      f"{np.abs(chunk[k - 1] - state).max():>9.2f} "
                      f"{REF_START[k]:>11.1f} {REF_MID[k]:>9.1f}")

        # The deadlock check: if the chunk is still flat at step N, a rollout at
        # that N can never move, and never will, because the observation is frozen.
        flat_until = 0
        for k in range(1, chunk.shape[0] + 1):
            if np.abs(chunk[k - 1] - state).max() < 10.0:
                flat_until = k
            else:
                break
        print(f"\n  chunk stays within 10 deg of the current pose until step "
              f"{flat_until} ({flat_until / args.fps:.2f}s)")
        print(f"  -> n_action_steps must exceed {flat_until} or the rollout deadlocks here")

        # The physical floor. A commanded error below this simply does not move a
        # gravity-loaded joint, no matter how correct the policy is.
        print("\n\nServo motion thresholds (raw units; lerobot's configure() lowers P to 16)")
        print(f"{'motor':<16} {'P_Coef':>7} {'MinStartF':>10} {'CW_dead':>8} {'CCW_dead':>9}")
        print("-" * 54)
        for m in robot.bus.motors:
            vals = []
            for reg in ("P_Coefficient", "Minimum_Startup_Force", "CW_Dead_Zone", "CCW_Dead_Zone"):
                try:
                    vals.append(str(robot.bus.read(reg, m, normalize=False)))
                except Exception as e:  # noqa: BLE001 - diagnostic only
                    vals.append(f"?({type(e).__name__})")
            print(f"{m:<16} {vals[0]:>7} {vals[1]:>10} {vals[2]:>8} {vals[3]:>9}")

        print()
        if d.max() < 1.0:
            print("VERDICT: the policy is commanding the arm to stay where it is.")
            print("  Not a chunking problem. The observation is out of distribution —")
            print("  check camera framing and lighting against the recorded episodes.")
            if args.save_frames:
                print(f"  Frames written to {args.save_frames}/ — compare them to the dataset.")
        elif flat_until >= 20:
            print(f"VERDICT: the chunk prescribes {flat_until / args.fps:.2f}s of holding still")
            print("  before it moves — the learned copy of the pause at the head of every")
            print("  demonstration. Any n_action_steps at or below "
                  f"{flat_until} deadlocks: the arm")
            print("  executes only the pause, the observation never changes, and the next")
            print("  chunk prescribes the same pause. The policy is not broken.")
            print("  Fix the data (trim the idle frames and retrain), or keep N above it.")
        else:
            print(f"VERDICT: step 0 commands {d.max():.1f} deg and the chunk ramps by step "
                  f"{flat_until + 1}.")
            print("  Nothing here blocks a short n_action_steps. If the arm still does not")
            print("  move, the command is not reaching the motors: 12 V rail, bus, torque.")
    finally:
        robot.disconnect()


if __name__ == "__main__":
    main()
