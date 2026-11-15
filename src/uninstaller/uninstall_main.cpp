// Windows 7 Aero Explorer - Uninstaller (Uninstall.exe)
//
// Removes the installed application, its shortcuts, the shell context menu
// entry and the Programs and Features registration. Supports /S plus the
// switches written by the installer: /DIR=, /REMOVESETTINGS, /REMOVECTXMENU,
// /FROMTEMP. Runs elevated via its embedded manifest.
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0a00
#endif

#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <objidl.h>
#include <gdiplus.h>
#include <uxtheme.h>

#include <string>
#include <vector>

#include "../common/version.h"
#include "uninstall_res.h"

using namespace Gdiplus;

namespace {

struct UninstallOptions {
    std::wstring installDir;
    bool removeSettings = true;
    bool removeContextMenu = true;
    bool silent = false;
    bool fromTemp = false;
};

UninstallOptions g_opt;
std::wstring g_lastError;
bool g_uninstallCompleted = false;
HWND g_hDlg = nullptr;
HINSTANCE g_hInst = nullptr;

constexpr UINT_PTR kCleanupTimer = 1;

std::wstring RegReadString(HKEY root, const wchar_t* subKey, const wchar_t* value) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(root, subKey, 0, KEY_READ | KEY_WOW64_64KEY, &key) != ERROR_SUCCESS) {
        return L"";
    }
    wchar_t buf[2048] = {};
    DWORD size = sizeof(buf) - sizeof(wchar_t);
    DWORD type = 0;
    std::wstring out;
    if (RegQueryValueExW(key, value, nullptr, &type, reinterpret_cast<LPBYTE>(buf), &size) == ERROR_SUCCESS &&
        (type == REG_SZ || type == REG_EXPAND_SZ)) {
        buf[size / sizeof(wchar_t)] = L'\0';
        out = buf;
    }
    RegCloseKey(key);
    return out;
}

std::wstring QuoteArg(const std::wstring& s) {
    return L"\"" + s + L"\"";
}

bool DirectoryExists(const std::wstring& dir) {
    DWORD attrs = GetFileAttributesW(dir.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY);
}

bool DeleteTreeRecursive(const std::wstring& dir) {
    if (dir.size() <= 3) {
        g_lastError = L"Refusing to delete a root folder: " + dir;
        return false;
    }
    std::wstring pattern = dir + L"\\*";
    WIN32_FIND_DATAW fd = {};
    HANDLE hFind = FindFirstFileW(pattern.c_str(), &fd);
    bool ok = true;
    if (hFind != INVALID_HANDLE_VALUE) {
        do {
            std::wstring name = fd.cFileName;
            if (name == L"." || name == L"..") continue;
            std::wstring path = dir + L"\\" + name;
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                if (!DeleteTreeRecursive(path)) ok = false;
            } else {
                SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_NORMAL);
                if (!DeleteFileW(path.c_str())) {
                    ok = false;
                    if (g_lastError.empty()) g_lastError = L"Could not delete " + path;
                }
            }
        } while (FindNextFileW(hFind, &fd));
        FindClose(hFind);
    }
    if (!RemoveDirectoryW(dir.c_str())) {
        ok = false;
        if (DirectoryExists(dir) && g_lastError.empty()) {
            g_lastError = L"Could not remove folder " + dir;
        }
    }
    return ok;
}

std::vector<std::wstring> ShortcutFolders() {
    std::vector<std::wstring> dirs;
    wchar_t buf[MAX_PATH] = {};
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_DESKTOPDIRECTORY, nullptr, 0, buf))) dirs.emplace_back(buf);
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_COMMON_DESKTOPDIRECTORY, nullptr, 0, buf))) dirs.emplace_back(buf);
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_PROGRAMS, nullptr, 0, buf))) dirs.emplace_back(buf);
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_COMMON_PROGRAMS, nullptr, 0, buf))) dirs.emplace_back(buf);
    return dirs;
}

void RemoveShortcuts() {
    for (const auto& dir : ShortcutFolders()) {
        const std::wstring names[] = {
            L"Windows 7 Aero Explorer.lnk",
            L"AeroExplorer.lnk",
            L"Windows 7 Aero Explorer (FTP).lnk",
        };
        for (const auto& nm : names) {
            std::wstring path = dir + L"\\" + nm;
            DeleteFileW(path.c_str());
        }
        // Program group folders created by the installer.
        DeleteTreeRecursive(dir + L"\\" + AERO_SHORT_NAME_W);
        DeleteTreeRecursive(dir + L"\\Windows 7 Aero Explorer");

        // Older installs may have dropped the exe directly in a program folder.
        std::wstring legacyPif = dir + L"\\" + AERO_EXE_NAME_W;
        DeleteFileW(legacyPif.c_str());
    }
}

void RemoveContextMenuEntries() {
    const wchar_t* roots[] = {
        L"Software\\Classes\\Directory\\shell\\AeroExplorer",
        L"Software\\Classes\\Directory\\Background\\shell\\AeroExplorer",
        L"Software\\Classes\\Drive\\shell\\AeroExplorer",
        L"Software\\Classes\\Applications\\AeroExplorer.exe",
        L"Software\\Classes\\*\\shell\\AeroExplorer",
    };
    for (const wchar_t* path : roots) {
        SHDeleteKeyW(HKEY_CURRENT_USER, path);
        SHDeleteKeyW(HKEY_LOCAL_MACHINE, path);
    }
    SHDeleteKeyW(HKEY_CURRENT_USER, L"Software\\Classes\\.aeroftp");

    // Refresh the shell icon / association cache so the entry disappears at once.
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

void RemoveUninstallEntry() {
    RegDeleteKeyW(HKEY_CURRENT_USER, AERO_UNINSTALL_REG_KEY);
    RegDeleteKeyW(HKEY_LOCAL_MACHINE, AERO_UNINSTALL_REG_KEY);
    SHDeleteKeyW(HKEY_LOCAL_MACHINE, L"Software\\AeroExplorer");
    SHDeleteKeyW(HKEY_CURRENT_USER, L"Software\\AeroExplorer");
    SHDeleteKeyW(HKEY_LOCAL_MACHINE,
                 L"Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\AeroExplorer.exe");
}

void RemoveSettings() {
    wchar_t appData[MAX_PATH] = {};
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, appData))) {
        DeleteTreeRecursive(std::wstring(appData) + L"\\" + AERO_SETTINGS_SUBDIR_W);
    }
    wchar_t localAppData[MAX_PATH] = {};
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, localAppData))) {
        DeleteTreeRecursive(std::wstring(localAppData) + L"\\" + AERO_SETTINGS_SUBDIR_W);
    }
}

void ProcessRemoval(const UninstallOptions& opt, HWND hProgress, HWND hStatus) {
    auto step = [&](int percent, const std::wstring& text) {
        if (hProgress) SendMessageW(hProgress, PBM_SETPOS, static_cast<WPARAM>(percent), 0);
        if (hStatus) SetWindowTextW(hStatus, text.c_str());
        if (percent % 10 == 0) {
            MSG msg = {};
            while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
            UpdateWindow(hProgress ? hProgress : nullptr);
        }
    };

    step(5, L"Removing desktop and Start menu shortcuts...");
    RemoveShortcuts();

    step(25, L"Removing Windows Explorer context menu integration...");
    if (opt.removeContextMenu) {
        RemoveContextMenuEntries();
    }

    step(45, L"Removing Programs and Features registration...");
    RemoveUninstallEntry();

    if (opt.removeSettings) {
        step(60, L"Deleting saved FTP sites and settings...");
        RemoveSettings();
    }

    step(75, L"Deleting program files...");
    if (!opt.installDir.empty() && DirectoryExists(opt.installDir)) {
        // Delete everything except this running uninstaller, then queue the rest.
        DeleteTreeRecursive(opt.installDir);
    }

    step(95, L"Finishing up...");
    // Queued deletion of any remaining files (including our own) at reboot.
    if (!opt.installDir.empty()) {
        std::wstring key = L"Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce";
        HKEY hk = nullptr;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, key.c_str(), 0, nullptr, 0, KEY_SET_VALUE,
                            nullptr, &hk, nullptr) == ERROR_SUCCESS) {
            std::wstring cmd = L"cmd.exe /c rmdir /s /q " + QuoteArg(opt.installDir);
            RegSetValueExW(hk, L"AeroExplorerCleanup", 0, REG_SZ,
                           reinterpret_cast<const BYTE*>(cmd.c_str()),
                           static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t)));
            RegCloseKey(hk);
        }
    }
    step(100, L"Windows 7 Aero Explorer was removed from this computer.");
}

void RestartExplorerShell() {
    // Notify Explorer that associations changed so cached icons refresh.
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

int RunSilent() {
    ProcessRemoval(g_opt, nullptr, nullptr);
    RestartExplorerShell();
    return 0;
}

INT_PTR CALLBACK UninstallDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_INITDIALOG: {
            g_hDlg = hDlg;
            SetWindowTextW(hDlg, L"Windows 7 Aero Explorer Uninstall");
            SetDlgItemTextW(hDlg, IDC_UN_TITLE,
                            (std::wstring(AERO_APP_NAME_W) + L" " + AERO_VERSION_W + L" (64-bit)").c_str());
            std::wstring dirText = g_opt.installDir.empty() ? L"(not found - cleaning registry only)"
                                                            : g_opt.installDir;
            SetDlgItemTextW(hDlg, IDC_UN_INSTALLDIR, dirText.c_str());
            CheckDlgButton(hDlg, IDC_UN_SETTINGS, g_opt.removeSettings ? BST_CHECKED : BST_UNCHECKED);
            CheckDlgButton(hDlg, IDC_UN_CTXMENU, g_opt.removeContextMenu ? BST_CHECKED : BST_UNCHECKED);
            SetDlgItemTextW(hDlg, IDC_UN_STATUS,
                            L"Click Uninstall to remove the application from this computer.");
            SetDlgItemTextW(hDlg, IDOK, L"Uninstall");
            HWND hProgress = GetDlgItem(hDlg, IDC_UN_PROGRESS);
            SendMessageW(hProgress, PBM_SETRANGE, 0, MAKELPARAM(0, 100));
            SendMessageW(hProgress, PBM_SETPOS, 0, 0);
            EnableWindow(GetDlgItem(hDlg, IDOK), TRUE);
            return TRUE;
        }

        case WM_COMMAND: {
            int id = LOWORD(wParam);
            if (id == IDOK) {
                g_opt.removeSettings = IsDlgButtonChecked(hDlg, IDC_UN_SETTINGS) == BST_CHECKED;
                g_opt.removeContextMenu = IsDlgButtonChecked(hDlg, IDC_UN_CTXMENU) == BST_CHECKED;

                std::wstring prompt =
                    L"Remove " + std::wstring(AERO_APP_NAME_W) + L" from this computer?";
                if (MessageBoxW(hDlg, prompt.c_str(), L"Windows 7 Aero Explorer Uninstall",
                                MB_ICONQUESTION | MB_YESNO | MB_DEFBUTTON2) != IDYES) {
                    return TRUE;
                }

                EnableWindow(GetDlgItem(hDlg, IDOK), FALSE);
                EnableWindow(GetDlgItem(hDlg, IDCANCEL), FALSE);
                EnableWindow(GetDlgItem(hDlg, IDC_UN_SETTINGS), FALSE);
                EnableWindow(GetDlgItem(hDlg, IDC_UN_CTXMENU), FALSE);

                ProcessRemoval(g_opt, GetDlgItem(hDlg, IDC_UN_PROGRESS), GetDlgItem(hDlg, IDC_UN_STATUS));
                RestartExplorerShell();

                std::wstring doneText = L"Uninstall completed successfully.";
                if (!g_lastError.empty()) {
                    doneText += L"\r\n\r\nSome files could not be deleted and will be removed "
                                L"automatically the next time you sign in:\r\n" + g_lastError;
                }
                SetDlgItemTextW(hDlg, IDC_UN_STATUS, doneText.c_str());
                SetWindowTextW(GetDlgItem(hDlg, IDOK), L"Close");
                EnableWindow(GetDlgItem(hDlg, IDOK), TRUE);
                SetFocus(GetDlgItem(hDlg, IDOK));
                g_uninstallCompleted = true;
                return TRUE;
            }
            if (id == IDCANCEL) {
                if (g_uninstallCompleted) {
                    EndDialog(hDlg, IDOK);
                    return TRUE;
                }
                EndDialog(hDlg, IDCANCEL);
                return TRUE;
            }
            break;
        }

        case WM_CLOSE:
            if (g_uninstallCompleted) {
                EndDialog(hDlg, IDOK);
            } else {
                EndDialog(hDlg, IDCANCEL);
            }
            return TRUE;

        case WM_ERASEBKGND: {
            HDC dc = reinterpret_cast<HDC>(wParam);
            RECT rc = {};
            GetClientRect(hDlg, &rc);
            // Simple two-stop vertical fill (GdiGradientFill lives in msimg32, which
            // keeps this binary dependency-free).
            const int height = rc.bottom - rc.top;
            for (int y = 0; y < height; ++y) {
                const double t = height > 1 ? static_cast<double>(y) / (height - 1) : 0.0;
                const int r = static_cast<int>(234 + (207 - 234) * t);
                const int g = static_cast<int>(244 + (229 - 244) * t);
                const int b = static_cast<int>(255 + (248 - 255) * t);
                HPEN pen = CreatePen(PS_SOLID, 1, RGB(r, g, b));
                HGDIOBJ oldPen = SelectObject(dc, pen);
                MoveToEx(dc, rc.left, rc.top + y, nullptr);
                LineTo(dc, rc.right, rc.top + y);
                SelectObject(dc, oldPen);
                DeleteObject(pen);
            }
            return TRUE;
        }

        case WM_CTLCOLORSTATIC: {
            HDC dc = reinterpret_cast<HDC>(wParam);
            SetBkMode(dc, TRANSPARENT);
            SetTextColor(dc, RGB(30, 52, 80));
            static HBRUSH hollow = CreateSolidBrush(RGB(234, 244, 255));
            return reinterpret_cast<INT_PTR>(hollow);
        }

        case WM_TIMER:
            if (wParam == kCleanupTimer) {
                KillTimer(hDlg, kCleanupTimer);
            }
            return TRUE;
    }
    return FALSE;
}

void ParseCommandLine(UninstallOptions& opt) {
    opt.installDir = RegReadString(HKEY_CURRENT_USER, AERO_UNINSTALL_REG_KEY, L"InstallLocation");
    if (opt.installDir.empty()) {
        opt.installDir = RegReadString(HKEY_LOCAL_MACHINE, AERO_UNINSTALL_REG_KEY, L"InstallLocation");
    }

    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return;

    for (int i = 1; i < argc; ++i) {
        std::wstring arg = argv[i];
        if (_wcsicmp(arg.c_str(), L"/S") == 0 || _wcsicmp(arg.c_str(), L"-S") == 0 ||
            _wcsicmp(arg.c_str(), L"/SILENT") == 0) {
            opt.silent = true;
        } else if (_wcsnicmp(arg.c_str(), L"/DIR=", 5) == 0) {
            std::wstring dir = arg.substr(5);
            if (dir.size() >= 2 && dir.front() == L'"' && dir.back() == L'"') {
                dir = dir.substr(1, dir.size() - 2);
            }
            while (!dir.empty() && (dir.back() == L'\\' || dir.back() == L'/')) dir.pop_back();
            opt.installDir = dir;
        } else if (_wcsicmp(arg.c_str(), L"/REMOVESETTINGS") == 0) {
            opt.removeSettings = true;
        } else if (_wcsicmp(arg.c_str(), L"/KEEPSETTINGS") == 0) {
            opt.removeSettings = false;
        } else if (_wcsicmp(arg.c_str(), L"/REMOVECTXMENU") == 0) {
            opt.removeContextMenu = true;
        } else if (_wcsicmp(arg.c_str(), L"/KEEPCTXMENU") == 0) {
            opt.removeContextMenu = false;
        } else if (_wcsicmp(arg.c_str(), L"/FROMTEMP") == 0) {
            opt.fromTemp = true;
            opt.silent = true;
        }
    }
    LocalFree(argv);
}

} // namespace

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, PWSTR, int) {
    g_hInst = hInstance;

    INITCOMMONCONTROLSEX icc = {};
    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_STANDARD_CLASSES | ICC_PROGRESS_CLASS;
    InitCommonControlsEx(&icc);
    OleInitialize(nullptr);

    GdiplusStartupInput gdipInput;
    ULONG_PTR token = 0;
    GdiplusStartup(&token, &gdipInput, nullptr);

    ParseCommandLine(g_opt);
    if (g_opt.installDir.empty()) {
        wchar_t selfPath[MAX_PATH] = {};
        GetModuleFileNameW(nullptr, selfPath, MAX_PATH);
        std::wstring dir = selfPath;
        size_t slash = dir.find_last_of(L'\\');
        if (slash != std::wstring::npos) dir = dir.substr(0, slash);
        g_opt.installDir = dir;
    }

    int result = 0;
    if (g_opt.silent) {
        result = RunSilent();
        if (!g_opt.fromTemp) {
            // GUI process: relaunch a copy from %TEMP% so our own file can be replaced,
            // then the temp copy deletes the install directory and itself.
            wchar_t selfPath[MAX_PATH] = {};
            GetModuleFileNameW(nullptr, selfPath, MAX_PATH);
            unsigned long long tick = static_cast<unsigned long long>(GetTickCount64());
            std::wstring tempDir;
            wchar_t tmp[MAX_PATH] = {};
            if (GetTempPathW(MAX_PATH, tmp) > 0) tempDir = tmp;
            else tempDir = L"C:\\Windows\\Temp\\";
            std::wstring tempExe = tempDir + L"AeroUninst_" + std::to_wstring(tick) + L".exe";

            bool relaunched = SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, nullptr)) &&
                              !!CopyFileW(selfPath, tempExe.c_str(), FALSE);
            if (relaunched) {
                std::wstring args = L"/S /FROMTEMP /DIR=" + QuoteArg(g_opt.installDir);
                args += g_opt.removeSettings ? L" /REMOVESETTINGS" : L" /KEEPSETTINGS";
                args += g_opt.removeContextMenu ? L" /REMOVECTXMENU" : L" /KEEPCTXMENU";
                SHELLEXECUTEINFOW sei = {};
                sei.cbSize = sizeof(sei);
                sei.fMask = SEE_MASK_NOCLOSEPROCESS;
                sei.lpVerb = L"open";
                sei.lpFile = tempExe.c_str();
                sei.lpParameters = args.c_str();
                sei.nShow = SW_HIDE;
                if (ShellExecuteExW(&sei)) {
                    if (sei.hProcess) {
                        WaitForSingleObject(sei.hProcess, 60000);
                        CloseHandle(sei.hProcess);
                    }
                } else {
                    relaunched = false;
                }
            }
            UninstallOptions cleanupOpt = g_opt;
            if (relaunched) {
                cleanupOpt.installDir.clear();
            }
            ProcessRemoval(cleanupOpt, nullptr, nullptr);
            DeleteFileW(tempExe.c_str());
            if (!relaunched && !g_opt.installDir.empty()) {
                ProcessRemoval(g_opt, nullptr, nullptr);
            }
        } else {
            // Running from %TEMP%: delete everything and clean up both copies.
            wchar_t selfPath[MAX_PATH] = {};
            GetModuleFileNameW(nullptr, selfPath, MAX_PATH);
            std::wstring self = selfPath;
            ProcessRemoval(g_opt, nullptr, nullptr);
            std::wstring cmd = L"/c ping -n 3 127.0.0.1 >nul & del /f /q " + QuoteArg(self);
            if (!g_opt.installDir.empty()) {
                cmd += L" & rmdir /s /q " + QuoteArg(g_opt.installDir);
            }
            STARTUPINFOW si = {};
            si.cb = sizeof(si);
            si.dwFlags = STARTF_USESHOWWINDOW;
            si.wShowWindow = SW_HIDE;
            PROCESS_INFORMATION pi = {};
            std::wstring fullCmd = L"cmd.exe " + cmd;
            std::vector<wchar_t> mutableCmd(fullCmd.begin(), fullCmd.end());
            mutableCmd.push_back(L'\0');
            if (CreateProcessW(nullptr, mutableCmd.data(), nullptr, nullptr, FALSE,
                               CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
                CloseHandle(pi.hThread);
                CloseHandle(pi.hProcess);
            }
        }
    } else {
        INT_PTR res = DialogBoxParamW(hInstance, MAKEINTRESOURCEW(IDD_UNINSTALL), nullptr,
                                      UninstallDlgProc, 0);
        result = (res == IDCANCEL) ? 1 : 0;
    }

    if (token) GdiplusShutdown(token);
    OleUninitialize();
    return result;
}
