// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#include <algorithm>
#include <chrono>
#include <cmath>
#include <format>
#include <numeric>
#include <string>

#include "common/fs/file.h"
#include "common/fs/fs.h"
#include "common/fs/path_util.h"
#include "common/logging.h"
#include "core/frame_profiler.h"

namespace Core {

FrameProfiler& FrameProfiler::Instance() {
    static FrameProfiler instance;
    return instance;
}

void FrameProfiler::Start() {
    frame_counter_ = 0;
    frametime_window_.fill(0.0);
    frametime_window_index_ = 0;
    frametime_window_count_ = 0;

    // Reset all atomics
    pending_shader_compiles_.store(0, std::memory_order_relaxed);
    pending_shader_compile_time_us_.store(0, std::memory_order_relaxed);
    pending_buffer_creates_.store(0, std::memory_order_relaxed);
    pending_buffer_deletes_.store(0, std::memory_order_relaxed);
    pending_draw_calls_.store(0, std::memory_order_relaxed);
    pending_vram_bytes_.store(0, std::memory_order_relaxed);

    timeline_.clear();
    timeline_.reserve(60 * 60 * 10); // Pre-allocate for 10 minutes at 60fps

    start_time_ = Clock::now();
    active_.store(true, std::memory_order_release);

    LOG_INFO(Core, "FrameProfiler started");
}

void FrameProfiler::Stop() {
    active_.store(false, std::memory_order_release);
    FlushToFile();
    LOG_INFO(Core, "FrameProfiler stopped — {} frames recorded", timeline_.size());
}

// ---------------------------------------------------------------------------
// Event recording (any thread)
// ---------------------------------------------------------------------------

void FrameProfiler::RecordShaderCompile(double duration_us) {
    if (!active_.load(std::memory_order_relaxed)) return;
    pending_shader_compiles_.fetch_add(1, std::memory_order_relaxed);
    // Store duration as fixed-point microseconds * 1000 to avoid floating-point atomics
    auto encoded = static_cast<uint64_t>(duration_us * 1000.0);
    pending_shader_compile_time_us_.fetch_add(encoded, std::memory_order_relaxed);
}

void FrameProfiler::RecordBufferCreate() {
    if (!active_.load(std::memory_order_relaxed)) return;
    pending_buffer_creates_.fetch_add(1, std::memory_order_relaxed);
}

void FrameProfiler::RecordBufferDelete() {
    if (!active_.load(std::memory_order_relaxed)) return;
    pending_buffer_deletes_.fetch_add(1, std::memory_order_relaxed);
}

void FrameProfiler::RecordDrawCall() {
    if (!active_.load(std::memory_order_relaxed)) return;
    pending_draw_calls_.fetch_add(1, std::memory_order_relaxed);
}

void FrameProfiler::RecordVRAMUsage(uint64_t bytes) {
    if (!active_.load(std::memory_order_relaxed)) return;
    pending_vram_bytes_.store(bytes, std::memory_order_relaxed);
}

// ---------------------------------------------------------------------------
// Frame lifecycle (system frame thread only)
// ---------------------------------------------------------------------------

void FrameProfiler::EndFrame(double frametime_ms, double game_fps, double emulation_speed) {
    if (!active_.load(std::memory_order_relaxed)) return;
    if (timeline_.size() >= MAX_FRAMES) return; // Safety cap

    const auto now = Clock::now();
    const double timestamp_ms =
        std::chrono::duration<double, std::milli>(now - start_time_).count();

    // Snapshot and reset atomic counters
    FrameRecord record;
    record.frame_number = frame_counter_++;
    record.timestamp_ms = timestamp_ms;
    record.frametime_ms = frametime_ms;
    record.game_fps = game_fps;
    record.emulation_speed = emulation_speed;

    record.shader_compiles = pending_shader_compiles_.exchange(0, std::memory_order_relaxed);
    const uint64_t raw_time = pending_shader_compile_time_us_.exchange(0, std::memory_order_relaxed);
    record.shader_compile_time_us = static_cast<double>(raw_time) / 1000.0;
    record.buffer_creates = pending_buffer_creates_.exchange(0, std::memory_order_relaxed);
    record.buffer_deletes = pending_buffer_deletes_.exchange(0, std::memory_order_relaxed);
    record.draw_calls = pending_draw_calls_.exchange(0, std::memory_order_relaxed);
    record.vram_usage_bytes = pending_vram_bytes_.load(std::memory_order_relaxed);

    // Dip detection
    record.is_dip = DetectDip(frametime_ms);

    timeline_.push_back(record);
}

bool FrameProfiler::DetectDip(double frametime_ms) {
    // Update rolling window
    frametime_window_[frametime_window_index_] = frametime_ms;
    frametime_window_index_ = (frametime_window_index_ + 1) % DIP_WINDOW_SIZE;
    if (frametime_window_count_ < DIP_WINDOW_SIZE) {
        frametime_window_count_++;
    }

    // Need at least 10 samples for meaningful dip detection
    if (frametime_window_count_ < 10) {
        return false;
    }

    // Calculate median of the rolling window
    std::array<double, DIP_WINDOW_SIZE> sorted;
    std::copy_n(frametime_window_.begin(), frametime_window_count_, sorted.begin());
    std::sort(sorted.begin(), sorted.begin() + frametime_window_count_);
    const double median = sorted[frametime_window_count_ / 2];

    // A dip is: frametime > 2x median, OR frametime > 33ms (below 30 FPS)
    constexpr double ABSOLUTE_THRESHOLD_MS = 33.33;
    return (frametime_ms > median * 2.0) || (frametime_ms > ABSOLUTE_THRESHOLD_MS);
}

// ---------------------------------------------------------------------------
// CSV export
// ---------------------------------------------------------------------------

void FrameProfiler::FlushToFile() const {
    if (timeline_.empty()) return;

    const auto path = Common::FS::GetEdenPath(Common::FS::EdenPath::LogDir);
    const auto filepath = path / "frame_timeline.csv";

    if (!Common::FS::CreateParentDir(filepath)) {
        LOG_ERROR(Core, "FrameProfiler: failed to create log directory");
        return;
    }

    Common::FS::IOFile file(filepath, Common::FS::FileAccessMode::Write,
                            Common::FS::FileType::TextFile);

    // CSV header
    file.WriteString("frame_number,timestamp_ms,frametime_ms,game_fps,emulation_speed,"
                     "shader_compiles,shader_compile_time_us,buffer_creates,buffer_deletes,"
                     "draw_calls,vram_usage_mb,is_dip\n");

    for (const auto& r : timeline_) {
        std::string line = std::format(
            "{},{:.2f},{:.3f},{:.2f},{:.2f},{},{:.1f},{},{},{},{:.1f},{}\n",
            r.frame_number, r.timestamp_ms, r.frametime_ms, r.game_fps,
            r.emulation_speed, r.shader_compiles, r.shader_compile_time_us,
            r.buffer_creates, r.buffer_deletes, r.draw_calls,
            static_cast<double>(r.vram_usage_bytes) / (1024.0 * 1024.0),
            r.is_dip ? 1 : 0);
        file.WriteString(line);
    }

    LOG_INFO(Core, "FrameProfiler: wrote {} frames to {}", timeline_.size(),
             filepath.string());
}

// ---------------------------------------------------------------------------
// Query methods
// ---------------------------------------------------------------------------

std::vector<FrameRecord> FrameProfiler::GetRecentFrames(size_t count) const {
    if (timeline_.empty()) return {};
    const size_t start = timeline_.size() > count ? timeline_.size() - count : 0;
    return std::vector<FrameRecord>(timeline_.begin() + start, timeline_.end());
}

std::string FrameProfiler::GetSummary() const {
    if (timeline_.empty()) return "No profiling data recorded.";

    double total_frametime = 0.0;
    double max_frametime = 0.0;
    size_t dip_count = 0;
    uint32_t total_shader_compiles = 0;
    uint32_t total_draw_calls = 0;

    std::vector<double> frametimes;
    frametimes.reserve(timeline_.size());

    for (const auto& r : timeline_) {
        total_frametime += r.frametime_ms;
        max_frametime = std::max(max_frametime, r.frametime_ms);
        if (r.is_dip) dip_count++;
        total_shader_compiles += r.shader_compiles;
        total_draw_calls += r.draw_calls;
        frametimes.push_back(r.frametime_ms);
    }

    // Sort for percentile calculations
    std::sort(frametimes.begin(), frametimes.end(), std::greater<>());

    const double avg_frametime = total_frametime / static_cast<double>(timeline_.size());
    const double avg_fps = 1000.0 / avg_frametime;

    // 1% low = average of worst 1% of frames
    const size_t one_pct_count = std::max<size_t>(1, frametimes.size() / 100);
    double one_pct_sum = 0.0;
    for (size_t i = 0; i < one_pct_count; ++i) one_pct_sum += frametimes[i];
    const double one_pct_low_fps = 1000.0 / (one_pct_sum / static_cast<double>(one_pct_count));

    // 0.1% low
    const size_t point_one_pct_count = std::max<size_t>(1, frametimes.size() / 1000);
    double point_one_pct_sum = 0.0;
    for (size_t i = 0; i < point_one_pct_count; ++i) point_one_pct_sum += frametimes[i];
    const double point_one_pct_low_fps = 1000.0 / (point_one_pct_sum / static_cast<double>(point_one_pct_count));

    return std::format(
        "=== Eden Performance Summary ===\n"
        "Total Frames:       {}\n"
        "Average FPS:        {:.1f}\n"
        "1% Low FPS:         {:.1f}\n"
        "0.1% Low FPS:       {:.1f}\n"
        "Avg Frametime:      {:.2f} ms\n"
        "Worst Frame:        {:.2f} ms\n"
        "Performance Dips:   {}\n"
        "Shader Compiles:    {}\n"
        "Total Draw Calls:   {}\n",
        timeline_.size(), avg_fps, one_pct_low_fps, point_one_pct_low_fps,
        avg_frametime, max_frametime, dip_count, total_shader_compiles, total_draw_calls);
}

} // namespace Core
