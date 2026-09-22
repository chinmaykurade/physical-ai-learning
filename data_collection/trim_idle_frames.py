"""trim_idle_frames.py — cut the operator's settling pause off the head of every episode.

THE BUG THIS EXISTS FOR (notes/learnings.md, L1). Every demonstration in
so101_cube_to_bowl_50 opens with the arm standing still while the operator settles
their hand on the leader — median 34 frames, 1.1 s. ACT learns that pause, and under
action chunking it becomes an ABSORBING STATE: with n_action_steps=20 the rollout
executes 0.67 s of a 1.13 s pause, the arm does not move, so the observation does not
change, so the next chunk prescribes the identical pause. Forever.

The fix is in the data. For each episode, find the frame where motion actually starts
and drop everything before it (less a small margin, so the policy still sees "arm at
rest, move NOW" rather than "arm already mid-reach").

    onset = first frame where max|action - observation.state[0]| > THRESHOLD
    trim  = max(0, onset - MARGIN)

PER-EPISODE, NEVER A FIXED OFFSET. At least one of the 50 episodes starts moving on
frame 0; a global offset would eat the first real motion of that demonstration.

THE TAIL IS LEFT ALONE. Stillness after the cube lands is the policy learning to stop,
which is wanted. Only the head is idle-by-accident.

    The original dataset is never touched. It is the published D3 artifact; this writes
    a NEW dataset and the source is opened read-only.

FORMAT NOTES — v3.0 concatenates all 50 episodes into one shared parquet and one shared
mp4 per camera, with frame ranges, per-episode metadata and dataset stats all pointing
into them. Hand-editing any one of those desynchronises the rest, so this rebuilds
through the authoring API (create → add_frame → save_episode → finalize), which
recomputes every one of them. Two traps live in that path:

  * `add_frame` validates against the DECLARED feature shape, which is HWC (480,640,3),
    but `__getitem__` hands back video as CHW. A CHW array is rejected by
    `validate_feature_image_or_video` (lerobot/datasets/feature_utils.py) — it unpacks
    the declared shape as `c, h, w`, so for an HWC declaration the accepted forms are
    (480,640,3) and (640,3,480), and (3,480,640) is neither. Hence the permute. And
    `return_uint8=True` on the reader, so frames make the round trip as uint8 instead of
    float32-in-[0,1] scaled back up by the image writer.
  * `streaming_encoding=True` (what record_episodes.sh uses live) DROPS FRAMES when the
    encoder queue fills. That is the right trade at 30 fps against a real camera and the
    wrong one here, where frames arrive as fast as the decoder can produce them. This
    writes PNGs and encodes per episode instead: slower, and it cannot silently lose a
    frame.

Frames are re-encoded, so the video goes through one extra AV1 generation (crf 30, the
same encoder settings as the source — `verify` diffs them). Visually indistinguishable
at this crf; worth knowing it is not a bit-exact copy.

Nothing here touches the Hub. `push_to_hub` is not a parameter of the authoring API —
publication is a separate, deliberate step (data_collection/push_dataset.sh).

Invoked by trim_dataset.sh; the arguments come from that file's CONFIG.
"""

import argparse
import sys
import time
from pathlib import Path

import numpy as np
import pyarrow.parquet as pq

from lerobot.datasets.lerobot_dataset import LeRobotDataset
from lerobot.utils.constants import DEFAULT_FEATURES

# Thresholds shown by `profile`, in degrees. 2.0 is the default build threshold:
# comfortably above servo read noise (~0.1 deg) and well below a deliberate motion.
PROFILE_THRESHOLDS = (0.5, 1.0, 2.0, 5.0, 10.0)


def episode_bounds(meta) -> list[tuple[int, int]]:
    """(from, to) absolute frame index per episode, in episode order."""
    eps = meta.episodes
    return [
        (int(eps[i]["dataset_from_index"]), int(eps[i]["dataset_to_index"]))
        for i in range(meta.total_episodes)
    ]


def load_trajectories(root: Path, meta) -> tuple[np.ndarray, np.ndarray]:
    """action and observation.state for the whole dataset, straight from the parquet.

    Read directly rather than through __getitem__: the onset only depends on the joint
    columns, and decoding 36k video frames to find out where the arm starts moving would
    be absurd.
    """
    paths = sorted((root / "data").rglob("*.parquet"))
    if not paths:
        raise FileNotFoundError(f"no data parquet under {root / 'data'}")
    table = pq.read_table(paths, columns=["action", "observation.state", "index"])
    order = np.argsort(np.asarray(table["index"]))
    action = np.stack(table["action"].to_pylist()).astype(np.float32)[order]
    state = np.stack(table["observation.state"].to_pylist()).astype(np.float32)[order]
    if len(action) != meta.total_frames:
        raise ValueError(f"parquet has {len(action)} frames, info.json says {meta.total_frames}")
    return action, state


def motion_onsets(action: np.ndarray, state: np.ndarray, bounds, threshold: float) -> np.ndarray:
    """Per-episode index of the first frame that commands `threshold` deg of motion.

    Measured against the episode's OWN starting pose, not a global home position — each
    demonstration starts from wherever the previous one left the arm.

    Returns 0 for an episode that is already moving on frame 0 (nothing to trim) and the
    episode length for one that never moves, which would be a dead demonstration and is
    reported rather than silently trimmed away.
    """
    onsets = np.empty(len(bounds), dtype=np.int64)
    for e, (f0, f1) in enumerate(bounds):
        travel = np.abs(action[f0:f1] - state[f0]).max(axis=1)
        moved = np.flatnonzero(travel > threshold)
        onsets[e] = moved[0] if moved.size else (f1 - f0)
    return onsets


def summarise(onsets: np.ndarray, lengths: np.ndarray, total_frames: int) -> str:
    return (
        f"median {np.median(onsets):>6.1f}  mean {onsets.mean():>6.1f}  "
        f"min {onsets.min():>3d}  max {onsets.max():>3d}  "
        f"cut {onsets.sum():>6d}  ({100 * onsets.sum() / total_frames:>4.1f}% of frames)"
    )


def print_profile(action, state, bounds, lengths, total_frames) -> None:
    print("Leading idle frames per episode, by motion threshold")
    print("  onset = first frame with max|action - state_at_frame_0| > threshold\n")
    print(f"{'threshold':>10} {'median':>8} {'mean':>8} {'min':>5} {'max':>5} "
          f"{'frames cut':>11} {'% of data':>10}")
    print("-" * 62)
    for thr in PROFILE_THRESHOLDS:
        o = motion_onsets(action, state, bounds, thr)
        print(f"{thr:>9.1f}° {np.median(o):>8.1f} {o.mean():>8.1f} {o.min():>5d} "
              f"{o.max():>5d} {o.sum():>11d} {100 * o.sum() / total_frames:>9.1f}%")
    print("\n  min = 0 on any row means at least one episode starts moving immediately.")
    print("  That is why the trim is per-episode and never a fixed offset.")


def build(src: LeRobotDataset, dst_repo_id: str, dst_root: Path, trims: np.ndarray,
          bounds, progress_every: int = 1) -> LeRobotDataset:
    meta = src.meta
    features = {k: v for k, v in meta.features.items() if k not in DEFAULT_FEATURES}
    video_keys = list(meta.video_keys)

    print(f"\ncreating {dst_root}")
    print(f"  features   {', '.join(features)}")
    print(f"  fps {meta.fps}  robot_type {meta.robot_type}  "
          f"encoder settings inherited from lerobot defaults (verified after build)\n")

    dst = LeRobotDataset.create(
        repo_id=dst_repo_id,
        fps=meta.fps,
        features=features,
        root=dst_root,
        robot_type=meta.robot_type,
        use_videos=True,
        # PNG-then-encode, NOT streaming: the streaming encoder drops frames when its
        # queue fills, and here frames arrive far faster than real time.
        streaming_encoding=False,
        image_writer_processes=0,
        image_writer_threads=4 * max(len(video_keys), 1),
        data_files_size_in_mb=meta.info.get("data_files_size_in_mb"),
        video_files_size_in_mb=meta.info.get("video_files_size_in_mb"),
    )

    t_start = time.time()
    written = 0
    for e, (f0, f1) in enumerate(bounds):
        start = f0 + int(trims[e])
        for i in range(start, f1):
            item = src[i]
            frame = {"task": item["task"]}
            for key in features:
                value = item[key]
                if key in video_keys:
                    # CHW uint8 -> HWC uint8. See the module docstring: the declared
                    # feature shape is HWC and validate_frame rejects CHW against it.
                    value = value.permute(1, 2, 0).contiguous()
                frame[key] = value.numpy()
            dst.add_frame(frame)
            written += 1
        dst.save_episode()
        if (e + 1) % progress_every == 0 or e + 1 == len(bounds):
            kept, dropped = f1 - start, int(trims[e])
            elapsed = time.time() - t_start
            eta = elapsed / (e + 1) * (len(bounds) - e - 1)
            print(f"  ep {e:>3d}  -{dropped:>3d} frames  kept {kept:>4d}  "
                  f"[{written:>6d} written, {elapsed / 60:>5.1f} min, ETA {eta / 60:>5.1f} min]")

    dst.finalize()
    print(f"\nfinalized: {written} frames in {len(bounds)} episodes, "
          f"{(time.time() - t_start) / 60:.1f} min")
    return dst


def verify(src_root: Path, dst_root: Path, src_repo_id: str, dst_repo_id: str,
           trims: np.ndarray, src_bounds, threshold: float, margin: int) -> bool:
    """Reload both datasets and check the trim did what it claims.

    This is the part worth not skipping: a rebuild that silently drops or misaligns a
    frame produces a dataset that trains fine and behaves wrong.
    """
    print("\n" + "=" * 70)
    print("VERIFY")
    print("=" * 70)

    src = LeRobotDataset(src_repo_id, root=src_root, return_uint8=True)
    dst = LeRobotDataset(dst_repo_id, root=dst_root, return_uint8=True)
    ok = True

    def check(label: str, passed: bool, detail: str = "") -> None:
        nonlocal ok
        ok = ok and passed
        print(f"  [{'ok ' if passed else 'FAIL'}] {label}{'  ' + detail if detail else ''}")

    sb, db = src_bounds, episode_bounds(dst.meta)
    src_frames = sum(b - a for a, b in sb)
    check("episode count preserved",
          dst.meta.total_episodes == len(sb),
          f"{len(sb)} -> {dst.meta.total_episodes}")
    check("frame count matches the trim plan",
          dst.meta.total_frames == src_frames - int(trims.sum()),
          f"{src_frames} - {int(trims.sum())} = {dst.meta.total_frames}")
    check("feature schema unchanged",
          set(dst.meta.features) == set(src.meta.features))
    check("fps unchanged", dst.meta.fps == src.meta.fps)

    # Encoder settings: the trimmed videos should be the same codec/quality as the
    # source, or "same dataset minus the pause" is not an honest description of it.
    for key in src.meta.video_keys:
        s = {k: v for k, v in src.meta.features[key]["info"].items() if k.startswith("video.")}
        d = {k: v for k, v in dst.meta.features[key]["info"].items() if k.startswith("video.")}
        diff = {k: (s.get(k), d.get(k)) for k in set(s) | set(d) if s.get(k) != d.get(k)}
        check(f"{key}: encoder settings match source", not diff, str(diff) if diff else "")

    # Per-episode alignment. Episode e of the new dataset must start exactly at frame
    # trims[e] of episode e of the old one, and run to the same end.
    bad_len, bad_state, bad_action, bad_task = [], [], [], []
    for e, ((sf0, sf1), (df0, df1)) in enumerate(zip(sb, db, strict=True)):
        if (df1 - df0) != (sf1 - sf0 - int(trims[e])):
            bad_len.append(e)
            continue
        s_item, d_item = src[sf0 + int(trims[e])], dst[df0]
        if not np.array_equal(s_item["observation.state"].numpy(), d_item["observation.state"].numpy()):
            bad_state.append(e)
        if not np.array_equal(s_item["action"].numpy(), d_item["action"].numpy()):
            bad_action.append(e)
        if s_item["task"] != d_item["task"]:
            bad_task.append(e)

    check("episode lengths match the per-episode trim", not bad_len, f"bad: {bad_len}")
    check("frame 0 state == source frame at the trim point", not bad_state, f"bad: {bad_state}")
    check("frame 0 action == source frame at the trim point", not bad_action, f"bad: {bad_action}")
    check("task string preserved", not bad_task, f"bad: {bad_task}")

    # The last frame of every episode must be untouched — the tail is deliberately kept.
    bad_tail = [
        e for e, ((_, sf1), (_, df1)) in enumerate(zip(sb, db, strict=True))
        if not np.array_equal(src[sf1 - 1]["action"].numpy(), dst[df1 - 1]["action"].numpy())
    ]
    check("last frame of each episode unchanged (tail not trimmed)", not bad_tail, f"bad: {bad_tail}")

    # Video decodes and is aligned. Re-encoding is lossy, so compare statistically:
    # a misaligned or shifted stream shows up as a large mean absolute difference,
    # while an extra AV1 generation at crf 30 stays in the low single digits per pixel.
    worst = 0.0
    for e in range(0, dst.meta.total_episodes, max(1, dst.meta.total_episodes // 5)):
        s_item, d_item = src[sb[e][0] + int(trims[e])], dst[db[e][0]]
        for key in src.meta.video_keys:
            a = s_item[key].numpy().astype(np.float32)
            b = d_item[key].numpy().astype(np.float32)
            if a.shape != b.shape:
                check(f"ep {e} {key}: frame shape", False, f"{a.shape} vs {b.shape}")
                continue
            worst = max(worst, float(np.abs(a - b).mean()))
    check("video frame 0 matches the source frame it came from",
          worst < 8.0, f"worst mean |Δpixel| across sampled episodes: {worst:.2f}/255")

    # And the thing the whole exercise is for: the pause should be gone.
    action, state = load_trajectories(dst_root, dst.meta)
    onsets = motion_onsets(action, state, db, threshold)
    print(f"\n  Residual idle frames at {threshold:.1f}° in the TRIMMED dataset:")
    lengths = np.array([b - a for a, b in db])
    print(f"    {summarise(onsets, lengths, dst.meta.total_frames)}")
    print(f"    (expected ~{margin} — the margin deliberately left in front of the onset)")
    check("residual pause is at most the margin plus a frame",
          int(onsets.max()) <= margin + 1,
          f"max residual {int(onsets.max())} frames vs margin {margin}")

    print("\n" + ("VERIFY PASSED" if ok else "VERIFY FAILED"))
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src-repo-id", required=True)
    ap.add_argument("--src-root", required=True, type=Path)
    ap.add_argument("--dst-repo-id")
    ap.add_argument("--dst-root", type=Path)
    ap.add_argument("--threshold", type=float, default=2.0,
                    help="degrees of commanded travel that counts as motion (default 2.0)")
    ap.add_argument("--margin", type=int, default=3,
                    help="frames kept in front of the onset so each episode still opens "
                         "from a static pose (default 3)")
    ap.add_argument("--mode", choices=("profile", "build", "verify"), default="profile")
    ap.add_argument("--episodes", type=int, default=0, metavar="N",
                    help="only process the first N episodes — for a smoke run of the "
                         "pipeline, not for a dataset anyone trains on (default: all)")
    args = ap.parse_args()

    if args.mode in ("build", "verify") and not (args.dst_repo_id and args.dst_root):
        ap.error("--dst-repo-id and --dst-root are required for build and verify")

    src = LeRobotDataset(args.src_repo_id, root=args.src_root, return_uint8=True)
    meta = src.meta
    bounds = episode_bounds(meta)
    action, state = load_trajectories(args.src_root, meta)

    print(f"source  {args.src_root}")
    print(f"        {meta.total_episodes} episodes, {meta.total_frames} frames, "
          f"{meta.fps} fps, lengths "
          f"{min(b - a for a, b in bounds)}–{max(b - a for a, b in bounds)}\n")

    if args.episodes:
        bounds = bounds[: args.episodes]
        print(f"        SMOKE RUN: first {len(bounds)} episodes only\n")
    lengths = np.array([b - a for a, b in bounds])
    total_frames = int(lengths.sum())

    if args.mode == "profile":
        print_profile(action, state, bounds, lengths, total_frames)
        return 0

    onsets = motion_onsets(action, state, bounds, args.threshold)
    if (onsets >= lengths).any():
        dead = np.flatnonzero(onsets >= lengths).tolist()
        print(f"error: episodes {dead} never move {args.threshold}° from their start pose. "
              f"Trimming them would delete the whole demonstration.", file=sys.stderr)
        return 1
    trims = np.maximum(onsets - args.margin, 0)

    print(f"trim plan  threshold {args.threshold}°  margin {args.margin} frames")
    print(f"  onsets   {summarise(onsets, lengths, total_frames)}")
    print(f"  trims    {summarise(trims, lengths, total_frames)}")
    print(f"  kept     {total_frames - int(trims.sum())} of {total_frames} frames "
          f"in {len(bounds)} episodes")
    zero = int((trims == 0).sum())
    if zero:
        print(f"  {zero} episode(s) trimmed by 0 frames — already moving at the start")

    if args.mode == "build":
        if args.dst_root.exists():
            print(f"\nerror: {args.dst_root} already exists. lerobot refuses to write into an "
                  f"existing dataset root; move it aside or pick another name.", file=sys.stderr)
            return 1
        build(src, args.dst_repo_id, args.dst_root, trims, bounds)

    return 0 if verify(args.src_root, args.dst_root, args.src_repo_id, args.dst_repo_id,
                       trims, bounds, args.threshold, args.margin) else 1


if __name__ == "__main__":
    raise SystemExit(main())
