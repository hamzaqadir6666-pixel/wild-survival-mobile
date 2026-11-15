#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <cstdint>
#include <string>
#include <vector>

namespace aero {

enum class ViewMode {
    Details = 0,
    Tiles = 1,
    LargeIcons = 2,
    List = 3,
    Content = 4
};

enum class SortColumn {
    Name = 0,
    DateModified = 1,
    Type = 2,
    Size = 3
};

enum class ComputerGroup {
    None = 0,
    HardDisk = 1,
    RemovableOrOptical = 2,
    NetworkOrFtp = 3
};

struct FileEntry {
    std::wstring name;
    std::wstring displayName;
    std::wstring fullPath;       // Local path or full FTP URL
    std::wstring remoteRelPath;  // Remote path when on FTP (e.g. "/pub/readme.txt")
    std::wstring typeName;
    std::wstring modifiedText;
    FILETIME modifiedTime = { 0, 0 };
    uint64_t sizeBytes = 0;
    uint64_t freeBytes = 0;
    uint64_t totalBytes = 0;
    DWORD attributes = 0;

    bool isDirectory = false;
    bool isDrive = false;
    bool hasCapacity = false;
    bool isFtpItem = false;
    bool isFtpBookmark = false;
    int ftpBookmarkIndex = -1;
    ComputerGroup group = ComputerGroup::None;

    bool selected = false;
    HICON iconSmall = nullptr; // 16x16 cached
    HICON iconLarge = nullptr; // 32x32 or 48x48 cached
    RECT hitRect = { 0, 0, 0, 0 };
};

struct FtpSiteProfile {
    std::wstring title;
    std::wstring host;
    uint16_t port = 21;
    bool anonymous = true;
    std::wstring username = L"anonymous";
    std::wstring password = L"anonymous@aeroexplorer.local";
    std::wstring initialPath = L"/";
    bool passive = true;
    bool useFtps = false;
};

struct FtpProgressPayload {
    std::wstring statusText;
    uint64_t doneBytes = 0;
    uint64_t totalBytes = 0;
    int percent = 0; // 0..100
};

struct FtpAsyncListResult {
    bool success = false;
    std::wstring fullUrl;
    std::wstring host;
    std::wstring remotePath;
    std::wstring errorMessage;
    std::vector<FileEntry> entries;
};

struct FtpAsyncOpResult {
    bool success = false;
    bool refreshAfter = false;
    std::wstring openLocalFileAfter; // Non-empty when double-clicking a remote file to view locally
    std::wstring message;
};

} // namespace aero
