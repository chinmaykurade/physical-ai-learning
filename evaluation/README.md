# evaluation/ — running the policy on the real arm

The **G2** gate: does ACT, trained on 50 demonstrations, put the cube in the bowl **≥ 8 times
out of 10**? ([`docs/progress.md`](../docs/progress.md))

| Script | Job |
|---|---|
| `run_policy.sh` | `info` · `check` · `dry` · `eval` · `score` — preflight, one supervised attempt, the ten scored trials, and the evaluation log. |

```bash
cd evaluation
./run_policy.sh check   # hardware + the policy/camera key match. The arm does not move
./run_policy.sh dry     # ONE autonomous attempt, nothing recorded
./run_policy.sh eval    # the 10 trials, recorded
./run_policy.sh score   # tally -> notes/<date>-g2-eval.md
```

Do not skip `dry`. It is one 15-second attempt with your hand on the switch, and it is where
you find out whether the policy learned the task or learned something else.

---

## Before the arm moves

The follower moves **by itself**. The leader is not connected and grabbing it does nothing.

- Clear the workspace of everything except the cube and the bowl.
- Hand on the **12 V supply switch** — that is the stop button. Stand where you can reach it
  without leaning across the arm.
- **ACT is open-loop between inferences.** Each inference commits to `n_action_steps` actions
  and executes all of them before looking at a camera again; a trajectory heading somewhere
  wrong will not correct itself inside that window. The checkpoint's own value is 100 — 3.3 s
  at 30 fps — but `N_ACTION_STEPS` in `run_policy.sh` overrides it at inference time and is
  set to **20 (0.67 s)**. `run_policy.sh info` prints the window in seconds, and the
  confirmation prompt repeats it. This is the single most important thing to know the first
  time you watch it run.
- **Esc, not Ctrl-C.** `return_to_initial_position` is on by default and returns the arm
  smoothly to its startup pose — but only on a clean shutdown. Ctrl-C leaves it wherever it
  stopped, still under torque.

---

## The check that actually matters

The policy was trained on feature keys `observation.images.top` and `observation.images.wrist`.
Those keys come from the **names** in the `CAMERAS` array, not from the devices. Hand the same
policy a robot exposing `front` and `side` and nothing errors — LeRobot builds the observation
dict from whatever the robot reports, and the policy simply receives garbage in the slots it
cares about. It looks exactly like a policy that failed to learn.

So `check` reads `input_features` out of the checkpoint's own `config.json` and compares:

```
  policy expects cameras : top, wrist
  CONFIG provides        : top, wrist
  MATCH
```

A mismatch refuses to run. Swapping the two *devices* while keeping the names is not caught by
this and cannot be — if the wrist camera is plugged into the top camera's name, only the video
shows it. Which is the other reason to run `dry` first.

---

## What each subcommand runs

`dry` uses `--strategy.type=base`: autonomous, no dataset, `--duration` seconds, Rerun display
on. `eval` uses `--strategy.type=episodic`, which mirrors `lerobot-record`'s flow — a timed
episode, then a reset window for you to reposition the cube, `--dataset.num_episodes` times,
recording every frame. Same keys as recording: **→** ends a trial early, **←** discards and
re-records it, **Esc** stops the session.

`--dataset.push_to_hub` defaults to **true** in LeRobot, exactly as in recording, so the eval
dataset would upload itself the moment the tenth trial ended. It is pinned to `false` here.

The recorded trials are the evidence behind the number — ten videos of what the policy actually
did, from both cameras. That is what makes a failure diagnosable a week later, and it is the
input to the G7 #1 writeup.

`score` is interactive and writes `notes/<date>-g2-eval.md`, the Phase-A **evaluation log**
deliverable. Success is a human judgement: the cube ends up in the bowl, unaided, inside the
episode. A nudge, a hand re-grasp, or a cube knocked off the table is a failure.

**Vary the cube position between trials**, within the range you demonstrated. Ten trials from
one position measures memorization.

---

## Which checkpoint

`POLICY=best` (the default) asks the training module for the checkpoint with the lowest
held-out eval loss — it shells out to `../training/train_act.sh best --quiet`, so there is one
source of truth for "best". Override it:

```bash
POLICY=090000 ./run_policy.sh dry                          # a specific step
POLICY=chinmaykurade/act_cube_to_bowl ./run_policy.sh eval  # a Hub repo id
```

For this run `best` resolves to step **100000** (eval loss 0.2458) — the loss was still falling
at the end, so the final checkpoint is also the best one.

---

## If it does badly

Eval loss and task success agree only loosely for behaviour cloning, so a low loss and a bad
arm is a normal outcome, not a contradiction. In rough order of likelihood:

**Camera framing drifted.** Risk **R4**. The policy is extremely sensitive to the workspace
looking like the training data. If the arm moves *confidently to the wrong place*, suspect this
before suspecting the model — a camera bumped since recording is the classic cause.

**Chunk-boundary jerk.** If the motion is fine but stutters every ~3.3 s, turn on temporal
ensembling: set `TEMPORAL_ENSEMBLE=true` in CONFIG. It queries the policy every step and
exponentially averages overlapping chunks. It is an *inference-time* switch — the same
checkpoint works both ways, no retraining — and costs 100× the inference calls, which ACT on a
3080 can afford. Worth a second 10-trial pass either way, since it is a free ablation for the
writeup.

**Failures cluster by cube position.** Then it is a data-coverage problem, not a model problem,
and the fix is demonstrations at the positions that fail — which is Phase B's scaling question
arriving early.

**It barely moves.** Check that `observation.state` is sane: the arm must be calibrated with
the *same* `id` used during recording, or the normalization statistics are meaningless.

---

## Reference

- LeRobot — [Imitation Learning on Real-World Robots](https://huggingface.co/docs/lerobot/il_robots)
  (the `lerobot-rollout` section)
- `lerobot==0.6.0` sources: `scripts/lerobot_rollout.py` (strategies and every flag),
  `rollout/strategies/episodic.py`, `rollout/configs.py`
- Zhao et al. — *ACT/ALOHA*, [arXiv:2304.13705](https://arxiv.org/abs/2304.13705) — §temporal
  ensembling is the part to read before deciding on that second pass
