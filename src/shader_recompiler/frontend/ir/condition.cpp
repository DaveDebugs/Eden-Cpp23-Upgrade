// SPDX-FileCopyrightText: Copyright 2021 yuzu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include <format>
#include <string>



#include "shader_recompiler/frontend/ir/condition.h"

namespace Shader::IR {

std::string NameOf(Condition condition) {
    std::string ret;
    if (condition.GetFlowTest() != FlowTest::T) {
        ret = std::format("{}", condition.GetFlowTest());
    }
    const auto [pred, negated]{condition.GetPred()};
    if (!ret.empty()) {
        ret += '&';
    }
    if (negated) {
        ret += '!';
    }
    ret += std::format("{}", pred);
    return ret;
}

} // namespace Shader::IR
