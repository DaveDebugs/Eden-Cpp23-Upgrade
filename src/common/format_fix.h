// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <format>

// In C++23, MSVC treats unsigned char (u8) as a character type in std::format.
// This causes crashes when using integer format specs like {:02X} on u8 values,
// because the formatter routes through _Write_escaped instead of _Write_integral.
// This specialization forces u8 to always format as an unsigned integer.
template <>
struct std::formatter<unsigned char, char> : std::formatter<unsigned int, char> {
    auto format(unsigned char value, auto& ctx) const {
        return std::formatter<unsigned int, char>::format(static_cast<unsigned int>(value), ctx);
    }
};
