// SPDX-FileCopyrightText: Copyright 2018 yuzu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include <span>
#include "core/crypto/encryption_layer.h"

namespace Core::Crypto {

EncryptionLayer::EncryptionLayer(FileSys::VirtualFile base_) : base(std::move(base_)) {}

std::string EncryptionLayer::GetName() const {
    return base->GetName();
}

std::size_t EncryptionLayer::GetSize() const {
    return base->GetSize();
}

bool EncryptionLayer::Resize(std::size_t new_size) {
    return false;
}

std::shared_ptr<FileSys::VfsDirectory> EncryptionLayer::GetContainingDirectory() const {
    return base->GetContainingDirectory();
}

bool EncryptionLayer::IsWritable() const {
    return false;
}

bool EncryptionLayer::IsReadable() const {
    return true;
}

std::size_t EncryptionLayer::Write(std::span<const u8> data_span, std::size_t offset) {
    const u8* data = data_span.data();
    std::size_t length = data_span.size_bytes();
    return 0;
}

bool EncryptionLayer::Rename(std::string_view name) {
    return base->Rename(name);
}
} // namespace Core::Crypto
