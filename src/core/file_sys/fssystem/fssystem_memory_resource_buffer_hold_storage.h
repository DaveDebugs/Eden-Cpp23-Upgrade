// SPDX-FileCopyrightText: Copyright 2023 yuzu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <span>
#include "core/file_sys/fssystem/fs_i_storage.h"

namespace FileSys {

class MemoryResourceBufferHoldStorage : public IStorage {
    YUZU_NON_COPYABLE(MemoryResourceBufferHoldStorage);
    YUZU_NON_MOVEABLE(MemoryResourceBufferHoldStorage);

public:
    MemoryResourceBufferHoldStorage(VirtualFile storage, size_t buffer_size)
        : m_storage(std::move(storage)), m_buffer(::operator new(buffer_size)),
          m_buffer_size(buffer_size) {}

    virtual ~MemoryResourceBufferHoldStorage() {
        // If we have a buffer, deallocate it.
        if (m_buffer != nullptr) {
            ::operator delete(m_buffer);
        }
    }

    bool IsValid() const {
        return m_buffer != nullptr;
    }
    void* GetBuffer() const {
        return m_buffer;
    }

public:
    virtual size_t Read(std::span<u8> buffer_span, size_t offset) const override {
        u8* buffer = buffer_span.data();
        size_t size = buffer_span.size_bytes();
        // Check pre-conditions.
        ASSERT(m_storage != nullptr);

        return m_storage->Read(buffer, size, offset);
    }

    virtual size_t GetSize() const override {
        // Check pre-conditions.
        ASSERT(m_storage != nullptr);

        return m_storage->GetSize();
    }

    virtual size_t Write(std::span<const u8> buffer_span, size_t offset) override {
        const u8* buffer = buffer_span.data();
        size_t size = buffer_span.size_bytes();
        // Check pre-conditions.
        ASSERT(m_storage != nullptr);

        return m_storage->Write(buffer, size, offset);
    }

private:
    VirtualFile m_storage;
    void* m_buffer;
    size_t m_buffer_size;
};

} // namespace FileSys
