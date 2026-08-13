# Code Review: `private/cpp23-modernization` vs upstream `master`

**Scope:** 45 files, +2031 / −145, merge-base `0a7e023`. Reviewed the 30
source/CMake files; the 15 tooling/doc files are the benchmark harness and
report built this session. Every finding below was checked against the actual
tree, not just the diff — three initial concerns were dropped after
verification and are listed at the end so they don't get re-raised later.

## Summary

The renderer bug-fix commits (`f2a6411`, `4a80b34`, `a308293`) are solid,
correct, and unusually well-commented — each explains *why*, not just *what*.
The concerns are: one measured performance regression whose default is still
unset (GPL), one latent correctness gap in a rarely-hit MSAA path, and some
housekeeping — most notably that HEAD's committed report still carries numbers
the author has already corrected on disk.

## Critical

| # | File | Line | Issue | Severity |
|---|------|------|-------|----------|
| S1 | `.git/config` (untracked) | — | GitHub PAT stored in plaintext in the remote URL, and it was echoed into this session's output during a push attempt. Anyone with the transcript or the working copy has push access to `DaveDebugs/Eden-Cpp23-Upgrade`. | 🔴 Critical |

S1 is not in the tracked diff, but it's the highest-priority item in the repo.
Rotate the token today (GitHub → Settings → Developer settings → revoke), then
set the remote back to a bare `https://github.com/...` URL and let a credential
helper hold the token out-of-tree.

## Correctness

| # | File | Line | Issue | Severity | Verdict |
|---|------|------|-------|----------|---------|
| C1 | `vk_texture_cache.cpp` | ~1070, 1921 | MSAA depth/stencil download now falls through to the generic path, which issues `CopyImageToBuffer` on the multisampled source image. That's a spec violation (copy source must be 1-sample) and can trip validation or device-loss. | 🟡 Medium | PLAUSIBLE |
| C2 | `vk_pipeline_cache.cpp` | 432 | `has_broken_spirv_position_input` is now permanently `false`. The comment correctly notes the old `driver_id == false` never fired — but if some driver genuinely needs the workaround, it still silently won't get it. | 🟢 Low | CONFIRMED |

On **C1**: the fix is a real improvement — the old code recorded *no copy at
all* for MSAA depth/stencil and returned stale staging memory silently, which
is worse. But the new fallback can't legally copy a multisampled image either.
Neither old nor new is correct; a true fix needs a depth-aware resolve (the
color path already resolves through a temp image via `MSAACopyPass`, which has
no depth/stencil support). The trigger is rare (MSAA depth readback), which is
why it survived. Marked PLAUSIBLE because I verified the code path structurally
but did not trigger it under validation layers — worth a tracked follow-up and
a sync-validation run rather than an immediate block.

On **C2**: this is inherited from upstream, not introduced here, and the fork
did the right thing by documenting it. Just don't let "written explicitly to
preserve behavior" become "resolved."

## Performance

| # | File | Line | Issue | Severity |
|---|------|------|-------|----------|
| P1 | `vk_graphics_pipeline.cpp` / `vulkan_device.h` | 585 / 781 | GPL is taken whenever the driver advertises fast-linking, but measured on this NVIDIA setup it costs +9.7% GPU-time (locked config) and ~7% on cold cache, because NVIDIA's own `VkPipelineCache` already dedupes the shader sets the library split is meant to save. | 🟡 Medium |
| P2 | `vk_pipeline_cache.cpp` | 309 | `GetTotalPipelineWorkers` went from `max(hw,2)−1` to `max(hw,1)`, so it now spawns a worker on every core with none left for the render/main thread during the boot compile storm. | 🟢 Low |

**P1** is the item the current A/B is built to settle. The fast-linking gate
(`SupportsFastPipelineLibraryLinking`, P2 in the commit history) was the right
first cut — it correctly avoids the path on drivers that recompile at link
time. But "fast-linking advertised" is not the same as "GPL is a net win here,"
and the numbers say it isn't on NVIDIA. Recommendation stands from the perf
work: make GPL opt-in per driver, or keep fast-linking for the first draw and
re-link with `LINK_TIME_OPTIMIZATION` in the background. The runtime toggle for
the A/B is staged (`Bench-GplAB.ps1`).

**P2** is defensible (use all cores to drain the compile queue faster at boot),
but on a 4–8 core machine leaving zero headroom for the render thread can *add*
hitching during the exact window it's trying to shorten. Worth a quick A/B, not
a blocker.

## Maintainability

| # | File | Line | Issue | Category |
|---|------|------|-------|----------|
| M1 | `docs/eden_performance_comparison.md` | 108, 124 | Committed at `dba473d` with the GPU-busy `+24%` figure and the "wider spread" claim that the author has since corrected on disk (to +9.7%, claim withdrawn) but not re-committed. HEAD ships numbers already known to be wrong. | Docs |
| M2 | `common/msvc_stl_shims.cpp` | 1 | Disabled by wrapping the whole file in `#if 0` instead of removing it from the build. Dead translation unit left in the tree. | Cleanliness |
| M3 | `eden_dump/CMakeLists.txt` | — | `add_subdirectory(eden_dump)` is unconditional, so a homebrew dump tool with `/WX`, reaching into `../tests/common/undefined_fix.cpp` and linking `video_core` for VMA, is now part of every build's failure surface. Gate it behind an option. | Build |
| M4 | `.gitignore` | — | Stored in an encoding git reports as binary (UTF-16/BOM). Ignore rules currently resolve (`build/` verified via `check-ignore`), but re-save as UTF-8 before it silently stops matching. | Nit |

**M1 is the one to fix before anyone reads the report.** The corrected doc is
sitting in the working tree uncommitted; `git add docs/ && git commit` closes
it. Everything else here is low-stakes.

## What looks good

- **The use-after-free fixes are correct and I verified each.** The GPL library
  lifetime fix works because `pipeline_libraries` is declared before `pipeline`
  (reverse-order destruction keeps the libraries alive past the pipeline that
  references them). The MSAA-download temp image is now a `shared_ptr` captured
  into the recorded command *and* drained with `Flush`/`Wait` before it drops —
  both halves are needed and both are present.
- **The boot-abort fix is real and complete.** Length-validating the on-disk
  block size, bounding `num_envs`, and widening the catch to `std::exception`
  together stop the 2 TB `bad_alloc` that was aborting every launch. Throwing
  (to delete the bad cache) rather than `break`ing (which stranded it forever)
  is the correct call and is well-explained in the comment.
- **`CACHE_VERSION` 18→19 (and OpenGL 15→16) is necessary**, not cosmetic — the
  zstd block-format change shipped without it, which is what let stale caches
  misparse.
- **`notify_all` lost-wakeup fix** is correct for multiple waiters on distinct
  target ticks.
- **P1 dynamic-state dedup** (thread the resolved pipeline instead of
  re-resolving it 2–4× per draw) is a clean, behavior-preserving win.
- **`retired_buffers` replacing `scheduler.Finish()`** is correct — I checked
  `CurrentTick`/`IsFree`: retiring against the current tick is conservative and
  never frees a buffer the GPU might still read.
- **The VFS `std::span` migration** moves call sites off the `[[deprecated]]`
  pointer overloads onto the upstream span API — cleanup, not risk.

## Dropped after verification (don't re-raise)

- *`eden_dump` duplicate `VMA_IMPLEMENTATION`* — not a duplicate. VMA impl is
  per-executable across the tree (`yuzu.cpp`, `main_window.cpp`, `native.cpp`);
  `eden_dump/main.cpp` follows the same pattern, `video_core` doesn't export it.
- *VFS span overloads missing* — upstream `vfs.h` defines the virtual span
  `Read`/`Write`; the pointer forms are the deprecated shims.
- *`bit_ceil(num_indices_)` / `Log2Ceil` behavior change* — the `std::bit_*`
  rewrites are behavior-preserving for all valid (non-zero, non-overflowing)
  inputs, same preconditions as the `NextPow2` they replace.

## Verdict

**Request changes** — but almost all of it is small. Two things before publish:
re-commit the corrected report (**M1**) and pick the GPL default (**P1**, which
the A/B will decide). **S1** (rotate the token) is independent and urgent.
**C1** deserves a tracked issue and a sync-validation run, not a block. The core
renderer work is good and I'd merge it once M1 and P1 are settled.
