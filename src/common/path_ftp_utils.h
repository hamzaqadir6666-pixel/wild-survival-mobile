#pragma once

#include <algorithm>
#include <cstdint>
#include <cwctype>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace aero {

struct FtpUrlInfo {
    bool valid = false;
    bool useFtps = false;
    bool passive = true;
    std::wstring host;
    uint16_t port = 21;
    std::wstring username = L"anonymous";
    std::wstring password = L"anonymous@aeroexplorer.local";
    bool explicitCredentials = false;
    std::wstring remotePath = L"/";
};

struct BreadcrumbPart {
    std::wstring label;
    std::wstring target;
};

inline std::wstring TrimW(const std::wstring& s) {
    size_t start = 0;
    while (start < s.size() && std::iswspace(s[start])) ++start;
    size_t end = s.size();
    while (end > start && std::iswspace(s[end - 1])) --end;
    return s.substr(start, end - start);
}

inline std::wstring ToLowerW(std::wstring s) {
    for (wchar_t& ch : s) {
        ch = static_cast<wchar_t>(std::towlower(ch));
    }
    return s;
}

inline bool StartsWithIgnoreCase(const std::wstring& s, const std::wstring& prefix) {
    if (s.size() < prefix.size()) return false;
    for (size_t i = 0; i < prefix.size(); ++i) {
        if (std::towlower(s[i]) != std::towlower(prefix[i])) return false;
    }
    return true;
}

inline int HexDigitValue(wchar_t c) {
    if (c >= L'0' && c <= L'9') return c - L'0';
    if (c >= L'a' && c <= L'f') return 10 + (c - L'a');
    if (c >= L'A' && c <= L'F') return 10 + (c - L'A');
    return -1;
}

inline std::wstring UrlDecodeW(const std::wstring& in) {
    std::string utf8;
    utf8.reserve(in.size());
    for (size_t i = 0; i < in.size(); ++i) {
        if (in[i] == L'%' && i + 2 < in.size()) {
            int hi = HexDigitValue(in[i + 1]);
            int lo = HexDigitValue(in[i + 2]);
            if (hi >= 0 && lo >= 0) {
                utf8.push_back(static_cast<char>((hi << 4) | lo));
                i += 2;
                continue;
            }
        }
        if (in[i] < 0x80) {
            utf8.push_back(static_cast<char>(in[i]));
        } else {
            // Preserve BMP non-ASCII directly as UTF-8
            uint32_t cp = static_cast<uint32_t>(in[i]);
            if (cp < 0x800) {
                utf8.push_back(static_cast<char>(0xC0 | (cp >> 6)));
                utf8.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
            } else {
                utf8.push_back(static_cast<char>(0xE0 | (cp >> 12)));
                utf8.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
                utf8.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
            }
        }
    }
    // Decode UTF-8 back to wstring
    std::wstring out;
    size_t i = 0;
    while (i < utf8.size()) {
        uint8_t b0 = static_cast<uint8_t>(utf8[i]);
        if (b0 < 0x80) {
            out.push_back(static_cast<wchar_t>(b0));
            ++i;
        } else if ((b0 & 0xE0) == 0xC0 && i + 1 < utf8.size()) {
            uint32_t cp = ((b0 & 0x1F) << 6) | (static_cast<uint8_t>(utf8[i + 1]) & 0x3F);
            out.push_back(static_cast<wchar_t>(cp));
            i += 2;
        } else if ((b0 & 0xF0) == 0xE0 && i + 2 < utf8.size()) {
            uint32_t cp = ((b0 & 0x0F) << 12) |
                          ((static_cast<uint8_t>(utf8[i + 1]) & 0x3F) << 6) |
                          (static_cast<uint8_t>(utf8[i + 2]) & 0x3F);
            out.push_back(static_cast<wchar_t>(cp));
            i += 3;
        } else {
            out.push_back(static_cast<wchar_t>(b0));
            ++i;
        }
    }
    return out;
}

inline std::wstring UrlEncodeCredentialW(const std::wstring& s) {
    std::wostringstream oss;
    oss << std::uppercase << std::hex;
    for (wchar_t ch : s) {
        if ((ch >= L'a' && ch <= L'z') || (ch >= L'A' && ch <= L'Z') ||
            (ch >= L'0' && ch <= L'9') || ch == L'-' || ch == L'_' || ch == L'.' || ch == L'~') {
            oss << ch;
        } else if (ch < 0x80) {
            oss << L'%' << std::setw(2) << std::setfill(L'0') << static_cast<int>(ch);
        } else {
            oss << ch;
        }
    }
    return oss.str();
}

inline std::wstring NormalizeFtpPath(const std::wstring& path) {
    if (path.empty()) return L"/";
    std::wstring cleaned;
    cleaned.reserve(path.size() + 2);
    for (wchar_t ch : path) {
        wchar_t c = (ch == L'\\') ? L'/' : ch;
        if (c == L'/' && !cleaned.empty() && cleaned.back() == L'/') continue;
        cleaned.push_back(c);
    }
    if (cleaned.empty() || cleaned.front() != L'/') {
        cleaned.insert(cleaned.begin(), L'/');
    }
    if (cleaned.size() > 1 && cleaned.back() == L'/') {
        cleaned.pop_back();
    }
    return cleaned;
}

inline std::wstring JoinFtpPath(const std::wstring& dir, const std::wstring& child) {
    std::wstring base = NormalizeFtpPath(dir);
    std::wstring sub = child;
    while (!sub.empty() && (sub.front() == L'/' || sub.front() == L'\\')) {
        sub.erase(sub.begin());
    }
    if (sub.empty()) return base;
    if (base == L"/") return L"/" + sub;
    return base + L"/" + sub;
}

inline std::wstring ParentFtpPath(const std::wstring& path) {
    std::wstring norm = NormalizeFtpPath(path);
    if (norm == L"/") return L"/";
    size_t slash = norm.rfind(L'/');
    if (slash == std::wstring::npos || slash == 0) return L"/";
    return norm.substr(0, slash);
}

inline bool IsFtpUrl(const std::wstring& input) {
    std::wstring t = TrimW(input);
    return StartsWithIgnoreCase(t, L"ftp://") || StartsWithIgnoreCase(t, L"ftps://");
}

inline FtpUrlInfo ParseFtpUrl(const std::wstring& rawUrl) {
    FtpUrlInfo info;
    std::wstring s = TrimW(rawUrl);
    size_t schemeLen = 0;
    if (StartsWithIgnoreCase(s, L"ftps://")) {
        info.useFtps = true;
        info.port = 21;
        schemeLen = 7;
    } else if (StartsWithIgnoreCase(s, L"ftp://")) {
        info.useFtps = false;
        info.port = 21;
        schemeLen = 6;
    } else {
        return info;
    }

    std::wstring rest = s.substr(schemeLen);
    if (rest.empty()) return info;

    std::wstring authority;
    size_t slashPos = rest.find(L'/');
    if (slashPos == std::wstring::npos) {
        authority = rest;
        info.remotePath = L"/";
    } else {
        authority = rest.substr(0, slashPos);
        info.remotePath = NormalizeFtpPath(UrlDecodeW(rest.substr(slashPos)));
    }

    if (authority.empty()) return info;

    std::wstring hostPort = authority;
    // Use rfind('@') so even unencoded '@' in username still splits on last '@' before host!
    size_t atPos = authority.rfind(L'@');
    if (atPos != std::wstring::npos) {
        info.explicitCredentials = true;
        std::wstring userPass = authority.substr(0, atPos);
        hostPort = authority.substr(atPos + 1);
        size_t colonPos = userPass.find(L':');
        if (colonPos == std::wstring::npos) {
            info.username = UrlDecodeW(userPass);
            info.password.clear();
        } else {
            info.username = UrlDecodeW(userPass.substr(0, colonPos));
            info.password = UrlDecodeW(userPass.substr(colonPos + 1));
        }
        if (info.username.empty()) {
            info.username = L"anonymous";
        }
    }

    // Parse host[:port] (including IPv6 [::1]:21)
    if (!hostPort.empty() && hostPort.front() == L'[') {
        size_t closeBracket = hostPort.find(L']');
        if (closeBracket == std::wstring::npos) return info;
        info.host = hostPort.substr(1, closeBracket - 1);
        if (closeBracket + 1 < hostPort.size() && hostPort[closeBracket + 1] == L':') {
            std::wstring portStr = hostPort.substr(closeBracket + 2);
            try {
                int p = std::stoi(portStr);
                if (p > 0 && p <= 65535) info.port = static_cast<uint16_t>(p);
            } catch (...) {
                return info;
            }
        }
    } else {
        size_t colonPos = hostPort.rfind(L':');
        if (colonPos != std::wstring::npos) {
            std::wstring portStr = hostPort.substr(colonPos + 1);
            info.host = hostPort.substr(0, colonPos);
            if (!portStr.empty()) {
                try {
                    int p = std::stoi(portStr);
                    if (p > 0 && p <= 65535) info.port = static_cast<uint16_t>(p);
                    else return info;
                } catch (...) {
                    return info;
                }
            }
        } else {
            info.host = hostPort;
        }
    }

    info.valid = !info.host.empty();
    return info;
}

inline std::wstring BuildFtpUrl(const FtpUrlInfo& info, bool includePassword = false) {
    std::wostringstream oss;
    oss << (info.useFtps ? L"ftps://" : L"ftp://");
    bool isAnon = (ToLowerW(info.username) == L"anonymous" || info.username.empty());
    if (!isAnon || info.explicitCredentials) {
        oss << UrlEncodeCredentialW(info.username);
        if (includePassword && !info.password.empty()) {
            oss << L":" << UrlEncodeCredentialW(info.password);
        }
        oss << L"@";
    }
    oss << info.host;
    if (info.port != 21) {
        oss << L":" << info.port;
    }
    std::wstring norm = NormalizeFtpPath(info.remotePath);
    oss << norm;
    return oss.str();
}

inline std::wstring FormatBytesWin7(uint64_t bytes) {
    const wchar_t* units[] = { L"bytes", L"KB", L"MB", L"GB", L"TB" };
    if (bytes < 1024) {
        return std::to_wstring(bytes) + L" " + units[0];
    }
    double val = static_cast<double>(bytes);
    int unitIdx = 0;
    while (val >= 1024.0 && unitIdx < 4) {
        val /= 1024.0;
        ++unitIdx;
    }
    std::wostringstream oss;
    if (val >= 100.0 || unitIdx == 1) {
        oss << static_cast<uint64_t>(val + 0.5) << L" " << units[unitIdx];
    } else if (val >= 10.0) {
        oss << std::fixed << std::setprecision(1) << val << L" " << units[unitIdx];
    } else {
        oss << std::fixed << std::setprecision(2) << val << L" " << units[unitIdx];
    }
    return oss.str();
}

inline std::wstring FormatDriveSpaceWin7(uint64_t freeBytes, uint64_t totalBytes) {
    return FormatBytesWin7(freeBytes) + L" free of " + FormatBytesWin7(totalBytes);
}

inline std::vector<BreadcrumbPart> BuildBreadcrumbs(const std::wstring& location) {
    std::vector<BreadcrumbPart> parts;
    if (location.empty() || location == L"computer://") {
        parts.push_back({ L"Computer", L"computer://" });
        return parts;
    }
    if (IsFtpUrl(location)) {
        FtpUrlInfo ftp = ParseFtpUrl(location);
        if (!ftp.valid) {
            parts.push_back({ location, location });
            return parts;
        }
        FtpUrlInfo rootInfo = ftp;
        rootInfo.remotePath = L"/";
        std::wstring hostLabel = L"FTP (" + ftp.host + L")";
        parts.push_back({ L"Computer", L"computer://" });
        parts.push_back({ hostLabel, BuildFtpUrl(rootInfo, true) });

        std::wstring norm = NormalizeFtpPath(ftp.remotePath);
        if (norm != L"/") {
            std::wstring accum;
            size_t start = 1;
            while (start < norm.size()) {
                size_t slash = norm.find(L'/', start);
                std::wstring seg = (slash == std::wstring::npos)
                                       ? norm.substr(start)
                                       : norm.substr(start, slash - start);
                if (!seg.empty()) {
                    accum += L"/" + seg;
                    FtpUrlInfo segInfo = ftp;
                    segInfo.remotePath = accum;
                    parts.push_back({ seg, BuildFtpUrl(segInfo, true) });
                }
                if (slash == std::wstring::npos) break;
                start = slash + 1;
            }
        }
        return parts;
    }

    // Local Windows path (e.g., C:\Users\Public\Documents)
    parts.push_back({ L"Computer", L"computer://" });
    std::wstring norm = location;
    for (wchar_t& ch : norm) {
        if (ch == L'/') ch = L'\\';
    }
    while (norm.size() > 3 && norm.back() == L'\\') {
        norm.pop_back();
    }

    if (norm.size() >= 2 && norm[1] == L':') {
        std::wstring driveRoot = norm.substr(0, 2) + L"\\";
        std::wstring driveLabel = L"Local Disk (" + norm.substr(0, 2) + L")";
        parts.push_back({ driveLabel, driveRoot });

        if (norm.size() > 3) {
            std::wstring accum = norm.substr(0, 2);
            size_t start = 3;
            while (start < norm.size()) {
                size_t sep = norm.find(L'\\', start);
                std::wstring seg = (sep == std::wstring::npos)
                                       ? norm.substr(start)
                                       : norm.substr(start, sep - start);
                if (!seg.empty()) {
                    accum += L"\\" + seg;
                    parts.push_back({ seg, accum });
                }
                if (sep == std::wstring::npos) break;
                start = sep + 1;
            }
        }
    } else {
        parts.push_back({ norm, norm });
    }
    return parts;
}

inline std::wstring ObfuscateSecret(const std::wstring& plain) {
    static const uint16_t kKey[8] = { 0x4E71, 0x9A3C, 0x2F55, 0xB81E, 0x6D09, 0xC4A2, 0x17F3, 0x85D4 };
    std::wostringstream oss;
    oss << std::uppercase << std::hex;
    for (size_t i = 0; i < plain.size(); ++i) {
        uint16_t v = static_cast<uint16_t>(plain[i]) ^ kKey[i % 8] ^ static_cast<uint16_t>(i * 37);
        oss << std::setw(4) << std::setfill(L'0') << v;
    }
    return oss.str();
}

inline std::wstring DeobfuscateSecret(const std::wstring& hexStr) {
    static const uint16_t kKey[8] = { 0x4E71, 0x9A3C, 0x2F55, 0xB81E, 0x6D09, 0xC4A2, 0x17F3, 0x85D4 };
    if (hexStr.size() % 4 != 0) return L"";
    std::wstring out;
    out.reserve(hexStr.size() / 4);
    for (size_t i = 0; i < hexStr.size(); i += 4) {
        uint16_t v = 0;
        for (size_t j = 0; j < 4; ++j) {
            int d = HexDigitValue(hexStr[i + j]);
            if (d < 0) return L"";
            v = static_cast<uint16_t>((v << 4) | d);
        }
        size_t idx = i / 4;
        wchar_t ch = static_cast<wchar_t>(v ^ kKey[idx % 8] ^ static_cast<uint16_t>(idx * 37));
        out.push_back(ch);
    }
    return out;
}

} // namespace aero
