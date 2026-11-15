#pragma once

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace aeropak {

static constexpr uint32_t kMagic = 0x314B5041u; // "APK1"

inline uint32_t ComputeCrc32(const uint8_t* data, size_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (int b = 0; b < 8; ++b) {
            uint32_t mask = -(crc & 1u);
            crc = (crc >> 1) ^ (0xEDB88320u & mask);
        }
    }
    return ~crc;
}

// Fast byte-aligned LZSS compressor (4KB sliding window, 3..18 byte match length)
inline std::vector<uint8_t> CompressLzss(const std::vector<uint8_t>& src) {
    std::vector<uint8_t> out;
    out.reserve(src.size());

    constexpr int kWinSize = 4096;
    constexpr int kMinMatch = 3;
    constexpr int kMaxMatch = 18;
    constexpr int kHashSize = 8192;

    std::vector<int> head(kHashSize, -1);
    std::vector<int> prev(src.size(), -1);

    auto hash3 = [&](size_t pos) -> int {
        uint32_t h = (static_cast<uint32_t>(src[pos]) << 10) ^
                     (static_cast<uint32_t>(src[pos + 1]) << 5) ^
                     static_cast<uint32_t>(src[pos + 2]);
        return static_cast<int>(h & (kHashSize - 1));
    };

    size_t pos = 0;
    const size_t n = src.size();

    while (pos < n) {
        size_t flagPos = out.size();
        out.push_back(0); // placeholder for 8-bit flag byte
        uint8_t flags = 0;

        for (int bit = 0; bit < 8 && pos < n; ++bit) {
            int bestLen = 0;
            int bestDist = 0;

            if (pos + kMinMatch <= n) {
                int h = hash3(pos);
                int cand = head[h];
                int chainSteps = 0;
                while (cand >= 0 && (static_cast<int>(pos) - cand) <= kWinSize && chainSteps < 48) {
                    int maxL = static_cast<int>(std::min<size_t>(kMaxMatch, n - pos));
                    if (src[cand + bestLen] == src[pos + bestLen]) {
                        int l = 0;
                        while (l < maxL && src[cand + l] == src[pos + l]) {
                            ++l;
                        }
                        if (l >= kMinMatch && l > bestLen) {
                            bestLen = l;
                            bestDist = static_cast<int>(pos) - cand;
                            if (bestLen == kMaxMatch) break;
                        }
                    }
                    cand = prev[cand];
                    ++chainSteps;
                }
            }

            if (bestLen >= kMinMatch) {
                flags |= static_cast<uint8_t>(1u << bit);
                uint16_t distMinus1 = static_cast<uint16_t>(bestDist - 1); // 0..4095 (12 bits)
                uint8_t lenMinus3 = static_cast<uint8_t>(bestLen - kMinMatch); // 0..15 (4 bits)
                uint8_t b0 = static_cast<uint8_t>(distMinus1 & 0xFFu);
                uint8_t b1 = static_cast<uint8_t>(((distMinus1 >> 8) & 0x0Fu) | (lenMinus3 << 4));
                out.push_back(b0);
                out.push_back(b1);

                for (int k = 0; k < bestLen; ++k) {
                    if (pos + k + kMinMatch <= n) {
                        int h = hash3(pos + k);
                        prev[pos + k] = head[h];
                        head[h] = static_cast<int>(pos + k);
                    }
                }
                pos += static_cast<size_t>(bestLen);
            } else {
                out.push_back(src[pos]);
                if (pos + kMinMatch <= n) {
                    int h = hash3(pos);
                    prev[pos] = head[h];
                    head[h] = static_cast<int>(pos);
                }
                ++pos;
            }
        }

        out[flagPos] = flags;
    }

    return out;
}

inline bool DecompressLzss(const uint8_t* comp, size_t compLen, size_t expectedSize, std::vector<uint8_t>& out) {
    out.clear();
    out.reserve(expectedSize);
    size_t pos = 0;

    while (pos < compLen && out.size() < expectedSize) {
        uint8_t flags = comp[pos++];
        for (int bit = 0; bit < 8 && pos < compLen && out.size() < expectedSize; ++bit) {
            if (flags & (1u << bit)) {
                if (pos + 2 > compLen) return false;
                uint8_t b0 = comp[pos++];
                uint8_t b1 = comp[pos++];
                size_t dist = static_cast<size_t>((b0 | ((b1 & 0x0Fu) << 8)) + 1);
                size_t len = static_cast<size_t>((b1 >> 4) + 3);
                if (dist == 0 || dist > out.size()) return false;
                if (out.size() + len > expectedSize) return false;
                size_t copyPos = out.size() - dist;
                for (size_t k = 0; k < len; ++k) {
                    out.push_back(out[copyPos + k]);
                }
            } else {
                out.push_back(comp[pos++]);
            }
        }
    }

    return out.size() == expectedSize;
}

struct PackedEntry {
    std::string relativeName; // UTF-8 filename (e.g. "AeroExplorer.exe")
    uint32_t originalSize = 0;
    uint32_t crc32 = 0;
    std::vector<uint8_t> data; // Uncompressed bytes
};

inline void WriteU32LE(std::vector<uint8_t>& buf, uint32_t v) {
    buf.push_back(static_cast<uint8_t>(v & 0xFFu));
    buf.push_back(static_cast<uint8_t>((v >> 8) & 0xFFu));
    buf.push_back(static_cast<uint8_t>((v >> 16) & 0xFFu));
    buf.push_back(static_cast<uint8_t>((v >> 24) & 0xFFu));
}

inline bool ReadU32LE(const uint8_t* data, size_t len, size_t& offset, uint32_t& out) {
    if (offset + 4 > len) return false;
    out = static_cast<uint32_t>(data[offset]) |
          (static_cast<uint32_t>(data[offset + 1]) << 8) |
          (static_cast<uint32_t>(data[offset + 2]) << 16) |
          (static_cast<uint32_t>(data[offset + 3]) << 24);
    offset += 4;
    return true;
}

inline std::vector<uint8_t> BuildArchive(const std::vector<PackedEntry>& entries) {
    std::vector<uint8_t> blob;
    WriteU32LE(blob, kMagic);
    WriteU32LE(blob, static_cast<uint32_t>(entries.size()));

    for (const auto& e : entries) {
        uint32_t crc = ComputeCrc32(e.data.data(), e.data.size());
        std::vector<uint8_t> comp = CompressLzss(e.data);
        WriteU32LE(blob, static_cast<uint32_t>(e.relativeName.size()));
        blob.insert(blob.end(), e.relativeName.begin(), e.relativeName.end());
        WriteU32LE(blob, static_cast<uint32_t>(e.data.size()));
        WriteU32LE(blob, static_cast<uint32_t>(comp.size()));
        WriteU32LE(blob, crc);
        blob.insert(blob.end(), comp.begin(), comp.end());
    }
    return blob;
}

inline bool ExtractArchive(const uint8_t* archiveBytes, size_t archiveLen, std::vector<PackedEntry>& outEntries) {
    outEntries.clear();
    size_t off = 0;
    uint32_t magic = 0;
    uint32_t count = 0;
    if (!ReadU32LE(archiveBytes, archiveLen, off, magic) || magic != kMagic) return false;
    if (!ReadU32LE(archiveBytes, archiveLen, off, count) || count > 256) return false;

    outEntries.reserve(count);
    for (uint32_t i = 0; i < count; ++i) {
        uint32_t nameLen = 0, origSize = 0, compSize = 0, crc = 0;
        if (!ReadU32LE(archiveBytes, archiveLen, off, nameLen) || nameLen == 0 || nameLen > 512) return false;
        if (off + nameLen > archiveLen) return false;
        std::string name(reinterpret_cast<const char*>(archiveBytes + off), nameLen);
        off += nameLen;

        if (!ReadU32LE(archiveBytes, archiveLen, off, origSize)) return false;
        if (!ReadU32LE(archiveBytes, archiveLen, off, compSize)) return false;
        if (!ReadU32LE(archiveBytes, archiveLen, off, crc)) return false;
        if (off + compSize > archiveLen) return false;

        PackedEntry entry;
        entry.relativeName = std::move(name);
        entry.originalSize = origSize;
        entry.crc32 = crc;
        if (origSize == 0) {
            entry.data.clear();
        } else {
            if (!DecompressLzss(archiveBytes + off, compSize, origSize, entry.data)) {
                return false;
            }
        }
        off += compSize;

        uint32_t actualCrc = ComputeCrc32(entry.data.data(), entry.data.size());
        if (actualCrc != crc) {
            return false;
        }
        outEntries.push_back(std::move(entry));
    }
    return true;
}

} // namespace aeropak
