// SPDX-FileCopyrightText: Copyright 2018 yuzu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <memory>

#include "common/common_types.h"

namespace FileSys {

class VfsDirectory;
class VfsFile;
class VfsFilesystem;

// Declarations for Vfs* pointer types

using VirtualDir = std::shared_ptr<VfsDirectory>;
using VirtualFile = std::shared_ptr<VfsFile>;
using VirtualFilesystem = std::shared_ptr<VfsFilesystem>;

struct FileTimeStampRaw {
    u64 created{};
    u64 accessed{};
    u64 modified{};
    u64 padding{};
};
static_assert(sizeof(FileTimeStampRaw) == 32, "FileTimeStampRaw must be exactly 32 bytes");
static_assert(std::is_trivially_copyable_v<FileTimeStampRaw>, "FileTimeStampRaw must be trivially copyable");
static_assert(std::is_standard_layout_v<FileTimeStampRaw>, "FileTimeStampRaw must be standard layout");

} // namespace FileSys
