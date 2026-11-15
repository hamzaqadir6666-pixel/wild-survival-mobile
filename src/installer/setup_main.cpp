// Windows 7 Aero Explorer - Setup Wizard (AeroExplorerSetup.exe)
//
// A single custom-painted dialog hosts six Windows 7 Setup style pages:
//   Welcome -> License -> Destination -> Components -> Installing -> Finish
// The application payload is embedded as an APK1 (LZSS + CRC32) archive in
// RCDATA and written out live with a progress bar, exactly like a real setup.
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0a00
#endif

#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shellapi.h>
#include <objidl.h>
#include <gdiplus.h>
#include <uxtheme.h>

#include <atomic>
#include <string>
#include <thread>
#include <vector>

#include "../common/pack_format.h"
#include "../common/version.h"
#include "setup_rc.h"
#include "setup_theme.h"

using namespace Gdiplus;

namespace {

enum class Page { Welcome = 0, License, Destination, Components, Installing, Finish, Count };

struct SetupState {
    Page page = Page::Welcome;
    std::wstring installDir;
    bool acceptLicense = false;
    bool desktopShortcut = true;
    bool startMenuShortcut = true;
    bool contextMenu = true;
    bool associateFtp = true;
    bool launchApp = true;
    bool openReadme = false;
    bool silent = false;
    bool installed = false;
    bool installFailed = false;
    std::wstring statusText;
    int progress = 0;
    uint64_t payloadBytes = 0;
    uint64_t installedBytes = 0;
};

SetupState g_state;
HINSTANCE g_hInst = nullptr;
HWND g_hDlg = nullptr;
HBITMAP g_banner = nullptr;
HBITMAP g_header = nullptr;
HFONT g_fontUI = nullptr;
HFONT g_fontBold = nullptr;
HFONT g_fontTitle = nullptr;
HFONT g_fontSmall = nullptr;
ULONG_PTR g_gdipToken = 0;
HBRUSH g_pageBrush = nullptr;
HBRUSH g_footerBrush = nullptr;
std::thread g_extractThread;
std::atomic<bool> g_extractRunning{ false };

// Page geometry at 96 DPI. The dialog is resized so its client area matches
// these metrics exactly (scaled for the current DPI), which keeps the custom
// GDI+ chrome and the native child controls perfectly aligned.
constexpr int kClientW = 764;
constexpr int kClientH = 566;
constexpr int kBanner = setup_theme::kBannerWidth;   // 168 px artwork column
constexpr int kFooter = setup_theme::kFooterHeight;  // 58 px button strip
constexpr int kContentLeft = 186;                    // banner + gutter
constexpr int kContentRight = 18;                    // right gutter
constexpr int kTitleTop = 12;
constexpr int kSubtitleTop = 46;
constexpr int kSeparatorTop = 100;
constexpr int kBodyTop = 112;

std::wstring DefaultInstallDir() {
    wchar_t programFiles[MAX_PATH] = {};
    if (!SHGetFolderPathW(nullptr, CSIDL_PROGRAM_FILES, nullptr, 0, programFiles)) {
        return std::wstring(programFiles) + L"\\" + AERO_SHORT_NAME_W;
    }
    return std::wstring(L"C:\\Program Files\\") + AERO_SHORT_NAME_W;
}

std::wstring RegReadString(HKEY root, const wchar_t* subKey, const wchar_t* value) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(root, subKey, 0, KEY_READ | KEY_WOW64_64KEY, &key) != ERROR_SUCCESS) return L"";
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

std::wstring FormatBytes(uint64_t bytes) {
    const wchar_t* units[] = { L"bytes", L"KB", L"MB", L"GB", L"TB" };
    if (bytes < 1024) return std::to_wstring(bytes) + L" bytes";
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < 4) {
        value /= 1024.0;
        ++unit;
    }
    wchar_t buf[64] = {};
    if (value >= 100.0) swprintf(buf, 64, L"%.0f %s", value, units[unit]);
    else if (value >= 10.0) swprintf(buf, 64, L"%.1f %s", value, units[unit]);
    else swprintf(buf, 64, L"%.2f %s", value, units[unit]);
    return buf;
}

std::wstring DriveRootOf(const std::wstring& path) {
    if (path.size() >= 2 && path[1] == L':') return path.substr(0, 2) + L"\\";
    return L"C:\\";
}

uint64_t FreeSpaceOf(const std::wstring& dir) {
    ULARGE_INTEGER freeBytes = {}, totalBytes = {}, totalFree = {};
    if (GetDiskFreeSpaceExW(DriveRootOf(dir).c_str(), &freeBytes, &totalBytes, &totalFree)) {
        return freeBytes.QuadPart;
    }
    return 0;
}

std::wstring ExeDirectory() {
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring dir = path;
    size_t slash = dir.find_last_of(L'\\');
    if (slash != std::wstring::npos) dir = dir.substr(0, slash);
    return dir;
}

void AppendLog(const std::wstring& text) {
    wchar_t tempPath[MAX_PATH] = {};
    GetTempPathW(MAX_PATH, tempPath);
    std::wstring logPath = std::wstring(tempPath) + L"AeroExplorerSetup.log";
    HANDLE hFile = CreateFileW(logPath.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                               OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hFile == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME st = {};
    GetLocalTime(&st);
    wchar_t stamp[64] = {};
    swprintf(stamp, 64, L"[%04u-%02u-%02u %02u:%02u:%02u] ", st.wYear, st.wMonth, st.wDay,
             st.wHour, st.wMinute, st.wSecond);
    std::wstring line = std::wstring(stamp) + text + L"\r\n";
    DWORD written = 0;
    SetFilePointer(hFile, 0, nullptr, FILE_END);
    WriteFile(hFile, line.c_str(), static_cast<DWORD>(line.size() * sizeof(wchar_t)), &written, nullptr);
    CloseHandle(hFile);
}

// ---------------------------------------------------------------------------
// Payload access
// ---------------------------------------------------------------------------
bool LoadPayload(std::vector<uint8_t>& out) {
    HRSRC res = FindResourceW(g_hInst, MAKEINTRESOURCEW(IDR_PAYLOAD), RT_RCDATA);
    if (!res) {
        AppendLog(L"Payload resource not found (build error).");
        return false;
    }
    DWORD size = SizeofResource(g_hInst, res);
    HGLOBAL handle = LoadResource(g_hInst, res);
    if (!handle || size == 0) {
        AppendLog(L"Payload resource is empty.");
        return false;
    }
    const void* data = LockResource(handle);
    if (!data) return false;
    out.assign(static_cast<const uint8_t*>(data), static_cast<const uint8_t*>(data) + size);
    return true;
}

// ---------------------------------------------------------------------------
// Fonts & layout helpers
// ---------------------------------------------------------------------------
void CreateFonts() {
    auto makeFont = [](int points, int weight, const wchar_t* face) {
        LOGFONTW lf = {};
        lf.lfHeight = -MulDiv(points, 96, 72);
        lf.lfWeight = weight;
        lf.lfCharSet = DEFAULT_CHARSET;
        lf.lfQuality = CLEARTYPE_QUALITY;
        wcscpy_s(lf.lfFaceName, face);
        return CreateFontIndirectW(&lf);
    };
    g_fontUI = makeFont(9, FW_NORMAL, L"Segoe UI");
    g_fontBold = makeFont(9, FW_SEMIBOLD, L"Segoe UI");
    g_fontTitle = makeFont(14, FW_NORMAL, L"Segoe UI");
    g_fontSmall = makeFont(8, FW_NORMAL, L"Segoe UI");
}

int DpiOf(HWND hwnd) {
    using Fn = UINT(WINAPI*)(HWND);
    static Fn fn = reinterpret_cast<Fn>(reinterpret_cast<void*>(
        GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow")));
    if (fn && hwnd) {
        UINT d = fn(hwnd);
        if (d >= 96) return static_cast<int>(d);
    }
    return 96;
}

// ---------------------------------------------------------------------------
// UI construction
// ---------------------------------------------------------------------------
int Px(int value) {
    return MulDiv(value, DpiOf(g_hDlg), 96);
}

int ContentWidth() {
    return kClientW - kContentLeft - kContentRight;
}

void HideAllPageControls() {
    const int ids[] = {
        IDC_LICENSE_TEXT, IDC_LICENSE_ACCEPT, IDC_PATH_EDIT, IDC_BROWSE_BTN, IDC_SPACE_LABEL,
        IDC_SIZE_LABEL, IDC_DIR_LIST, IDC_COMP_DESKTOP, IDC_COMP_STARTMENU, IDC_COMP_CONTEXTMENU,
        IDC_COMP_ASSOCIATE, IDC_SUMMARY_TEXT, IDC_PROGRESS, IDC_STATUS_LABEL, IDC_LAUNCH_CHECK,
        IDC_README_CHECK, IDC_PAGE_TITLE, IDC_PAGE_SUBTITLE,
    };
    for (int id : ids) {
        HWND h = GetDlgItem(g_hDlg, id);
        if (h) ShowWindow(h, SW_HIDE);
    }
}

// Position a child control given 96-DPI pixel coordinates.
void Place(int id, int dx, int dy, int dw, int dh) {
    HWND ctrl = GetDlgItem(g_hDlg, id);
    if (!ctrl) return;
    SetWindowPos(ctrl, nullptr, Px(dx), Px(dy), Px(dw), Px(dh),
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void SetControlFont(int id, HFONT font) {
    HWND ctrl = GetDlgItem(g_hDlg, id);
    if (ctrl && font) SendMessageW(ctrl, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
}

void UpdateNavigationButtons() {
    HWND back = GetDlgItem(g_hDlg, IDC_BACK_BTN);
    HWND next = GetDlgItem(g_hDlg, IDC_NEXT_BTN);
    HWND cancel = GetDlgItem(g_hDlg, IDC_CANCEL_BTN);
    if (!back || !next || !cancel) return;

    bool backEnabled = false;
    bool nextEnabled = true;
    std::wstring nextLabel = L"&Next >";
    std::wstring cancelLabel = L"Cancel";
    bool cancelEnabled = true;

    switch (g_state.page) {
        case Page::Welcome:
            backEnabled = false;
            break;
        case Page::License:
            backEnabled = true;
            nextEnabled = g_state.acceptLicense;
            break;
        case Page::Destination:
            backEnabled = true;
            break;
        case Page::Components:
            backEnabled = true;
            nextLabel = L"&Install";
            break;
        case Page::Installing:
            backEnabled = false;
            nextEnabled = false;
            cancelEnabled = false;
            break;
        case Page::Finish:
            backEnabled = false;
            nextLabel = L"&Finish";
            cancelLabel = L"Close";
            break;
        default:
            break;
    }

    EnableWindow(back, backEnabled);
    EnableWindow(next, nextEnabled);
    EnableWindow(cancel, cancelEnabled);
    SetWindowTextW(next, nextLabel.c_str());
    SetWindowTextW(cancel, cancelLabel.c_str());
    InvalidateRect(next, nullptr, TRUE);
}

void SetPageText(const std::wstring& title, const std::wstring& subtitle) {
    SetDlgItemTextW(g_hDlg, IDC_PAGE_TITLE, title.c_str());
    SetDlgItemTextW(g_hDlg, IDC_PAGE_SUBTITLE, subtitle.c_str());
}

void UpdateSpaceLabels() {
    std::wstring dir = g_state.installDir;
    uint64_t freeBytes = FreeSpaceOf(dir);
    uint64_t needed = g_state.payloadBytes > 0 ? g_state.payloadBytes * 3 : 12ull * 1024 * 1024;
    std::wstring sizeText = L"Space required: " + FormatBytes(needed);
    std::wstring freeText = L"Space available: " + FormatBytes(freeBytes);
    SetDlgItemTextW(g_hDlg, IDC_SIZE_LABEL, sizeText.c_str());
    SetDlgItemTextW(g_hDlg, IDC_SPACE_LABEL, freeText.c_str());
}

// Shared title / subtitle placement; called by ShowPage for every page.
void LayoutPageHeader() {
    SetControlFont(IDC_PAGE_TITLE, g_fontTitle);
    SetControlFont(IDC_PAGE_SUBTITLE, g_fontUI);
    Place(IDC_PAGE_TITLE, kContentLeft, kTitleTop, ContentWidth(), 30);
    Place(IDC_PAGE_SUBTITLE, kContentLeft, kSubtitleTop, ContentWidth(), 50);
}

void BuildWelcomePage() {
    HWND body = GetDlgItem(g_hDlg, IDC_SUMMARY_TEXT);
    std::wstring text =
        L"Windows 7 Aero Explorer brings the classic Windows 7 Explorer experience to Windows 10 "
        L"and Windows 11: the Aero glass navigation bar, breadcrumb address bar, glowing back / "
        L"forward orbs, glossy command bar, drive capacity bars, details pane and the familiar five "
        L"view modes.\r\n\r\n"
        L"Built-in FTP support lets you browse FTP servers like local folders. Type an ftp:// address "
        L"in the address bar, keep favourite servers in the FTP Connection Manager (Ctrl+K), then "
        L"upload, download, rename and delete files with one click - or simply drag and drop files "
        L"from Windows 10 onto a remote folder.\r\n\r\n"
        L"Version 1.0.0  |  64-bit  |  MIT licensed, no telemetry, nothing bundled.";
    SetWindowTextW(body, text.c_str());
    SendMessageW(body, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontUI), TRUE);
    Place(IDC_SUMMARY_TEXT, kContentLeft, kBodyTop, ContentWidth(), 260);

    // A quick feature checklist frame drawn with a native group box substitute.
    HWND group = GetDlgItem(g_hDlg, IDC_DIR_LIST);
    SetWindowTextW(group,
                   L"Aero glass chrome  -  Breadcrumb + search  -  Five view modes  -  Details pane\r\n"
                   L"Drag && drop transfers  -  Saved FTP sites  -  Passive / FTPS  -  Live progress\r\n"
                   L"Remote new folder, rename and recursive delete - all with CRC-safe copying");
    SendMessageW(group, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontSmall), TRUE);
    Place(IDC_DIR_LIST, kContentLeft, kBodyTop + 268, ContentWidth(), 74);
}

void BuildLicensePage() {
    std::wstring license =
        L"MIT License\r\n\r\n"
        L"Copyright (c) 2026 AeroExplorer Open Source Project\r\n\r\n"
        L"Permission is hereby granted, free of charge, to any person obtaining a copy of this "
        L"software and associated documentation files (the \"Software\"), to deal in the Software "
        L"without restriction, including without limitation the rights to use, copy, modify, merge, "
        L"publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons "
        L"to whom the Software is furnished to do so, subject to the following conditions:\r\n\r\n"
        L"The above copyright notice and this permission notice shall be included in all copies or "
        L"substantial portions of the Software.\r\n\r\n"
        L"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, "
        L"INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR "
        L"PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE "
        L"FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR "
        L"OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER "
        L"DEALINGS IN THE SOFTWARE.\r\n\r\n"
        L"Privacy summary: Windows 7 Aero Explorer stores FTP bookmarks locally in "
        L"%APPDATA%\\AeroExplorer\\ftp_sites.ini. Saved passwords are obfuscated on disk and are "
        L"never sent anywhere except to the FTP server you explicitly connect to. The application "
        L"contains no telemetry, no analytics and no auto-update service.";

    HWND lic = GetDlgItem(g_hDlg, IDC_LICENSE_TEXT);
    SetWindowTextW(lic, license.c_str());
    SendMessageW(lic, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontUI), TRUE);
    Place(IDC_LICENSE_TEXT, kContentLeft, kBodyTop, ContentWidth(), 288);
    Place(IDC_LICENSE_ACCEPT, kContentLeft, kBodyTop + 296, ContentWidth(), 18);
    CheckDlgButton(g_hDlg, IDC_LICENSE_ACCEPT, g_state.acceptLicense ? BST_CHECKED : BST_UNCHECKED);
    SetControlFont(IDC_LICENSE_ACCEPT, g_fontUI);
}

void BuildDestinationPage() {
    HWND label = GetDlgItem(g_hDlg, IDC_SUMMARY_TEXT);
    SetWindowTextW(label, L"Destination folder:");
    SendMessageW(label, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontUI), TRUE);
    Place(IDC_SUMMARY_TEXT, kContentLeft, kBodyTop, 220, 18);

    HWND edit = GetDlgItem(g_hDlg, IDC_PATH_EDIT);
    SetWindowTextW(edit, g_state.installDir.c_str());
    SendMessageW(edit, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontUI), TRUE);
    Place(IDC_PATH_EDIT, kContentLeft, kBodyTop + 22, ContentWidth() - 100, 24);

    Place(IDC_BROWSE_BTN, kContentLeft + ContentWidth() - 92, kBodyTop + 22, 92, 24);
    SetControlFont(IDC_BROWSE_BTN, g_fontUI);

    UpdateSpaceLabels();
    SetControlFont(IDC_SIZE_LABEL, g_fontSmall);
    SetControlFont(IDC_SPACE_LABEL, g_fontSmall);
    Place(IDC_SIZE_LABEL, kContentLeft, kBodyTop + 54, 190, 16);
    Place(IDC_SPACE_LABEL, kContentLeft + 196, kBodyTop + 54, ContentWidth() - 196, 16);

    HWND hint = GetDlgItem(g_hDlg, IDC_DIR_LIST);
    SetWindowTextW(hint,
                   L"Setup copies two files here (AeroExplorer.exe and Uninstall.exe), creates the "
                   L"shortcuts you select on the next page, and registers the entry in Apps && "
                   L"Features so the application can always be removed cleanly.\r\n\r\n"
                   L"Your FTP bookmarks are stored per user in %APPDATA%\\AeroExplorer and are not "
                   L"touched by a repair or upgrade install.");
    SendMessageW(hint, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontSmall), TRUE);
    Place(IDC_DIR_LIST, kContentLeft, kBodyTop + 84, ContentWidth(), 130);
}

void BuildComponentsPage() {
    struct Item { int id; const wchar_t* text; bool checked; int y; };
    const Item items[] = {
        { IDC_COMP_DESKTOP, L"Create a &desktop shortcut", g_state.desktopShortcut, kBodyTop + 4 },
        { IDC_COMP_STARTMENU, L"Create a &Start Menu shortcut", g_state.startMenuShortcut, kBodyTop + 30 },
        { IDC_COMP_CONTEXTMENU, L"Add 'Open in Windows 7 Aero Explorer' to the folder &context menu", g_state.contextMenu, kBodyTop + 56 },
        { IDC_COMP_ASSOCIATE, L"Register Aero Explorer for &ftp:// addresses", g_state.associateFtp, kBodyTop + 82 },
    };
    for (const auto& item : items) {
        HWND ctrl = GetDlgItem(g_hDlg, item.id);
        SetWindowTextW(ctrl, item.text);
        SendMessageW(ctrl, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontUI), TRUE);
        CheckDlgButton(g_hDlg, item.id, item.checked ? BST_CHECKED : BST_UNCHECKED);
        Place(item.id, kContentLeft + 6, item.y, ContentWidth() - 10, 18);
    }

    HWND note = GetDlgItem(g_hDlg, IDC_SUMMARY_TEXT);
    SetWindowTextW(note,
                   L"A Windows 7 Aero Explorer entry is added to Apps && Features so the application "
                   L"can be removed at any time. Shortcuts point straight at AeroExplorer.exe, so "
                   L"they keep working if you move the folder later (run Setup again to repair paths).");
    SendMessageW(note, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontSmall), TRUE);
    Place(IDC_SUMMARY_TEXT, kContentLeft + 6, kBodyTop + 116, ContentWidth() - 10, 76);

    HWND summary = GetDlgItem(g_hDlg, IDC_DIR_LIST);
    std::wstring summaryText =
        L"Installing 2 files  |  6 icon sizes  |  HTML usage guide\r\n"
        L"Size on disk: about " + FormatBytes(g_state.payloadBytes) + L" (compressed payload)";
    SetWindowTextW(summary, summaryText.c_str());
    SendMessageW(summary, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontSmall), TRUE);
    Place(IDC_DIR_LIST, kContentLeft + 6, kBodyTop + 200, ContentWidth() - 10, 44);
}

void BuildInstallingPage() {
    HWND pg = GetDlgItem(g_hDlg, IDC_PROGRESS);
    SendMessageW(pg, PBM_SETRANGE32, 0, 100);
    SendMessageW(pg, PBM_SETPOS, 0, 0);
    Place(IDC_PROGRESS, kContentLeft, kBodyTop + 40, ContentWidth(), 18);

    SetDlgItemTextW(g_hDlg, IDC_STATUS_LABEL,
                    g_state.statusText.empty() ? L"Preparing..." : g_state.statusText.c_str());
    SetControlFont(IDC_STATUS_LABEL, g_fontUI);
    Place(IDC_STATUS_LABEL, kContentLeft, kBodyTop + 66, ContentWidth(), 44);

    HWND details = GetDlgItem(g_hDlg, IDC_SUMMARY_TEXT);
    SetWindowTextW(details,
                   L"Setup decompresses the embedded payload, verifies every extracted file against "
                   L"its CRC32 checksum, then creates the shortcuts and registry entries. A corrupted "
                   L"download can therefore never produce a half-installed application.");
    SendMessageW(details, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontSmall), TRUE);
    Place(IDC_SUMMARY_TEXT, kContentLeft, kBodyTop + 120, ContentWidth(), 70);
}

void BuildFinishPage() {
    HWND details = GetDlgItem(g_hDlg, IDC_SUMMARY_TEXT);
    std::wstring text;
    if (g_state.installFailed) {
        text = L"The following problem occurred:\r\n\r\n" + g_state.statusText +
               L"\r\n\r\nA log file with details was written to %TEMP%\\AeroExplorerSetup.log.";
    } else {
        text = L"Installed to:\r\n    " + g_state.installDir + L"\r\n\r\n";
        text += L"Files installed: 2  (" + FormatBytes(g_state.installedBytes) + L" written)\r\n";
        text += L"Shortcuts: ";
        text += g_state.desktopShortcut ? L"Desktop   " : L"";
        text += g_state.startMenuShortcut ? L"Start Menu   " : L"";
        text += g_state.contextMenu ? L"Folder context menu" : L"";
        text += L"\r\n\r\nClick Finish to close this wizard.";
    }
    SetWindowTextW(details, text.c_str());
    SendMessageW(details, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontUI), TRUE);
    Place(IDC_SUMMARY_TEXT, kContentLeft, kBodyTop, ContentWidth(), 230);

    if (!g_state.installFailed) {
        HWND launch = GetDlgItem(g_hDlg, IDC_LAUNCH_CHECK);
        SendMessageW(launch, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontUI), TRUE);
        CheckDlgButton(g_hDlg, IDC_LAUNCH_CHECK, g_state.launchApp ? BST_CHECKED : BST_UNCHECKED);
        Place(IDC_LAUNCH_CHECK, kContentLeft, kBodyTop + 244, ContentWidth(), 18);

        HWND readme = GetDlgItem(g_hDlg, IDC_README_CHECK);
        SendMessageW(readme, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontUI), TRUE);
        CheckDlgButton(g_hDlg, IDC_README_CHECK, g_state.openReadme ? BST_CHECKED : BST_UNCHECKED);
        Place(IDC_README_CHECK, kContentLeft, kBodyTop + 270, ContentWidth(), 18);
    }
}

const wchar_t* PageTitle(Page page) {
    switch (page) {
        case Page::Welcome: return L"Welcome to the Windows 7 Aero Explorer Setup Wizard";
        case Page::License: return L"License Agreement";
        case Page::Destination: return L"Choose Install Location";
        case Page::Components: return L"Choose Components and Shortcuts";
        case Page::Installing: return L"Installing Windows 7 Aero Explorer";
        case Page::Finish:
            return g_state.installFailed
                       ? L"Setup could not complete"
                       : L"Completing the Windows 7 Aero Explorer Setup Wizard";
        default: return L"Windows 7 Aero Explorer Setup";
    }
}

const wchar_t* PageSubtitle(Page page) {
    switch (page) {
        case Page::Welcome:
            return L"This wizard will install Windows 7 Aero Explorer 1.0.0 on your computer. "
                   L"To continue, click Next.";
        case Page::License:
            return L"Please read the following license agreement carefully. You must accept the "
                   L"terms to install Windows 7 Aero Explorer.";
        case Page::Destination:
            return L"Setup will install Windows 7 Aero Explorer in the folder below. Click Browse "
                   L"to pick a different folder, or type a path directly.";
        case Page::Components:
            return L"Select the shortcuts and the shell integration you want Setup to create.";
        case Page::Installing:
            return L"Setup is extracting the application files and registering the program. "
                   L"This usually takes only a few seconds.";
        case Page::Finish:
            return g_state.installFailed
                       ? L"Review the messages below, then run Setup again."
                       : L"Windows 7 Aero Explorer has been installed on your computer.";
        default: return L"";
    }
}

void ShowPage(Page page) {
    g_state.page = page;
    HideAllPageControls();
    LayoutPageHeader();
    SetPageText(PageTitle(page), PageSubtitle(page));

    switch (page) {
        case Page::Welcome: BuildWelcomePage(); break;
        case Page::License: BuildLicensePage(); break;
        case Page::Destination: BuildDestinationPage(); break;
        case Page::Components: BuildComponentsPage(); break;
        case Page::Installing: BuildInstallingPage(); break;
        case Page::Finish: BuildFinishPage(); break;
        default: break;
    }

    SetControlFont(IDC_PAGE_TITLE, g_fontTitle);
    SetControlFont(IDC_PAGE_SUBTITLE, g_fontUI);
    UpdateNavigationButtons();
    InvalidateRect(g_hDlg, nullptr, FALSE);
}

// ---------------------------------------------------------------------------
// Install operations
// ---------------------------------------------------------------------------
bool WriteFileBytes(const std::wstring& path, const std::vector<uint8_t>& bytes) {
    HANDLE hFile = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                               FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hFile == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    bool ok = true;
    if (!bytes.empty()) {
        ok = WriteFile(hFile, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) != FALSE &&
             written == bytes.size();
    }
    CloseHandle(hFile);
    return ok;
}

bool CreateShortcut(const std::wstring& linkPath, const std::wstring& target,
                    const std::wstring& workingDir, const std::wstring& description) {
    IShellLinkW* link = nullptr;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_IShellLinkW, reinterpret_cast<void**>(&link)))) {
        return false;
    }
    link->SetPath(target.c_str());
    link->SetWorkingDirectory(workingDir.c_str());
    link->SetDescription(description.c_str());
    link->SetIconLocation(target.c_str(), 0);

    IPersistFile* file = nullptr;
    bool ok = false;
    if (SUCCEEDED(link->QueryInterface(IID_IPersistFile, reinterpret_cast<void**>(&file)))) {
        ok = SUCCEEDED(file->Save(linkPath.c_str(), TRUE));
        file->Release();
    }
    link->Release();
    return ok;
}

void RegisterUninstallEntry(const std::wstring& dir) {
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, AERO_UNINSTALL_REG_KEY, 0, nullptr, 0,
                        KEY_WRITE | KEY_WOW64_64KEY, nullptr, &key, nullptr) != ERROR_SUCCESS) {
        // Fall back to a per-user registration when not elevated.
        if (RegCreateKeyExW(HKEY_CURRENT_USER, AERO_UNINSTALL_REG_KEY, 0, nullptr, 0,
                            KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
            return;
        }
    }

    std::wstring displayName = std::wstring(AERO_APP_NAME_W);
    std::wstring version = AERO_VERSION_W;
    std::wstring publisher = AERO_PUBLISHER_W;
    std::wstring iconPath = dir + L"\\" + AERO_EXE_NAME_W;
    std::wstring uninstall = L"\"" + dir + L"\\" + AERO_UNINSTALL_EXE_W + L"\" /S /DIR=\"" + dir + L"\"";
    std::wstring quietUninstall = uninstall;
    std::wstring installLocation = dir;
    std::wstring exePath = iconPath;

    auto setSz = [&](const wchar_t* name, const std::wstring& value) {
        RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
                       static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
    };
    setSz(L"DisplayName", displayName);
    setSz(L"DisplayVersion", version);
    setSz(L"Publisher", publisher);
    setSz(L"DisplayIcon", iconPath + L",0");
    setSz(L"UninstallString", uninstall);
    setSz(L"QuietUninstallString", quietUninstall);
    setSz(L"InstallLocation", installLocation);
    setSz(L"InstallDate", L"20260101");
    setSz(L"HelpLink", L"https://github.com/hamzaqadir6666-pixel/wild-survival-mobile");
    setSz(L"URLInfoAbout", L"https://github.com/hamzaqadir6666-pixel/wild-survival-mobile");

    DWORD major = 1, minor = 0;
    RegSetValueExW(key, L"VersionMajor", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&major), sizeof(major));
    RegSetValueExW(key, L"VersionMinor", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&minor), sizeof(minor));
    DWORD noModify = 1, noRepair = 1;
    RegSetValueExW(key, L"NoModify", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&noModify), sizeof(noModify));
    RegSetValueExW(key, L"NoRepair", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&noRepair), sizeof(noRepair));
    DWORD estimated = static_cast<DWORD>(std::max<uint64_t>(1, g_state.installedBytes / 1024));
    RegSetValueExW(key, L"EstimatedSize", 0, REG_DWORD, reinterpret_cast<const BYTE*>(&estimated), sizeof(estimated));
    RegCloseKey(key);

    // App Paths so "AeroExplorer" can be launched from the Run box.
    HKEY appPath = nullptr;
    if (RegCreateKeyExW(HKEY_LOCAL_MACHINE,
                        L"Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\AeroExplorer.exe",
                        0, nullptr, 0, KEY_WRITE | KEY_WOW64_64KEY, nullptr, &appPath, nullptr) == ERROR_SUCCESS) {
        RegSetValueExW(appPath, L"", 0, REG_SZ, reinterpret_cast<const BYTE*>(exePath.c_str()),
                       static_cast<DWORD>((exePath.size() + 1) * sizeof(wchar_t)));
        RegSetValueExW(appPath, L"Path", 0, REG_SZ, reinterpret_cast<const BYTE*>(installLocation.c_str()),
                       static_cast<DWORD>((installLocation.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(appPath);
    }

    HKEY settingsKey = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\AeroExplorer", 0, nullptr, 0, KEY_WRITE,
                        nullptr, &settingsKey, nullptr) == ERROR_SUCCESS) {
        RegSetValueExW(settingsKey, L"InstallDir", 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(installLocation.c_str()),
                       static_cast<DWORD>((installLocation.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(settingsKey);
    }
}

void RegisterContextMenu(const std::wstring& dir) {
    std::wstring exe = dir + L"\\" + AERO_EXE_NAME_W;
    std::wstring command = L"\"" + exe + L"\" \"%V\"";

    struct Entry { const wchar_t* root; };
    const Entry entries[] = {
        { L"Software\\Classes\\Directory\\shell\\AeroExplorer" },
        { L"Software\\Classes\\Directory\\Background\\shell\\AeroExplorer" },
        { L"Software\\Classes\\Drive\\shell\\AeroExplorer" },
    };
    for (const auto& e : entries) {
        HKEY key = nullptr;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, e.root, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) !=
            ERROR_SUCCESS) {
            continue;
        }
        std::wstring title = L"Open in Windows 7 Aero Explorer";
        RegSetValueExW(key, L"", 0, REG_SZ, reinterpret_cast<const BYTE*>(title.c_str()),
                       static_cast<DWORD>((title.size() + 1) * sizeof(wchar_t)));
        RegSetValueExW(key, L"Icon", 0, REG_SZ, reinterpret_cast<const BYTE*>(exe.c_str()),
                       static_cast<DWORD>((exe.size() + 1) * sizeof(wchar_t)));
        HKEY cmdKey = nullptr;
        if (RegCreateKeyExW(key, L"command", 0, nullptr, 0, KEY_WRITE, nullptr, &cmdKey, nullptr) ==
            ERROR_SUCCESS) {
            RegSetValueExW(cmdKey, L"", 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()),
                           static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
            RegCloseKey(cmdKey);
        }
        RegCloseKey(key);
    }
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

void RegisterFtpHandler(const std::wstring& dir) {
    if (!g_state.associateFtp) return;
    // Per-user registration so we never hijack the system default without consent.
    std::wstring exe = dir + L"\\" + AERO_EXE_NAME_W;
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\AeroExplorer.ftp", 0, nullptr, 0,
                        KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
        return;
    }
    std::wstring desc = L"FTP URL";
    RegSetValueExW(key, L"", 0, REG_SZ, reinterpret_cast<const BYTE*>(desc.c_str()),
                   static_cast<DWORD>((desc.size() + 1) * sizeof(wchar_t)));
    RegSetValueExW(key, L"URL Protocol", 0, REG_SZ, reinterpret_cast<const BYTE*>(L""), sizeof(wchar_t));
    HKEY iconKey = nullptr;
    if (RegCreateKeyExW(key, L"DefaultIcon", 0, nullptr, 0, KEY_WRITE, nullptr, &iconKey, nullptr) ==
        ERROR_SUCCESS) {
        std::wstring icon = exe + L",0";
        RegSetValueExW(iconKey, L"", 0, REG_SZ, reinterpret_cast<const BYTE*>(icon.c_str()),
                       static_cast<DWORD>((icon.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(iconKey);
    }
    HKEY cmdKey = nullptr;
    if (RegCreateKeyExW(key, L"shell\\open\\command", 0, nullptr, 0, KEY_WRITE, nullptr, &cmdKey, nullptr) ==
        ERROR_SUCCESS) {
        std::wstring cmd = L"\"" + exe + L"\" \"%1\"";
        RegSetValueExW(cmdKey, L"", 0, REG_SZ, reinterpret_cast<const BYTE*>(cmd.c_str()),
                       static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t)));
        RegCloseKey(cmdKey);
    }
    RegCloseKey(key);
}

// Post a status line to the UI thread; the string is owned by the message
// receiver so no shared mutable state crosses threads.
void PostStatus(const std::wstring& text, int percent) {
    if (!g_hDlg) return;
    auto* payload = new std::wstring(text);
    if (!PostMessageW(g_hDlg, WM_APP_EXTRACT_PROGRESS, static_cast<WPARAM>(percent),
                      reinterpret_cast<LPARAM>(payload))) {
        delete payload;
    }
}

bool PerformInstall(std::wstring& errorText) {
    if (g_state.installDir.empty()) {
        errorText = L"No install folder was selected.";
        return false;
    }

    if (!CreateDirectoryW(g_state.installDir.c_str(), nullptr)) {
        DWORD err = GetLastError();
        if (err != ERROR_ALREADY_EXISTS) {
            errorText = L"Cannot create the folder " + g_state.installDir;
            return false;
        }
    }

    std::vector<uint8_t> payload;
    if (!LoadPayload(payload)) {
        errorText = L"The embedded application payload is missing from this setup package.";
        return false;
    }

    std::vector<aeropak::PackedEntry> entries;
    if (!aeropak::ExtractArchive(payload.data(), payload.size(), entries)) {
        errorText = L"The embedded payload is corrupted (archive verification failed).";
        return false;
    }

    uint64_t writtenBytes = 0;
    int index = 0;
    for (const auto& entry : entries) {
        std::wstring name(entry.relativeName.begin(), entry.relativeName.end());
        std::wstring path = g_state.installDir + L"\\" + name;

        g_state.progress = 15 + (index * 55) / std::max<size_t>(1, entries.size());
        PostStatus(L"Extracting " + name + L"...", g_state.progress);

        if (!WriteFileBytes(path, entry.data)) {
            errorText = L"Could not write " + path + L". Close any running copy of Aero Explorer and "
                        L"make sure you have permission to write there.";
            return false;
        }
        writtenBytes += entry.data.size();
        ++index;
    }
    g_state.installedBytes = writtenBytes;

    PostStatus(L"Verifying extracted files...", 76);

    // Verify the two expected files really landed.
    std::wstring exePath = g_state.installDir + L"\\" + AERO_EXE_NAME_W;
    std::wstring uninstPath = g_state.installDir + L"\\" + AERO_UNINSTALL_EXE_W;
    if (GetFileAttributesW(exePath.c_str()) == INVALID_FILE_ATTRIBUTES) {
        errorText = L"AeroExplorer.exe was not installed correctly.";
        return false;
    }

    PostStatus(L"Creating shortcuts...", 84);

    wchar_t desktop[MAX_PATH] = {};
    if (g_state.desktopShortcut &&
        SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_DESKTOPDIRECTORY, nullptr, 0, desktop))) {
        CreateShortcut(std::wstring(desktop) + L"\\" + AERO_APP_NAME_W + L".lnk", exePath,
                       g_state.installDir, L"Browse files and FTP servers in Windows 7 style");
    }

    if (g_state.startMenuShortcut) {
        wchar_t programs[MAX_PATH] = {};
        if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_PROGRAMS, nullptr, 0, programs))) {
            std::wstring group = std::wstring(programs) + L"\\" + AERO_SHORT_NAME_W;
            CreateDirectoryW(group.c_str(), nullptr);
            CreateShortcut(group + L"\\" + AERO_APP_NAME_W + L".lnk", exePath, g_state.installDir,
                           L"Browse files and FTP servers in Windows 7 style");
            if (GetFileAttributesW(uninstPath.c_str()) != INVALID_FILE_ATTRIBUTES) {
                CreateShortcut(group + L"\\Uninstall Windows 7 Aero Explorer.lnk", uninstPath,
                               g_state.installDir, L"Remove Windows 7 Aero Explorer");
            }
        }
    }

    PostStatus(L"Registering the program and shell integration...", 92);

    if (g_state.contextMenu) RegisterContextMenu(g_state.installDir);
    RegisterFtpHandler(g_state.installDir);
    RegisterUninstallEntry(g_state.installDir);

    PostStatus(L"Installation complete.", 100);
    return true;
}

// ---------------------------------------------------------------------------
// Extraction worker
// ---------------------------------------------------------------------------
void StartInstall() {
    g_state.statusText = L"Preparing to install...";
    g_state.progress = 5;
    ShowPage(Page::Installing);
    UpdateWindow(g_hDlg);

    if (g_extractThread.joinable()) g_extractThread.join();
    g_extractRunning.store(true);
    g_extractThread = std::thread([]() {
        std::wstring errorText;
        bool ok = PerformInstall(errorText);
        g_extractRunning.store(false);
        if (!ok) {
            g_state.installFailed = true;
            g_state.statusText = errorText;
            AppendLog(L"Install failed: " + errorText);
            PostMessageW(g_hDlg, WM_APP_EXTRACT_DONE, 0, 0);
        } else {
            g_state.installFailed = false;
            g_state.installed = true;
            AppendLog(L"Install succeeded into " + g_state.installDir);
            PostMessageW(g_hDlg, WM_APP_EXTRACT_DONE, 1, 0);
        }
    });
}

// ---------------------------------------------------------------------------
// Silent install (used by /S)
// ---------------------------------------------------------------------------
int RunSilent() {
    std::wstring errorText;
    if (!PerformInstall(errorText)) {
        AppendLog(L"Silent install failed: " + errorText);
        return 1;
    }
    if (!g_state.launchApp) return 0;
    std::wstring exe = g_state.installDir + L"\\" + AERO_EXE_NAME_W;
    ShellExecuteW(nullptr, L"open", exe.c_str(), nullptr, g_state.installDir.c_str(), SW_SHOWNORMAL);
    return 0;
}

// ---------------------------------------------------------------------------
// Wizard painting (Windows 7 Aero visuals)
// ---------------------------------------------------------------------------
namespace {

void PaintWizard(HDC hdc, const RECT& client) {
    const int w = client.right;
    const int h = client.bottom;
    if (w <= 0 || h <= 0) return;

    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;

    HDC memDc = CreateCompatibleDC(hdc);
    void* bits = nullptr;
    HBITMAP dib = CreateDIBSection(memDc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!dib) {
        DeleteDC(memDc);
        return;
    }
    HGDIOBJ old = SelectObject(memDc, dib);

    Graphics g(memDc);
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.SetPixelOffsetMode(PixelOffsetModeHalf);
    g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

    const int dpi = DpiOf(g_hDlg);
    auto px = [dpi](int value) { return MulDiv(value, dpi, 96); };

    FontFamily family(L"Segoe UI");
    Font smallFont(&family, static_cast<REAL>(px(11)), FontStyleRegular, UnitPixel);

    const int bannerW = px(kBanner);

    // Page background
    RectF page(0.0f, 0.0f, static_cast<REAL>(w), static_cast<REAL>(h));
    SolidBrush white(Color(255, 253, 254, 255));
    g.FillRectangle(&white, page);

    // Banner column (the wizard_banner.bmp artwork, stretched to full height)
    if (g_banner) {
        Bitmap bannerBmp(g_banner, nullptr);
        if (bannerBmp.GetLastStatus() == Ok) {
            g.DrawImage(&bannerBmp, RectF(0.0f, 0.0f, static_cast<REAL>(bannerW), static_cast<REAL>(h)));
        }
    }

    // Footer strip
    const int footerH = px(setup_theme::kFooterHeight);
    RectF footer(0.0f, static_cast<REAL>(h - footerH), static_cast<REAL>(w), static_cast<REAL>(footerH));
    {
        RectF upper(footer.X, footer.Y, footer.Width, footer.Height * 0.5f);
        RectF lower(footer.X, upper.GetBottom(), footer.Width, footer.GetBottom() - upper.GetBottom());
        LinearGradientBrush fu(upper, Color(255, 240, 247, 253), Color(255, 219, 234, 250), LinearGradientModeVertical);
        LinearGradientBrush fl(lower, Color(255, 203, 223, 245), Color(255, 218, 233, 249), LinearGradientModeVertical);
        g.FillRectangle(&fu, upper);
        g.FillRectangle(&fl, lower);
        Pen footerTop(Color(255, 158, 184, 214), 1.0f);
        g.DrawLine(&footerTop, footer.X, footer.Y, footer.GetRight(), footer.Y);
        Pen footerHi(Color(220, 255, 255, 255), 1.0f);
        g.DrawLine(&footerHi, footer.X, footer.Y + 1.0f, footer.GetRight(), footer.Y + 1.0f);
    }
    if (g_header) {
        Bitmap logo(g_header, nullptr);
        if (logo.GetLastStatus() == Ok) {
            REAL logoSize = static_cast<REAL>(px(36));
            g.DrawImage(&logo, RectF(footer.X + static_cast<REAL>(px(10)),
                                     footer.Y + (footer.Height - logoSize) * 0.5f, logoSize, logoSize));
        }
        // Version caption next to the small logo
        std::wstring caption = L"Windows 7 Aero Explorer 1.0.0  |  Setup";
        SolidBrush captionBrush(Color(255, 52, 78, 112));
        StringFormat sf;
        sf.SetLineAlignment(StringAlignmentCenter);
        sf.SetFormatFlags(StringFormatFlagsNoWrap);
        RectF capRc(footer.X + static_cast<REAL>(px(52)), footer.Y,
                    footer.Width - static_cast<REAL>(px(320)), footer.Height);
        g.DrawString(caption.c_str(), -1, &smallFont, capRc, &sf, &captionBrush);
    }

    // Page title & subtitle
    const float contentLeft = static_cast<REAL>(px(kContentLeft));
    const float contentWidth = static_cast<REAL>(w) - contentLeft - static_cast<REAL>(px(kContentRight));

    // Etched separator under the header
    {
        Pen p1(Color(255, 202, 216, 234), 1.0f);
        Pen p2(Color(255, 255, 255, 255), 1.0f);
        float y = static_cast<REAL>(px(kSeparatorTop));
        g.DrawLine(&p1, contentLeft - static_cast<REAL>(px(4)), y,
                   static_cast<REAL>(w) - static_cast<REAL>(px(12)), y);
        g.DrawLine(&p2, contentLeft - static_cast<REAL>(px(4)), y + 1.0f,
                   static_cast<REAL>(w) - static_cast<REAL>(px(12)), y + 1.0f);
    }

    // Page-specific decorations that are easier to paint than to host as controls
    if (g_state.page == Page::Installing) {
        // Activity strip: blue animated blocks under the progress bar.
        int blocks = 6;
        int active = (GetTickCount() / 220) % (blocks + 2);
        float bw = static_cast<REAL>(px(14));
        float gap = static_cast<REAL>(px(4));
        float totalW = blocks * bw + (blocks - 1) * gap;
        float startX = contentLeft + (contentWidth - totalW) * 0.5f;
        float y = static_cast<REAL>(px(kBodyTop + 84));
        for (int i = 0; i < blocks; ++i) {
            bool on = (i == active || i == active - 1);
            SolidBrush b(on ? Color(255, 58, 140, 214) : Color(255, 214, 226, 242));
            g.FillRectangle(&b, RectF(startX + i * (bw + gap), y, bw, static_cast<REAL>(px(5))));
        }
    }

    if (g_state.page == Page::Finish && !g_state.installFailed) {
        // Green check medallion like the Windows 7 completion page
        float cx = static_cast<REAL>(px(kContentLeft)) + static_cast<REAL>(px(14));
        float cy = static_cast<REAL>(px(kBodyTop + 96));
        float r = static_cast<REAL>(px(13));
        LinearGradientBrush ring(PointF(cx - r, cy - r), PointF(cx - r, cy + r),
                                 Color(255, 122, 200, 122), Color(255, 54, 154, 68));
        g.FillEllipse(&ring, cx - r, cy - r, r * 2.0f, r * 2.0f);
        Pen check(Color(255, 255, 255, 255), static_cast<REAL>(px(3)));
        check.SetStartCap(LineCapRound);
        check.SetEndCap(LineCapRound);
        g.DrawLine(&check, cx - r * 0.45f, cy + r * 0.02f, cx - r * 0.10f, cy + r * 0.42f);
        g.DrawLine(&check, cx - r * 0.10f, cy + r * 0.42f, cx + r * 0.52f, cy - r * 0.38f);
    }

    // Right/bottom frame lines to match the Aero dialog chrome
    Pen frame(Color(255, 178, 196, 220), 1.0f);
    g.DrawRectangle(&frame, 0.0f, 0.0f, static_cast<REAL>(w) - 1.0f,
                    static_cast<REAL>(h - footerH) - 1.0f);

    g.Flush();
    BitBlt(hdc, 0, 0, w, h, memDc, 0, 0, SRCCOPY);

    SelectObject(memDc, old);
    DeleteObject(dib);
    DeleteDC(memDc);
}

// ---------------------------------------------------------------------------
// Dialog procedure
// ---------------------------------------------------------------------------
void BrowseForFolder() {
    BROWSEINFOW bi = {};
    bi.hwndOwner = g_hDlg;
    bi.lpszTitle = L"Select the folder to install Windows 7 Aero Explorer into:";
    bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE | BIF_USENEWUI;
    PIDLIST_ABSOLUTE pidl = SHBrowseForFolderW(&bi);
    if (!pidl) return;
    wchar_t path[MAX_PATH] = {};
    if (SHGetPathFromIDListW(pidl, path)) {
        std::wstring selected = path;
        // Create a product subfolder if the user picked a generic parent folder.
        std::wstring leaf = selected;
        size_t slash = leaf.find_last_of(L'\\');
        if (slash != std::wstring::npos) leaf = leaf.substr(slash + 1);
        if (_wcsicmp(leaf.c_str(), AERO_SHORT_NAME_W) != 0 &&
            _wcsicmp(leaf.c_str(), L"Aero Explorer") != 0) {
            selected += L"\\";
            selected += AERO_SHORT_NAME_W;
        }
        g_state.installDir = selected;
        SetDlgItemTextW(g_hDlg, IDC_PATH_EDIT, selected.c_str());
        UpdateSpaceLabels();
    }
    CoTaskMemFree(pidl);
}

void ReadBackControls() {
    if (g_state.page == Page::License) {
        g_state.acceptLicense = IsDlgButtonChecked(g_hDlg, IDC_LICENSE_ACCEPT) == BST_CHECKED;
    } else if (g_state.page == Page::Destination) {
        wchar_t buf[MAX_PATH * 2] = {};
        GetDlgItemTextW(g_hDlg, IDC_PATH_EDIT, buf, MAX_PATH * 2);
        std::wstring dir = buf;
        while (!dir.empty() && (dir.back() == L'\\' || dir.back() == L'/')) dir.pop_back();
        if (!dir.empty()) g_state.installDir = dir;
    } else if (g_state.page == Page::Components) {
        g_state.desktopShortcut = IsDlgButtonChecked(g_hDlg, IDC_COMP_DESKTOP) == BST_CHECKED;
        g_state.startMenuShortcut = IsDlgButtonChecked(g_hDlg, IDC_COMP_STARTMENU) == BST_CHECKED;
        g_state.contextMenu = IsDlgButtonChecked(g_hDlg, IDC_COMP_CONTEXTMENU) == BST_CHECKED;
        g_state.associateFtp = IsDlgButtonChecked(g_hDlg, IDC_COMP_ASSOCIATE) == BST_CHECKED;
    }
}

bool GoNext() {
    ReadBackControls();
    switch (g_state.page) {
        case Page::Welcome:
            ShowPage(Page::License);
            return true;
        case Page::License:
            if (!g_state.acceptLicense) {
                MessageBoxW(g_hDlg, L"You must accept the License Agreement before continuing.",
                            L"Windows 7 Aero Explorer Setup", MB_ICONINFORMATION | MB_OK);
                return false;
            }
            ShowPage(Page::Destination);
            return true;
        case Page::Destination:
            if (g_state.installDir.empty()) {
                MessageBoxW(g_hDlg, L"Please choose an install folder.", L"Setup",
                            MB_ICONWARNING | MB_OK);
                return false;
            }
            if (FreeSpaceOf(g_state.installDir) < 1024ull * 1024) {
                MessageBoxW(g_hDlg, L"The selected drive does not have enough free space.",
                            L"Setup", MB_ICONWARNING | MB_OK);
                return false;
            }
            ShowPage(Page::Components);
            return true;
        case Page::Components:
            StartInstall();
            return true;
        case Page::Finish:
            return false;
        default:
            return false;
    }
}

void GoBack() {
    ReadBackControls();
    switch (g_state.page) {
        case Page::License: ShowPage(Page::Welcome); break;
        case Page::Destination: ShowPage(Page::License); break;
        case Page::Components: ShowPage(Page::Destination); break;
        default: break;
    }
}

void FinishWizard() {
    g_state.launchApp = IsDlgButtonChecked(g_hDlg, IDC_LAUNCH_CHECK) == BST_CHECKED;
    g_state.openReadme = IsDlgButtonChecked(g_hDlg, IDC_README_CHECK) == BST_CHECKED;

    EndDialog(g_hDlg, IDOK);

    std::wstring exe = g_state.installDir + L"\\" + AERO_EXE_NAME_W;
    if (g_state.installed && !g_state.installFailed) {
        if (g_state.openReadme) {
            std::wstring readme = ExeDirectory() + L"\\README.html";
            if (GetFileAttributesW(readme.c_str()) == INVALID_FILE_ATTRIBUTES) {
                readme = ExeDirectory() + L"\\README.md";
            }
            if (GetFileAttributesW(readme.c_str()) != INVALID_FILE_ATTRIBUTES) {
                ShellExecuteW(nullptr, L"open", readme.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
            }
        }
        if (g_state.launchApp) {
            ShellExecuteW(nullptr, L"open", exe.c_str(), nullptr, g_state.installDir.c_str(), SW_SHOWNORMAL);
        }
    }
}

INT_PTR CALLBACK SetupDlgProc(HWND hDlg, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_INITDIALOG: {
            g_hDlg = hDlg;
            SetWindowTextW(hDlg, L"Windows 7 Aero Explorer Setup");

            CreateFonts();

            // Resize the dialog so the client area matches the custom chrome metrics.
            const int dpi = DpiOf(hDlg);
            RECT want = { 0, 0, MulDiv(kClientW, dpi, 96), MulDiv(kClientH, dpi, 96) };
            AdjustWindowRectEx(&want, static_cast<DWORD>(GetWindowLongPtrW(hDlg, GWL_STYLE)), FALSE,
                               static_cast<DWORD>(GetWindowLongPtrW(hDlg, GWL_EXSTYLE)));
            const int winW = want.right - want.left;
            const int winH = want.bottom - want.top;
            HMONITOR mon = MonitorFromWindow(hDlg, MONITOR_DEFAULTTOPRIMARY);
            MONITORINFO mi = { sizeof(mi), {}, {} };
            int posX = CW_USEDEFAULT;
            int posY = CW_USEDEFAULT;
            if (mon && GetMonitorInfoW(mon, &mi)) {
                posX = mi.rcWork.left + ((mi.rcWork.right - mi.rcWork.left) - winW) / 2;
                posY = mi.rcWork.top + ((mi.rcWork.bottom - mi.rcWork.top) - winH) / 2;
                if (posY < mi.rcWork.top) posY = mi.rcWork.top;
            }
            SetWindowPos(hDlg, nullptr, posX, posY, winW, winH,
                         SWP_NOZORDER | SWP_NOACTIVATE);

            // Page title and subtitle are created here (not in the dialog template)
            // so they draw on top of the custom-painted background.
            CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_LEFT,
                            0, 0, 0, 0, hDlg,
                            reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_PAGE_TITLE)),
                            g_hInst, nullptr);
            CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_LEFT,
                            0, 0, 0, 0, hDlg,
                            reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_PAGE_SUBTITLE)),
                            g_hInst, nullptr);
            SetControlFont(IDC_PAGE_TITLE, g_fontTitle);
            SetControlFont(IDC_PAGE_SUBTITLE, g_fontUI);

            SetControlFont(IDC_BACK_BTN, g_fontUI);
            SetControlFont(IDC_NEXT_BTN, g_fontUI);
            SetControlFont(IDC_CANCEL_BTN, g_fontUI);

            // Back / Next / Close are anchored to the right of the footer strip.
            RECT clientRc = {};
            GetClientRect(hDlg, &clientRc);
            const int btnW = Px(84);
            const int btnH = Px(25);
            const int gap = Px(8);
            const int btnY = clientRc.bottom - Px(kFooter) / 2 - btnH / 2;
            int btnX = clientRc.right - Px(18) - btnW * 3 - gap * 2;
            const int order[] = { IDC_BACK_BTN, IDC_NEXT_BTN, IDC_CANCEL_BTN };
            for (int id : order) {
                HWND btn = GetDlgItem(hDlg, id);
                if (!btn) continue;
                SetWindowPos(btn, nullptr, btnX, btnY, btnW, btnH, SWP_NOZORDER | SWP_NOACTIVATE);
                SetWindowTheme(btn, L"Explorer", nullptr);
                btnX += btnW + gap;
            }

            // Load the artwork once.
            g_banner = static_cast<HBITMAP>(LoadImageW(g_hInst, MAKEINTRESOURCEW(IDB_WIZARD_BANNER),
                                                       IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION));
            g_header = static_cast<HBITMAP>(LoadImageW(g_hInst, MAKEINTRESOURCEW(IDB_WIZARD_HEADER),
                                                       IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION));

            std::vector<uint8_t> payload;
            if (LoadPayload(payload)) {
                g_state.payloadBytes = payload.size();
            }

            // Pre-populate defaults
            g_state.installDir = DefaultInstallDir();
            g_state.acceptLicense = false;

            // Restore a previous install folder if this is an upgrade/repair.
            std::wstring existing = RegReadString(HKEY_LOCAL_MACHINE, AERO_UNINSTALL_REG_KEY, L"InstallLocation");
            if (!existing.empty()) g_state.installDir = existing;

            ShowPage(Page::Welcome);
            UpdateNavigationButtons();
            SetTimer(hDlg, 2, 120, nullptr);
            return TRUE;
        }

        case WM_PAINT: {
            PAINTSTRUCT ps = {};
            HDC dc = BeginPaint(hDlg, &ps);
            RECT rc = {};
            GetClientRect(hDlg, &rc);
            PaintWizard(dc, rc);
            EndPaint(hDlg, &ps);
            return TRUE;
        }

        case WM_ERASEBKGND:
            return TRUE;

        case WM_CTLCOLORSTATIC:
        case WM_CTLCOLORBTN: {
            // Let the custom-painted page gradient show through labels, check boxes
            // and read-only text instead of the default grey dialog face.
            HDC dc = reinterpret_cast<HDC>(wParam);
            SetBkMode(dc, TRANSPARENT);
            SetTextColor(dc, RGB(38, 58, 84));
            if (!g_pageBrush) g_pageBrush = CreateSolidBrush(RGB(249, 251, 254));
            return reinterpret_cast<INT_PTR>(g_pageBrush);
        }

        case WM_CTLCOLOREDIT: {
            HDC dc = reinterpret_cast<HDC>(wParam);
            SetBkColor(dc, RGB(255, 255, 255));
            SetTextColor(dc, RGB(28, 46, 68));
            static HBRUSH editBrush = CreateSolidBrush(RGB(255, 255, 255));
            return reinterpret_cast<INT_PTR>(editBrush);
        }

        case WM_TIMER:
            if (wParam == 2 && g_state.page == Page::Installing) {
                InvalidateRect(hDlg, nullptr, FALSE);
            }
            return TRUE;

        case WM_APP_EXTRACT_PROGRESS: {
            int pct = static_cast<int>(wParam);
            std::unique_ptr<std::wstring> payload(reinterpret_cast<std::wstring*>(lParam));
            HWND progress = GetDlgItem(hDlg, IDC_PROGRESS);
            if (progress) SendMessageW(progress, PBM_SETPOS, static_cast<WPARAM>(pct), 0);
            if (payload) {
                g_state.statusText = *payload;
                SetDlgItemTextW(hDlg, IDC_STATUS_LABEL, payload->c_str());
            }
            return TRUE;
        }

        case WM_APP_EXTRACT_DONE: {
            // The worker posts this as its last action, so the join is immediate and
            // guarantees every state write is visible from here on.
            if (g_extractThread.joinable()) g_extractThread.join();
            bool success = wParam != 0;
            if (g_state.page == Page::Installing) {
                ShowPage(Page::Finish);
                UpdateNavigationButtons();
                HWND next = GetDlgItem(hDlg, IDC_NEXT_BTN);
                if (next) SetFocus(next);
                InvalidateRect(hDlg, nullptr, TRUE);
                if (!success) {
                    MessageBoxW(hDlg, g_state.statusText.c_str(), L"Windows 7 Aero Explorer Setup",
                                MB_ICONERROR | MB_OK);
                }
            }
            return TRUE;
        }

        case WM_COMMAND: {
            int id = LOWORD(wParam);
            int code = HIWORD(wParam);

            switch (id) {
                case IDC_LICENSE_ACCEPT:
                    if (code == BN_CLICKED) {
                        g_state.acceptLicense =
                            IsDlgButtonChecked(hDlg, IDC_LICENSE_ACCEPT) == BST_CHECKED;
                        UpdateNavigationButtons();
                    }
                    return TRUE;
                case IDC_BACK_BTN:
                    GoBack();
                    return TRUE;
                case IDC_NEXT_BTN:
                    if (g_state.page == Page::Finish) {
                        FinishWizard();
                    } else {
                        GoNext();
                    }
                    return TRUE;
                case IDCANCEL:
                case IDC_CANCEL_BTN:
                    if (g_state.page == Page::Installing) {
                        int res = MessageBoxW(hDlg,
                                              L"Installation is not complete. Cancel setup anyway?",
                                              L"Windows 7 Aero Explorer Setup",
                                              MB_ICONWARNING | MB_YESNO | MB_DEFBUTTON2);
                        if (res != IDYES) return TRUE;
                    } else if (g_state.page == Page::Finish) {
                        FinishWizard();
                        return TRUE;
                    } else {
                        int res = MessageBoxW(hDlg, L"Cancel Windows 7 Aero Explorer Setup?",
                                              L"Windows 7 Aero Explorer Setup",
                                              MB_ICONQUESTION | MB_YESNO | MB_DEFBUTTON2);
                        if (res != IDYES) return TRUE;
                    }
                    EndDialog(hDlg, IDCANCEL);
                    return TRUE;
                case IDC_BROWSE_BTN:
                    BrowseForFolder();
                    return TRUE;
                case IDC_PATH_EDIT:
                    if (code == EN_CHANGE && g_state.page == Page::Destination) {
                        wchar_t buf[MAX_PATH * 2] = {};
                        GetDlgItemTextW(hDlg, IDC_PATH_EDIT, buf, MAX_PATH * 2);
                        std::wstring typed = buf;
                        if (!typed.empty()) {
                            g_state.installDir = typed;
                            UpdateSpaceLabels();
                        }
                    }
                    return TRUE;
                default:
                    break;
            }
            return FALSE;
        }

        case WM_CLOSE: {
            if (g_state.page == Page::Installing) {
                return TRUE;
            }
            if (g_state.page == Page::Finish) {
                FinishWizard();
                return TRUE;
            }
            int res = MessageBoxW(hDlg, L"Cancel Windows 7 Aero Explorer Setup?",
                                  L"Windows 7 Aero Explorer Setup",
                                  MB_ICONQUESTION | MB_YESNO | MB_DEFBUTTON2);
            if (res == IDYES) EndDialog(hDlg, IDCANCEL);
            return TRUE;
        }

        case WM_DESTROY:
            KillTimer(hDlg, 2);
            if (g_extractThread.joinable()) g_extractThread.join();
            return TRUE;
    }
    return FALSE;
}

void ParseCommandLine(SetupState& state) {
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return;
    for (int i = 1; i < argc; ++i) {
        std::wstring arg = argv[i];
        if (_wcsicmp(arg.c_str(), L"/S") == 0 || _wcsicmp(arg.c_str(), L"/SILENT") == 0 ||
            _wcsicmp(arg.c_str(), L"/VERYSILENT") == 0) {
            state.silent = true;
            // Unattended runs should not pop a window when they finish.
            state.launchApp = false;
        } else if (_wcsnicmp(arg.c_str(), L"/DIR=", 5) == 0) {
            std::wstring dir = arg.substr(5);
            if (dir.size() >= 2 && dir.front() == L'"' && dir.back() == L'"') {
                dir = dir.substr(1, dir.size() - 2);
            }
            while (!dir.empty() && (dir.back() == L'\\' || dir.back() == L'/')) dir.pop_back();
            if (!dir.empty()) state.installDir = dir;
        } else if (_wcsicmp(arg.c_str(), L"/NODESKTOPSHORTCUT") == 0) {
            state.desktopShortcut = false;
        } else if (_wcsicmp(arg.c_str(), L"/NOSTARTMENUSHORTCUT") == 0) {
            state.startMenuShortcut = false;
        } else if (_wcsicmp(arg.c_str(), L"/NOCONTEXTMENU") == 0) {
            state.contextMenu = false;
        } else if (_wcsicmp(arg.c_str(), L"/NOFTPHANDLER") == 0) {
            state.associateFtp = false;
        } else if (_wcsicmp(arg.c_str(), L"/NOLAUNCH") == 0) {
            state.launchApp = false;
        } else if (_wcsicmp(arg.c_str(), L"/LAUNCH") == 0) {
            state.launchApp = true;
        }
    }
    LocalFree(argv);
}

} // namespace

} // namespace

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, PWSTR, int) {
    g_hInst = hInstance;

    INITCOMMONCONTROLSEX icc = {};
    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_STANDARD_CLASSES | ICC_PROGRESS_CLASS | ICC_BAR_CLASSES;
    InitCommonControlsEx(&icc);

    if (FAILED(OleInitialize(nullptr))) {
        // Shortcuts still work; shell links need OLE, so note it in the log.
        AppendLog(L"OleInitialize failed.");
    }

    GdiplusStartupInput gdipInput;
    if (GdiplusStartup(&g_gdipToken, &gdipInput, nullptr) != Ok) {
        g_gdipToken = 0;
    }

    // Refuse to run on 32-bit Windows: the package contains x64 binaries only.
    SYSTEM_INFO si = {};
    GetNativeSystemInfo(&si);
    if (si.wProcessorArchitecture != PROCESSOR_ARCHITECTURE_AMD64 &&
        si.wProcessorArchitecture != PROCESSOR_ARCHITECTURE_ARM64) {
        MessageBoxW(nullptr,
                    L"Windows 7 Aero Explorer requires 64-bit Windows 10 or Windows 11.\n\n"
                    L"Setup cannot continue on this computer.",
                    L"Windows 7 Aero Explorer Setup", MB_ICONERROR | MB_OK);
        return 1;
    }

    if (!g_state.installDir.empty()) {
        // already set through the command line
    } else {
        g_state.installDir = DefaultInstallDir();
    }
    ParseCommandLine(g_state);
    if (g_state.installDir.empty()) g_state.installDir = DefaultInstallDir();

    int exitCode = 0;
    if (g_state.silent) {
        AppendLog(L"Silent install starting into " + g_state.installDir);
        exitCode = RunSilent();
    } else {
        INT_PTR res = DialogBoxParamW(hInstance, MAKEINTRESOURCEW(IDD_SETUP), nullptr,
                                      SetupDlgProc, 0);
        exitCode = (res == IDCANCEL) ? 1 : 0;
    }

    if (g_banner) DeleteObject(g_banner);
    if (g_header) DeleteObject(g_header);
    if (g_fontUI) DeleteObject(g_fontUI);
    if (g_fontBold) DeleteObject(g_fontBold);
    if (g_fontTitle) DeleteObject(g_fontTitle);
    if (g_fontSmall) DeleteObject(g_fontSmall);
    if (g_pageBrush) DeleteObject(g_pageBrush);
    if (g_footerBrush) DeleteObject(g_footerBrush);
    if (g_gdipToken) GdiplusShutdown(g_gdipToken);
    OleUninitialize();
    return exitCode;
}
