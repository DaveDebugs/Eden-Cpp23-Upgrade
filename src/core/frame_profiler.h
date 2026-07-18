// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <array>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace Core {

/// Per-frame snapshot of profiling data.
struct FrameRecord {
    uint64_t frame_number{0};
    double timestamp_ms{0.0};       // Wall-clock time since game start
    double frametime_ms{0.0};       // Time spent processing this frame
    double game_fps{0.0};           // Instantaneous game FPS
    double emulation_speed{0.0};    // Emulation speed percentage

    // GPU events (accumulated per frame via atomics, then snapshotted)
    uint32_t shader_compiles{0};
    double shader_compile_time_us{0.0};
    uint32_t buffer_creates{0};
    uint32_t buffer_deletes{0};
    uint32_t draw_calls{0};

    // Memory
    uint64_t vram_usage_bytes{0};

    // Dip detection
    bool is_dip{false};
};

/**
 * Lightweight always-on frame profiler. Records per-frame metrics with near-zero
 * overhead (atomic increments) and flushes a CSV timeline on shutdown.
 *
 * Thread-safe: Record*() methods use atomics for cross-thread accumulation.
 * The EndFrame() / FlushToFile() methods are called from a single thread (the
 * system frame thread).
 */
class FrameProfiler {
public:
    static FrameProfiler& Instance();

    /// Called once when a game starts to reset state and begin recording.
    void Start();

    /// Called once when a game stops to finalize recording.
    void Stop();

    /// Returns true if profiling is active (between Start/Stop).
    bool IsActive() const { return active_.load(std::memory_order_relaxed); }

    // -----------------------------------------------------------------------
    // Per-frame event recording (called from any thread, uses atomics)
    // -----------------------------------------------------------------------

    /// Record a shader pipeline compilation with its duration in microseconds.
    void RecordShaderCompile(double duration_us);

    /// Record a GPU buffer creation.
    void RecordBufferCreate();

    /// Record a GPU buffer deletion.
    void RecordBufferDelete();

    /// Record a draw call submission.
    void RecordDrawCall();

    /// Record current VRAM usage in bytes (called once per frame).
    void RecordVRAMUsage(uint64_t bytes);

    // -----------------------------------------------------------------------
    // Frame lifecycle (called from the system frame thread only)
    // -----------------------------------------------------------------------

    /// Finalize the current frame with its frametime and perf stats.
    /// This snapshots the atomic counters, performs dip detection, and
    /// appends a FrameRecord to the timeline.
    void EndFrame(double frametime_ms, double game_fps, double emulation_speed);

    /// Write the accumulated timeline to a CSV file.
    void FlushToFile() const;

    /// Get the most recent N frame records for overlay rendering.
    std::vector<FrameRecord> GetRecentFrames(size_t count) const;

    /// Get summary statistics as a formatted string.
    std::string GetSummary() const;

private:
    FrameProfiler() = default;

    /// Dip detection: returns true if this frametime is a performance dip.
    bool DetectDip(double frametime_ms);

    std::atomic<bool> active_{false};
    uint64_t frame_counter_{0};

    using Clock = std::chrono::steady_clock;
    Clock::time_point start_time_{};

    // Atomic accumulators for cross-thread event recording.
    // These are reset to 0 at the end of each frame.
    std::atomic<uint32_t> pending_shader_compiles_{0};
    std::atomic<uint64_t> pending_shader_compile_time_us_{0}; // stored as fixed-point * 1000
    std::atomic<uint32_t> pending_buffer_creates_{0};
    std::atomic<uint32_t> pending_buffer_deletes_{0};
    std::atomic<uint32_t> pending_draw_calls_{0};
    std::atomic<uint64_t> pending_vram_bytes_{0};

    // Rolling window for dip detection (last 60 frametimes).
    static constexpr size_t DIP_WINDOW_SIZE = 60;
    std::array<double, DIP_WINDOW_SIZE> frametime_window_{};
    size_t frametime_window_index_{0};
    size_t frametime_window_count_{0};

    // Recorded timeline.
    static constexpr size_t MAX_FRAMES = 1'000'000; // ~4.6 hours at 60fps
    std::vector<FrameRecord> timeline_;

    // Title ID for file naming.
    uint64_t title_id_{0};

public:
    void SetTitleId(uint64_t id) { title_id_ = id; }
};

} // namespace Core
