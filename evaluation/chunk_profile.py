"""chunk_profile.py — does the policy's action chunk RAMP, or does it sit flat?

The offline half of probe_live.py. Same measurement, no hardware: feed the policy a
recorded observation and ask how far the commanded position has travelled from the arm's
pose by step k of the chunk.

    reach(k)  = max_joint | chunk[k-1] - observation.state |   in degrees
    travel(k) = max_joint | chunk[k-1] - chunk[0]          |   in degrees

`reach` is what the servo is asked to close, and is the number probe_live.py prints on
live hardware. `travel` is how far the chunk moves away from its OWN first command.
Both are here because `reach` carries a constant the deadlock argument does not:
`action` is the leader arm's pose and `observation.state` is the follower's, and the
follower lags under load, so |action - state| sits at several degrees on some episodes
even with everything motionless. That standing offset makes a flat chunk look less flat
than it is. `travel` starts at exactly 0 by construction and only grows when the policy
actually prescribes motion, so it is the one to read for "does this chunk go anywhere".

WHY THIS IS THE TEST THAT MATTERS. `n_action_steps = N` executes the chunk only up to
step N and then re-queries the cameras. If the chunk is still FLAT at step N — the arm
has not been asked to go anywhere — then the arm does not move, the observation does not
change, and the next chunk is the same chunk. The rollout deadlocks. That is not a
hypothetical: it is exactly what the first cube-to-bowl policy did below N≈40, because
every demonstration opened with a 1.1 s pause that ACT learned faithfully
(notes/learnings.md, L1).

    old policy, at frame 0 of episode 0, `reach`:
        k=1  6.43°   k=20  6.45°   k=30  6.60°   k=50  11.50°   k=70  62.48°
                     ^^^^ a second and a half of commanded stillness

MEASURE AT THE RIGHT POSE. The profile is a function of the observation, and a chunk
predicted at an episode START behaves nothing like one predicted MID-REACH. Comparing
the two is what sent the original debugging session after the wrong root cause. `--at`
picks which, and `both` prints them side by side.

The recorded demonstration is profiled alongside the policy, from the same frame, using
the dataset's own actions. That column is the ground truth the policy is imitating: if
the policy is flat and the demo is flat, the policy is right and the DATA is the problem.
If the policy is flat and the demo ramps, the policy is the problem.

Used as the acceptance test for the idle-frame trim (data_collection/trim_dataset.sh):
run it against the retrained checkpoint and the trimmed dataset, and the start-pose
profile should climb from k=1 with no flat region.

    PASS  chunk clears the 10° deadlock threshold within a few steps
    FAIL  still flat through k=20 -> the trim threshold was too low, or the margin too
          generous. Rebuild the dataset before spending another night training.

It also prints the REF_START / REF_MID blocks to paste into probe_live.py, whose
constants are stale the moment a new checkpoint exists.
"""

import argparse
from pathlib import Path

import numpy as np
import torch

from lerobot.configs.policies import PreTrainedConfig
from lerobot.datasets.lerobot_dataset import LeRobotDataset
from lerobot.policies.factory import make_policy, make_pre_post_processors

# The k values probe_live.py reports. Kept identical so the two tools' tables can be
# read against each other line for line.
PROFILE_K = (1, 5, 10, 20, 30, 50, 70, 100)

# A commanded error below this does not reliably move a gravity-loaded STS3215 joint,
# and is the threshold probe_live.py uses to call a chunk "flat".
DEADLOCK_DEG = 10.0


def build_batch(item: dict, video_keys, task: str) -> dict:
    """One dataset frame in the shape the policy's preprocessor expects.

    The dataset already hands back video as float32 CHW in [0,1], which is what
    probe_live.py constructs by hand from the live camera (permute + /255). Same tensor,
    same scale — the two tools are measuring the same function.
    """
    batch = {"observation.state": item["observation.state"], "task": task}
    for key in video_keys:
        batch[key] = item[key]
    return batch


def policy_chunk(policy, pre, post, batch: dict) -> np.ndarray:
    policy.reset()
    pre.reset()
    post.reset()
    with torch.inference_mode():
        chunk = post(policy.predict_action_chunk(pre(batch)))
    return chunk.squeeze(0).float().cpu().numpy()


def flat_until(profile: np.ndarray, threshold: float = DEADLOCK_DEG) -> int:
    """Last step k for which the chunk has still not moved `threshold` degrees.

    Counted from the start and stopping at the first step that clears it — a chunk that
    dips back under later has already moved the arm, so the observation has changed and
    the deadlock argument no longer applies.
    """
    k = 0
    for i, d in enumerate(profile, start=1):
        if d < threshold:
            k = i
        else:
            break
    return k


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--policy-path", required=True)
    ap.add_argument("--repo-id", required=True)
    ap.add_argument("--dataset-root", required=True, type=Path)
    ap.add_argument("--at", choices=("start", "mid", "both"), default="both",
                    help="which frame of each episode to predict from (default both)")
    ap.add_argument("--episodes", type=int, default=10,
                    help="episodes to sample, spread evenly over the dataset (default 10)")
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--fps", type=int, default=30)
    args = ap.parse_args()

    ds = LeRobotDataset(args.repo_id, root=args.dataset_root)
    meta = ds.meta
    video_keys = list(meta.video_keys)
    bounds = [
        (int(meta.episodes[i]["dataset_from_index"]), int(meta.episodes[i]["dataset_to_index"]))
        for i in range(meta.total_episodes)
    ]

    cfg = PreTrainedConfig.from_pretrained(args.policy_path)
    cfg.pretrained_path = args.policy_path
    cfg.device = args.device
    policy = make_policy(cfg, ds_meta=meta).eval()
    pre, post = make_pre_post_processors(cfg, pretrained_path=args.policy_path,
                                         dataset_stats=meta.stats)

    print(f"policy    {args.policy_path}")
    print(f"          chunk_size={cfg.chunk_size} n_action_steps={cfg.n_action_steps} "
          f"device={args.device}")
    print(f"dataset   {args.dataset_root}")
    print(f"          {meta.total_episodes} episodes, {meta.total_frames} frames, {meta.fps} fps")

    step = max(1, meta.total_episodes // args.episodes)
    sampled = list(range(0, meta.total_episodes, step))[: args.episodes]
    print(f"sampling  {len(sampled)} episodes: {sampled}\n")

    modes = ("start", "mid") if args.at == "both" else (args.at,)
    refs: dict[str, dict[int, float]] = {}
    start_worst: int | None = None

    for mode in modes:
        reach_rows, travel_rows, demo_rows, flats = [], [], [], []
        for e in sampled:
            f0, f1 = bounds[e]
            frame = f0 if mode == "start" else f0 + (f1 - f0) // 2
            item = ds[frame]
            state = item["observation.state"].numpy()

            chunk = policy_chunk(policy, pre, post, build_batch(item, video_keys, item["task"]))
            reach_rows.append(np.abs(chunk - state).max(axis=1))
            travel = np.abs(chunk - chunk[0]).max(axis=1)
            travel_rows.append(travel)
            flats.append(flat_until(travel))

            # The demonstration the policy is imitating, from the same frame: the
            # recorded actions' own travel away from their first command. Same
            # definition as `travel`, so the two columns are directly comparable.
            horizon = min(cfg.chunk_size, f1 - frame)
            demo = np.full(cfg.chunk_size, np.nan)
            recorded = np.stack([ds[frame + i]["action"].numpy() for i in range(horizon)])
            demo[:horizon] = np.abs(recorded - recorded[0]).max(axis=1)
            demo_rows.append(demo)

        reach = np.stack(reach_rows).mean(axis=0)
        travel = np.stack(travel_rows).mean(axis=0)
        demo = np.nanmean(np.stack(demo_rows), axis=0)
        refs[mode] = {k: float(reach[k - 1]) for k in PROFILE_K if k <= len(reach)}

        label = "EPISODE START (the pose a rollout begins in)" if mode == "start" \
            else "MID-EPISODE (arm already in motion)"
        print(f"{'=' * 68}\n{label}\n{'=' * 68}")
        print(f"Degrees, mean over {len(sampled)} episodes. `travel` is the one to read:\n"
              f"it starts at 0 and grows only when the chunk prescribes real motion.\n")
        print(f"{'k':>5} {'time':>8} {'reach':>9} | {'travel':>9} {'demo travel':>13} {'diff':>8}")
        print("-" * 60)
        for k in PROFILE_K:
            if k <= len(reach):
                print(f"{k:>5} {k / args.fps:>7.2f}s {reach[k - 1]:>9.2f} | "
                      f"{travel[k - 1]:>9.2f} {demo[k - 1]:>13.2f} "
                      f"{travel[k - 1] - demo[k - 1]:>+8.2f}")

        flats = np.array(flats)
        print(f"\n  chunk travels less than {DEADLOCK_DEG:.0f}° until step "
              f"{flats.mean():.1f} on average "
              f"(min {flats.min()}, max {flats.max()}, {flats.mean() / args.fps:.2f}s)")

        if mode == "start":
            start_worst = worst = int(flats.max())
            print(f"  -> n_action_steps must exceed {worst} on every episode, or a rollout "
                  f"starting from\n     one of these poses can never move.\n")
            if worst >= 20:
                print(f"  FAIL: the chunk prescribes up to {worst / args.fps:.2f}s of holding "
                      f"still at the start of\n        an episode. n_action_steps=20 deadlocks. "
                      f"The demonstrations still\n        contain the pause — raise the trim "
                      f"threshold and rebuild the dataset.")
            else:
                print(f"  PASS: the chunk ramps by step {worst + 1} "
                      f"({(worst + 1) / args.fps:.2f}s). n_action_steps=20 has room.")
            print()

    print("=" * 62)
    print("Paste into evaluation/probe_live.py (its constants are per-checkpoint):")
    for mode, name in (("start", "REF_START"), ("mid", "REF_MID")):
        if mode in refs:
            body = ", ".join(f"{k}: {v:.1f}" for k, v in refs[mode].items())
            print(f"    {name} = {{{body}}}")

    # Non-zero exit when the start-pose chunk is flat past the horizon a rollout would
    # use, so this can gate the retrain in a script instead of being eyeballed.
    return 1 if start_worst is not None and start_worst >= 20 else 0


if __name__ == "__main__":
    raise SystemExit(main())
