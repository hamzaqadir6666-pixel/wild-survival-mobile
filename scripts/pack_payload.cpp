// Host-side packer: builds the APK1 (LZSS + CRC32) payload embedded in
// AeroExplorerSetup.exe from the compiled Windows binaries.
//
// Usage: pack_payload <output.bin> <name>=<path> [<name>=<path> ...]
//
// Built with the host compiler (g++) because the archive format is pure C++17
// with no Windows dependencies.
#include "../src/common/pack_format.h"

#include <cstdio>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

bool ReadWholeFile(const std::string& path, std::vector<uint8_t>& out) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return false;
    in.seekg(0, std::ios::end);
    std::streamoff size = in.tellg();
    if (size < 0) return false;
    in.seekg(0, std::ios::beg);
    out.resize(static_cast<size_t>(size));
    if (size > 0) in.read(reinterpret_cast<char*>(out.data()), size);
    return static_cast<bool>(in) || in.eof();
}

} // namespace

int main(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: pack_payload <output.bin> <archiveName>=<inputPath> ...\n";
        return 2;
    }

    std::string outputPath = argv[1];
    std::vector<aeropak::PackedEntry> entries;

    for (int i = 2; i < argc; ++i) {
        std::string spec = argv[i];
        size_t eq = spec.find('=');
        if (eq == std::string::npos || eq == 0 || eq + 1 >= spec.size()) {
            std::cerr << "error: argument must be name=path (got '" << spec << "')\n";
            return 2;
        }
        aeropak::PackedEntry entry;
        entry.relativeName = spec.substr(0, eq);
        std::string inputPath = spec.substr(eq + 1);

        if (!ReadWholeFile(inputPath, entry.data)) {
            std::cerr << "error: cannot read '" << inputPath << "'\n";
            return 1;
        }
        if (entry.relativeName.find("..") != std::string::npos ||
            entry.relativeName.find('/') != std::string::npos ||
            entry.relativeName.find('\\') != std::string::npos) {
            std::cerr << "error: archive names must be plain file names\n";
            return 2;
        }
        entry.originalSize = static_cast<uint32_t>(entry.data.size());
        std::cout << "  packing " << entry.relativeName << " (" << entry.data.size() << " bytes)\n";
        entries.push_back(std::move(entry));
    }

    std::vector<uint8_t> archive = aeropak::BuildArchive(entries);
    if (archive.empty() || archive.size() > 64u * 1024u * 1024u) {
        std::cerr << "error: archive size out of range\n";
        return 1;
    }

    // Round-trip verification before we bake it into the setup executable.
    std::vector<aeropak::PackedEntry> restored;
    if (!aeropak::ExtractArchive(archive.data(), archive.size(), restored) ||
        restored.size() != entries.size()) {
        std::cerr << "error: archive failed round-trip verification\n";
        return 1;
    }
    for (size_t i = 0; i < entries.size(); ++i) {
        if (restored[i].relativeName != entries[i].relativeName ||
            restored[i].data != entries[i].data) {
            std::cerr << "error: archive mismatch for '" << entries[i].relativeName << "'\n";
            return 1;
        }
    }

    std::ofstream out(outputPath, std::ios::binary | std::ios::trunc);
    if (!out) {
        std::cerr << "error: cannot write '" << outputPath << "'\n";
        return 1;
    }
    out.write(reinterpret_cast<const char*>(archive.data()),
              static_cast<std::streamsize>(archive.size()));
    out.close();
    if (!out) {
        std::cerr << "error: short write to '" << outputPath << "'\n";
        return 1;
    }

    uint64_t raw = 0;
    for (const auto& e : entries) raw += e.data.size();
    std::cout << "  archive: " << archive.size() << " bytes (from " << raw << " raw bytes, "
              << entries.size() << " entries)\n";
    return 0;
}
