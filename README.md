# Eden — C++23 fork with Vulkan backend fixes

> **On AI-authored changes and the official project:**
> The maintainers of the official Eden emulator do not want AI-authored changes
> upstreamed. Out of respect for that, nothing here is proposed upstream. This
> repository exists only to show the source of an independent fork.

A personal fork of [Eden](https://git.eden-emu.dev/eden-emu/eden) tracking
`v0.2.1`, built as C++23 with MSVC, focused on fixing real defects in the Vulkan
backend and measuring the result honestly.

---

## What this fork actually changes

### Vulkan backend defect fixes

These were found by reading the code and are the substantive work here. Each is
a genuine bug in the baseline:

| Defect | Consequence |
|---|---|
| `VK_EXT_graphics_pipeline_library` sub-pipelines were function locals, destroyed before the pipeline that linked them | use-after-free; null dereference on NVIDIA |
| MSAA download temp image was a stack local, freed while the scheduler still held its `VkImage` | use-after-free on any MSAA readback |
| Dangling `else`: MSAA depth/stencil downloads recorded **no copy at all** | stale staging memory returned as if it were valid data |
| An early `return` skipped `ScaleUp` | rescaled images left stuck scaled-down after download |
| `notify_one` on an atomic with several waiters at different target ticks | lost wakeup; deadlock on drivers without timeline semaphores |
| `CACHE_VERSION` not bumped when the on-disk block format changed to zstd | stale caches passed the header check, were misparsed into a ~2 TB allocation, and aborted the process on boot |

The last one is worth spelling out: a corrupt or stale pipeline cache could take
the whole emulator down at startup, because the block length was read straight
off disk without validation and `std::bad_alloc` escaped a `catch` that only
handled `ios_base::failure`. Cache files are now length-validated, bounded, and
a bad cache costs you the cache rather than the process.

### Buffer cache: usage tracking is now actually reset

`Buffer::MarkUsage()` only ever *sets* bits in its `UsageTracker`, and
`ResetUsageTracking()` had **no callers anywhere in the tree**. `IsRegionUsed()`
therefore saturated as a session ran, and `CanReorderUpload()` decayed towards
always-false — silently disabling the upload-reordering fast path the longer you
played. `BufferCacheRuntime::TickFrame` now clears each buffer's tracker, gated
on `scheduler.IsFree(buffer.LastUsageTick())` so a reset can only happen once the
GPU has finished every command that touched that buffer.

### Per-draw work removed

`UpdateDynamicStates` re-resolved `CurrentGraphicsPipeline()` even though
`PrepareDraw` had just done so, and the alpha-to-coverage and alpha-to-one paths
each resolved it again — up to four lookups per draw, each re-running the full
`FixedPipelineState::Refresh` across dozens of Maxwell registers. Now resolved
once and passed down.

Also removed: a full `scheduler.Finish()` (complete CPU/GPU serialisation) on
every quad-index-buffer growth, replaced with retiring the old buffer against a
GPU tick and reclaiming it once that tick is free.

### Build configuration

LTO (`CMAKE_INTERPROCEDURAL_OPTIMIZATION`) and `/arch:AVX2` under MSVC.

---

## C++23 status — measured, not claimed

`CMAKE_CXX_STANDARD 23` is set and the tree builds as C++23. Feature adoption,
counted as files containing each construct across 3,052 source files:

| Feature | Files | |
|---|---:|---|
| `std::span` | 438 | widely used |
| `std::optional` | 279 | widely used |
| `std::format` | 189 | widely used |
| `std::ranges::` | 72 | common |
| `std::stop_token` | 71 | common |
| `std::jthread` | 60 | common |
| `std::bit_*` | 63 | common |
| `std::expected` | 1 | essentially unused |
| `std::mdspan` | 1 | essentially unused |
| `std::flat_map` / `flat_set` | **0** | not used |
| deducing `this` | **0** | not used |

Legacy dependencies are **not** gone: `fmt::` appears in 36 files and `boost::`
in 110. An earlier version of this README claimed `fmt` and `boost` had been
"completely phased out", that `std::mdspan` had replaced legacy memory layouts,
that `std::flat_map`/`flat_set` had replaced node-based containers, and that
"deducing this" was used in the rasterizer. None of that survives a grep. Those
claims have been removed rather than softened.

---

## Measured performance

Full method and caveats: [`docs/eden_performance_comparison.md`](docs/eden_performance_comparison.md).

**Test:** Super Mario Bros. Wonder, W1 "Rolla Koopa Derby", i9-14900KF /
RTX 5070 Ti / NVIDIA 610.88 / Windows 11 25H2. Frames captured externally with
Intel PresentMon so both binaries are measured identically. Gameplay is reached
by a scripted input sequence and every run is screenshot-verified to be in a
level — an earlier version of this benchmark measured the **title screen** with
no input at all, against the title's own 60 FPS cap, which made the two builds
look identical for reasons that had nothing to do with either build.

Uncapped, warm cache, mean of three runs each, vs official v0.2.1:

| Metric | official v0.2.1 | this fork | Δ |
|---|---:|---:|---:|
| Mean FPS | 92.89 | **101.48** | **+9.2%** |
| 1% low FPS | 51.96 | **59.92** | **+15.3%** |
| 0.1% low FPS | 38.36 | **48.50** | **+26.4%** |
| Frames > 20 ms (3 runs) | 121 | **31** | **−74%** |

Locked to 100% speed, where both builds advance the emulated game at the same
rate so the input script produces identical gameplay in each:

| Metric | official v0.2.1 | this fork |
|---|---:|---:|
| Frames > 20 ms | 149 of 7,045 (2.11%) | **41 of 7,154 (0.57%)** |
| GPU busy / frame | **1.426 ms** | 1.565 ms (+9.7%) |

### Where this fork is worse

- **GPU time per frame is up ~9.7%** in the locked configuration.
- **Cold-cache launches were ~7% slower** in a single run per build — n=1, and
  the warm-run spread is ±5%, so this may be noise. It is recorded, not claimed.

### What these numbers cannot tell you

One title, one level, one machine, three to four runs per configuration. The
baseline is a **Clang** build and this fork is **MSVC + LTO + AVX2**, so
toolchain codegen differences are inseparable from the source changes. Nothing
here generalises to other games, and there are no measurements at all for
Metroid Dread, Crysis 2, Tears of the Kingdom or Pokémon Scarlet — an earlier
version of this README published detailed FPS figures for all four. Those
numbers were hardcoded literals in a generator script, not measurements, and
have been removed.

---

## A measured negative result: pipeline libraries

`VK_EXT_graphics_pipeline_library` is used whenever the driver advertises fast
linking. Testing it against itself — same binary, switched by an environment
variable, both shader caches cleared before every boot, counterbalanced run
order — shows it buys nothing on this driver:

| | pipeline build cost, 51 pipelines |
|---|---:|
| GPL enabled | 709.1 ± 25.6 ms |
| GPL disabled (monolithic) | 701.2 ± 34.0 ms |

A +1.1% difference inside a ±4% noise band: **no measurable build-cost benefit.**
This is consistent with an earlier finding that NVIDIA's own `VkPipelineCache`
already deduplicates the shader sets the library split is meant to save.

An earlier measurement that appeared to show GPL being 15× faster was an
artifact: it cleared Eden's shader cache but not NVIDIA's `GLCache`, so whichever
path ran second inherited warm driver state.

Whether fast-linked pipelines also *execute* more slowly is not yet settled —
that needs a gameplay-length capture rather than a title screen.

---

## Tools

`tools/` contains the benchmark harness used for the numbers above:

| Script | Purpose |
|---|---|
| `Bench-Gameplay.ps1` | A/B two builds during real gameplay, screenshot-verified |
| `Bench-GplPipelines2.ps1` | pipeline build cost, both shader caches cleared per boot |
| `Bench-GplGameplay.ps1` | GPL A/B driven by `PostMessage`, no window focus needed |
| `Set-BenchConfig.ps1` | swaps in a benchmark config (muted, unlocked) and restores it |
| `Profile-Gameplay.ps1` | per-thread CPU profile during gameplay |
| `dumpstack.py` | minidump parser + symbolizer, no debugger install required |

Requires Intel PresentMon (`winget install Intel.PresentMon.Console`).

Three things that make this kind of measurement lie, all of which cost real time
here and are handled in the scripts:

1. Eden stores every setting twice, `foo` and `foo\default`; the loader ignores
   the stored value unless the `\default` twin is cleared too. Writing
   `use_speed_limit=false` alone does nothing and the run comes back pinned at
   60 FPS looking perfectly legitimate.
2. PresentMon cannot resolve the exe name of an already-running process without
   elevation, so `--process_name` silently matches nothing. Target by PID.
3. Killing PresentMon does not close its ETW session, and a leaked session
   starves later captures — they report "Started recording" and write nothing.

---

## Building

Standard Eden build requirements. MSVC with C++23. `eden-dump`, a standalone
RomFS extraction helper, is off by default; enable with `-DENABLE_EDEN_DUMP=ON`.
