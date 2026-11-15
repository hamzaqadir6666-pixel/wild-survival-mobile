#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shlobj.h>
#include <wininet.h>

#include <functional>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "../common/path_ftp_utils.h"
#include "../common/version.h"
#include "models.h"

namespace aero {

using FtpProgressCallback = std::function<void(const std::wstring& status, uint64_t done, uint64_t total)>;

class AeroFtpClient {
public:
    AeroFtpClient() = default;
    ~AeroFtpClient() {
        Disconnect();
    }

    static std::wstring FormatFileTimeWin7(const FILETIME& ft) {
        if (ft.dwLowDateTime == 0 && ft.dwHighDateTime == 0) {
            return L"";
        }
        SYSTEMTIME stUTC = {}, stLocal = {};
        if (!FileTimeToSystemTime(&ft, &stUTC)) return L"";
        if (!SystemTimeToTzSpecificLocalTime(nullptr, &stUTC, &stLocal)) {
            stLocal = stUTC;
        }
        wchar_t buf[64] = {};
        swprintf(buf, 64, L"%04u-%02u-%02u %02u:%02u",
                 stLocal.wYear, stLocal.wMonth, stLocal.wDay,
                 stLocal.wHour, stLocal.wMinute);
        return buf;
    }

    static std::wstring GetProfilesIniPath() {
        PWSTR appData = nullptr;
        std::wstring dir;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &appData)) && appData) {
            dir = appData;
            CoTaskMemFree(appData);
        } else {
            wchar_t tmp[MAX_PATH] = {};
            GetTempPathW(MAX_PATH, tmp);
            dir = tmp;
        }
        if (!dir.empty() && dir.back() != L'\\') dir.push_back(L'\\');
        dir += AERO_SETTINGS_SUBDIR_W;
        CreateDirectoryW(dir.c_str(), nullptr);
        return dir + L"\\ftp_sites.ini";
    }

    static std::vector<FtpSiteProfile> LoadProfiles() {
        std::wstring ini = GetProfilesIniPath();
        int count = GetPrivateProfileIntW(L"General", L"Count", -1, ini.c_str());
        std::vector<FtpSiteProfile> list;

        if (count < 0) {
            // First launch: provide a ready-to-test public read-only demo FTP server bookmark
            FtpSiteProfile demo;
            demo.title = L"Rebex Public Demo FTP";
            demo.host = L"test.rebex.net";
            demo.port = 21;
            demo.anonymous = false;
            demo.username = L"demo";
            demo.password = L"password";
            demo.initialPath = L"/pub/example";
            demo.passive = true;
            demo.useFtps = false;
            list.push_back(demo);
            SaveProfiles(list);
            return list;
        }

        for (int i = 0; i < count && i < 100; ++i) {
            std::wstring sec = L"Site" + std::to_wstring(i);
            wchar_t title[256] = {}, host[256] = {}, user[256] = {}, passHex[1024] = {}, path[512] = {};
            GetPrivateProfileStringW(sec.c_str(), L"Title", L"", title, 256, ini.c_str());
            GetPrivateProfileStringW(sec.c_str(), L"Host", L"", host, 256, ini.c_str());
            if (wcslen(host) == 0) continue;

            FtpSiteProfile p;
            p.title = wcslen(title) ? title : host;
            p.host = host;
            p.port = static_cast<uint16_t>(GetPrivateProfileIntW(sec.c_str(), L"Port", 21, ini.c_str()));
            p.anonymous = GetPrivateProfileIntW(sec.c_str(), L"Anonymous", 0, ini.c_str()) != 0;
            GetPrivateProfileStringW(sec.c_str(), L"Username", L"anonymous", user, 256, ini.c_str());
            GetPrivateProfileStringW(sec.c_str(), L"PasswordEnc", L"", passHex, 1024, ini.c_str());
            GetPrivateProfileStringW(sec.c_str(), L"InitialPath", L"/", path, 512, ini.c_str());
            p.username = user;
            p.password = p.anonymous ? L"anonymous@aeroexplorer.local" : DeobfuscateSecret(passHex);
            p.initialPath = NormalizeFtpPath(path);
            p.passive = GetPrivateProfileIntW(sec.c_str(), L"Passive", 1, ini.c_str()) != 0;
            p.useFtps = GetPrivateProfileIntW(sec.c_str(), L"UseFtps", 0, ini.c_str()) != 0;
            list.push_back(p);
        }
        return list;
    }

    static void SaveProfiles(const std::vector<FtpSiteProfile>& list) {
        std::wstring ini = GetProfilesIniPath();
        DeleteFileW(ini.c_str());
        std::wstring cnt = std::to_wstring(list.size());
        WritePrivateProfileStringW(L"General", L"Count", cnt.c_str(), ini.c_str());
        for (size_t i = 0; i < list.size(); ++i) {
            const auto& p = list[i];
            std::wstring sec = L"Site" + std::to_wstring(i);
            WritePrivateProfileStringW(sec.c_str(), L"Title", p.title.c_str(), ini.c_str());
            WritePrivateProfileStringW(sec.c_str(), L"Host", p.host.c_str(), ini.c_str());
            WritePrivateProfileStringW(sec.c_str(), L"Port", std::to_wstring(p.port).c_str(), ini.c_str());
            WritePrivateProfileStringW(sec.c_str(), L"Anonymous", p.anonymous ? L"1" : L"0", ini.c_str());
            WritePrivateProfileStringW(sec.c_str(), L"Username", p.username.c_str(), ini.c_str());
            std::wstring enc = p.anonymous ? L"" : ObfuscateSecret(p.password);
            WritePrivateProfileStringW(sec.c_str(), L"PasswordEnc", enc.c_str(), ini.c_str());
            WritePrivateProfileStringW(sec.c_str(), L"InitialPath", p.initialPath.c_str(), ini.c_str());
            WritePrivateProfileStringW(sec.c_str(), L"Passive", p.passive ? L"1" : L"0", ini.c_str());
            WritePrivateProfileStringW(sec.c_str(), L"UseFtps", p.useFtps ? L"1" : L"0", ini.c_str());
        }
    }

    bool IsConnected() const {
        std::lock_guard<std::mutex> lk(mtx_);
        return hConnect_ != nullptr && currentSession_.valid;
    }

    FtpUrlInfo CurrentSession() const {
        std::lock_guard<std::mutex> lk(mtx_);
        return currentSession_;
    }

    void Disconnect() {
        std::lock_guard<std::mutex> lk(mtx_);
        CloseHandlesLocked();
        currentSession_ = FtpUrlInfo{};
    }

    bool ConnectAndList(const FtpUrlInfo& target,
                        std::vector<FileEntry>& outEntries,
                        std::wstring& outResolvedUrl,
                        std::wstring& outError,
                        const FtpProgressCallback& onProgress = nullptr) {
        std::lock_guard<std::mutex> lk(mtx_);
        if (!target.valid) {
            outError = L"Invalid FTP URL or server hostname.";
            return false;
        }

        // Reuse existing connection if host/port/user match; if target URL omitted credentials
        // while we already have an authenticated session to the same host:port, preserve session credentials!
        FtpUrlInfo effective = target;
        if (currentSession_.valid &&
            ToLowerW(currentSession_.host) == ToLowerW(target.host) &&
            currentSession_.port == target.port) {
            if (!target.explicitCredentials) {
                effective.username = currentSession_.username;
                effective.password = currentSession_.password;
                effective.explicitCredentials = currentSession_.explicitCredentials;
                effective.passive = currentSession_.passive;
                effective.useFtps = currentSession_.useFtps;
            }
        }

        bool sameSession = (hConnect_ != nullptr &&
                            currentSession_.valid &&
                            ToLowerW(currentSession_.host) == ToLowerW(effective.host) &&
                            currentSession_.port == effective.port &&
                            currentSession_.username == effective.username &&
                            currentSession_.password == effective.password &&
                            currentSession_.passive == effective.passive);

        if (!sameSession) {
            if (onProgress) {
                onProgress(L"Connecting to " + effective.host + L":" + std::to_wstring(effective.port) + L"...", 15, 100);
            }
            if (!OpenSessionLocked(effective, outError)) {
                return false;
            }
        }

        if (onProgress) {
            onProgress(L"Listing " + NormalizeFtpPath(effective.remotePath) + L"...", 55, 100);
        }

        if (!ListDirLocked(effective.remotePath, outEntries, outError)) {
            // Transparent 1-time reconnect if idle connection timed out!
            if (onProgress) {
                onProgress(L"Reconnecting to " + effective.host + L"...", 35, 100);
            }
            std::wstring reconnErr;
            if (OpenSessionLocked(effective, reconnErr) &&
                ListDirLocked(effective.remotePath, outEntries, outError)) {
                // Reconnected cleanly!
            } else {
                return false;
            }
        }

        currentSession_ = effective;
        currentSession_.remotePath = NormalizeFtpPath(effective.remotePath);
        outResolvedUrl = BuildFtpUrl(currentSession_, true);
        return true;
    }

    bool CreateRemoteFolder(const std::wstring& remoteDirPath, std::wstring& outError) {
        std::lock_guard<std::mutex> lk(mtx_);
        if (!EnsureSessionLocked(outError)) return false;
        if (!FtpCreateDirectoryW(hConnect_, remoteDirPath.c_str())) {
            outError = DescribeLastWinInetError(L"Could not create remote FTP folder");
            return false;
        }
        return true;
    }

    bool RenameRemoteItem(const std::wstring& oldRemotePath, const std::wstring& newRemotePath, std::wstring& outError) {
        std::lock_guard<std::mutex> lk(mtx_);
        if (!EnsureSessionLocked(outError)) return false;
        if (!FtpRenameFileW(hConnect_, oldRemotePath.c_str(), newRemotePath.c_str())) {
            outError = DescribeLastWinInetError(L"Could not rename remote FTP item");
            return false;
        }
        return true;
    }

    bool DeleteRemoteItem(const std::wstring& remotePath, bool isDirectory, std::wstring& outError) {
        std::lock_guard<std::mutex> lk(mtx_);
        if (!EnsureSessionLocked(outError)) return false;
        if (!isDirectory) {
            if (!FtpDeleteFileW(hConnect_, remotePath.c_str())) {
                outError = DescribeLastWinInetError(L"Could not delete remote file");
                return false;
            }
            return true;
        }
        return DeleteRemoteDirRecursiveLocked(remotePath, outError);
    }

    bool DownloadItemToLocal(const std::wstring& remotePath,
                             const std::wstring& localPath,
                             bool isDirectory,
                             uint64_t knownSize,
                             const FtpProgressCallback& onProgress,
                             std::wstring& outError) {
        std::lock_guard<std::mutex> lk(mtx_);
        if (!EnsureSessionLocked(outError)) return false;
        if (!isDirectory) {
            return DownloadSingleFileLocked(remotePath, localPath, knownSize, onProgress, outError);
        }
        return DownloadDirRecursiveLocked(remotePath, localPath, onProgress, outError);
    }

    bool UploadLocalToRemote(const std::wstring& localPath,
                             const std::wstring& remoteDestPath,
                             const FtpProgressCallback& onProgress,
                             std::wstring& outError) {
        std::lock_guard<std::mutex> lk(mtx_);
        if (!EnsureSessionLocked(outError)) return false;
        DWORD attrs = GetFileAttributesW(localPath.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES) {
            outError = L"Local file not found: " + localPath;
            return false;
        }
        if (attrs & FILE_ATTRIBUTE_DIRECTORY) {
            return UploadDirRecursiveLocked(localPath, remoteDestPath, onProgress, outError);
        }
        return UploadSingleFileLocked(localPath, remoteDestPath, onProgress, outError);
    }

private:
    mutable std::mutex mtx_;
    HINTERNET hInternet_ = nullptr;
    HINTERNET hConnect_ = nullptr;
    FtpUrlInfo currentSession_;

    void CloseHandlesLocked() {
        if (hConnect_) {
            InternetCloseHandle(hConnect_);
            hConnect_ = nullptr;
        }
        if (hInternet_) {
            InternetCloseHandle(hInternet_);
            hInternet_ = nullptr;
        }
    }

    bool EnsureSessionLocked(std::wstring& outError) {
        if (hConnect_ && currentSession_.valid) return true;
        if (currentSession_.valid) {
            return OpenSessionLocked(currentSession_, outError);
        }
        outError = L"Not connected to an FTP server.";
        return false;
    }

    bool OpenSessionLocked(const FtpUrlInfo& info, std::wstring& outError) {
        CloseHandlesLocked();

        hInternet_ = InternetOpenW(L"Windows7AeroExplorer/1.0",
                                   INTERNET_OPEN_TYPE_PRECONFIG,
                                   nullptr, nullptr, 0);
        if (!hInternet_) {
            outError = DescribeLastWinInetError(L"Failed to initialize WinINet");
            return false;
        }

        DWORD connectTimeoutMs = 12000;
        DWORD ioTimeoutMs = 20000;
        InternetSetOptionW(hInternet_, INTERNET_OPTION_CONNECT_TIMEOUT, &connectTimeoutMs, sizeof(connectTimeoutMs));
        InternetSetOptionW(hInternet_, INTERNET_OPTION_RECEIVE_TIMEOUT, &ioTimeoutMs, sizeof(ioTimeoutMs));
        InternetSetOptionW(hInternet_, INTERNET_OPTION_SEND_TIMEOUT, &ioTimeoutMs, sizeof(ioTimeoutMs));

        DWORD flags = info.passive ? INTERNET_FLAG_PASSIVE : 0;
        std::wstring user = info.username.empty() ? L"anonymous" : info.username;
        std::wstring pass = info.password;
        if (ToLowerW(user) == L"anonymous" && pass.empty()) {
            pass = L"anonymous@aeroexplorer.local";
        }

        hConnect_ = InternetConnectW(hInternet_,
                                     info.host.c_str(),
                                     info.port,
                                     user.c_str(),
                                     pass.c_str(),
                                     INTERNET_SERVICE_FTP,
                                     flags,
                                     0);
        if (!hConnect_) {
            outError = DescribeLastWinInetError(L"FTP connection failed to " + info.host);
            CloseHandlesLocked();
            return false;
        }

        // Request UTF-8 mode if server supports RFC 2640 (harmlessly ignored if unsupported)
        FtpCommandW(hConnect_, FALSE, FTP_TRANSFER_TYPE_ASCII, L"OPTS UTF8 ON", 0, nullptr);
        if (info.useFtps) {
            FtpCommandW(hConnect_, FALSE, FTP_TRANSFER_TYPE_ASCII, L"AUTH TLS", 0, nullptr);
        }

        currentSession_ = info;
        return true;
    }

    bool ListDirLocked(const std::wstring& rawRemoteDir,
                       std::vector<FileEntry>& outEntries,
                       std::wstring& outError) {
        outEntries.clear();
        std::wstring normDir = NormalizeFtpPath(rawRemoteDir);

        if (!FtpSetCurrentDirectoryW(hConnect_, normDir.c_str())) {
            outError = DescribeLastWinInetError(L"Cannot open remote directory " + normDir);
            return false;
        }

        WIN32_FIND_DATAW fd = {};
        HINTERNET hFind = FtpFindFirstFileW(
            hConnect_,
            L"*",
            &fd,
            INTERNET_FLAG_RELOAD | INTERNET_FLAG_NO_CACHE_WRITE,
            0);

        if (!hFind) {
            DWORD err = GetLastError();
            if (err == ERROR_NO_MORE_FILES) {
                return true; // Empty directory is valid!
            }
            // Some FTP servers return 550 or empty response when folder has 0 files
            DWORD inetErr = 0, len = 0;
            InternetGetLastResponseInfoW(&inetErr, nullptr, &len);
            if (err == ERROR_INTERNET_EXTENDED_ERROR) {
                std::wstring resp = GetServerResponseText();
                if (resp.find(L"226") != std::wstring::npos || resp.find(L"No files") != std::wstring::npos) {
                    return true;
                }
            }
            outError = DescribeLastWinInetError(L"Failed to list FTP directory " + normDir);
            return false;
        }

        do {
            std::wstring name = fd.cFileName;
            // Trim any trailing CR/LF quirks from non-standard FTP servers
            while (!name.empty() && (name.back() == L'\r' || name.back() == L'\n')) {
                name.pop_back();
            }
            if (name.empty() || name == L"." || name == L"..") {
                continue;
            }

            FileEntry item;
            item.name = name;
            item.displayName = name;
            item.isFtpItem = true;
            item.isDirectory = (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
            item.attributes = fd.dwFileAttributes;
            item.sizeBytes = (static_cast<uint64_t>(fd.nFileSizeHigh) << 32) | fd.nFileSizeLow;
            item.modifiedTime = fd.ftLastWriteTime;
            item.modifiedText = FormatFileTimeWin7(fd.ftLastWriteTime);
            item.remoteRelPath = JoinFtpPath(normDir, name);

            FtpUrlInfo itemUrl = currentSession_;
            itemUrl.remotePath = item.remoteRelPath;
            item.fullPath = BuildFtpUrl(itemUrl, true);
            outEntries.push_back(std::move(item));
        } while (InternetFindNextFileW(hFind, &fd));

        InternetCloseHandle(hFind);
        return true;
    }

    bool DownloadSingleFileLocked(const std::wstring& remotePath,
                                  const std::wstring& localPath,
                                  uint64_t knownSize,
                                  const FtpProgressCallback& onProgress,
                                  std::wstring& outError) {
        HINTERNET hFile = FtpOpenFileW(
            hConnect_,
            remotePath.c_str(),
            GENERIC_READ,
            FTP_TRANSFER_TYPE_BINARY | INTERNET_FLAG_RELOAD | INTERNET_FLAG_DONT_CACHE,
            0);

        if (!hFile) {
            // Fallback to FtpGetFileW
            if (FtpGetFileW(hConnect_, remotePath.c_str(), localPath.c_str(), FALSE,
                            FILE_ATTRIBUTE_NORMAL, FTP_TRANSFER_TYPE_BINARY | INTERNET_FLAG_RELOAD, 0)) {
                return true;
            }
            outError = DescribeLastWinInetError(L"Failed to download " + remotePath);
            return false;
        }

        if (knownSize == 0) {
            DWORD high = 0;
            DWORD low = FtpGetFileSize(hFile, &high);
            if (low != INVALID_FILE_SIZE) {
                knownSize = (static_cast<uint64_t>(high) << 32) | low;
            }
        }

        HANDLE hLocal = CreateFileW(localPath.c_str(), GENERIC_WRITE, 0, nullptr,
                                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (hLocal == INVALID_HANDLE_VALUE) {
            InternetCloseHandle(hFile);
            outError = L"Cannot create local file: " + localPath;
            return false;
        }

        std::vector<uint8_t> buf(65536);
        uint64_t totalRead = 0;
        DWORD bytesRead = 0;
        bool ok = true;

        std::wstring shortName = remotePath;
        size_t sl = shortName.rfind(L'/');
        if (sl != std::wstring::npos) shortName = shortName.substr(sl + 1);

        while (true) {
            if (!InternetReadFile(hFile, buf.data(), static_cast<DWORD>(buf.size()), &bytesRead)) {
                ok = false;
                outError = DescribeLastWinInetError(L"Read error while downloading " + shortName);
                break;
            }
            if (bytesRead == 0) break;
            DWORD written = 0;
            if (!WriteFile(hLocal, buf.data(), bytesRead, &written, nullptr) || written != bytesRead) {
                ok = false;
                outError = L"Disk write error for " + localPath;
                break;
            }
            totalRead += bytesRead;
            if (onProgress) {
                onProgress(L"Downloading " + shortName + L"...", totalRead, knownSize);
            }
        }

        CloseHandle(hLocal);
        InternetCloseHandle(hFile);
        if (!ok) DeleteFileW(localPath.c_str());
        return ok;
    }

    bool DownloadDirRecursiveLocked(const std::wstring& remoteDir,
                                    const std::wstring& localDir,
                                    const FtpProgressCallback& onProgress,
                                    std::wstring& outError) {
        CreateDirectoryW(localDir.c_str(), nullptr);
        std::vector<FileEntry> children;
        if (!ListDirLocked(remoteDir, children, outError)) {
            return false;
        }
        for (const auto& child : children) {
            std::wstring childLocal = localDir + L"\\" + child.name;
            if (child.isDirectory) {
                if (!DownloadDirRecursiveLocked(child.remoteRelPath, childLocal, onProgress, outError)) {
                    return false;
                }
            } else {
                if (!DownloadSingleFileLocked(child.remoteRelPath, childLocal, child.sizeBytes, onProgress, outError)) {
                    return false;
                }
            }
        }
        return true;
    }

    bool UploadSingleFileLocked(const std::wstring& localPath,
                                const std::wstring& remoteDestPath,
                                const FtpProgressCallback& onProgress,
                                std::wstring& outError) {
        HANDLE hLocal = CreateFileW(localPath.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                                    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (hLocal == INVALID_HANDLE_VALUE) {
            outError = L"Cannot open local file for upload: " + localPath;
            return false;
        }

        LARGE_INTEGER liSize = {};
        GetFileSizeEx(hLocal, &liSize);
        uint64_t totalBytes = static_cast<uint64_t>(liSize.QuadPart);

        HINTERNET hRemote = FtpOpenFileW(
            hConnect_,
            remoteDestPath.c_str(),
            GENERIC_WRITE,
            FTP_TRANSFER_TYPE_BINARY | INTERNET_FLAG_RELOAD,
            0);

        if (!hRemote) {
            CloseHandle(hLocal);
            // Fallback to FtpPutFileW
            if (FtpPutFileW(hConnect_, localPath.c_str(), remoteDestPath.c_str(),
                            FTP_TRANSFER_TYPE_BINARY, 0)) {
                return true;
            }
            outError = DescribeLastWinInetError(L"Failed to upload to " + remoteDestPath);
            return false;
        }

        std::wstring shortName = localPath;
        size_t bs = shortName.rfind(L'\\');
        if (bs != std::wstring::npos) shortName = shortName.substr(bs + 1);

        std::vector<uint8_t> buf(65536);
        uint64_t sentTotal = 0;
        DWORD bytesRead = 0;
        bool ok = true;

        while (ReadFile(hLocal, buf.data(), static_cast<DWORD>(buf.size()), &bytesRead, nullptr) && bytesRead > 0) {
            DWORD written = 0;
            if (!InternetWriteFile(hRemote, buf.data(), bytesRead, &written) || written != bytesRead) {
                ok = false;
                outError = DescribeLastWinInetError(L"Upload interrupted for " + shortName);
                break;
            }
            sentTotal += written;
            if (onProgress) {
                onProgress(L"Uploading " + shortName + L"...", sentTotal, totalBytes);
            }
        }

        InternetCloseHandle(hRemote);
        CloseHandle(hLocal);
        return ok;
    }

    bool UploadDirRecursiveLocked(const std::wstring& localDir,
                                  const std::wstring& remoteDir,
                                  const FtpProgressCallback& onProgress,
                                  std::wstring& outError) {
        FtpCreateDirectoryW(hConnect_, remoteDir.c_str());

        std::wstring pattern = localDir + L"\\*";
        WIN32_FIND_DATAW fd = {};
        HANDLE hFind = FindFirstFileW(pattern.c_str(), &fd);
        if (hFind == INVALID_HANDLE_VALUE) return true;

        bool ok = true;
        do {
            std::wstring name = fd.cFileName;
            if (name == L"." || name == L"..") continue;
            std::wstring childLocal = localDir + L"\\" + name;
            std::wstring childRemote = JoinFtpPath(remoteDir, name);
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                if (!UploadDirRecursiveLocked(childLocal, childRemote, onProgress, outError)) {
                    ok = false;
                    break;
                }
            } else {
                if (!UploadSingleFileLocked(childLocal, childRemote, onProgress, outError)) {
                    ok = false;
                    break;
                }
            }
        } while (FindNextFileW(hFind, &fd));

        FindClose(hFind);
        return ok;
    }

    bool DeleteRemoteDirRecursiveLocked(const std::wstring& remoteDir, std::wstring& outError) {
        std::vector<FileEntry> children;
        if (ListDirLocked(remoteDir, children, outError)) {
            for (const auto& c : children) {
                if (c.isDirectory) {
                    if (!DeleteRemoteDirRecursiveLocked(c.remoteRelPath, outError)) return false;
                } else {
                    if (!FtpDeleteFileW(hConnect_, c.remoteRelPath.c_str())) {
                        outError = DescribeLastWinInetError(L"Could not delete " + c.remoteRelPath);
                        return false;
                    }
                }
            }
        }
        // Navigate to parent before removing directory so server doesn't lock cwd
        std::wstring parent = ParentFtpPath(remoteDir);
        FtpSetCurrentDirectoryW(hConnect_, parent.c_str());
        if (!FtpRemoveDirectoryW(hConnect_, remoteDir.c_str())) {
            outError = DescribeLastWinInetError(L"Could not remove FTP directory " + remoteDir);
            return false;
        }
        return true;
    }

    static std::wstring GetServerResponseText() {
        DWORD inetErr = 0, len = 0;
        InternetGetLastResponseInfoW(&inetErr, nullptr, &len);
        if (len == 0) return L"";
        std::vector<wchar_t> buf(len + 2, 0);
        if (InternetGetLastResponseInfoW(&inetErr, buf.data(), &len)) {
            return TrimW(buf.data());
        }
        return L"";
    }

    static std::wstring DescribeLastWinInetError(const std::wstring& prefix) {
        DWORD err = GetLastError();
        std::wstring serverResp = GetServerResponseText();

        wchar_t sysMsg[512] = {};
        HMODULE hWinInet = GetModuleHandleW(L"wininet.dll");
        DWORD got = FormatMessageW(
            FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS |
                (hWinInet ? FORMAT_MESSAGE_FROM_HMODULE : 0),
            hWinInet,
            err,
            0,
            sysMsg,
            512,
            nullptr);

        std::wostringstream oss;
        oss << prefix << L" (Code " << err << L")";
        if (got > 0) {
            std::wstring cleanSys = TrimW(sysMsg);
            if (!cleanSys.empty()) oss << L": " << cleanSys;
        }
        if (!serverResp.empty()) {
            oss << L"\r\nServer response: " << serverResp;
        }
        return oss.str();
    }
};

} // namespace aero
