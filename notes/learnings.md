# Learnings — practical difficulties, and what they cost to find

Debugging war stories from this rig, written to be **retellable**. Each entry is something
that cost real time, where the obvious explanation was wrong and the actual cause was worth
knowing. These are the answers to "tell me about a hard bug you debugged."

Dated session narrative lives in the other `notes/` files. This one is cumulative and
undated: it grows an entry whenever a problem turns out to have a non-obvious root cause.

**Entry format** — symptom → what was ruled out → root cause → fix → why it generalizes.
The ruled-out section is not padding: in an interview it is the part that shows method.

---

## L1 — The arm froze when I made the policy *more* reactive

**2026-09-22** · build Phase A · ACT on 50 demos, cube-to-bowl

### Symptom

Trained ACT ran on the follower and moved. I lowered `n_action_steps` from 100 to 20 to make
it re-plan 5× more often — more closed-loop, on fresher camera frames. The arm went
**completely still**. Not slow, not jerky: motionless. Set it to 70 and it moved again. The
policy, the checkpoint and the hardware were identical in both cases.

### Two signals that looked like the cause and were not

**A frame-rate warning.** `Record loop is running slower (3.5 Hz) than the target FPS (30.0
Hz)` — the obvious suspect, since "policy inference taking too long" is one of the causes it
names. Wrong. The warning fired **once**, on the first loop iteration, and it is unthrottled
— it sits in the `else` branch of every iteration in lerobot's `strategies/base.py`. So the
other ~450 iterations of a 15 s run all hit 30 Hz. The single slow tick was the first CUDA
forward pass: cuDNN autotune and kernel JIT, ~300 ms, once.

> **Lesson:** before reading meaning into a warning's *rarity*, check whether it is
> rate-limited. An unthrottled warning that appears once is telling you the opposite of what
> a throttled one would.

**Out-of-distribution observations.** My first real hypothesis. The arm's `elbow_flex` sat at
97.98° against a training maximum of 97.45° — genuinely outside the data. It was a red
herring; 0.5° past a boundary does not freeze an arm. Worth recording because it was
*plausible, checkable and wrong*, which is the honest shape of most debugging.

### What was ruled out, and how

Everything here was measured, not reasoned about:

| Suspect | How it was eliminated |
|---|---|
| Policy collapsed to a constant | Replayed the checkpoint offline against training episodes: **0.85° MAE** vs recorded actions, full range (shoulder_lift swings 135°) |
| The chunk setting itself | Swept `n_action_steps` 100/50/20/10 offline → MAE 0.85 / 0.83 / 0.98 / 0.89. No effect |
| Servo safety clamp | `max_relative_target` is `None` — no clamp configured |
| Torque never enabled | lerobot's `torque_disabled()` context manager re-enables in its `finally` |
| `torch.compile` warmup skipping sends | `use_torch_compile` defaults `False`, so the warmup gate never fires |
| Action interpolator swallowing commands | multiplier is 1 — pass-through |
| Image scaling mismatch | Verified the probe's `/255` + CHW permute matches lerobot's live path, and the normalizer holds ImageNet stats on `[0,1]` |

The offline sweep has a limitation worth stating out loud, because an interviewer will ask:
replaying against a dataset feeds **ground-truth observations at every step**, so it cannot
reproduce closed-loop drift. It proves the network is not broken. It does not prove the
policy works on the robot.

### The measurement that cracked it

A probe that reads one live observation — both cameras, all six joints — runs the policy, and
prints the commanded goal against the present position **without sending anything to the
motors**. Safe to run repeatedly with the arm powered and the workspace as-is.

Then the thing that actually mattered: profile the whole action chunk. *How far has the
commanded position travelled from the arm's current pose by step k?*

Live, parked at the start pose: flat at ~5° through k=30, then 24° at k=50, 100° at k=70,
131° at k=100.

**And here I nearly drew the wrong conclusion.** My training-data reference had been sampled
*mid-episode*, where the arm is already in motion — a smooth ramp from step 1. Against that,
the live profile looked pathologically flat, which reads as "policy hedging on an unfamiliar
observation." But the live probe was measured at the **parked start pose**. Different
condition. Re-measured at frame 0 of recorded episodes:

| k | time | policy chunk | recorded demo |
|---|---|---|---|
| 1 | 0.03 s | 1.48 | 1.47 |
| 20 | 0.67 s | 1.50 | 1.57 |
| 30 | 1.00 s | 3.33 | 2.93 |
| 50 | 1.67 s | 32.91 | 31.43 |
| 70 | 2.33 s | 100.50 | 100.66 |
| 100 | 3.33 s | 140.74 | 137.95 |

The policy tracks the demonstration to about 1°. It is flat at the start because **the
demonstrations are flat at the start**.

> **Lesson:** a baseline is only a baseline if it was measured under the same conditions as
> the thing you are comparing it to. Mine was off by one variable and pointed at the wrong
> root cause.

### Root cause

**Every one of the 50 demonstrations opens with a pause.** Median **40 frames — 1.33 s** —
before the arm first moves 10° from its start pose. That is me settling my hand on the leader
before starting the teleop. ACT learned it faithfully, because it is in the data.

So `n_action_steps=20` executes 0.67 s of a 1.33 s pause and then re-queries. The arm has not
moved, so the observation has not changed, so the next chunk prescribes the *identical*
pause. Self-reinforcing:

```
chunk says "hold 1.33 s, then reach"
  → execute first 0.67 s (all hold)
  → arm stationary
  → observation unchanged
  → chunk says "hold 1.33 s, then reach"   ← forever
```

`n_action_steps=70` runs 2.33 s, past step 50 where the ramp begins. The arm moves, the
observation changes, and the loop escapes.

**Idle frames at the head of an episode are an absorbing state under action chunking.** That
is the whole bug in one sentence.

### Fix

The fix is in the **data**, not the config.

1. **Trim the leading idle frames and retrain.** Deletes the learned pause; small
   `n_action_steps` then works as intended. Costs one retrain.
2. **Record episodes starting when motion starts.** Protocol change, free, prevents recurrence.
3. *Workaround:* keep `n_action_steps ≥ 50`. Works, but it is maximally open-loop — the exact
   opposite of what I was trying to achieve.
4. *Workaround:* temporal ensembling. Escapes around t≈40 because the exponential average
   pulls in older chunks whose later indices are already past the pause. The 1.3 s dead period
   at the start remains.

### Why it generalizes

- **Idle time in demonstrations is not neutral.** Behaviour cloning learns the idle along with
  the task. Under action chunking it can become a state the policy cannot leave.
- **An inference-time knob interacted with a data property to produce total failure.**
  `n_action_steps` "only affects smoothness" right up until it does not.
- **The failure was in the data and the symptom was in the control loop.** Nothing in the
  traceback, the logs or the config pointed at the dataset.
- **Build the non-invasive probe.** The decisive tool read real hardware and computed the real
  policy output while commanding nothing — which meant it could be run over and over, safely,
  with the arm live. That is what made the chunk profile cheap enough to iterate on.

---

## L2 — `chunk_size` is architecture; `n_action_steps` is the knob

**2026-09-22** · the confusion that started L1

I went in meaning to "reduce the action chunk size for more accurate inference." You cannot,
not at inference time:

- **`chunk_size` (100)** is baked into the checkpoint at training time. ACT's decoder has
  exactly that many action slots. Lowering it means retraining.
- **`n_action_steps` (100)** is how many of those predicted actions are executed before the
  policy looks at the cameras again. Pure inference-time choice — the *same checkpoint* runs
  at any value ≤ `chunk_size`. In `modeling_act.py` the chunk is sliced to `n_action_steps`
  and the queue refills when it drains.

So "more reactive" is `n_action_steps`, and it costs one extra forward pass per N steps.
lerobot validates `n_action_steps ≤ chunk_size` and refuses to build the config otherwise.

Worth knowing cold: the two are conflated constantly, including by the ACT paper's own
framing, where the chunk size and the execution horizon are equal by default.
