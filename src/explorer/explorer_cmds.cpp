// Menus, commands, clipboard and local file operations for Aero Explorer.
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0a00
#endif

#include "app.h"
#include "dialogs.h"

#include <shlobj.h>
#include <algorithm>
#include <memory>

using namespace aero;

namespace {

bool IsFolderPath(const std::wstring& path) {
    if (IsFtpUrl(path) || path == L"computer://") return true;
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring LeafName(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    return (slash == std::wstring::npos) ? path : path.substr(slash + 1);
}

bool CopyFolderRecursive(const std::wstring& from, const std::wstring& to) {
    CreateDirectoryW(to.c_str(), nullptr);
    std::wstring pattern = from + L"\\*";
    WIN32_FIND_DATAW fd = {};
    HANDLE hFind = FindFirstFileW(pattern.c_str(), &fd);
    if (hFind == INVALID_HANDLE_VALUE) return false;
    bool ok = true;
    do {
        std::wstring name = fd.cFileName;
        if (name == L"." || name == L"..") continue;
        std::wstring src = from + L"\\" + name;
        std::wstring dst = to + L"\\" + name;
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            if (!CopyFolderRecursive(src, dst)) ok = false;
        } else {
            if (!CopyFileW(src.c_str(), dst.c_str(), FALSE)) ok = false;
        }
    } while (FindNextFileW(hFind, &fd));
    FindClose(hFind);
    return ok;
}

} // namespace

// ---------------------------------------------------------------------------
// Menu construction
// ---------------------------------------------------------------------------
void ExplorerApp::ShowOrganizeMenu(POINT pt) {
    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, IDM_CMD_NEW_FOLDER, L"New folder\tCtrl+Shift+N");
    AppendMenuW(menu, MF_STRING, IDM_ORG_NEW_WINDOW, L"Open in new window");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_ORG_RENAME, L"Rename\tF2");
    AppendMenuW(menu, MF_STRING, IDM_ORG_DELETE, L"Delete\tDel");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, L"Layout");
    AppendMenuW(menu, MF_STRING, IDM_ORG_TOGGLE_NAVPANE,
                L"Navigation pane");
    AppendMenuW(menu, MF_STRING, IDM_ORG_TOGGLE_DETAILSPANE, L"Details pane");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_CMD_OPEN_CMD_HERE, L"Open command window here");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_ORG_TOGGLE_HIDDEN, L"Show hidden files");
    AppendMenuW(menu, MF_STRING, IDM_ORG_TOGGLE_EXT, L"Show file extensions (system)");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_CMD_CONTROL_PANEL, L"Control Panel");
    AppendMenuW(menu, MF_STRING, IDM_HELP_ABOUT, L"About / Shortcuts");

    CheckMenuItem(menu, IDM_ORG_TOGGLE_HIDDEN,
                  MF_BYCOMMAND | (showHidden_ ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(menu, IDM_ORG_TOGGLE_DETAILSPANE,
                  MF_BYCOMMAND | (detailsVisible_ ? MF_CHECKED : MF_UNCHECKED));

    TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_LEFTALIGN, pt.x, pt.y, 0, hwnd_, nullptr);
    DestroyMenu(menu);
}

void ExplorerApp::ShowViewMenu(POINT pt) {
    HMENU menu = CreatePopupMenu();
    HMENU sub = CreatePopupMenu();
    AppendMenuW(sub, MF_STRING, IDM_VIEW_LARGE_ICONS, L"Large Icons");
    AppendMenuW(sub, MF_STRING, IDM_VIEW_TILES, L"Tiles");
    AppendMenuW(sub, MF_STRING, IDM_VIEW_DETAILS, L"Details");
    AppendMenuW(sub, MF_STRING, IDM_VIEW_LIST, L"List");
    AppendMenuW(sub, MF_STRING, IDM_VIEW_CONTENT, L"Content");
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(sub), L"View mode");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_SORT_NAME, L"Sort by name");
    AppendMenuW(menu, MF_STRING, IDM_SORT_DATE, L"Sort by date modified");
    AppendMenuW(menu, MF_STRING, IDM_SORT_TYPE, L"Sort by type");
    AppendMenuW(menu, MF_STRING, IDM_SORT_SIZE, L"Sort by size");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_ORG_TOGGLE_HIDDEN, L"Show hidden files");
    AppendMenuW(menu, MF_STRING, IDM_VIEW_REFRESH, L"Refresh\tF5");

    CheckMenuItem(sub, IDM_VIEW_LARGE_ICONS, MF_BYCOMMAND | (view_ == ViewMode::LargeIcons ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(sub, IDM_VIEW_TILES, MF_BYCOMMAND | (view_ == ViewMode::Tiles ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(sub, IDM_VIEW_DETAILS, MF_BYCOMMAND | (view_ == ViewMode::Details ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(sub, IDM_VIEW_LIST, MF_BYCOMMAND | (view_ == ViewMode::List ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(sub, IDM_VIEW_CONTENT, MF_BYCOMMAND | (view_ == ViewMode::Content ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(menu, IDM_SORT_NAME, MF_BYCOMMAND | (sortCol_ == SortColumn::Name ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(menu, IDM_SORT_DATE, MF_BYCOMMAND | (sortCol_ == SortColumn::DateModified ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(menu, IDM_SORT_TYPE, MF_BYCOMMAND | (sortCol_ == SortColumn::Type ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(menu, IDM_SORT_SIZE, MF_BYCOMMAND | (sortCol_ == SortColumn::Size ? MF_CHECKED : MF_UNCHECKED));
    CheckMenuItem(menu, IDM_ORG_TOGGLE_HIDDEN, MF_BYCOMMAND | (showHidden_ ? MF_CHECKED : MF_UNCHECKED));

    TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_LEFTALIGN, pt.x, pt.y, 0, hwnd_, nullptr);
    DestroyMenu(menu);
}

void ExplorerApp::ShowFtpMenu(POINT pt) {
    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, IDM_FTP_CONNECT_DLG, L"FTP Connection Manager...\tCtrl+K");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

    if (CurrentIsFtp()) {
        AppendMenuW(menu, MF_STRING, IDM_FTP_UPLOAD_FILES, L"Upload files to this folder...");
        AppendMenuW(menu, MF_STRING, IDM_FTP_DOWNLOAD_SEL, L"Download selected item(s)...");
        AppendMenuW(menu, MF_STRING, IDM_CMD_NEW_FOLDER, L"New remote folder");
        AppendMenuW(menu, MF_STRING, IDM_FTP_DISCONNECT, L"Disconnect from server");
    } else {
        AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, L"Upload files (open an FTP folder first)");
        AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, L"Download selected (open an FTP folder first)");
    }

    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    HMENU bookmarks = CreatePopupMenu();
    if (ftpProfiles_.empty()) {
        AppendMenuW(bookmarks, MF_STRING | MF_GRAYED, 0, L"(no saved FTP sites)");
    } else {
        for (size_t i = 0; i < ftpProfiles_.size() && i < 90; ++i) {
            const auto& p = ftpProfiles_[i];
            std::wstring label = p.title.empty() ? p.host : p.title;
            AppendMenuW(bookmarks, MF_STRING, IDM_FTP_QUICK_BASE + i, label.c_str());
        }
    }
    AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(bookmarks), L"Saved FTP sites");

    TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_LEFTALIGN, pt.x, pt.y, 0, hwnd_, nullptr);
    DestroyMenu(menu);
}

void ExplorerApp::ShowExplorerMenuBar(POINT pt) {
    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, IDM_ORG_NEW_WINDOW, L"New window");
    AppendMenuW(menu, MF_STRING, IDM_VIEW_DETAILS, L"Details view");
    AppendMenuW(menu, MF_STRING, IDM_FTP_CONNECT_DLG, L"FTP Connection Manager...");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_HELP_ABOUT, L"About Windows 7 Aero Explorer");
    TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_LEFTALIGN, pt.x, pt.y, 0, hwnd_, nullptr);
    DestroyMenu(menu);
}

void ExplorerApp::ShowItemContextMenu(POINT screenPt) {
    HMENU menu = CreatePopupMenu();
    std::vector<int> sel = SelectedIndices();
    bool ftp = CurrentIsFtp();
    bool single = sel.size() == 1;

    if (single) {
        AppendMenuW(menu, MF_STRING | MF_DEFAULT, IDM_CMD_OPEN, ftp ? L"Download and open" : L"Open");
        if (ftp) {
            AppendMenuW(menu, MF_STRING, IDM_FTP_DOWNLOAD_SEL, L"Download to local folder...");
            AppendMenuW(menu, MF_STRING, IDM_FTP_UPLOAD_FILES, L"Upload file here...");
        }
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    }

    AppendMenuW(menu, MF_STRING, IDM_ORG_CUT, L"Cut\tCtrl+X");
    AppendMenuW(menu, MF_STRING, IDM_ORG_COPY, L"Copy\tCtrl+C");
    if (!ftp) AppendMenuW(menu, MF_STRING, IDM_ORG_PASTE, L"Paste\tCtrl+V");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_ORG_RENAME, L"Rename\tF2");
    AppendMenuW(menu, MF_STRING, IDM_ORG_DELETE, L"Delete\tDel");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_CMD_COPY_PATH, L"Copy as path");
    if (!ftp) AppendMenuW(menu, MF_STRING, IDM_CMD_SYS_PROPS, L"Properties");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, IDM_ORG_SELECT_ALL, L"Select all\tCtrl+A");

    TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_LEFTALIGN, screenPt.x, screenPt.y, 0, hwnd_, nullptr);
    DestroyMenu(menu);
}

// ---------------------------------------------------------------------------
// Command dispatch
// ---------------------------------------------------------------------------
void ExplorerApp::OnMenuCommand(int id) {
    if (id >= IDM_FTP_QUICK_BASE && id < IDM_FTP_QUICK_BASE + 100) {
        int idx = id - IDM_FTP_QUICK_BASE;
        if (idx >= 0 && idx < static_cast<int>(ftpProfiles_.size())) {
            const auto& p = ftpProfiles_[idx];
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
            NavigateTo(BuildFtpUrl(info, true), true);
        }
        return;
    }

    switch (id) {
        case IDM_CMD_NEW_FOLDER:
            if (CurrentIsFtp()) StartFtpNewFolder();
            else CreateNewFolderLocal();
            break;
        case IDM_CMD_OPEN: {
            std::vector<int> sel = SelectedIndices();
            if (!sel.empty()) ActivateItem(sel.front());
            break;
        }
        case IDM_CMD_OPEN_CMD_HERE: {
            if (CurrentIsFtp() || currentPath_ == L"computer://") break;
            std::wstring args = L"/K cd /d \"" + currentPath_ + L"\"";
            ShellExecuteW(hwnd_, L"open", L"cmd.exe", args.c_str(), nullptr, SW_SHOWNORMAL);
            break;
        }
        case IDM_CMD_CONTROL_PANEL:
            ShellExecuteW(hwnd_, L"open", L"control.exe", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case IDM_CMD_APPWIZ:
            ShellExecuteW(hwnd_, L"open", L"appwiz.cpl", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case IDM_CMD_COPY_PATH:
            CopyPathOfSelected();
            break;
        case IDM_CMD_SYS_PROPS:
            ShowPropertiesOfSelected();
            break;
        case IDM_ORG_CUT:
            CopySelected(true);
            break;
        case IDM_ORG_COPY:
            CopySelected(false);
            break;
        case IDM_ORG_PASTE:
            PasteClipboard();
            break;
        case IDM_ORG_RENAME:
            if (CurrentIsFtp()) {
                std::vector<int> sel = SelectedIndices();
                StartFtpRename(sel.empty() ? -1 : sel.front());
            } else {
                RenameSelected();
            }
            break;
        case IDM_ORG_DELETE:
            DeleteSelected();
            break;
        case IDM_ORG_SELECT_ALL:
            for (auto& item : items_) item.selected = true;
            InvalidateAll();
            break;
        case IDM_VIEW_REFRESH:
            Refresh();
            break;
        case IDM_ORG_TOGGLE_HIDDEN:
            showHidden_ = !showHidden_;
            Refresh();
            break;
        case IDM_ORG_TOGGLE_NAVPANE: {
            const bool visible = IsWindowVisible(hTree_) != FALSE;
            ShowWindow(hTree_, visible ? SW_HIDE : SW_SHOW);
            InvalidateAll();
            break;
        }
        case IDM_ORG_TOGGLE_DETAILSPANE:
            detailsVisible_ = !detailsVisible_;
            RecalcLayout();
            InvalidateAll();
            break;
        case IDM_ORG_TOGGLE_EXT:
            MessageBoxW(hwnd_,
                        L"File extension visibility is controlled by Windows 10 Explorer settings.\n"
                        L"Open Folder Options in Windows to change it globally.",
                        L"Windows 7 Aero Explorer", MB_ICONINFORMATION | MB_OK);
            break;
        case IDM_ORG_NEW_WINDOW: {
            std::wstring exePath(MAX_PATH * 2, L'\0');
            DWORD len = GetModuleFileNameW(nullptr, &exePath[0], MAX_PATH * 2);
            exePath.resize(len);
            std::wstring args = L"\"" + exePath + L"\"";
            ShellExecuteW(hwnd_, L"open", exePath.c_str(), nullptr,
                          IsFtpUrl(currentPath_) || currentPath_ == L"computer://" ? nullptr
                                                                                   : currentPath_.c_str(),
                          SW_SHOWNORMAL);
            break;
        }
        case IDM_FTP_CONNECT_DLG:
            OpenFtpManager();
            break;
        case IDM_FTP_UPLOAD_FILES:
            if (CurrentIsFtp()) {
                // Pick files with the standard common dialog.
                wchar_t buf[32768] = {};
                OPENFILENAMEW ofn = {};
                ofn.lStructSize = sizeof(ofn);
                ofn.hwndOwner = hwnd_;
                ofn.lpstrFilter = L"All Files\0*.*\0";
                ofn.lpstrFile = buf;
                ofn.nMaxFile = 32768;
                ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_ALLOWMULTISELECT | OFN_EXPLORER;
                if (GetOpenFileNameW(&ofn)) {
                    std::vector<std::wstring> paths;
                    const wchar_t* p = buf;
                    std::wstring dir = p;
                    p += dir.size() + 1;
                    if (*p == L'\0') {
                        paths.push_back(dir);
                    } else {
                        if (!dir.empty() && dir.back() != L'\\') dir += L'\\';
                        while (*p) {
                            std::wstring name = p;
                            paths.push_back(dir + name);
                            p += name.size() + 1;
                        }
                    }
                    if (!paths.empty()) StartFtpUpload(paths);
                }
            } else {
                MessageBoxW(hwnd_, L"Open an FTP folder first (Ctrl+K opens the FTP Connection Manager).",
                            L"FTP Upload", MB_ICONINFORMATION | MB_OK);
            }
            break;
        case IDM_FTP_DOWNLOAD_SEL:
            StartFtpDownloadSelected();
            break;
        case IDM_FTP_DISCONNECT:
            if (ftp_) ftp_->Disconnect();
            lastError_.clear();
            NavigateTo(L"computer://", true);
            MessageBoxW(hwnd_, L"Disconnected from the FTP server.", L"Windows 7 Aero Explorer",
                        MB_ICONINFORMATION | MB_OK);
            break;
        case IDM_VIEW_LARGE_ICONS:
            view_ = ViewMode::LargeIcons;
            ApplySortAndFilter();
            break;
        case IDM_VIEW_TILES:
            view_ = ViewMode::Tiles;
            ApplySortAndFilter();
            break;
        case IDM_VIEW_DETAILS:
            view_ = ViewMode::Details;
            ApplySortAndFilter();
            break;
        case IDM_VIEW_LIST:
            view_ = ViewMode::List;
            ApplySortAndFilter();
            break;
        case IDM_VIEW_CONTENT:
            view_ = ViewMode::Content;
            ApplySortAndFilter();
            break;
        case IDM_SORT_NAME:
        case IDM_SORT_DATE:
        case IDM_SORT_TYPE:
        case IDM_SORT_SIZE: {
            SortColumn target = SortColumn::Name;
            if (id == IDM_SORT_DATE) target = SortColumn::DateModified;
            else if (id == IDM_SORT_TYPE) target = SortColumn::Type;
            else if (id == IDM_SORT_SIZE) target = SortColumn::Size;
            if (sortCol_ == target) sortAsc_ = !sortAsc_;
            else { sortCol_ = target; sortAsc_ = true; }
            ApplySortAndFilter();
            break;
        }
        case IDM_HELP_ABOUT:
            ShowAboutDialog(hInst_, hwnd_);
            break;
        default:
            break;
    }
    InvalidateAll();
}

// ---------------------------------------------------------------------------
// Local file operations
// ---------------------------------------------------------------------------
void ExplorerApp::CreateNewFolderLocal() {
    if (CurrentIsFtp()) {
        StartFtpNewFolder();
        return;
    }
    if (currentPath_ == L"computer://") return;

    std::wstring base = currentPath_;
    if (!base.empty() && base.back() != L'\\') base += L'\\';

    std::wstring name = L"New folder";
    int counter = 1;
    while (GetFileAttributesW((base + name).c_str()) != INVALID_FILE_ATTRIBUTES) {
        name = L"New folder (" + std::to_wstring(counter++) + L")";
    }

    if (!ShowInputPromptDialog(hInst_, hwnd_, L"New Folder", L"Enter a name for the new folder:", name)) {
        return;
    }
    std::wstring full = base + name;
    if (!CreateDirectoryW(full.c_str(), nullptr)) {
        DWORD err = GetLastError();
        wchar_t msg[512] = {};
        FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                       nullptr, err, 0, msg, 512, nullptr);
        MessageBoxW(hwnd_, (L"Could not create the folder.\n\n" + std::wstring(msg)).c_str(),
                    L"New Folder", MB_ICONERROR | MB_OK);
        return;
    }
    Refresh();
    for (size_t pos = 0; pos < display_.size(); ++pos) {
        if (items_[display_[pos]].fullPath == full) {
            SelectOnly(static_cast<int>(pos));
            EnsureVisible(static_cast<int>(pos));
        }
    }
    InvalidateAll();
}

void ExplorerApp::RenameSelected() {
    if (CurrentIsFtp()) {
        std::vector<int> sel = SelectedIndices();
        StartFtpRename(sel.empty() ? -1 : sel.front());
        return;
    }
    std::vector<int> sel = SelectedIndices();
    if (sel.empty()) return;
    int idx = sel.front();
    if (idx < 0 || idx >= static_cast<int>(display_.size())) return;

    FileEntry& item = items_[display_[idx]];
    std::wstring oldPath = item.fullPath;
    std::wstring newName = item.name;
    if (!ShowInputPromptDialog(hInst_, hwnd_, L"Rename", L"Enter a new name:", newName)) return;
    if (newName == item.name) return;

    std::wstring folder = oldPath;
    size_t slash = folder.find_last_of(L'\\');
    if (slash != std::wstring::npos) folder = folder.substr(0, slash);
    std::wstring newPath = folder + L"\\" + newName;

    BOOL ok = MoveFileExW(oldPath.c_str(), newPath.c_str(), MOVEFILE_COPY_ALLOWED);
    if (!ok) {
        DWORD err = GetLastError();
        wchar_t msg[512] = {};
        FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                       nullptr, err, 0, msg, 512, nullptr);
        MessageBoxW(hwnd_, (L"Could not rename the item.\n\n" + std::wstring(msg)).c_str(),
                    L"Rename", MB_ICONERROR | MB_OK);
        return;
    }
    Refresh();
}

void ExplorerApp::DeleteSelected() {
    std::vector<int> sel = SelectedIndices();
    if (sel.empty()) return;

    if (CurrentIsFtp()) {
        StartFtpDelete(sel);
        return;
    }

    std::wstring prompt;
    if (sel.size() == 1) {
        prompt = L"Are you sure you want to move '" + items_[display_[sel.front()]].name +
                 L"' to the Recycle Bin?";
    } else {
        prompt = L"Are you sure you want to move these " + std::to_wstring(sel.size()) +
                 L" items to the Recycle Bin?";
    }
    if (MessageBoxW(hwnd_, prompt.c_str(), L"Delete File",
                    MB_ICONQUESTION | MB_YESNO | MB_DEFBUTTON2) != IDYES) {
        return;
    }

    std::vector<std::wstring> paths;
    for (int di : sel) paths.push_back(items_[display_[di]].fullPath);

    std::wstring doubleNull;
    for (const auto& p : paths) {
        doubleNull += p;
        doubleNull.push_back(L'\0');
    }
    doubleNull.push_back(L'\0');

    SHFILEOPSTRUCTW op = {};
    op.hwnd = hwnd_;
    op.wFunc = FO_DELETE;
    op.pFrom = doubleNull.c_str();
    op.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT;
    int result = SHFileOperationW(&op);
    if (result != 0) {
        // Fall back to a permanent delete when the Recycle Bin is unavailable.
        for (const auto& p : paths) {
            DWORD attrs = GetFileAttributesW(p.c_str());
            if (attrs == INVALID_FILE_ATTRIBUTES) continue;
            if (attrs & FILE_ATTRIBUTE_DIRECTORY) RemoveDirectoryW(p.c_str());
            else DeleteFileW(p.c_str());
        }
    }
    Refresh();
}

void ExplorerApp::CopySelected(bool cut) {
    clipPaths_.clear();
    clipCut_ = cut;
    for (int di : SelectedIndices()) {
        clipPaths_.push_back(items_[display_[di]].fullPath);
    }
    if (clipPaths_.empty()) return;

    // Also publish the selection to the Windows clipboard as CF_HDROP.
    std::wstring doubleNull;
    for (const auto& p : clipPaths_) {
        doubleNull += p;
        doubleNull.push_back(L'\0');
    }
    doubleNull.push_back(L'\0');

    size_t bytes = (doubleNull.size() + 1) * sizeof(wchar_t) + sizeof(DROPFILES);
    HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytes);
    if (!mem) return;
    auto* drop = static_cast<DROPFILES*>(GlobalLock(mem));
    if (!drop) {
        GlobalFree(mem);
        return;
    }
    drop->pFiles = sizeof(DROPFILES);
    drop->fWide = TRUE;
    memcpy(reinterpret_cast<BYTE*>(drop) + sizeof(DROPFILES), doubleNull.c_str(),
           (doubleNull.size() + 1) * sizeof(wchar_t));
    GlobalUnlock(mem);

    if (OpenClipboard(hwnd_)) {
        EmptyClipboard();
        SetClipboardData(CF_HDROP, mem);
        CloseClipboard();
    } else {
        GlobalFree(mem);
    }
    statusNote_ = cut ? L"Items cut to clipboard" : L"Items copied to clipboard";
    InvalidateAll();
}

void ExplorerApp::PasteClipboard() {
    if (clipPaths_.empty()) {
        statusNote_ = L"Clipboard is empty";
        InvalidateAll();
        return;
    }
    if (CurrentIsFtp()) {
        StartFtpUpload(clipPaths_);
        if (clipCut_) {
            clipPaths_.clear();
            clipCut_ = false;
        }
        return;
    }
    if (currentPath_ == L"computer://") return;

    std::wstring dest = currentPath_;
    if (!dest.empty() && dest.back() != L'\\') dest += L'\\';

    int copied = 0;
    for (const auto& src : clipPaths_) {
        std::wstring name = LeafName(src);
        if (name.empty()) continue;
        std::wstring target = dest + name;
        if (src == target) continue;

        BOOL ok = FALSE;
        if (clipCut_) {
            ok = MoveFileExW(src.c_str(), target.c_str(), MOVEFILE_COPY_ALLOWED | MOVEFILE_REPLACE_EXISTING);
        } else if (IsFolderPath(src)) {
            ok = CopyFolderRecursive(src, target) ? TRUE : FALSE;
        } else {
            ok = CopyFileW(src.c_str(), target.c_str(), FALSE);
        }
        if (ok) ++copied;
    }
    if (clipCut_) {
        clipPaths_.clear();
        clipCut_ = false;
    }
    statusNote_ = std::to_wstring(copied) + L" item(s) pasted";
    Refresh();
}

void ExplorerApp::CopyPathOfSelected() {
    std::wstring paths;
    for (int di : SelectedIndices()) {
        if (!paths.empty()) paths += L"\r\n";
        paths += items_[display_[di]].fullPath;
    }
    if (paths.empty()) return;

    if (OpenClipboard(hwnd_)) {
        EmptyClipboard();
        size_t bytes = (paths.size() + 1) * sizeof(wchar_t);
        HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, bytes);
        if (mem) {
            void* p = GlobalLock(mem);
            if (p) {
                memcpy(p, paths.c_str(), bytes);
                GlobalUnlock(mem);
                SetClipboardData(CF_UNICODETEXT, mem);
            } else {
                GlobalFree(mem);
            }
        }
        CloseClipboard();
    }
    statusNote_ = L"Path copied to clipboard";
    InvalidateAll();
}

void ExplorerApp::ShowPropertiesOfSelected() {
    std::vector<int> sel = SelectedIndices();
    if (sel.empty()) return;
    std::wstring path = items_[display_[sel.front()]].fullPath;
    SHELLEXECUTEINFOW sei = {};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_INVOKEIDLIST;
    sei.hwnd = hwnd_;
    sei.lpVerb = L"properties";
    sei.lpFile = path.c_str();
    sei.nShow = SW_SHOWNORMAL;
    ShellExecuteExW(&sei);
}

void ExplorerApp::OpenSelectedWithShell() {
    std::vector<int> sel = SelectedIndices();
    if (!sel.empty()) ActivateItem(sel.front());
}

void ExplorerApp::SetDropHighlight(bool on) {
    if (dropHighlight_ == on) return;
    dropHighlight_ = on;
    InvalidateCanvas();
}

void ExplorerApp::QuickConnectFromText(const std::wstring& text) {
    std::wstring query = TrimW(text);
    if (query.empty()) return;
    if (IsFtpUrl(query)) {
        NavigateTo(query, true);
        return;
    }
    // Bare hostname: treat as an FTP server.
    if (query.find(L'.') != std::wstring::npos || query.find(L':') != std::wstring::npos) {
        NavigateTo(L"ftp://" + query, true);
    }
}

void ExplorerApp::HandleDroppedPaths(const std::vector<std::wstring>& paths) {
    if (paths.empty()) return;
    if (CurrentIsFtp()) {
        StartFtpUpload(paths);
        return;
    }
    if (currentPath_ == L"computer://") {
        // Open the first dropped folder.
        for (const auto& p : paths) {
            if (IsFolderPath(p)) {
                NavigateTo(p, true);
                return;
            }
        }
        return;
    }

    std::wstring dest = currentPath_;
    if (!dest.empty() && dest.back() != L'\\') dest += L'\\';
    int copied = 0;
    for (const auto& src : paths) {
        std::wstring name = LeafName(src);
        if (name.empty()) continue;
        std::wstring target = dest + name;
        if (src == target) continue;
        if (IsFolderPath(src)) {
            if (CopyFolderRecursive(src, target)) ++copied;
        } else if (CopyFileW(src.c_str(), target.c_str(), FALSE)) {
            ++copied;
        }
    }
    statusNote_ = std::to_wstring(copied) + L" item(s) copied here";
    Refresh();
}
