// Navigation, filesystem enumeration, sorting/filtering and history for Aero Explorer.
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0a00
#endif

#include "app.h"

#include <algorithm>
#include <cwctype>

using namespace aero;

namespace {

bool IsAltDrive(UINT type) {
    return type == DRIVE_REMOVABLE || type == DRIVE_CDROM;
}

std::wstring DriveTypeLabel(UINT type) {
    switch (type) {
        case DRIVE_REMOVABLE: return L"Removable Disk";
        case DRIVE_FIXED: return L"Local Disk";
        case DRIVE_CDROM: return L"DVD/CD-RW Drive";
        case DRIVE_RAMDISK: return L"RAM Disk";
        case DRIVE_REMOTE: return L"Network Drive";
        default: return L"Local Disk";
    }
}

} // namespace

std::wstring ExplorerApp::ResolveLocalPath(const std::wstring& input) const {
    std::wstring text = TrimW(input);
    if (text.empty()) return L"";

    if (text.size() >= 2 && text.front() == L'"' && text.back() == L'"') {
        text = text.substr(1, text.size() - 2);
    }

    // Shell folder aliases mapped to real paths, e.g. "Desktop" or "$Recycle.Bin".
    if (text == L".") return currentPath_;

    wchar_t expanded[MAX_PATH * 2] = {};
    ExpandEnvironmentStringsW(text.c_str(), expanded, MAX_PATH * 2);
    if (expanded[0] != L'\0') text = expanded;

    if (text.size() == 2 && text[1] == L':') {
        text += L'\\';
    }

    wchar_t full[MAX_PATH * 2] = {};
    if (GetFullPathNameW(text.c_str(), MAX_PATH * 2, full, nullptr) > 0) {
        DWORD attrs = GetFileAttributesW(full);
        if (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
            return full;
        }
    }

    // Relative to the current folder.
    if (!IsFtpUrl(currentPath_) && currentPath_ != L"computer://" && text.size() >= 1) {
        std::wstring candidate = currentPath_;
        if (!candidate.empty() && candidate.back() != L'\\') candidate += L'\\';
        candidate += text;
        DWORD attrs = GetFileAttributesW(candidate.c_str());
        if (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
            return candidate;
        }
    }

    // Known shell folder names (Desktop, Documents, Downloads, ...).
    struct KnownEntry { const wchar_t* name; REFKNOWNFOLDERID id; };
    const KnownEntry known[] = {
        { L"desktop", FOLDERID_Desktop },
        { L"documents", FOLDERID_Documents },
        { L"downloads", FOLDERID_Downloads },
        { L"pictures", FOLDERID_Pictures },
        { L"music", FOLDERID_Music },
        { L"videos", FOLDERID_Videos },
    };
    for (const auto& entry : known) {
        if (ToLowerW(text) == entry.name) {
            PWSTR p = nullptr;
            if (SUCCEEDED(SHGetKnownFolderPath(entry.id, 0, nullptr, &p)) && p) {
                std::wstring out = p;
                CoTaskMemFree(p);
                return out;
            }
        }
    }
    return L"";
}

void ExplorerApp::NavigateTo(const std::wstring& rawPath, bool addHistory) {
    std::wstring target = TrimW(rawPath);
    // Shell integration passes quoted paths ("C:\Some Folder").
    if (target.size() >= 2 && target.front() == L'"' && target.back() == L'"') {
        target = TrimW(target.substr(1, target.size() - 2));
    }
    if (target.empty()) return;

    if (navigating_ && addHistory) {
        // Ignore re-entrant navigation while a network listing is outstanding.
        return;
    }

    if (IsFtpUrl(target)) {
        StartFtpList(target);
        if (addHistory) {
            if (historyPos_ + 1 < static_cast<int>(history_.size())) {
                history_.erase(history_.begin() + historyPos_ + 1, history_.end());
            }
            history_.push_back(target);
            historyPos_ = static_cast<int>(history_.size()) - 1;
        }
        return;
    }

    if (target == L"computer://" || target == L"Computer" || ToLowerW(target) == L"my computer") {
        if (addHistory) {
            if (historyPos_ + 1 < static_cast<int>(history_.size())) {
                history_.erase(history_.begin() + historyPos_ + 1, history_.end());
            }
            history_.push_back(L"computer://");
            historyPos_ = static_cast<int>(history_.size()) - 1;
        }
        LoadComputerRoot();
        return;
    }

    std::wstring resolved = ResolveLocalPath(target);
    if (resolved.empty()) {
        std::wstring msg = L"Windows cannot find '" + target + L"'.\n\nCheck the spelling and try again.";
        MessageBoxW(hwnd_, msg.c_str(), L"Windows 7 Aero Explorer", MB_ICONERROR | MB_OK);
        return;
    }

    std::wstring errorText;
    if (!LoadLocalFolder(resolved, errorText)) {
        if (!errorText.empty()) {
            MessageBoxW(hwnd_, errorText.c_str(), L"Windows 7 Aero Explorer", MB_ICONERROR | MB_OK);
        }
        return;
    }

    if (addHistory) {
        if (historyPos_ + 1 < static_cast<int>(history_.size())) {
            history_.erase(history_.begin() + historyPos_ + 1, history_.end());
        }
        history_.push_back(resolved);
        historyPos_ = static_cast<int>(history_.size()) - 1;
    }
}

void ExplorerApp::Refresh() {
    if (currentPath_ == L"computer://") {
        LoadComputerRoot();
    } else if (CurrentIsFtp()) {
        StartFtpList(currentPath_);
    } else {
        std::wstring errorText;
        LoadLocalFolder(currentPath_, errorText);
    }
    InvalidateAll();
}

void ExplorerApp::GoBack() {
    if (historyPos_ <= 0) return;
    --historyPos_;
    std::wstring target = history_[static_cast<size_t>(historyPos_)];
    NavigateTo(target, false);
}

void ExplorerApp::GoForward() {
    if (historyPos_ + 1 >= static_cast<int>(history_.size())) return;
    ++historyPos_;
    std::wstring target = history_[static_cast<size_t>(historyPos_)];
    NavigateTo(target, false);
}

void ExplorerApp::GoUp() {
    if (currentPath_ == L"computer://") return;

    if (CurrentIsFtp()) {
        FtpUrlInfo info = ParseFtpUrl(currentPath_);
        std::wstring parent = ParentFtpPath(info.remotePath);
        if (parent == NormalizeFtpPath(info.remotePath)) return;
        info.remotePath = parent;
        NavigateTo(BuildFtpUrl(info, true), true);
        return;
    }

    std::wstring path = currentPath_;
    while (path.size() > 3 && (path.back() == L'\\' || path.back() == L'/')) {
        path.pop_back();
    }
    size_t slash = path.rfind(L'\\');
    if (slash == std::wstring::npos || slash < 2) {
        NavigateTo(L"computer://", true);
        return;
    }
    NavigateTo(path.substr(0, slash), true);
}

void ExplorerApp::LoadComputerRoot() {
    currentPath_ = L"computer://";
    searchText_.clear();
    if (hSearchEdit_) SetWindowTextW(hSearchEdit_, L"");
    items_.clear();

    // "Hard Disk Drives" group: fixed volumes and USB drives with capacity bars.
    DWORD mask = GetLogicalDrives();
    for (int i = 0; i < 26; ++i) {
        if (!(mask & (1u << i))) continue;
        wchar_t root[8] = { static_cast<wchar_t>(L'A' + i), L':', L'\\', L'\0' };
        UINT type = GetDriveTypeW(root);
        if (type == DRIVE_NO_ROOT_DIR || type == DRIVE_UNKNOWN) continue;

        FileEntry drive;
        drive.name = std::wstring(root, 2);
        drive.fullPath = root;
        drive.isDrive = true;
        drive.isDirectory = true;
        drive.hasCapacity = (type == DRIVE_FIXED || type == DRIVE_REMOVABLE || type == DRIVE_RAMDISK);
        drive.group = IsAltDrive(type) ? ComputerGroup::RemovableOrOptical : ComputerGroup::HardDisk;

        wchar_t label[MAX_PATH + 1] = {};
        GetVolumeInformationW(root, label, MAX_PATH, nullptr, nullptr, nullptr, nullptr, 0);
        std::wstring display = (label[0] != L'\0') ? label : DriveTypeLabel(type);
        drive.displayName = display + L" (" + std::wstring(root, 2) + L")";

        if (drive.hasCapacity) {
            ULARGE_INTEGER freeBytes = {}, totalBytes = {};
            if (GetDiskFreeSpaceExW(root, &freeBytes, &totalBytes, nullptr)) {
                drive.freeBytes = freeBytes.QuadPart;
                drive.totalBytes = totalBytes.QuadPart;
            }
        }

        drive.typeName = DriveTypeLabel(type);
        drive.modifiedText.clear();
        CachedFileVisuals vis = icons_.GetForLocalItem(root, drive.displayName, true, true);
        drive.iconSmall = vis.iconSmall;
        drive.iconLarge = vis.iconLarge;
        items_.push_back(std::move(drive));
    }

    // Network + FTP group as Windows 7 "Network Location" tiles.
    {
        FileEntry net;
        net.name = L"Network";
        net.displayName = L"Network";
        net.fullPath = L"shell:network";
        net.typeName = L"Network Location";
        net.group = ComputerGroup::NetworkOrFtp;
        net.iconSmall = icons_.GetNetworkIconSmall();
        net.iconLarge = icons_.GetNetworkIconLarge();
        items_.push_back(std::move(net));
    }
    for (size_t i = 0; i < ftpProfiles_.size(); ++i) {
        const auto& p = ftpProfiles_[i];
        FileEntry entry;
        entry.name = p.title.empty() ? p.host : p.title;
        entry.displayName = entry.name;
        entry.isDirectory = true;
        entry.isFtpBookmark = true;
        entry.ftpBookmarkIndex = static_cast<int>(i);
        entry.group = ComputerGroup::NetworkOrFtp;
        entry.typeName = L"FTP Site";
        entry.modifiedText.clear();
        FtpUrlInfo info;
        info.valid = true;
        info.host = p.host;
        info.port = p.port;
        info.username = p.username;
        info.password = p.password;
        info.explicitCredentials = !p.anonymous;
        info.remotePath = p.initialPath;
        info.passive = p.passive;
        info.useFtps = p.useFtps;
        entry.fullPath = BuildFtpUrl(info, true);
        entry.iconSmall = icons_.GetNetworkIconSmall();
        entry.iconLarge = icons_.GetNetworkIconLarge();
        items_.push_back(std::move(entry));
    }

    navigating_ = false;
    SetWindowTextW(hwnd_, L"Computer - Windows 7 Aero Explorer");
    ApplySortAndFilter();
    SyncTreeSelection();
    UpdateStatusFromFolder();
    InvalidateAll();
}

bool ExplorerApp::LoadLocalFolder(const std::wstring& path, std::wstring& errorText) {
    WIN32_FIND_DATAW fd = {};
    std::wstring pattern = path;
    if (!pattern.empty() && pattern.back() != L'\\') pattern += L'\\';
    std::wstring search = pattern + L"*";

    HANDLE hFind = FindFirstFileExW(search.c_str(), FindExInfoBasic, &fd,
                                    FindExSearchNameMatch, nullptr, FIND_FIRST_EX_LARGE_FETCH);
    if (hFind == INVALID_HANDLE_VALUE) {
        DWORD err = GetLastError();
        if (err == ERROR_ACCESS_DENIED) {
            errorText = L"Access is denied.\n\n" + path +
                        L"\n\nTip: run Aero Explorer as administrator to browse this location.";
        } else if (err == ERROR_FILE_NOT_FOUND) {
            // Empty folder is perfectly valid.
            items_.clear();
            currentPath_ = path;
            SetWindowTextW(hwnd_, (path + L" - Windows 7 Aero Explorer").c_str());
            ApplySortAndFilter();
            SyncTreeSelection();
            UpdateStatusFromFolder();
            InvalidateAll();
            return true;
        } else {
            wchar_t msg[512] = {};
            FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                           nullptr, err, 0, msg, 512, nullptr);
            errorText = L"Windows cannot access:\n" + path + L"\n\n" + TrimW(msg);
        }
        return false;
    }

    items_.clear();
    std::wstring base = path;
    if (!base.empty() && base.back() != L'\\') base += L'\\';

    do {
        std::wstring name = fd.cFileName;
        if (name == L"." || name == L"..") continue;

        bool isDir = (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        bool hidden = (fd.dwFileAttributes & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM)) != 0;
        if (hidden && !showHidden_) continue;
        if (name == L"desktop.ini") continue;

        FileEntry entry;
        entry.name = name;
        entry.displayName = name;
        entry.fullPath = base + name;
        entry.isDirectory = isDir;
        entry.attributes = fd.dwFileAttributes;
        entry.modifiedTime = fd.ftLastWriteTime;
        entry.modifiedText = AeroFtpClient::FormatFileTimeWin7(fd.ftLastWriteTime);
        entry.sizeBytes = (static_cast<uint64_t>(fd.nFileSizeHigh) << 32) | fd.nFileSizeLow;

        CachedFileVisuals vis = icons_.GetForLocalItem(entry.fullPath, name, isDir, false);
        entry.iconSmall = vis.iconSmall;
        entry.iconLarge = vis.iconLarge;
        entry.typeName = vis.typeName.empty() ? (isDir ? L"File folder" : L"File") : vis.typeName;
        items_.push_back(std::move(entry));
    } while (FindNextFileW(hFind, &fd));

    FindClose(hFind);

    currentPath_ = path;
    navigating_ = false;
    SetWindowTextW(hwnd_, (path + L" - Windows 7 Aero Explorer").c_str());
    ApplySortAndFilter();
    SyncTreeSelection();
    UpdateStatusFromFolder();
    InvalidateAll();
    return true;
}

void ExplorerApp::SortItems() {
    std::vector<FileEntry>& v = items_;
    auto nameLess = [](const FileEntry& a, const FileEntry& b) {
        return StrCmpLogicalW(a.displayName.c_str(), b.displayName.c_str()) < 0;
    };
    auto sortFn = [&](const FileEntry& a, const FileEntry& b) -> bool {
        // Folders always precede files, exactly like Windows 7.
        if (a.isDirectory != b.isDirectory) return a.isDirectory;
        switch (sortCol_) {
            case SortColumn::DateModified: {
                int cmp = CompareFileTime(&a.modifiedTime, &b.modifiedTime);
                if (cmp != 0) return sortAsc_ ? (cmp < 0) : (cmp > 0);
                return nameLess(a, b);
            }
            case SortColumn::Type: {
                int cmp = StrCmpLogicalW(a.typeName.c_str(), b.typeName.c_str());
                if (cmp != 0) return sortAsc_ ? (cmp < 0) : (cmp > 0);
                return nameLess(a, b);
            }
            case SortColumn::Size: {
                if (a.sizeBytes != b.sizeBytes) {
                    return sortAsc_ ? (a.sizeBytes < b.sizeBytes) : (a.sizeBytes > b.sizeBytes);
                }
                return nameLess(a, b);
            }
            case SortColumn::Name:
            default: {
                bool less = nameLess(a, b);
                return sortAsc_ ? less : !less;
            }
        }
    };

    std::stable_sort(v.begin(), v.end(), sortFn);
}

void ExplorerApp::ApplySortAndFilter() {
    SortItems();

    display_.clear();
    std::wstring needle = ToLowerW(TrimW(searchText_));
    for (size_t i = 0; i < items_.size(); ++i) {
        if (!needle.empty() && ToLowerW(items_[i].displayName).find(needle) == std::wstring::npos) {
            continue;
        }
        display_.push_back(i);
    }

    for (auto& item : items_) item.selected = false;
    anchorDisplay_ = -1;
    scrollY_ = 0;
    contentHeight_ = 0;
    RelayoutItems();
    UpdateScrollBar();
    InvalidateCanvas();
}

std::vector<int> ExplorerApp::SelectedIndices() const {
    std::vector<int> out;
    for (size_t pos = 0; pos < display_.size(); ++pos) {
        if (items_[display_[pos]].selected) out.push_back(static_cast<int>(pos));
    }
    return out;
}

std::wstring ExplorerApp::ItemSubtitle(const FileEntry& item) const {
    if (item.isDrive) {
        if (item.hasCapacity && item.totalBytes > 0) {
            return FormatDriveSpaceWin7(item.freeBytes, item.totalBytes);
        }
        return item.typeName;
    }
    if (item.isFtpBookmark) {
        FtpUrlInfo info = ParseFtpUrl(item.fullPath);
        return info.host;
    }
    if (item.isDirectory || item.isFtpItem) {
        return item.typeName.empty() ? L"File folder" : item.typeName;
    }
    return FormatBytesWin7(item.sizeBytes);
}

std::wstring ExplorerApp::StatusText() const {
    if (navigating_) return L"Connecting...";
    if (!lastError_.empty()) return lastError_;
    if (!progressText_.empty() && progressPct_ > 0 && progressPct_ < 100) {
        return progressText_;
    }

    size_t selCount = 0;
    uint64_t selBytes = 0;
    for (const auto& item : items_) {
        if (item.selected && !item.isDirectory) {
            ++selCount;
            selBytes += item.sizeBytes;
        } else if (item.selected) {
            ++selCount;
        }
    }

    if (selCount > 1) {
        return std::to_wstring(selCount) + L" items selected  " + FormatBytesWin7(selBytes);
    }

    if (CurrentIsFtp()) {
        FtpUrlInfo info = ParseFtpUrl(currentPath_);
        return L"FTP: " + info.host + L"  |  " + std::to_wstring(display_.size()) + L" items";
    }
    if (currentPath_ == L"computer://") {
        return std::to_wstring(display_.size()) + L" drives and locations";
    }
    return std::to_wstring(display_.size()) + L" items";
}

std::wstring ExplorerApp::AddressText() const {
    if (currentPath_ == L"computer://") return L"Computer";
    return currentPath_;
}

void ExplorerApp::UpdateStatusFromFolder() {
    if (!statusNote_.empty()) {
        lastError_ = statusNote_;
        statusNote_.clear();
    }
    InvalidateAll();
}
