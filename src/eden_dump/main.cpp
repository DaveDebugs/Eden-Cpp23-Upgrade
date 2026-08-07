#include <iostream>
#include <memory>
#include <string>

#include <fmt/format.h>

#include "core/crypto/key_manager.h"
#include "core/file_sys/content_archive.h"
#include "core/file_sys/partition_filesystem.h"
#include "core/file_sys/romfs.h"
#include "core/file_sys/vfs/vfs.h"
#include "core/file_sys/vfs/vfs_real.h"
#include "core/loader/loader.h"

int main(int argc, char** argv) {
    if (argc < 3) {
        fmt::print(stderr, "Usage: eden-dump <input_rom.nsp/nca/xci> <output_directory>\n");
        return 1;
    }

    std::string input_path = argv[1];
    std::string output_path = argv[2];

    fmt::print("Eden Dump Tool\n");
    fmt::print("Input File: {}\n", input_path);
    fmt::print("Output Directory: {}\n", output_path);

    // Initialize Cryptographic Keys
    Core::Crypto::KeyManager::Instance();

    auto vfs = std::make_shared<FileSys::RealVfsFilesystem>();

    auto input_file = vfs->OpenFile(input_path, FileSys::OpenMode::Read);
    if (!input_file) {
        fmt::print(stderr, "Failed to open input file: {}\n", input_path);
        return 1;
    }

    auto out_dir = vfs->CreateDirectory(output_path, FileSys::OpenMode::ReadWrite);
    if (!out_dir) {
        fmt::print(stderr, "Failed to create/open output directory: {}\n", output_path);
        return 1;
    }

    auto file_type = Loader::IdentifyFile(input_file);
    fmt::print("File type identified as: {}\n", Loader::GetFileTypeString(file_type));

    auto extract_romfs = [&](const FileSys::VirtualFile& rfs, const std::string& prefix) {
        if (!rfs) return;
        auto romfs_dir = FileSys::ExtractRomFS(rfs);
        if (!romfs_dir) {
            fmt::print(stderr, "Failed to extract RomFS from {}\n", prefix);
            return;
        }
        
        auto target_dir = out_dir->CreateSubdirectory(prefix);
        if (!target_dir) target_dir = out_dir; // fallback if it fails
        
        fmt::print("Extracting RomFS to {}...\n", target_dir->GetName());
        if (FileSys::VfsRawCopyD(romfs_dir, target_dir)) {
            fmt::print("Extraction successful for {}!\n", prefix);
        } else {
            fmt::print(stderr, "Extraction failed during copy for {}!\n", prefix);
        }
    };

    if (file_type == Loader::FileType::NCA) {
        FileSys::NCA nca(input_file);
        if (nca.GetStatus() != Loader::ResultStatus::Success) {
            fmt::print(stderr, "Failed to parse NCA: {}\n", Loader::GetResultStatusString(nca.GetStatus()));
            return 1;
        }
        extract_romfs(nca.GetRomFS(), "nca_romfs");
    } else if (file_type == Loader::FileType::NSP || file_type == Loader::FileType::XCI) {
        FileSys::PartitionFilesystem pfs(input_file);
        if (pfs.GetStatus() != Loader::ResultStatus::Success) {
            fmt::print(stderr, "Failed to parse NSP/XCI partition: {}\n", Loader::GetResultStatusString(pfs.GetStatus()));
            return 1;
        }
        for (const auto& file : pfs.GetFiles()) {
            if (file->GetExtension() == "nca") {
                FileSys::NCA nca(file);
                if (nca.GetStatus() == Loader::ResultStatus::Success && nca.GetRomFS() != nullptr) {
                    fmt::print("Found RomFS in NCA: {}\n", file->GetName());
                    extract_romfs(nca.GetRomFS(), file->GetName() + "_romfs");
                }
            }
        }
    } else {
        fmt::print(stderr, "Unsupported file format for extraction.\n");
        return 1;
    }

    return 0;
}

#define VMA_IMPLEMENTATION
#include "video_core/vulkan_common/vma.h"
