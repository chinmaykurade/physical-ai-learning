# Data Collection

Recording demonstrations on the SO-101 rig: the procedure, the gotchas, and
[`record_episodes.sh`](record_episodes.sh), which wraps it so nothing has to be retyped.

Companion to [../calibration/README.md](../calibration/README.md) — a recording is only
interpretable next to the calibration that produced it. Task status lives in
[../docs/progress.md](../docs/progress.md).

Everything here is verified against the pinned `lerobot==0.6.0` in
`/home/chinmay/lerobot-env`, **not** against the online docs, which track `main` and have
already drifted from this release.

---

## The script

```bash
./record_episodes.sh doctor    # USB power/topology audit — run FIRST if anything drops
./record_episodes.sh cameras   # which camera is which — capture sample images
./record_episodes.sh check     # teleop + live view, records nothing. Tape the mounts here
./record_episodes.sh smoke     # 2 throwaway episodes; confirm fps is stable
./record_episodes.sh record    # the real run
./record_episodes.sh resume    # continue an interrupted run
./record_episodes.sh view      # open the recorded dataset in the visualizer
./record_episodes.sh info      # print resolved config + the matching train command
```

Everything configurable sits in the `CONFIG` block at the top of the script — camera names
and devices, arm ports and IDs, task string, episode count and timing, dataset location.
Nothing below that block should need editing.

Every subcommand prints the full `lerobot-*` command before running it, so the script stays
a convenience rather than a black box: copy the line out and run it by hand whenever you
need to vary something the config doesn't cover.

`preflight` refuses to start if a port is missing, a camera device has vanished, or the
calibration for the configured arm ID cannot be resolved — all three are failures that
otherwise surface halfway into a recording session. `check`, `smoke`, `record` and `resume`
additionally run [`doctor`](#usb-stability-read-this-before-the-first-long-run) and make you
confirm before recording onto an unstable bus.

Arms are addressed by `/dev/serial/by-id/` path, not `/dev/ttyACM*` — see below for why.

---

## Procedure

### 1. Identify the cameras

```bash
./record_episodes.sh cameras
```

Captures a sample image per detected camera so you can tell the gripper view from the
workspace view, then set them in `CONFIG`:

```bash
CAMERAS=(
  "top=/dev/v4l/by-id/usb-Sonix_Technology_Co.__Ltd._Lenovo_FHD_Webcam_Audio_SN0001-video-index0"
  "wrist=/dev/v4l/by-id/usb-Arducam_Technology_Co.__Ltd._USB_2.0_Camera_SN0001-video-index0"
)
```

Two rules:

- **Use `/dev/v4l/by-id/` paths, never integer indices.** OpenCV indices renumber across
  reboots and replugs. With two cameras on the bus, an index swap silently relabels your
  wrist stream as the workspace stream and the dataset is quietly wrong.
- **Take the `-video-index0` node.** Each camera exposes two: `index0` is capture, `index1`
  is metadata and will not produce frames.

The name on the left becomes the dataset feature key — `top` → `observation.images.top`.
**Renaming a camera after recording starts creates a new, incompatible feature**, so pick
the names once.

### 2. Frame, then tape

```bash
./record_episodes.sh check
```

Teleoperates with the Rerun viewer up and records nothing. Run the full cube → bowl motion
and confirm:

- **top** sees the cube's entire start zone, the bowl, and the arm at full extension
- **wrist** still sees the cube at the moment of grasp

Then **tape both mounts and do not move them again** — not between episodes, not between
Phase A and Phase B. This is plan risk **R4**: the Phase-B scaling study re-records the same
task at 10/25/50/100 episodes, and a camera that moved in between turns the comparison into
noise.

### 3. Smoke-test

```bash
./record_episodes.sh smoke
```

Two throwaway episodes into a `_smoke` dataset. The thing to watch is the **reported fps** —
it should hold a stable 30. Two cameras double the image-writer load, and an unstable rate
means dropped or unevenly spaced frames in the real run.

If it is unstable, in this order: raise
`--dataset.num_image_writer_threads_per_camera` (default 4), then add
`--dataset.num_image_writer_processes=1`.

### 4. Record

```bash
./record_episodes.sh record
```

| Key | Effect |
|---|---|
| **→** | end the current episode early and move on |
| **←** | discard and re-record the last episode |
| **Esc** | stop the session — the dataset is still finalized cleanly |

**On Wayland, keep the terminal focused, not the Rerun window.** `pynput` cannot register
global hotkeys under Wayland; 0.6.0 falls back to a terminal listener that reads the
controlling TTY, so an unfocused terminal means the keys do nothing at all.

Interrupted? `./record_episodes.sh resume` continues the same dataset.

---

## USB stability — read this before the first long run

**A 45-minute recording session is only as good as the least reliable thing on the USB bus.**
On 2026-09-20 the first `check` run died 6 seconds in with

```
RuntimeError: OpenCVCamera(...Arducam...) read failed (status=False).
[WARN] VIDEOIO(V4L2:...): failed VIDIOC_REQBUFS: errno=19 (No such device)
```

`errno=19` is *No such device*: the camera did not fail to read, it left the bus. `doctor`
found why in one line — a bus-powered hub carrying more current than its upstream port
supplies:

```
1-1   hub, 776mA downstream (hub itself 100mA) — camera:wrist arm:follower arm:leader
```

A USB 2.0 port supplies **500 mA**. The Arducam alone declares 500 mA, and the two servo
adapters add 138 mA each. The camera is the largest load, so it browns out first — but the
kernel log showed both **servo adapters** dropping and re-enumerating too, and later the
whole hub disconnecting and taking all three with it.

**This is why it matters more than a lost video stream.** A camera dropping costs a session.
A servo adapter dropping mid-recording drops an arm under load and reshuffles the
`/dev/ttyACM*` numbers — plan risk **R8**. On this rig those names have already swapped once:
the tracker recorded follower=`ttyACM1` while the script had found it at `ttyACM0`.

### The wiring rule

- **Cameras and servo adapters never share a hub.** Put them on different root controllers.
- **The wrist camera goes on a root port**, not a hub — ideally one of the free USB 3.0
  controllers (900 mA) rather than a 480M port.
- **Any hub in the chain must have its external power adapter connected.** A bus-powered hub
  cannot feed a camera plus two adapters, whatever its descriptor claims.
- `lsusb -t` and `./record_episodes.sh doctor` both show which controller is which. Free
  controllers are listed at the bottom of `doctor` output.

### Address the arms by serial number, not by ttyACM

`/dev/ttyACM0` and `/dev/ttyACM1` are assigned in enumeration order, so a re-enumeration can
swap them — and then the script drives the torque-disabled **leader** as the follower. The
`by-id` path embeds the adapter's serial number and is stable across replugs and reboots:

```bash
FOLLOWER_PORT=/dev/serial/by-id/usb-1a86_USB_Single_Serial_5B3D048536-if00
LEADER_PORT=/dev/serial/by-id/usb-1a86_USB_Single_Serial_5B79019104-if00
```

`ls -l /dev/serial/by-id/` lists them. **Verify the mapping once** — unplug the follower, run
`doctor`, and confirm the `arm:follower` line reports MISSING. It is worth the thirty
seconds; getting it backwards commands the wrong arm.

### When something drops mid-session

1. `./record_episodes.sh doctor` — power budget and the kernel's fault log
2. `./record_episodes.sh resume` — continues the dataset from where it stopped, once the bus
   is stable again. Episodes already written are not lost.

---

## Defaults in 0.6.0 that will bite you

The script overrides all three. They are listed because they matter the moment you run
`lerobot-record` by hand.

| Setting | lerobot default | Here | Why |
|---|---|---|---|
| `dataset.push_to_hub` | **`true`** | `false` | Uploads the instant recording ends. Decision **D3** (dataset license) is still open and Hub publication is a Phase-B deliverable |
| `dataset.episode_time_s` | `60` | `15` | The canonical task is 10–15 s |
| `dataset.reset_time_s` | `60` | `10` | 45 dead seconds per episode, otherwise |

Flip `PUSH_TO_HUB=true` only once D3 is settled in [../docs/progress.md](../docs/progress.md).

---

## Recording both cameras

The wrist camera went on the gripper on 2026-09-20, five weeks before the plan expected it.
Both cameras are therefore recorded into the Phase-A dataset even though Phase A only needs
the workspace view.

The reason is Phase B's **wrist-camera ablation**. If only the top camera were recorded now,
the ablation would cost a second 50-episode session with a remounted camera — and R4 says a
moved camera invalidates the comparison. With both streams banked, the ablation becomes a
training-time operation on one dataset.

**The G2 baseline still trains on the top camera only**, matching the plan's Phase-A intent.
ACT infers its inputs from the dataset and would otherwise use both, so hold the baseline
one of two ways:

- set `--policy.input_features` explicitly at train time, or
- fork a wrist-free copy with `lerobot-edit-dataset --operation.type=remove_feature`

For the fork, **`--new_repo_id` is not optional**: without it `edit-dataset` rewrites the
dataset in place and the wrist stream is gone for good, taking the ablation with it.
`./record_episodes.sh info` prints both commands with the right paths filled in.

A VRAM note for whenever you do train on both: two camera streams means two vision backbones
in ACT, and risk **R6** binds at ~9.6 GiB usable. Drop the batch size before dropping the
camera.

---

## Where the data goes

**Local storage is unavoidable.** `lerobot-record` always writes to disk first; `push_to_hub`
only adds an upload afterwards. With `push_to_hub=false` the local copy is the *only* copy.

By default lerobot writes to `$HF_LEROBOT_HOME/<repo_id>`, i.e.
`~/.cache/huggingface/lerobot/`. This project overrides that to
[`../datasets/`](../datasets/) via `DATASET_ROOT`, so recordings sit beside the repo that
documents them rather than inside a cache directory that is easy to wipe by accident.

`datasets/` is gitignored (`.gitignore:41`, plus `*.mp4` and `*.parquet`) — **datasets are
never committed.** Their provenance is: this README, the calibration in
[../calibration/](../calibration/), and the Hub once D3 is settled.

**If you change `DATASET_ROOT`, every downstream tool needs the same root** — a dataset
outside the default cache is not found by `repo_id` alone:

```bash
lerobot-train        --dataset.repo_id=... --dataset.root=...
lerobot-dataset-viz  --repo-id=...         --root=...
lerobot-edit-dataset --repo_id=...         --root=...
```

Note the inconsistent spelling across those three — `--dataset.root`, `--root`, `--root`,
and `--repo-id` with a hyphen in the visualizer but `--repo_id` with an underscore
everywhere else. `./record_episodes.sh info` and `view` get this right for you.

Rough sizing at 640×480, 2 cameras, h264: a few MB per episode, so **~300–500 MB for the
50-episode Phase-A set** and **1–2 GB** once Phase B's 10/25/50/100 re-records land beside
it.

---

## What actually determines whether G2 hits 8/10

Phase A's stated learning outcome is *demonstration quality dominates architecture*. None of
the flags above matter as much as these:

- **Vary the cube's start position** across the taped zone on every episode. Fifty identical
  trajectories teach the policy exactly one trajectory.
- **No hesitation and no mid-episode corrections.** ACT clones your pauses and your
  backtracking as faithfully as the task itself. Press **←** and redo it.
- **Reset the scene during `reset_time_s`, never during the episode.** Your hand in frame
  becomes part of the demonstration.
- **Keep speed and grasp approach consistent.** Multimodal demonstrations are what Phase B's
  Diffusion Policy comparison exists to study; ACT is the baseline that struggles with them.
- **Same lighting for all 50.** Fixed artificial light, not the window (plan §5.4).

Budget ~35–45 minutes of wall clock for 50 episodes at 15 s plus 10 s reset, plus
re-records.

---

## References

- [Imitation Learning on Real-World Robots](https://huggingface.co/docs/lerobot/il_robots)
- [Getting Started with Real-World Robots](https://huggingface.co/docs/lerobot/main/getting_started_real_world_robot)
- [LeRobotDataset v3.0](https://huggingface.co/docs/lerobot/en/lerobot-dataset-v3) — the on-disk format
- [`il_robots.mdx` source](https://github.com/huggingface/lerobot/blob/main/docs/source/il_robots.mdx)

Local source of truth, which outranks all of the above for this env:
`/home/chinmay/lerobot-env/lib/python3.12/site-packages/lerobot/scripts/lerobot_record.py`
and `configs/dataset.py`.
