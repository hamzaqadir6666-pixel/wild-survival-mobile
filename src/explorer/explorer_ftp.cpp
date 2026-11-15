// FTP operations (background workers, progress reporting) for Aero Explorer.
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

std::wstring SanitizeName(const std::wstring& name) {
    std::wstring out = name;
    for (wchar_t& c : out) {
        if (c == L'\\' || c == L'/' || c == L':' || c == L'*' || c == L'?' ||
            c == L'"' || c == L'<' || c == L'>' || c == L'|') {
            c = L'_';
        }
    }
    if (out.empty()) out = L"item";
    return out;
}

bool PickFolder(HWND owner, std::wstring& outPath) {
    BROWSEINFOW bi = {};
    bi.hwndOwner = owner;
    bi.lpszTitle = L"Select a folder to save the downloaded item(s) into:";
    bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE | BIF_USENEWUI;
    PIDLIST_ABSOLUTE pidl = SHBrowseForFolderW(&bi);
    if (!pidl) return false;
    wchar_t path[MAX_PATH] = {};
    bool ok = SHGetPathFromIDListW(pidl, path) != FALSE;
    CoTaskMemFree(pidl);
    if (ok) outPath = path;
    return ok;
}

} // namespace

// ---------------------------------------------------------------------------
// Progress / timer helpers
// ---------------------------------------------------------------------------
void ExplorerApp::StartProgressAnimation() {
    if (!animTimer_) {
        animTimer_ = SetTimer(hwnd_, 1, 120, nullptr);
    }
}

void ExplorerApp::StopProgressAnimation() {
    if (animTimer_) {
        KillTimer(hwnd_, 1);
        animTimer_ = 0;
    }
    animPhase_ = 0;
}

void ExplorerApp::SetProgress(int pct, const std::wstring& text) {
    progressPct_ = std::max(0, std::min(100, pct));
    progressText_ = text;
    if (progressPct_ > 0 && progressPct_ < 100) StartProgressAnimation();
    InvalidateAll();
}

void ExplorerApp::ReportFtpError(const std::wstring& text) {
    lastError_ = text;
    StopProgressAnimation();
    progressPct_ = 0;
    progressText_.clear();
    MessageBoxW(hwnd_, text.c_str(), L"FTP", MB_ICONERROR | MB_OK);
    InvalidateAll();
}

void ExplorerApp::PostFtpOpDone(std::unique_ptr<FtpAsyncOpResult> result) {
    PostMessageW(hwnd_, WM_APP_FTP_OP_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
}

// ---------------------------------------------------------------------------
// Background workers
// ---------------------------------------------------------------------------
void ExplorerApp::StartFtpList(const std::wstring& url) {
    FtpUrlInfo target = ParseFtpUrl(url);
    if (!target.valid) {
        MessageBoxW(hwnd_, L"Invalid FTP address.\n\nUse the form ftp://user:password@host:port/path",
                    L"FTP", MB_ICONERROR | MB_OK);
        return;
    }

    if (ftpBusy_.load()) {
        // A transfer is already running: let the user know instead of interleaving.
        MessageBoxW(hwnd_, L"An FTP transfer is still running. Please wait for it to finish.",
                    L"FTP", MB_ICONINFORMATION | MB_OK);
        return;
    }
    ftpBusy_.store(true);
    navigating_ = true;
    lastError_.clear();
    SetProgress(15, L"Connecting to " + target.host + L"...");

    auto alive = alive_;
    HWND hwnd = hwnd_;
    std::wstring urlCopy = url;

    std::thread worker([this, urlCopy, target, alive, hwnd]() {
        auto result = std::make_unique<FtpAsyncListResult>();
        result->fullUrl = urlCopy;
        result->host = target.host;
        result->remotePath = target.remotePath;

        std::wstring resolvedUrl;
        std::wstring errorText;
        std::vector<FileEntry> entries;

        bool ok = false;
        {
            std::lock_guard<std::mutex> lk(ftpOpMutex_);
            ok = ftp_->ConnectAndList(target, entries, resolvedUrl, errorText,
                                      [alive, hwnd](const std::wstring& status, uint64_t done, uint64_t total) {
                                          if (!alive->load() || !IsWindow(hwnd)) return;
                                          auto* payload = new FtpProgressPayload();
                                          payload->statusText = status;
                                          payload->doneBytes = done;
                                          payload->totalBytes = total;
                                          payload->percent = (total > 0)
                                                                 ? static_cast<int>(std::min<uint64_t>(100, done * 100 / total))
                                                                 : 40;
                                          PostMessageW(hwnd, WM_APP_FTP_PROGRESS, 0,
                                                       reinterpret_cast<LPARAM>(payload));
                                      });
        }

        result->success = ok;
        if (ok) {
            result->entries = std::move(entries);
            result->fullUrl = resolvedUrl;
            result->remotePath = ftp_->CurrentSession().remotePath;
        } else {
            result->errorMessage = errorText.empty() ? L"FTP connection failed." : errorText;
        }

        ftpBusy_.store(false);
        if (alive->load() && IsWindow(hwnd)) {
            PostMessageW(hwnd, WM_APP_FTP_LIST_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
        }
    });

    {
        std::lock_guard<std::mutex> lk(workersMutex_);
        workers_.push_back(std::move(worker));
    }
}

void ExplorerApp::OpenFtpManager() {
    FtpUrlInfo target;
    bool changed = false;
    if (ShowFtpManagerDialog(hInst_, hwnd_, ftpProfiles_, target, changed)) {
        if (changed) BuildTree();
        NavigateTo(BuildFtpUrl(target, true), true);
    } else if (changed) {
        BuildTree();
    }
}

std::wstring ExplorerApp::CurrentFtpRemoteDir() const {
    if (!CurrentIsFtp()) return L"/";
    return ParseFtpUrl(currentPath_).remotePath;
}

// ---------------------------------------------------------------------------
// Upload
// ---------------------------------------------------------------------------
void ExplorerApp::StartFtpUpload(const std::vector<std::wstring>& localPaths) {
    if (!CurrentIsFtp() || localPaths.empty()) return;
    if (ftpBusy_.load()) {
        MessageBoxW(hwnd_, L"An FTP transfer is already running. Please wait for it to finish.",
                    L"FTP Upload", MB_ICONINFORMATION | MB_OK);
        return;
    }

    ftpBusy_.store(true);
    lastError_.clear();
    SetProgress(1, L"Starting upload...");

    auto alive = alive_;
    HWND hwnd = hwnd_;
    std::wstring remoteDir = CurrentFtpRemoteDir();
    std::vector<std::wstring> paths = localPaths;

    std::thread worker([this, paths, remoteDir, alive, hwnd]() {
        auto result = std::make_unique<FtpAsyncOpResult>();
        std::wstring errorText;
        int uploaded = 0;

        auto progress = [alive, hwnd](const std::wstring& status, uint64_t done, uint64_t total) {
            if (!alive->load() || !IsWindow(hwnd)) return;
            auto* payload = new FtpProgressPayload();
            payload->statusText = status;
            payload->doneBytes = done;
            payload->totalBytes = total;
            payload->percent = (total > 0) ? static_cast<int>(std::min<uint64_t>(100, done * 100 / total)) : 50;
            PostMessageW(hwnd, WM_APP_FTP_PROGRESS, 0, reinterpret_cast<LPARAM>(payload));
        };

        for (const auto& localPath : paths) {
            std::wstring name = localPath;
            size_t slash = name.find_last_of(L"\\/");
            if (slash != std::wstring::npos) name = name.substr(slash + 1);
            if (name.empty()) continue;

            std::wstring remoteDest = JoinFtpPath(remoteDir, name);
            bool ok = false;
            {
                std::lock_guard<std::mutex> lk(ftpOpMutex_);
                ok = ftp_->UploadLocalToRemote(localPath, remoteDest, progress, errorText);
            }
            if (!ok) {
                result->success = false;
                result->message = errorText;
                ftpBusy_.store(false);
                if (alive->load() && IsWindow(hwnd)) {
                    PostMessageW(hwnd, WM_APP_FTP_OP_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
                }
                return;
            }
            ++uploaded;
        }

        result->success = true;
        result->refreshAfter = true;
        result->message = std::to_wstring(uploaded) + L" item(s) uploaded to " + remoteDir;
        ftpBusy_.store(false);
        if (alive->load() && IsWindow(hwnd)) {
            PostMessageW(hwnd, WM_APP_FTP_OP_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
        }
    });

    {
        std::lock_guard<std::mutex> lk(workersMutex_);
        workers_.push_back(std::move(worker));
    }
}

// ---------------------------------------------------------------------------
// Download
// ---------------------------------------------------------------------------
void ExplorerApp::StartFtpDownloadSelected() {
    if (!CurrentIsFtp()) {
        MessageBoxW(hwnd_, L"Open an FTP folder first.", L"FTP Download", MB_ICONINFORMATION | MB_OK);
        return;
    }
    std::vector<int> sel = SelectedIndices();
    if (sel.empty()) {
        MessageBoxW(hwnd_, L"Select one or more remote files or folders to download.",
                    L"FTP Download", MB_ICONINFORMATION | MB_OK);
        return;
    }
    if (ftpBusy_.load()) {
        MessageBoxW(hwnd_, L"An FTP transfer is already running. Please wait for it to finish.",
                    L"FTP Download", MB_ICONINFORMATION | MB_OK);
        return;
    }

    std::wstring baseDir;
    if (!PickFolder(hwnd_, baseDir)) return;

    struct DownloadJob {
        std::wstring remotePath;
        std::wstring localPath;
        bool isDirectory = false;
        uint64_t size = 0;
    };
    std::vector<DownloadJob> jobs;
    for (int di : sel) {
        const FileEntry& item = items_[display_[di]];
        DownloadJob job;
        job.remotePath = item.remoteRelPath;
        job.isDirectory = item.isDirectory;
        job.size = item.sizeBytes;
        std::wstring name = SanitizeName(item.name);
        job.localPath = baseDir + L"\\" + name;
        jobs.push_back(job);
    }

    ftpBusy_.store(true);
    lastError_.clear();
    SetProgress(1, L"Starting download...");

    auto alive = alive_;
    HWND hwnd = hwnd_;

    std::thread worker([this, jobs, alive, hwnd]() {
        auto result = std::make_unique<FtpAsyncOpResult>();
        std::wstring errorText;
        int done = 0;

        auto progress = [alive, hwnd](const std::wstring& status, uint64_t doneBytes, uint64_t total) {
            if (!alive->load() || !IsWindow(hwnd)) return;
            auto* payload = new FtpProgressPayload();
            payload->statusText = status;
            payload->doneBytes = doneBytes;
            payload->totalBytes = total;
            payload->percent = (total > 0) ? static_cast<int>(std::min<uint64_t>(100, doneBytes * 100 / total)) : 50;
            PostMessageW(hwnd, WM_APP_FTP_PROGRESS, 0, reinterpret_cast<LPARAM>(payload));
        };

        for (const auto& job : jobs) {
            bool ok = false;
            {
                std::lock_guard<std::mutex> lk(ftpOpMutex_);
                ok = ftp_->DownloadItemToLocal(job.remotePath, job.localPath, job.isDirectory,
                                               job.size, progress, errorText);
            }
            if (!ok) {
                result->success = false;
                result->message = errorText;
                ftpBusy_.store(false);
                if (alive->load() && IsWindow(hwnd)) {
                    PostMessageW(hwnd, WM_APP_FTP_OP_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
                }
                return;
            }
            ++done;
        }

        result->success = true;
        result->message = std::to_wstring(done) + L" item(s) downloaded to " + jobs.front().localPath.substr(
                                                       0, jobs.front().localPath.find_last_of(L'\\'));
        if (jobs.size() == 1 && !jobs.front().isDirectory) {
            result->openLocalFileAfter = jobs.front().localPath;
        }
        ftpBusy_.store(false);
        if (alive->load() && IsWindow(hwnd)) {
            PostMessageW(hwnd, WM_APP_FTP_OP_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
        }
    });

    {
        std::lock_guard<std::mutex> lk(workersMutex_);
        workers_.push_back(std::move(worker));
    }
}

// ---------------------------------------------------------------------------
// Remote folder / rename / delete
// ---------------------------------------------------------------------------
void ExplorerApp::StartFtpNewFolder() {
    if (!CurrentIsFtp()) return;
    if (ftpBusy_.load()) return;

    std::wstring name = L"New folder";
    if (!ShowInputPromptDialog(hInst_, hwnd_, L"New Folder on FTP Server",
                               L"Enter a name for the remote folder:", name)) {
        return;
    }
    std::wstring remoteDir = JoinFtpPath(CurrentFtpRemoteDir(), name);

    ftpBusy_.store(true);
    SetProgress(30, L"Creating remote folder...");
    auto alive = alive_;
    HWND hwnd = hwnd_;

    std::thread worker([this, remoteDir, alive, hwnd]() {
        auto result = std::make_unique<FtpAsyncOpResult>();
        std::wstring errorText;
        bool ok = false;
        {
            std::lock_guard<std::mutex> lk(ftpOpMutex_);
            ok = ftp_->CreateRemoteFolder(remoteDir, errorText);
        }
        result->success = ok;
        result->refreshAfter = ok;
        result->message = ok ? (L"Created remote folder " + remoteDir) : errorText;
        ftpBusy_.store(false);
        if (alive->load() && IsWindow(hwnd)) {
            PostMessageW(hwnd, WM_APP_FTP_OP_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
        }
    });

    {
        std::lock_guard<std::mutex> lk(workersMutex_);
        workers_.push_back(std::move(worker));
    }
}

void ExplorerApp::StartFtpRename(int itemIndex) {
    if (!CurrentIsFtp() || itemIndex < 0 || itemIndex >= static_cast<int>(display_.size())) return;
    if (ftpBusy_.load()) return;

    const FileEntry& item = items_[display_[itemIndex]];
    std::wstring newName = item.name;
    if (!ShowInputPromptDialog(hInst_, hwnd_, L"Rename on FTP Server", L"Enter a new name:", newName)) {
        return;
    }
    if (newName == item.name) return;

    std::wstring oldRemote = item.remoteRelPath;
    std::wstring parentRemote = ParentFtpPath(oldRemote);
    std::wstring newRemote = JoinFtpPath(parentRemote, newName);

    ftpBusy_.store(true);
    SetProgress(30, L"Renaming remote item...");
    auto alive = alive_;
    HWND hwnd = hwnd_;

    std::thread worker([this, oldRemote, newRemote, alive, hwnd]() {
        auto result = std::make_unique<FtpAsyncOpResult>();
        std::wstring errorText;
        bool ok = false;
        {
            std::lock_guard<std::mutex> lk(ftpOpMutex_);
            ok = ftp_->RenameRemoteItem(oldRemote, newRemote, errorText);
        }
        result->success = ok;
        result->refreshAfter = ok;
        result->message = ok ? (L"Renamed to " + newRemote) : errorText;
        ftpBusy_.store(false);
        if (alive->load() && IsWindow(hwnd)) {
            PostMessageW(hwnd, WM_APP_FTP_OP_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
        }
    });

    {
        std::lock_guard<std::mutex> lk(workersMutex_);
        workers_.push_back(std::move(worker));
    }
}

void ExplorerApp::StartFtpDelete(const std::vector<int>& itemIndices) {
    if (!CurrentIsFtp() || itemIndices.empty()) return;
    if (ftpBusy_.load()) return;

    std::wstring prompt = itemIndices.size() == 1
                              ? L"Delete '" + items_[display_[itemIndices.front()]].name +
                                    L"' from the FTP server?\n\nThis cannot be undone."
                              : L"Delete these " + std::to_wstring(itemIndices.size()) +
                                    L" items from the FTP server?\n\nThis cannot be undone.";
    if (MessageBoxW(hwnd_, prompt.c_str(), L"Delete on FTP Server",
                    MB_ICONWARNING | MB_YESNO | MB_DEFBUTTON2) != IDYES) {
        return;
    }

    struct DeleteJob { std::wstring remotePath; bool isDirectory; std::wstring name; };
    std::vector<DeleteJob> jobs;
    for (int di : itemIndices) {
        const FileEntry& item = items_[display_[di]];
        jobs.push_back({ item.remoteRelPath, item.isDirectory, item.name });
    }

    ftpBusy_.store(true);
    SetProgress(20, L"Deleting remote item(s)...");
    auto alive = alive_;
    HWND hwnd = hwnd_;

    std::thread worker([this, jobs, alive, hwnd]() {
        auto result = std::make_unique<FtpAsyncOpResult>();
        std::wstring errorText;
        int deleted = 0;
        for (const auto& job : jobs) {
            bool ok = false;
            {
                std::lock_guard<std::mutex> lk(ftpOpMutex_);
                ok = ftp_->DeleteRemoteItem(job.remotePath, job.isDirectory, errorText);
            }
            if (!ok) {
                result->success = false;
                result->message = errorText;
                ftpBusy_.store(false);
                if (alive->load() && IsWindow(hwnd)) {
                    PostMessageW(hwnd, WM_APP_FTP_OP_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
                }
                return;
            }
            ++deleted;
        }
        result->success = true;
        result->refreshAfter = true;
        result->message = std::to_wstring(deleted) + L" remote item(s) deleted";
        ftpBusy_.store(false);
        if (alive->load() && IsWindow(hwnd)) {
            PostMessageW(hwnd, WM_APP_FTP_OP_DONE, 0, reinterpret_cast<LPARAM>(result.release()));
        }
    });

    {
        std::lock_guard<std::mutex> lk(workersMutex_);
        workers_.push_back(std::move(worker));
    }
}
