# Eden: measured performance comparison (gameplay)

**Baseline:** official Eden **v0.2.1** (Clang 22.1.4), `P:\Programming Repositories\eden-official\eden.exe`
**Fork:** `private/cpp23-modernization` @ `a308293`, MSVC 19.51 + LTO + AVX2
**Test system:** i9-14900KF, RTX 5070 Ti, NVIDIA 610.88, Windows 11 25H2
**Title:** Super Mario Bros. Wonder (`010015100B514000`) 1.0.1, W1 "Rolla Koopa Derby"
**Date:** 2026-08-12

---

## Why the previous version of this document was withdrawn

The earlier report measured both builds with **no input injected at any point**.
The protocol was: launch with `-g <rom>`, sleep 30 s, capture 60 s. The
emulator sat on the game's title/attract screen for the entire capture in both
cases.

That invalidates its headline table completely. Mario Wonder caps at 60 FPS,
the title screen costs almost nothing to render, so both builds trivially held
the cap and the report concluded they were equivalent. Observing that two
builds both fail to exceed a cap they are both pinned to is a tautology, not a
measurement. The one difference it did highlight — "half as many frames over
20 ms" — was 10 events versus 20 across ~3,590 frames on a static screen, which
is noise presented as a finding.

Everything below replaces it and was captured during actual gameplay.

---

## Method

Frames were captured with **Intel PresentMon 2.5.1**, externally over ETW, so
the unmodified upstream binary and the modified one are measured identically
with no instrumentation in either.

**Reaching gameplay.** `tools/Bench-Gameplay.ps1` drives the emulator from
launch into a level with synthetic keystrokes: title (L+R) → user select →
player count → character select → world map → level card → level. Eden reads
the keyboard through Qt key events, so injected keystrokes are
indistinguishable from real ones to the emulator. Each run screenshots the
window when it enters the level and again during the capture; every run below
has been visually confirmed to be in a level, not on a menu.

**Nabbit, not Luigi.** The first attempt used the save's default character and
the scripted "hold right, jump on a cadence" workload ran him into enemies. A
mid-capture screenshot caught official v0.2.1 sitting on the death screen at
the 40-second mark with three lives gone. A death screen is nearly black and
costs almost nothing to render, so that biases the result toward whichever
build dies more. Nabbit cannot take damage, which keeps the capture in the
level.

**Identical starting state.** The save file is snapshotted once and restored
before every run, so each run begins at the same level, same position, same
coin count. Two consecutive runs produced pixel-identical opening frames.

**Two configurations, because no single one can measure both things.**

The *uncapped* configuration disables Eden's 100% speed limiter and sets vsync
to Immediate. This is the only way to measure throughput: with the limiter on,
both builds are held to the same speed by definition. The cost is that the two
builds then advance the emulated game at different rates, so host-timed
keystrokes land on different emulated frames and the two builds do not play
quite the same 60 seconds. Hence four runs and a reported spread.

The *locked* configuration leaves the limiter at 100%. Both builds advance the
guest at the same rate, so the input script produces genuinely identical
gameplay in each. This cannot measure throughput, but it is the honest way to
compare frame consistency.

Both builds read the same `%APPDATA%\eden` config, rewritten from the same
backup before every run. Runs are grouped — all official, then all fork —
rather than alternating, because the two builds use different pipeline-cache
versions and each rejects the other's cache; alternating would leave every run
cold.

Percentile lows come from the **frametime** distribution (the 1% low is the
99th-percentile frametime converted to FPS), which is the correct method.

---

## Results: uncapped — throughput

| run | official v0.2.1 | this fork |
|---|---:|---:|
| r1 (cold cache) | 89.41 | 83.05 |
| r2 (warm) | 91.15 | 97.70 |
| r3 (warm) | 91.20 | 107.67 |
| r4 (warm) | 96.32 | 99.07 |

Warm-run means (r2–r4), which is the like-for-like comparison:

| metric | official | fork | Δ |
|---|---:|---:|---:|
| Mean FPS | 92.89 | **101.48** | **+9.2%** |
| Mean frametime | 10.77 ms | **9.85 ms** | −8.5% |
| 1% low FPS | 51.96 | **59.92** | **+15.3%** |
| 0.1% low FPS | 38.36 | **48.50** | **+26.4%** |
| Frames > 20 ms (3 runs) | 121 | **31** | **−74%** |

GPU busy per frame is deliberately **not** in that table. The uncapped runs do
not render the same scenes in the two builds, and the fork's values there are
bimodal — 1.405, 1.744, 1.409, 1.746, alternating by run order and not tracking
frame rate — while official's are flat (1.323, 1.321, 1.323). Averaging through
that would produce a number that means nothing. The GPU comparison belongs to
the locked configuration below, where the workload is identical.

The fork's slowest warm run (97.70) is faster than official's fastest (96.32),
so the gap is larger than the run-to-run spread rather than hidden inside it.

Both builds run the game at well over real time here — roughly 155% and 170% of
100% speed. That headroom is precisely what the title-screen protocol could not
see, because the cap flattened it to 60 for both.

## Results: locked to 100% — frame consistency

Identical deterministic workload in both builds.

| run | official mean FPS | official frames > 20 ms | fork mean FPS | fork frames > 20 ms |
|---|---:|---:|---:|---:|
| r1 (cold) | 59.27 | 44 | 58.60 | 84 |
| r2 (warm) | 59.17 | 50 | 59.57 | 26 |
| r3 (warm) | 58.35 | 99 | 59.75 | 15 |

Warm runs:

| metric | official | fork |
|---|---:|---:|
| Mean FPS | 58.76 | **59.66** |
| **1% low FPS** | **30.00** | **59.20** |
| Frames > 20 ms | 149 of 7,045 (**2.11%**) | 41 of 7,154 (**0.57%**) |
| GPU busy / frame | **1.426 ms** | 1.565 ms (**+9.7%**) |

The 1% low is the striking number and it needs explaining, because 30 versus 59
looks implausible until you see what it means. A 1% low of 30.0 says that more
than one frame in a hundred took ~33 ms — a doubled frame, i.e. a dropped one.
For the fork the 99th-percentile frametime is still ~16.9 ms, meaning fewer than
1% of its frames doubled. Same scene, same input, same duration: official drops
a frame about four times as often.

This is the metric that corresponds to what you feel while playing, and it is
measured in the configuration where both builds are provably doing the same
work.

---

## Where the fork is worse

Stated in the same table style as the wins, because a comparison that only
reports the favourable direction is not a comparison.

**Cold-cache launches are slower.** Uncapped: 83.05 vs 89.41 FPS, about 7%
behind, with 76 slow frames against official's 43. Locked: 84 slow frames
against 44. The first launch after a cache invalidation costs the fork more
than it costs official. Any claim that the shader-cache work is an unambiguous
improvement does not survive this — it is a warm-cache win and a cold-cache
loss, and since bumping `CACHE_VERSION` to 19 forces exactly one cold launch
for every existing user, that cost is real and not hypothetical.

**GPU busy time went up**, 1.426 → 1.565 ms per frame in the locked
configuration — **+9.7%**, measured where both builds provably render the same
scenes. Against a ~17 ms frame this is nowhere near the limiter, but the
direction is wrong and it is consistent across runs. The likely cause is the
graphics-pipeline-library link path, which links four sub-pipelines with no
`LINK_TIME_OPTIMIZATION`: the link is cheap but the driver cannot optimize
across the stage boundaries, so the linked pipeline executes more slowly than a
monolithic one. Untested until the GPL on/off A/B runs.

**A "wider run-to-run spread" claimed in an earlier draft is withdrawn.** It
came from the uncapped runs (fork σ = 5.40 FPS vs official σ = 2.97), where the
two builds play different scenes by construction. In the locked configuration
the ordering reverses — fork σ = 0.13, official σ = 0.58 — and the fork drops
far fewer slow frames in both runs. The uncapped spread is most likely the fork
covering more of the level per 60 seconds and so sampling more scene variety.

---

## What the frame numbers do not explain: the thread profile

Per-thread CPU sampled during gameplay (`tools/Profile-Gameplay.ps1`, 40 s
windows, fork build):

| | locked 100% | uncapped |
|---|---:|---:|
| **HostTiming** | **97.9%** | **98.8%** |
| CPUCore_2 | 33.1% | 58.5% |
| CPUCore_0 | 32.1% | 56.9% |
| CPUCore_1 | 31.1% | 65.1% |
| VulkanWorker | 11.5% | 9.0% |
| GPU | 11.0% | 15.3% |
| **cores used, of 32** | **2.27** | **3.21** |

The earlier version of this measurement was taken on the same flawed title
screen, so it has been redone under load. The finding holds and is if anything
sharper: `HostTiming` consumes a full core, more than any thread that does
actual emulation work, in both configurations.

The cause is `src/common/thread.cpp:240`. `Event::WaitFor` blocks properly on
POSIX via `condvar.wait_for`, but on Windows it spins:

```cpp
auto const end = Common::g_wall_clock.GetTimeNS() + time;
while (!is_set.load() && end > Common::g_wall_clock.GetTimeNS())
    Common::Windows::SleepForOneTick();
```

A high-resolution waitable timer (`CreateWaitableTimerEx` with
`CREATE_WAITABLE_TIMER_HIGH_RESOLUTION`) would give the same pacing precision
without the busy-wait. This is unimplemented — it is the largest remaining item,
and timing code is the riskiest thing in an emulator to change, so it wants
before/after measurement rather than confidence.

The wider point the profile makes: the emulator uses 2–3 of 32 cores. The
bottleneck is not throughput of work, it is that almost nothing is parallel.

---

## What this comparison still cannot show

- **One title, one level, one machine.** Mario Wonder is a 2D title with a
  ~1.4 ms GPU frame. A GPU-heavy 3D title could reverse the GPU-busy result
  entirely. Nothing here generalises to other games.
- **The fork's uncapped GPU-busy values are bimodal and unexplained** — 1.405,
  1.744, 1.409, 1.746, alternating by run order rather than tracking frame
  rate, with no such pattern in official or in the locked runs. With four
  samples a perfect alternation arises by chance roughly one time in three, so
  this may well be nothing; it is recorded rather than explained.
- **Three to four runs per configuration.** Enough to separate a 9% mean
  difference from a 3–5 FPS spread; not enough for a confident figure on the
  cold-cache regression or the wider variance.
- **The compiler is a confound.** Baseline is Clang, fork is MSVC + LTO +
  AVX2. Codegen differences between the two toolchains are inseparable from
  the source changes in these numbers.
- **The NVIDIA driver keeps its own shader cache** outside the emulator, warm
  for both builds throughout. "Cold" here means Eden's cache was cleared or
  rejected, not that the driver had never seen these shaders.
- **Synthetic input is not a player.** The workload holds right and jumps on a
  fixed cadence. It is repeatable and it is real gameplay, but it is not
  representative of how the level is actually played.

## Reproducing this

```powershell
# throughput
.\tools\Bench-Gameplay.ps1 -Runs 4 -CaptureSeconds 60
# frame consistency, deterministic workload
.\tools\Bench-Gameplay.ps1 -Runs 3 -CaptureSeconds 60 -LockedSpeed
# per-thread profile during gameplay
.\tools\Profile-Gameplay.ps1 -LockedSpeed
```

Requires PresentMon (`winget install Intel.PresentMon.Console`) with its path in
`%TEMP%\pm_path.txt`. Raw captures, per-run emulator logs and the proof
screenshots are under `build\bench\` and `build\bench_shots\`; every number
above is recomputable from them. `tools\cleanup_bench.ps1` clears orphaned
processes and ETW sessions between attempts.

### Three measurement bugs worth knowing about

All three failed *silently* — they produced empty or capped captures that
looked like valid results.

1. **Eden ignores a config value unless its `\default` flag is also cleared.**
   Settings are stored twice, `foo` and `foo\default`;
   `frontend_common/config.cpp:740` returns the compiled-in default whenever
   `foo\default=true`. Writing `use_speed_limit=false` alone does nothing, and
   the run comes back pinned to 60 FPS looking like a genuine result.
2. **PresentMon cannot resolve the exe name of an already-running process**
   without elevation — it appears as `<unknown>`, never matches
   `--process_name`, and the capture records nothing while reporting success.
   Target by PID instead. Removing the filter entirely is worse: the unfiltered
   trace overran the ETW buffers (227,748 events lost) and still wrote no CSV.
3. **Killing PresentMon does not close its ETW session.** Orphaned sessions
   accumulate, starve the shared trace buffers, and every later capture comes
   back empty. Use one fixed `--session_name`, `--terminate_after_timed`, and
   stop the session explicitly.
