// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

// SPDX-FileCopyrightText: Copyright 2021 yuzu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <exception>
#include <string>
#include <utility>
#include <type_traits>
#include <format>
#include <tuple>

#include "common/logging.h"

namespace Shader {

template <typename T>
decltype(auto) FormatArgCast(T&& t) {
    if constexpr (std::is_enum_v<std::remove_cvref_t<T>>) {
        return static_cast<std::underlying_type_t<std::remove_cvref_t<T>>>(t);
    } else {
        return std::forward<T>(t);
    }
}

template <typename... Args>
std::string FormatExceptionMessage(const char* message, Args&&... args) {
    auto t = std::make_tuple(FormatArgCast(std::forward<Args>(args))...);
    return std::apply([&](const auto&... formatted_args) {
        return std::vformat(message, std::make_format_args(formatted_args...));
    }, t);
}

class Exception : public std::exception {
public:
    explicit Exception(std::string message) noexcept : err_message{std::move(message)} {}

    [[nodiscard]] const char* what() const noexcept override {
        return err_message.c_str();
    }

    void Prepend(std::string_view prepend) {
        err_message.insert(0, prepend);
    }

    void Append(std::string_view append) {
        err_message += append;
    }

private:
    std::string err_message;
};

class LogicError : public Exception {
public:
    template <typename... Args>
    explicit LogicError(const char* message, Args&&... args)
        : Exception{FormatExceptionMessage(message, std::forward<Args>(args)...)} {}
};

class RuntimeError : public Exception {
public:
    template <typename... Args>
    explicit RuntimeError(const char* message, Args&&... args)
        : Exception{FormatExceptionMessage(message, std::forward<Args>(args)...)} {}
};

class NotImplementedException : public Exception {
public:
    template <typename... Args>
    explicit NotImplementedException(const char* message, Args&&... args)
        : Exception{FormatExceptionMessage(message, std::forward<Args>(args)...)} {
        Append(" is not implemented");
    }
};

class InvalidArgument : public Exception {
public:
    template <typename... Args>
    explicit InvalidArgument(const char* message, Args&&... args)
        : Exception{FormatExceptionMessage(message, std::forward<Args>(args)...)} {}
};

} // namespace Shader
