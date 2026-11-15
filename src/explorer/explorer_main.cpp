// Windows 7 Aero Explorer - main window, child controls, layout and message loop.
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0a00
#endif

#include "app.h"

#include "../common/app_ids.h"
#include "aero_theme.h"
#include "dialogs.h"

#include <algorithm>
#include <memory>

using namespace aero;
using namespace Gdiplus;

// ---------------------------------------------------------------------------
// CF_HDROP drop target implementation
// ---------------------------------------------------------------------------
HRESULT AeroDropTarget::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IDropTarget) {
        *ppv = static_cast<IDropTarget*>(this);
        return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
}

HRESULT AeroDropTarget::DragEnter(IDataObject* data, DWORD, POINTL, DWORD* effect) {
    if (!effect) return E_POINTER;
    FORMATETC fmt = { CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
    bool ok = app_ && data && data->QueryGetData(&fmt) == S_OK;
    *effect = ok ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    if (ok && app_) app_->SetDropHighlight(true);
    return S_OK;
}

HRESULT AeroDropTarget::DragOver(DWORD, POINTL, DWORD* effect) {
    if (!effect) return E_POINTER;
    *effect = app_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    return S_OK;
}

HRESULT AeroDropTarget::DragLeave() {
    if (app_) app_->SetDropHighlight(false);
    return S_OK;
}

HRESULT AeroDropTarget::Drop(IDataObject* data, DWORD, POINTL, DWORD* effect) {
    if (!effect) return E_POINTER;
    *effect = DROPEFFECT_NONE;
    if (app_) app_->SetDropHighlight(false);
    if (!data || !app_) return S_OK;

    FORMATETC fmt = { CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
    STGMEDIUM stg = {};
    if (data->GetData(&fmt, &stg) != S_OK) return S_OK;

    std::vector<std::wstring> paths;
    HDROP hDrop = static_cast<HDROP>(GlobalLock(stg.hGlobal));
    if (hDrop) {
        UINT count = DragQueryFileW(hDrop, 0xFFFFFFFF, nullptr, 0);
        for (UINT i = 0; i < count; ++i) {
            UINT len = DragQueryFileW(hDrop, i, nullptr, 0);
            if (len == 0) continue;
            std::wstring buf(static_cast<size_t>(len) + 1, L'\0');
            DragQueryFileW(hDrop, i, &buf[0], len + 1);
            buf.resize(len);
            if (!buf.empty()) paths.push_back(buf);
        }
        GlobalUnlock(stg.hGlobal);
    }
    ReleaseStgMedium(&stg);

    if (!paths.empty()) {
        *effect = DROPEFFECT_COPY;
        app_->HandleDroppedPaths(paths);
    }
    return S_OK;
}

// ---------------------------------------------------------------------------
// Construction / window creation
// ---------------------------------------------------------------------------
ExplorerApp::~ExplorerApp() {
    if (dropSite_) {
        dropSite_->Detach();
        dropSite_->Release();
        dropSite_ = nullptr;
    }
    if (dropTarget_) {
        dropTarget_->Detach();
        delete dropTarget_;
        dropTarget_ = nullptr;
    }
    {
        std::lock_guard<std::mutex> lk(workersMutex_);
        for (auto& th : workers_) {
            if (th.joinable()) th.join();
        }
        workers_.clear();
    }
    if (ftp_) ftp_->Disconnect();

    if (treeImages_) ImageList_Destroy(treeImages_);
    if (treeBgBrush_) DeleteObject(treeBgBrush_);
    if (canvasBgBrush_) DeleteObject(canvasBgBrush_);
    if (hFontUI_) DeleteObject(hFontUI_);
    if (hFontBold_) DeleteObject(hFontBold_);
    if (hFontSmall_) DeleteObject(hFontSmall_);
    if (hFontHeader_) DeleteObject(hFontHeader_);
    if (hFontBig_) DeleteObject(hFontBig_);
    if (gdipToken_) GdiplusShutdown(gdipToken_);
}

int ExplorerApp::DpiForWindow() const {
    using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
    static GetDpiForWindowFn fn = reinterpret_cast<GetDpiForWindowFn>(
        reinterpret_cast<void*>(GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow")));
    if (fn && hwnd_) {
        UINT d = fn(hwnd_);
        if (d >= 96 && d <= 480) return static_cast<int>(d);
    }
    HDC dc = GetDC(nullptr);
    int d = dc ? GetDeviceCaps(dc, LOGPIXELSX) : 96;
    if (dc) ReleaseDC(nullptr, dc);
    return d >= 96 ? d : 96;
}

void ExplorerApp::InitFonts() {
    auto makeFont = [this](int ptTenths, int weight, const wchar_t* face) -> HFONT {
        LOGFONTW lf = {};
        lf.lfHeight = -MulDiv(ptTenths, dpi_, 720);
        lf.lfWeight = weight;
        lf.lfCharSet = DEFAULT_CHARSET;
        lf.lfQuality = CLEARTYPE_QUALITY;
        lf.lfPitchAndFamily = DEFAULT_PITCH | FF_SWISS;
        wcscpy_s(lf.lfFaceName, face);
        return CreateFontIndirectW(&lf);
    };
    hFontUI_ = makeFont(90, FW_NORMAL, L"Segoe UI");
    hFontBold_ = makeFont(90, FW_SEMIBOLD, L"Segoe UI");
    hFontSmall_ = makeFont(80, FW_NORMAL, L"Segoe UI");
    hFontHeader_ = makeFont(90, FW_SEMIBOLD, L"Segoe UI");
    hFontBig_ = makeFont(120, FW_NORMAL, L"Segoe UI");
}

void ExplorerApp::InitControls() {
    hCanvas_ = CreateWindowExW(
        0, L"AeroExplorerCanvas", L"",
        WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_VSCROLL | WS_TABSTOP,
        0, 0, 100, 100, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_FILE_CANVAS)),
        hInst_, nullptr);
    if (!hCanvas_) return;
    SetWindowLongPtrW(hCanvas_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

    hTree_ = CreateWindowExW(
        0, WC_TREEVIEWW, L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | TVS_HASBUTTONS | TVS_HASLINES |
            TVS_LINESATROOT | TVS_SHOWSELALWAYS | TVS_INFOTIP,
        0, 0, 100, 100, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_NAV_TREE)),
        hInst_, nullptr);
    SetWindowLongPtrW(hTree_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    if (hTree_) {
        SetWindowTheme(hTree_, L"Explorer", nullptr);
        SendMessageW(hTree_, TVM_SETBKCOLOR, 0, static_cast<LPARAM>(RGB(255, 255, 255)));
        SendMessageW(hTree_, TVM_SETTEXTCOLOR, 0, static_cast<LPARAM>(RGB(24, 45, 74)));
        SendMessageW(hTree_, TVM_SETEXTENDEDSTYLE, TVS_EX_DOUBLEBUFFER, TVS_EX_DOUBLEBUFFER);
        SendMessageW(hTree_, TVM_SETITEMHEIGHT, static_cast<WPARAM>(Scale(20)), 0);
    }

    // Address bar edit (hidden until the user clicks the address bar)
    hAddrEdit_ = CreateWindowExW(
        WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_CHILD | ES_AUTOHSCROLL | ES_LEFT,
        0, 0, 10, 10, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_ADDRESS_EDIT)),
        hInst_, nullptr);
    SendMessageW(hAddrEdit_, WM_SETFONT, reinterpret_cast<WPARAM>(hFontUI_), TRUE);
    SetWindowLongPtrW(hAddrEdit_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    SetWindowSubclass(hAddrEdit_, &ExplorerApp::EditSubclassProc, 1,
                      reinterpret_cast<DWORD_PTR>(this));

    // Search box edit
    hSearchEdit_ = CreateWindowExW(
        0, L"EDIT", L"",
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_LEFT,
        0, 0, 10, 10, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_SEARCH_EDIT)),
        hInst_, nullptr);
    SendMessageW(hSearchEdit_, WM_SETFONT, reinterpret_cast<WPARAM>(hFontSmall_), TRUE);
    SetWindowLongPtrW(hSearchEdit_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    SetWindowSubclass(hSearchEdit_, &ExplorerApp::EditSubclassProc, 2,
                      reinterpret_cast<DWORD_PTR>(this));
    SendMessageW(hSearchEdit_, EM_SETCUEBANNER, TRUE,
                 reinterpret_cast<LPARAM>(L"Search"));
    Edit_SetCueBannerText(hSearchEdit_, L"Search");

    // Drag and drop into the file canvas (needs an OLE drop site wrapper).
    dropTarget_ = new AeroDropTarget(this);
    dropSite_ = new AeroDropSite(dropTarget_);
    if (FAILED(RegisterDragDrop(hCanvas_, dropSite_))) {
        dropSite_->Detach();
        dropSite_->Release();
        dropSite_ = nullptr;
        delete dropTarget_;
        dropTarget_ = nullptr;
    }
}

bool ExplorerApp::Create(HINSTANCE hInst, int nCmdShow) {
    hInst_ = hInst;

    GdiplusStartupInput gdipInput;
    if (GdiplusStartup(&gdipToken_, &gdipInput, nullptr) != Ok) {
        gdipToken_ = 0;
    }

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    wc.lpfnWndProc = &ExplorerApp::MainWndProc;
    wc.hInstance = hInst;
    wc.hIcon = static_cast<HICON>(LoadImageW(hInst, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
                                             0, 0, LR_DEFAULTSIZE | LR_DEFAULTCOLOR));
    wc.hIconSm = static_cast<HICON>(LoadImageW(hInst, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
                                               16, 16, LR_DEFAULTCOLOR));
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = nullptr;
    wc.lpszMenuName = nullptr;
    wc.lpszClassName = L"AeroExplorerMainWnd";
    if (!RegisterClassExW(&wc)) return false;

    WNDCLASSEXW cc = {};
    cc.cbSize = sizeof(cc);
    cc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    cc.lpfnWndProc = &ExplorerApp::CanvasWndProc;
    cc.hInstance = hInst;
    cc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    canvasBgBrush_ = CreateSolidBrush(RGB(255, 255, 255));
    cc.hbrBackground = canvasBgBrush_;
    cc.lpszClassName = L"AeroExplorerCanvas";
    if (!RegisterClassExW(&cc)) return false;

    icons_.Initialize(hInst, IDI_APP_ICON);
    ftpProfiles_ = AeroFtpClient::LoadProfiles();
    ftp_ = std::make_unique<AeroFtpClient>();
    alive_ = std::make_shared<std::atomic<bool>>(true);

    hwnd_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        L"AeroExplorerMainWnd",
        L"Computer - Windows 7 Aero Explorer",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT, CW_USEDEFAULT, 1180, 720,
        nullptr, nullptr, hInst, this);
    if (!hwnd_) return false;

    dpi_ = DpiForWindow();
    InitFonts();
    InitControls();

    ShowWindow(hwnd_, nCmdShow == 0 ? SW_SHOWNORMAL : nCmdShow);
    UpdateWindow(hwnd_);

    // Restore the shell tree and open My Computer, just like Windows 7.
    BuildTree();
    NavigateTo(L"computer://", true);
    SetFocus(hCanvas_);
    return true;
}

// ---------------------------------------------------------------------------
// Navigation pane tree
// ---------------------------------------------------------------------------
void ExplorerApp::BuildTree() {
    if (!hTree_) return;

    for (std::wstring* p : treeStrings_) delete p;
    treeStrings_.clear();

    if (treeImages_) {
        ImageList_Destroy(treeImages_);
        treeImages_ = nullptr;
    }
    treeImages_ = ImageList_Create(Scale(16), Scale(16), ILC_COLOR32 | ILC_MASK, 8, 8);

    auto addImage = [this](HICON icon) -> int {
        if (!icon || !treeImages_) return -1;
        return ImageList_AddIcon(treeImages_, icon);
    };

    int imgComputer = addImage(icons_.GetComputerIconSmall());
    int imgFolder = addImage(icons_.GetForVirtualFolder().iconSmall);
    int imgFav = addImage(icons_.GetFavoritesIconSmall());
    int imgFtp = addImage(icons_.GetNetworkIconSmall());

    SendMessageW(hTree_, TVM_SETIMAGELIST, TVSIL_NORMAL, reinterpret_cast<LPARAM>(treeImages_));
    TreeView_DeleteAllItems(hTree_);

    auto addNode = [&](HTREEITEM parent, const std::wstring& text, const std::wstring& target,
                       int image, bool expanded) -> HTREEITEM {
        std::wstring* stored = new std::wstring(target);
        treeStrings_.push_back(stored);

        TVINSERTSTRUCTW ins = {};
        ins.hParent = parent ? parent : TVI_ROOT;
        ins.hInsertAfter = TVI_LAST;
        ins.item.mask = TVIF_TEXT | TVIF_IMAGE | TVIF_SELECTEDIMAGE | TVIF_PARAM;
        ins.item.pszText = const_cast<wchar_t*>(text.c_str());
        ins.item.iImage = image;
        ins.item.iSelectedImage = image;
        ins.item.lParam = reinterpret_cast<LPARAM>(stored);
        HTREEITEM node = TreeView_InsertItem(hTree_, &ins);
        if (expanded) TreeView_Expand(hTree_, node, TVE_EXPAND);
        return node;
    };

    wchar_t desktop[MAX_PATH] = {};
    wchar_t downloads[MAX_PATH] = {};
    wchar_t documents[MAX_PATH] = {};
    wchar_t pictures[MAX_PATH] = {};
    wchar_t music[MAX_PATH] = {};
    wchar_t videos[MAX_PATH] = {};
    SHGetFolderPathW(nullptr, CSIDL_DESKTOPDIRECTORY, nullptr, 0, desktop);
    SHGetFolderPathW(nullptr, CSIDL_PERSONAL, nullptr, 0, documents);
    SHGetFolderPathW(nullptr, CSIDL_MYPICTURES, nullptr, 0, pictures);
    SHGetFolderPathW(nullptr, CSIDL_MYMUSIC, nullptr, 0, music);
    SHGetFolderPathW(nullptr, CSIDL_MYVIDEO, nullptr, 0, videos);
    {
        PWSTR p = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Downloads, 0, nullptr, &p)) && p) {
            wcscpy_s(downloads, p);
            CoTaskMemFree(p);
        } else {
            SHGetFolderPathW(nullptr, CSIDL_PERSONAL, nullptr, 0, downloads);
        }
    }

    HTREEITEM favRoot = addNode(nullptr, L"Favorites", L"", imgFav, true);
    addNode(favRoot, L"Desktop", desktop, imgFolder, false);
    addNode(favRoot, L"Downloads", downloads, imgFolder, false);
    addNode(favRoot, L"Documents", documents, imgFolder, false);
    addNode(favRoot, L"Pictures", pictures, imgFolder, false);
    addNode(favRoot, L"Music", music, imgFolder, false);
    addNode(favRoot, L"Videos", videos, imgFolder, false);

    HTREEITEM computer = addNode(nullptr, L"Computer", L"computer://", imgComputer, true);

    wchar_t drives[512] = {};
    DWORD mask = GetLogicalDrives();
    for (int i = 0; i < 26; ++i) {
        if (!(mask & (1u << i))) continue;
        wchar_t root[8] = { static_cast<wchar_t>(L'A' + i), L':', L'\\', L'\0' };
        UINT type = GetDriveTypeW(root);
        if (type == DRIVE_NO_ROOT_DIR || type == DRIVE_UNKNOWN || type == DRIVE_REMOTE) continue;

        wchar_t label[MAX_PATH + 1] = {};
        std::wstring text;
        if (GetVolumeInformationW(root, label, MAX_PATH, nullptr, nullptr, nullptr, nullptr, 0) &&
            label[0] != L'\0') {
            text = std::wstring(label) + L" (" + std::wstring(root, 2) + L")";
        } else {
            text = std::wstring(root, 2);
        }
        (void)drives;

        CachedFileVisuals vis = icons_.GetForLocalItem(root, text, true, true);
        int img = addImage(vis.iconSmall);
        if (img < 0) img = imgFolder;
        addNode(computer, text, root, img, false);
    }

    HTREEITEM ftpRoot = addNode(nullptr, L"FTP Servers", L"", imgFtp, true);
    for (size_t i = 0; i < ftpProfiles_.size(); ++i) {
        const auto& p = ftpProfiles_[i];
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
        addNode(ftpRoot, p.title.empty() ? p.host : p.title, BuildFtpUrl(info, true), imgFtp, false);
    }

    TreeView_Expand(hTree_, favRoot, TVE_EXPAND);
    TreeView_Expand(hTree_, computer, TVE_EXPAND);
    TreeView_Expand(hTree_, ftpRoot, TVE_EXPAND);
}

void ExplorerApp::SyncTreeSelection() {
    if (!hTree_) return;
    std::wstring target = currentPath_;
    for (wchar_t& c : target) c = static_cast<wchar_t>(towlower(c));

    HTREEITEM node = TreeView_GetRoot(hTree_);
    std::function<HTREEITEM(HTREEITEM)> walk = [&](HTREEITEM parent) -> HTREEITEM {
        while (parent) {
            TVITEMW item = {};
            item.mask = TVIF_PARAM;
            item.hItem = parent;
            if (TreeView_GetItem(hTree_, &item) && item.lParam) {
                const std::wstring* p = reinterpret_cast<const std::wstring*>(item.lParam);
                std::wstring candidate = *p;
                for (wchar_t& c : candidate) c = static_cast<wchar_t>(towlower(c));
                if (candidate == target) return parent;

                HTREEITEM child = TreeView_GetChild(hTree_, parent);
                if (child) {
                    HTREEITEM hit = walk(child);
                    if (hit) return hit;
                }
            }
            parent = TreeView_GetNextSibling(hTree_, parent);
        }
        return nullptr;
    };

    HTREEITEM found = walk(node);
    if (found) {
        treeSelectedPath_ = currentPath_;
        SendMessageW(hTree_, WM_SETREDRAW, FALSE, 0);
        TreeView_SelectItem(hTree_, found);
        TreeView_EnsureVisible(hTree_, found);
        SendMessageW(hTree_, WM_SETREDRAW, TRUE, 0);
        InvalidateRect(hTree_, nullptr, TRUE);
    }
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------
void ExplorerApp::RecalcLayout() {
    if (!hwnd_) return;
    RECT client = {};
    GetClientRect(hwnd_, &client);
    LayoutChrome(client);
    UpdateAddressEditPosition();
    UpdateSearchBoxPosition();
    RelayoutItems();
    UpdateScrollBar();
}

void ExplorerApp::LayoutChrome(const RECT& client) {
    const int w = client.right;
    const int h = client.bottom;

    navBandRc_ = { 0, 0, w, Scale(kNavBandH) };
    cmdBarRc_ = { 0, Scale(kNavBandH), w, Scale(kNavBandH + kCmdBarH) };

    const int statusTop = h - Scale(kStatusH);
    statusRc_ = { 0, statusTop, w, h };

    int detailsTop = detailsVisible_ ? statusTop - Scale(kDetailsH) : statusTop;
    if (detailsTop < Scale(kNavBandH + kCmdBarH) + Scale(120)) detailsTop = statusTop;
    detailsRc_ = { 0, detailsTop, w, statusTop };

    const int middleTop = Scale(kNavBandH + kCmdBarH);
    const int middleBottom = detailsTop;

    int navW = std::min(Scale(kNavPaneW), std::max(Scale(120), w / 4));
    navPaneRc_ = { 0, middleTop, navW, middleBottom };
    canvasRc_ = { navW, middleTop, w, middleBottom };

    const int orbSize = Scale(27);
    const int orbY = Scale(9);
    backOrbRc_ = { Scale(8), orbY, Scale(8) + orbSize, orbY + orbSize };
    fwdOrbRc_ = { Scale(38), orbY, Scale(38) + orbSize, orbY + orbSize };
    upOrbRc_ = { Scale(71), orbY, Scale(71) + orbSize, orbY + orbSize };

    const int searchW = Scale(200);
    const int boxY = Scale(11);
    const int boxH = Scale(23);
    int addrLeft = upOrbRc_.right + Scale(9);
    int searchLeft = w - searchW - Scale(10);
    if (searchLeft - Scale(14) < addrLeft + Scale(120)) {
        searchLeft = addrLeft + Scale(140);
    }
    addrBoxRc_ = { addrLeft, boxY, std::max(addrLeft + Scale(80), searchLeft - Scale(14)), boxY + boxH };
    searchBoxRc_ = { searchLeft, boxY, w - Scale(10), boxY + boxH };

    // Command bar buttons
    chromeHits_.clear();
    int bx = Scale(9);
    const int by = cmdBarRc_.top + Scale(4);
    const int bh = Scale(22);
    const wchar_t* labels[] = { L"Organize", L"View", L"FTP" };
    const int ids[] = { kCmdOrganize, kCmdViewMenu, kCmdFtpMenu };
    for (int i = 0; i < 3; ++i) {
        HDC dc = GetDC(hwnd_);
        HGDIOBJ old = SelectObject(dc, hFontUI_);
        SIZE sz = {};
        GetTextExtentPoint32W(dc, labels[i], static_cast<int>(wcslen(labels[i])), &sz);
        SelectObject(dc, old);
        ReleaseDC(hwnd_, dc);

        int bw = sz.cx + Scale(24);
        RECT rc = { bx, by, bx + bw, by + bh };
        chromeHits_.push_back({ rc, ids[i] });
        bx += bw + Scale(2);
    }

    // New folder split button
    {
        HDC dc = GetDC(hwnd_);
        HGDIOBJ old = SelectObject(dc, hFontUI_);
        SIZE sz = {};
        const wchar_t* label = L"New folder";
        GetTextExtentPoint32W(dc, label, static_cast<int>(wcslen(label)), &sz);
        SelectObject(dc, old);
        ReleaseDC(hwnd_, dc);
        int bw = sz.cx + Scale(52);
        RECT rc = { bx + Scale(6), by, bx + Scale(6) + bw, by + bh };
        chromeHits_.push_back({ rc, kCmdNewFolderBtn });
    }

    // Place children
    if (hTree_) {
        SetWindowPos(hTree_, nullptr,
                     navPaneRc_.left + Scale(5),
                     navPaneRc_.top + Scale(kNavHeaderH + 4),
                     std::max(10, static_cast<int>(navPaneRc_.right - navPaneRc_.left) - Scale(8)),
                     std::max(10, static_cast<int>(navPaneRc_.bottom - navPaneRc_.top) - Scale(6)),
                     SWP_NOZORDER | SWP_NOACTIVATE);
    }
    if (hCanvas_) {
        SetWindowPos(hCanvas_, nullptr,
                     canvasRc_.left, canvasRc_.top,
                     std::max(10, static_cast<int>(canvasRc_.right - canvasRc_.left)),
                     std::max(10, static_cast<int>(canvasRc_.bottom - canvasRc_.top)),
                     SWP_NOZORDER | SWP_NOACTIVATE);
    }
}

void ExplorerApp::UpdateAddressEditPosition() {
    if (!hAddrEdit_) return;
    if (!addrEditActive_) {
        ShowWindow(hAddrEdit_, SW_HIDE);
        return;
    }
    RECT rc = addrBoxRc_;
    InflateRect(&rc, -Scale(3), -Scale(3));
    SetWindowPos(hAddrEdit_, HWND_TOP, rc.left, rc.top,
                 std::max(10, static_cast<int>(rc.right - rc.left)),
                 std::max(10, static_cast<int>(rc.bottom - rc.top)),
                 SWP_SHOWWINDOW);
}

void ExplorerApp::UpdateSearchBoxPosition() {
    if (!hSearchEdit_) return;
    RECT rc = searchBoxRc_;
    RECT inner = { rc.left + Scale(22), rc.top + Scale(3), rc.right - Scale(3), rc.bottom - Scale(3) };
    SetWindowPos(hSearchEdit_, HWND_TOP, inner.left, inner.top,
                 std::max(10, static_cast<int>(inner.right - inner.left)),
                 std::max(10, static_cast<int>(inner.bottom - inner.top)),
                 SWP_NOACTIVATE | SWP_NOZORDER);
}

void ExplorerApp::HandleShortcutKey(WPARAM vk) {
    const bool ctrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
    const bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    const bool alt = (GetKeyState(VK_MENU) & 0x8000) != 0;

    if (vk == VK_LEFT && alt) { GoBack(); return; }
    if (vk == VK_RIGHT && alt) { GoForward(); return; }
    if (vk == VK_UP && alt) { GoUp(); return; }
    if (vk == VK_BACK) { GoUp(); return; }
    if (vk == VK_F5) { Refresh(); return; }
    if (vk == 'D' && alt) { BeginAddressEdit(); return; }
    if (vk == 'L' && ctrl) { BeginAddressEdit(); return; }
    if (vk == 'K' && ctrl) { OpenFtpManager(); return; }
    if (vk == 'N' && ctrl && shift) {
        if (CurrentIsFtp()) StartFtpNewFolder();
        else CreateNewFolderLocal();
        return;
    }
    if (vk == VK_F2) {
        if (CurrentIsFtp()) {
            std::vector<int> sel = SelectedIndices();
            StartFtpRename(sel.empty() ? -1 : sel.front());
        } else {
            RenameSelected();
        }
        return;
    }
    if (vk == VK_DELETE) { DeleteSelected(); return; }
    if (vk == 'O' && ctrl) {
        std::vector<int> sel = SelectedIndices();
        if (!sel.empty()) ActivateItem(sel.front());
        return;
    }
    if (vk == VK_F1) { ShowAboutDialog(hInst_, hwnd_); return; }
}

void ExplorerApp::InvalidateAll() {
    if (hwnd_) InvalidateRect(hwnd_, nullptr, FALSE);
    if (hCanvas_) InvalidateRect(hCanvas_, nullptr, FALSE);
}

void ExplorerApp::InvalidateCanvas() {
    if (hCanvas_) InvalidateRect(hCanvas_, nullptr, FALSE);
}

void ExplorerApp::UpdateScrollBar() {
    if (!hCanvas_) return;
    RECT client = {};
    GetClientRect(hCanvas_, &client);
    const int page = std::max(1, static_cast<int>(client.bottom));
    const int maxScroll = std::max(0, contentHeight_ - page + (contentHeight_ > page ? 1 : 0));
    if (scrollY_ > maxScroll) scrollY_ = maxScroll;
    if (scrollY_ < 0) scrollY_ = 0;

    SCROLLINFO si = {};
    si.cbSize = sizeof(si);
    si.fMask = SIF_RANGE | SIF_PAGE | SIF_POS | SIF_DISABLENOSCROLL;
    si.nMin = 0;
    si.nMax = contentHeight_ > page ? contentHeight_ - 1 : page - 1;
    si.nPage = static_cast<UINT>(page);
    si.nPos = scrollY_;
    SetScrollInfo(hCanvas_, SB_VERT, &si, TRUE);
}

// ---------------------------------------------------------------------------
// WinMain
// ---------------------------------------------------------------------------
int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, PWSTR lpCmdLine, int nCmdShow) {
    if (FAILED(OleInitialize(nullptr))) {
        // Drag & drop unavailable, but the shell still works.
    }
    INITCOMMONCONTROLSEX icc = {};
    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_TREEVIEW_CLASSES | ICC_STANDARD_CLASSES | ICC_BAR_CLASSES | ICC_LISTVIEW_CLASSES;
    InitCommonControlsEx(&icc);

    std::unique_ptr<ExplorerApp> app(new ExplorerApp());
    bool ok = app->Create(hInstance, nCmdShow);

    if (ok && lpCmdLine && lpCmdLine[0] != L'\0') {
        app->NavigateTo(TrimW(lpCmdLine), true);
    }

    int exitCode = 0;
    if (ok) {
        MSG msg = {};
        while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        exitCode = static_cast<int>(msg.wParam);
    }
    app.reset();
    OleUninitialize();
    return exitCode;
}
