#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0a00
#endif

#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <commdlg.h>
#include <objidl.h>
#include <oleidl.h>
#include <gdiplus.h>
#include <uxtheme.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "../common/path_ftp_utils.h"
#include "../common/version.h"
#include "ftp_client.h"
#include "models.h"
#include "resource.h"
#include "shell_icons.h"

namespace aero {

// Chrome metrics expressed at 96 DPI and scaled at runtime.
constexpr int kNavBandH = 46;
constexpr int kCmdBarH = 30;
constexpr int kNavHeaderH = 26;
constexpr int kDetailsH = 74;
constexpr int kStatusH = 22;
constexpr int kDetailsHeaderH = 26;
constexpr int kDetailsRowH = 23;
constexpr int kNavPaneW = 202;

constexpr int kCmdOrganize = 3000;
constexpr int kCmdViewMenu = 3001;
constexpr int kCmdFtpMenu = 3002;
constexpr int kCmdNewFolderBtn = 3003;

struct ChromeHit {
    RECT rc;
    int id;
};

struct GroupHeader {
    std::wstring title;
    RECT rc;
};

class ExplorerApp;

// Minimal CF_HDROP drop target that forwards to the explorer instance.
class AeroDropTarget final : public IDropTarget {
public:
    explicit AeroDropTarget(ExplorerApp* app) : app_(app) {}
    ~AeroDropTarget() = default;

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override;
    ULONG STDMETHODCALLTYPE AddRef() override { return 2; }
    ULONG STDMETHODCALLTYPE Release() override { return 1; }

    HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data, DWORD keyState, POINTL pt, DWORD* effect) override;
    HRESULT STDMETHODCALLTYPE DragOver(DWORD keyState, POINTL pt, DWORD* effect) override;
    HRESULT STDMETHODCALLTYPE DragLeave() override;
    HRESULT STDMETHODCALLTYPE Drop(IDataObject* data, DWORD keyState, POINTL pt, DWORD* effect) override;

    void Detach() { app_ = nullptr; }

private:
    ExplorerApp* app_ = nullptr;
};

// COM drop-site wrapper (ref-counted object that forwards to AeroDropTarget).
class AeroDropSite final : public IDropTarget {
public:
    explicit AeroDropSite(AeroDropTarget* sink) : sink_(sink) {}
    ~AeroDropSite() = default;
    void Detach() { sink_ = nullptr; }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IDropTarget) {
            *ppv = static_cast<IDropTarget*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return static_cast<ULONG>(InterlockedIncrement(&refs_)); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG v = InterlockedDecrement(&refs_);
        if (v == 0) delete this;
        return static_cast<ULONG>(v);
    }

    HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* d, DWORD k, POINTL p, DWORD* e) override {
        AeroDropTarget* s = sink_;
        return s ? s->DragEnter(d, k, p, e) : S_OK;
    }
    HRESULT STDMETHODCALLTYPE DragOver(DWORD k, POINTL p, DWORD* e) override {
        AeroDropTarget* s = sink_;
        return s ? s->DragOver(k, p, e) : S_OK;
    }
    HRESULT STDMETHODCALLTYPE DragLeave() override {
        AeroDropTarget* s = sink_;
        return s ? s->DragLeave() : S_OK;
    }
    HRESULT STDMETHODCALLTYPE Drop(IDataObject* d, DWORD k, POINTL p, DWORD* e) override {
        AeroDropTarget* s = sink_;
        return s ? s->Drop(d, k, p, e) : E_FAIL;
    }

private:
    AeroDropTarget* sink_ = nullptr;
    LONG refs_ = 1;
};

class ExplorerApp {
public:
    ExplorerApp() = default;
    ~ExplorerApp();

    bool Create(HINSTANCE hInst, int nCmdShow);

    HINSTANCE Instance() const { return hInst_; }
    HWND MainWindow() const { return hwnd_; }
    HWND Canvas() const { return hCanvas_; }

    // Window procedures
    static LRESULT CALLBACK MainWndProc(HWND, UINT, WPARAM, LPARAM);
    static LRESULT CALLBACK CanvasWndProc(HWND, UINT, WPARAM, LPARAM);
    static LRESULT CALLBACK EditSubclassProc(HWND, UINT, WPARAM, LPARAM,
                                             UINT_PTR, DWORD_PTR);

    // Messages handled
    LRESULT HandleMainMessage(HWND, UINT, WPARAM, LPARAM);
    LRESULT HandleCanvasMessage(HWND, UINT, WPARAM, LPARAM);

    // Navigation
    void NavigateTo(const std::wstring& rawPath, bool addHistory);
    void Refresh();
    void GoBack();
    void GoForward();
    void GoUp();

    // Drag and drop entry point (paths already extracted from CF_HDROP).
    void HandleDroppedPaths(const std::vector<std::wstring>& paths);
    void SetDropHighlight(bool on);

    // Commands
    void OnMenuCommand(int id);
    void ShowOrganizeMenu(POINT pt);
    void ShowViewMenu(POINT pt);
    void ShowFtpMenu(POINT pt);
    void ShowItemContextMenu(POINT screenPt);
    void ShowExplorerMenuBar(POINT screenPt);

    // FTP operations
    void OpenFtpManager();
    void StartFtpList(const std::wstring& url);
    void StartFtpUpload(const std::vector<std::wstring>& localPaths);
    void StartFtpDownloadSelected();
    void StartFtpNewFolder();
    void StartFtpRename(int itemIndex);
    void StartFtpDelete(const std::vector<int>& itemIndices);
    bool CurrentIsFtp() const { return IsFtpUrl(currentPath_); }

    // Introspection helpers used by canvas code
    int Scale(int v) const { return MulDiv(v, dpi_, 96); }
    bool IsComputerRoot() const { return currentPath_ == L"computer://"; }
    const std::vector<FileEntry>& Items() const { return items_; }
    const std::vector<size_t>& DisplayOrder() const { return display_; }
    const std::vector<RECT>& ItemRects() const { return itemRects_; }
    ViewMode CurrentView() const { return view_; }
    std::vector<int> SelectedIndices() const;
    std::wstring ItemSubtitle(const FileEntry& item) const;
    std::wstring StatusText() const;
    std::wstring AddressText() const;
    int AddressProgress() const { return progressPct_; }

    // Painting / layout
    void RecalcLayout();
    void RelayoutItems();
    void PaintChrome(HDC dc, const RECT& client);
    void PaintCanvas(HDC dc, const RECT& client);
    void HandleShortcutKey(WPARAM vk);
    void InvalidateAll();
    void InvalidateCanvas();
    void UpdateScrollBar();

    // Item interaction
    int HitTestItem(POINT clientPt) const;
    int HitTestColumnHeader(POINT clientPt) const;
    void SelectOnly(int displayIndex);
    void ToggleSelect(int displayIndex);
    void SelectRange(int displayIndex);
    void EnsureVisible(int displayIndex);
    void ActivateItem(int displayIndex);
    void ScrollBy(int delta);

    // Local operations
    void CreateNewFolderLocal();
    void RenameSelected();
    void DeleteSelected();
    void CopySelected(bool cut);
    void PasteClipboard();
    void CopyPathOfSelected();
    void ShowPropertiesOfSelected();
    void OpenSelectedWithShell();

private:
    HINSTANCE hInst_ = nullptr;
    HWND hwnd_ = nullptr;
    HWND hTree_ = nullptr;
    HWND hCanvas_ = nullptr;
    HWND hAddrEdit_ = nullptr;
    HWND hSearchEdit_ = nullptr;

    ShellIconCache icons_;
    std::vector<FtpSiteProfile> ftpProfiles_;
    std::unique_ptr<AeroFtpClient> ftp_;
    std::shared_ptr<std::atomic<bool>> alive_;
    std::atomic<bool> ftpBusy_{ false };
    std::mutex workersMutex_;
    std::mutex ftpOpMutex_;
    std::vector<std::thread> workers_;
    std::vector<std::wstring*> treeStrings_;

    std::wstring currentPath_ = L"computer://";
    std::vector<FileEntry> items_;
    std::vector<size_t> display_;
    std::vector<RECT> itemRects_;
    std::vector<GroupHeader> groupHeaders_;

    ViewMode view_ = ViewMode::Details;
    SortColumn sortCol_ = SortColumn::Name;
    bool sortAsc_ = true;
    bool showHidden_ = false;
    bool detailsVisible_ = true;
    std::wstring searchText_;
    bool navigating_ = false;

    int scrollY_ = 0;
    int contentHeight_ = 0;
    int dpi_ = 96;

    // Chrome geometry
    RECT navBandRc_{};
    RECT cmdBarRc_{};
    RECT navPaneRc_{};
    RECT canvasRc_{};
    RECT detailsRc_{};
    RECT statusRc_{};
    RECT detailsButton2ndRc_{};
    RECT backOrbRc_{};
    RECT fwdOrbRc_{};
    RECT upOrbRc_{};
    RECT addrBoxRc_{};
    RECT searchBoxRc_{};
    std::vector<ChromeHit> chromeHits_;
    std::vector<std::pair<RECT, std::wstring>> crumbHits_;
    int hotChromeId_ = 0;
    int hotCmdId_ = 0;

    // Selection & drag state
    int anchorDisplay_ = -1;
    bool rubberBand_ = false;
    POINT rubberStart_{ 0, 0 };
    RECT rubberRc_{};
    bool dropHighlight_ = false;
    int hotItem_ = -1;
    bool trackingMouse_ = false;

    // History
    std::vector<std::wstring> history_;
    int historyPos_ = -1;

    // Clipboard
    std::vector<std::wstring> clipPaths_;
    bool clipCut_ = false;

    // Address bar edit mode
    bool addrEditActive_ = false;
    std::vector<std::wstring> addrHistoryScratch_;
    std::wstring preEditPath_;

    // FTP progress display
    int progressPct_ = 0;
    std::wstring progressText_;
    UINT_PTR animTimer_ = 0;
    int animPhase_ = 0;
    std::wstring lastError_;
    std::wstring statusNote_;

    // GDI resources
    HFONT hFontUI_ = nullptr;
    HFONT hFontBold_ = nullptr;
    HFONT hFontSmall_ = nullptr;
    HFONT hFontHeader_ = nullptr;
    HFONT hFontBig_ = nullptr;
    ULONG_PTR gdipToken_ = 0;
    AeroDropTarget* dropTarget_ = nullptr;
    AeroDropSite* dropSite_ = nullptr;
    HIMAGELIST treeImages_ = nullptr;
    HBRUSH treeBgBrush_ = nullptr;
    HBRUSH canvasBgBrush_ = nullptr;
    std::wstring treeSelectedPath_;

    // Setup / helpers
    void InitFonts();
    void InitControls();
    void BuildTree();
    void SyncTreeSelection();
    void LayoutChrome(const RECT& client);
    void UpdateAddressEditPosition();
    void BeginAddressEdit();
    bool AddressEditActive() const { return addrEditActive_; }
    void CommitAddressEdit(bool navigate);
    void UpdateSearchBoxPosition();
    bool LoadLocalFolder(const std::wstring& path, std::wstring& errorText);
    void LoadComputerRoot();
    void ApplySortAndFilter();
    void SortItems();
    void UpdateStatusFromFolder();
    int DpiForWindow() const;
    void StartProgressAnimation();
    void StopProgressAnimation();
    void SetProgress(int pct, const std::wstring& text);
    void ReportFtpError(const std::wstring& text);
    void PostFtpOpDone(std::unique_ptr<FtpAsyncOpResult> result);
    bool ConfirmDelete(const std::vector<int>& displayIdxs);
    std::wstring ResolveLocalPath(const std::wstring& input) const;
    std::wstring CurrentFtpRemoteDir() const;
    void QuickConnectFromText(const std::wstring& text);
    void OpenLocalItem(const FileEntry& item);
};

} // namespace aero
