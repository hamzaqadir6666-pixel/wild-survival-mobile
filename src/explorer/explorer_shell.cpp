// Window procedures, input handling, commands and clipboard for Aero Explorer.
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0a00
#endif

#include "app.h"
#include "dialogs.h"

#include <algorithm>
#include <cwchar>
#include <cwctype>
#include <memory>

using namespace aero;

namespace {

bool PointInRect(const RECT& rc, POINT pt) {
    return pt.x >= rc.left && pt.x < rc.right && pt.y >= rc.top && pt.y < rc.bottom;
}

} // namespace

// ---------------------------------------------------------------------------
// Canvas window procedure
// ---------------------------------------------------------------------------
LRESULT CALLBACK ExplorerApp::CanvasWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    ExplorerApp* self = reinterpret_cast<ExplorerApp*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (msg == WM_NCCREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCTW*>(lParam);
        (void)cs;
    }
    if (!self) return DefWindowProcW(hwnd, msg, wParam, lParam);
    return self->HandleCanvasMessage(hwnd, msg, wParam, lParam);
}

LRESULT ExplorerApp::HandleCanvasMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_ERASEBKGND:
            return 1;

        case WM_PAINT: {
            PAINTSTRUCT ps = {};
            HDC dc = BeginPaint(hwnd, &ps);
            RECT rc = {};
            GetClientRect(hwnd, &rc);
            PaintCanvas(dc, rc);
            EndPaint(hwnd, &ps);
            return 0;
        }

        case WM_SIZE:
            RelayoutItems();
            UpdateScrollBar();
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;

        case WM_VSCROLL: {
            SCROLLINFO si = {};
            si.cbSize = sizeof(si);
            si.fMask = SIF_ALL;
            GetScrollInfo(hwnd, SB_VERT, &si);
            int pos = si.nPos;
            switch (LOWORD(wParam)) {
                case SB_LINEUP: pos -= Scale(24); break;
                case SB_LINEDOWN: pos += Scale(24); break;
                case SB_PAGEUP: pos -= static_cast<int>(si.nPage); break;
                case SB_PAGEDOWN: pos += static_cast<int>(si.nPage); break;
                case SB_THUMBTRACK:
                case SB_THUMBPOSITION: pos = si.nTrackPos; break;
                case SB_TOP: pos = si.nMin; break;
                case SB_BOTTOM: pos = si.nMax; break;
                default: break;
            }
            ScrollBy(pos - scrollY_);
            return 0;
        }

        case WM_MOUSEMOVE: {
            POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
            if (rubberBand_) {
                rubberRc_.right = pt.x;
                rubberRc_.bottom = pt.y;
                if (rubberRc_.right < rubberRc_.left) std::swap(rubberRc_.left, rubberRc_.right);
                if (rubberRc_.bottom < rubberRc_.top) std::swap(rubberRc_.top, rubberRc_.bottom);

                // Live rubber-band selection, additive with the anchor rect.
                for (size_t pos = 0; pos < display_.size() && pos < itemRects_.size(); ++pos) {
                    RECT r = itemRects_[pos];
                    r.top -= scrollY_;
                    r.bottom -= scrollY_;
                    RECT inter = {};
                    bool touches = IntersectRect(&inter, &r, &rubberRc_) != FALSE;
                    items_[display_[pos]].selected = touches;
                }
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            }

            int hit = HitTestItem(pt);
            if (hit != hotItem_) {
                hotItem_ = hit;
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            if (!trackingMouse_) {
                TRACKMOUSEEVENT tme = {};
                tme.cbSize = sizeof(tme);
                tme.dwFlags = TME_LEAVE;
                tme.hwndTrack = hwnd;
                TrackMouseEvent(&tme);
                trackingMouse_ = true;
            }
            return 0;
        }

        case WM_MOUSELEAVE:
            trackingMouse_ = false;
            if (hotItem_ != -1) {
                hotItem_ = -1;
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            return 0;

        case WM_LBUTTONDOWN: {
            POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
            SetFocus(hwnd);
            int hit = HitTestItem(pt);

            // Column header clicks sort the details list, like Windows 7.
            if (view_ == ViewMode::Details && !IsComputerRoot() && pt.y < Scale(kDetailsHeaderH)) {
                int hdr = HitTestColumnHeader(pt);
                if (hdr >= 0) {
                    SortColumn clicked = static_cast<SortColumn>(hdr);
                    if (sortCol_ == clicked) {
                        sortAsc_ = !sortAsc_;
                    } else {
                        sortCol_ = clicked;
                        sortAsc_ = true;
                    }
                    ApplySortAndFilter();
                    InvalidateRect(hwnd, nullptr, FALSE);
                    return 0;
                }
            }

            bool ctrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
            bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;

            if (hit < 0) {
                if (!ctrl && !shift) {
                    for (auto& item : items_) item.selected = false;
                    anchorDisplay_ = -1;
                }
                rubberBand_ = true;
                rubberStart_ = pt;
                rubberRc_ = { pt.x, pt.y, pt.x, pt.y };
                SetCapture(hwnd);
                InvalidateRect(hwnd, nullptr, FALSE);
                return 0;
            }

            if (shift && anchorDisplay_ >= 0) {
                SelectRange(hit);
            } else if (ctrl) {
                ToggleSelect(hit);
                anchorDisplay_ = hit;
            } else if (!items_[display_[hit]].selected) {
                SelectOnly(hit);
                anchorDisplay_ = hit;
            } else {
                anchorDisplay_ = hit;
            }
            InvalidateRect(hwnd, nullptr, FALSE);
            InvalidateRect(MainWindow(), nullptr, FALSE);
            return 0;
        }

        case WM_LBUTTONUP:
            if (rubberBand_) {
                rubberBand_ = false;
                ReleaseCapture();
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            return 0;

        case WM_LBUTTONDBLCLK: {
            POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
            int hit = HitTestItem(pt);
            if (hit >= 0) {
                SelectOnly(hit);
                ActivateItem(hit);
            } else if (currentPath_ != L"computer://" && !CurrentIsFtp()) {
                GoUp();
            }
            return 0;
        }

        case WM_RBUTTONUP: {
            POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
            ClientToScreen(hwnd, &pt);

            POINT client = pt;
            ScreenToClient(hwnd, &client);
            int hit = HitTestItem(client);
            if (hit >= 0) {
                if (!items_[display_[hit]].selected) SelectOnly(hit);
                InvalidateRect(hwnd, nullptr, FALSE);
                ShowItemContextMenu(pt);
            } else {
                for (auto& item : items_) item.selected = false;
                InvalidateRect(hwnd, nullptr, FALSE);
                ShowOrganizeMenu(pt);
            }
            return 0;
        }

        case WM_MOUSEWHEEL: {
            int delta = GET_WHEEL_DELTA_WPARAM(wParam);
            UINT lines = 3;
            SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
            if (lines == 0) lines = 3;
            ScrollBy(-(delta * static_cast<int>(lines) / WHEEL_DELTA) * Scale(20));
            return 0;
        }

        case WM_KEYDOWN: {
            const bool ctrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
            const bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
            const size_t total = display_.size();
            if (total == 0 && wParam != VK_F5 && wParam != 'A') {
                if (wParam == VK_BACK) GoUp();
                return 0;
            }

            int current = -1;
            for (size_t pos = 0; pos < total; ++pos) {
                if (items_[display_[pos]].selected) {
                    current = static_cast<int>(pos);
                    break;
                }
            }

            switch (wParam) {
                case VK_UP:
                    if (current > 0) {
                        SelectOnly(current - 1);
                        EnsureVisible(current - 1);
                    }
                    break;
                case VK_DOWN:
                    if (current < 0) {
                        SelectOnly(0);
                    } else if (current + 1 < static_cast<int>(total)) {
                        SelectOnly(current + 1);
                        EnsureVisible(current + 1);
                    }
                    break;
                case VK_HOME:
                    SelectOnly(0);
                    EnsureVisible(0);
                    break;
                case VK_END:
                    SelectOnly(static_cast<int>(total) - 1);
                    EnsureVisible(static_cast<int>(total) - 1);
                    break;
                case VK_PRIOR:
                    ScrollBy(-static_cast<int>(Scale(kDetailsRowH * 12)));
                    break;
                case VK_NEXT:
                    ScrollBy(Scale(kDetailsRowH * 12));
                    break;
                case VK_RETURN:
                    if (current >= 0) ActivateItem(current);
                    break;
                case VK_BACK:
                    GoUp();
                    break;
                case VK_F2:
                    if (CurrentIsFtp()) StartFtpRename(current);
                    else RenameSelected();
                    break;
                case VK_F5:
                    Refresh();
                    break;
                case VK_DELETE:
                    DeleteSelected();
                    break;
                case 'A':
                    if (ctrl) {
                        for (auto& item : items_) item.selected = true;
                        InvalidateRect(hwnd, nullptr, FALSE);
                        InvalidateRect(MainWindow(), nullptr, FALSE);
                    }
                    break;
                case 'C':
                    if (ctrl) CopySelected(false);
                    break;
                case 'X':
                    if (ctrl) CopySelected(true);
                    break;
                case 'V':
                    if (ctrl) PasteClipboard();
                    break;
                case 'N':
                    if (ctrl && shift) {
                        if (CurrentIsFtp()) StartFtpNewFolder();
                        else CreateNewFolderLocal();
                    }
                    break;
                case 'K':
                    if (ctrl) OpenFtpManager();
                    break;
                case 'L':
                    if (ctrl) BeginAddressEdit();
                    break;
                default:
                    break;
            }
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        }

        case WM_SETFOCUS:
        case WM_KILLFOCUS:
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;

        case WM_CONTEXTMENU:
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Hit testing / selection helpers
// ---------------------------------------------------------------------------
int ExplorerApp::HitTestItem(POINT clientPt) const {
    for (size_t pos = 0; pos < display_.size() && pos < itemRects_.size(); ++pos) {
        RECT r = itemRects_[pos];
        r.top -= scrollY_;
        r.bottom -= scrollY_;
        if (PointInRect(r, clientPt)) return static_cast<int>(pos);
    }
    return -1;
}

int ExplorerApp::HitTestColumnHeader(POINT clientPt) const {
    RECT client = {};
    GetClientRect(hCanvas_, &client);
    const int w = static_cast<int>(client.right);
    const int pad = Scale(8);
    const int nameCol = std::max(Scale(160), w - Scale(150 + 130 + 90) - pad * 2);
    int xName = pad;
    int xMod = pad + nameCol;
    int xType = xMod + Scale(150);
    int xSize = xType + Scale(130);

    if (clientPt.x >= xSize) return static_cast<int>(SortColumn::Size);
    if (clientPt.x >= xType) return static_cast<int>(SortColumn::Type);
    if (clientPt.x >= xMod) return static_cast<int>(SortColumn::DateModified);
    if (clientPt.x >= xName) return static_cast<int>(SortColumn::Name);
    return -1;
}

void ExplorerApp::SelectOnly(int displayIndex) {
    for (auto& item : items_) item.selected = false;
    if (displayIndex >= 0 && displayIndex < static_cast<int>(display_.size())) {
        items_[display_[displayIndex]].selected = true;
    }
}

void ExplorerApp::ToggleSelect(int displayIndex) {
    if (displayIndex < 0 || displayIndex >= static_cast<int>(display_.size())) return;
    FileEntry& item = items_[display_[displayIndex]];
    item.selected = !item.selected;
}

void ExplorerApp::SelectRange(int displayIndex) {
    if (anchorDisplay_ < 0 || anchorDisplay_ >= static_cast<int>(display_.size())) {
        SelectOnly(displayIndex);
        return;
    }
    int lo = std::min(anchorDisplay_, displayIndex);
    int hi = std::max(anchorDisplay_, displayIndex);
    for (auto& item : items_) item.selected = false;
    for (int pos = lo; pos <= hi && pos < static_cast<int>(display_.size()); ++pos) {
        items_[display_[pos]].selected = true;
    }
}

// ---------------------------------------------------------------------------
// Item activation
// ---------------------------------------------------------------------------
void ExplorerApp::ActivateItem(int displayIndex) {
    if (displayIndex < 0 || displayIndex >= static_cast<int>(display_.size())) return;
    const FileEntry& item = items_[display_[displayIndex]];
    const std::wstring path = item.fullPath;
    const bool isDir = item.isDirectory;
    const bool isFtp = item.isFtpItem;
    const bool isFtpBookmark = item.isFtpBookmark;

    if (item.isDrive) {
        NavigateTo(path, true);
        return;
    }
    if (isFtpBookmark) {
        NavigateTo(path, true);
        return;
    }
    if (isFtp) {
        if (isDir) {
            NavigateTo(path, true);
        } else {
            // Download to the local Downloads folder and open with the default app.
            StartFtpDownloadSelected();
        }
        return;
    }
    if (isDir) {
        NavigateTo(path, true);
        return;
    }
    ShellExecuteW(hwnd_, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

void ExplorerApp::OpenLocalItem(const FileEntry& item) {
    ShellExecuteW(hwnd_, L"open", item.fullPath.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

// ---------------------------------------------------------------------------
// Main window procedure
// ---------------------------------------------------------------------------
LRESULT CALLBACK ExplorerApp::MainWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    ExplorerApp* self = nullptr;
    if (msg == WM_NCCREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCTW*>(lParam);
        self = reinterpret_cast<ExplorerApp*>(cs->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self) self->hwnd_ = hwnd;
    } else {
        self = reinterpret_cast<ExplorerApp*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }
    if (!self) return DefWindowProcW(hwnd, msg, wParam, lParam);
    return self->HandleMainMessage(hwnd, msg, wParam, lParam);
}

LRESULT ExplorerApp::HandleMainMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE:
            DragAcceptFiles(hwnd, FALSE);
            return 0;

        case WM_ERASEBKGND:
            return 1;

        case WM_PAINT: {
            PAINTSTRUCT ps = {};
            HDC dc = BeginPaint(hwnd, &ps);
            RECT rc = {};
            GetClientRect(hwnd, &rc);
            PaintChrome(dc, rc);
            EndPaint(hwnd, &ps);
            return 0;
        }

        case WM_SIZE:
            dpi_ = DpiForWindow();
            RecalcLayout();
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;

        case WM_DPICHANGED: {
            dpi_ = HIWORD(wParam);
            RECT* suggested = reinterpret_cast<RECT*>(lParam);
            if (suggested) {
                SetWindowPos(hwnd, nullptr, suggested->left, suggested->top,
                             suggested->right - suggested->left,
                             suggested->bottom - suggested->top,
                             SWP_NOZORDER | SWP_NOACTIVATE);
            }
            if (hFontUI_) DeleteObject(hFontUI_);
            if (hFontBold_) DeleteObject(hFontBold_);
            if (hFontSmall_) DeleteObject(hFontSmall_);
            if (hFontHeader_) DeleteObject(hFontHeader_);
            if (hFontBig_) DeleteObject(hFontBig_);
            hFontUI_ = hFontBold_ = hFontSmall_ = hFontHeader_ = hFontBig_ = nullptr;
            InitFonts();
            if (hAddrEdit_) SendMessageW(hAddrEdit_, WM_SETFONT, reinterpret_cast<WPARAM>(hFontUI_), TRUE);
            if (hSearchEdit_) SendMessageW(hSearchEdit_, WM_SETFONT, reinterpret_cast<WPARAM>(hFontSmall_), TRUE);
            RecalcLayout();
            InvalidateRect(hwnd, nullptr, TRUE);
            return 0;
        }

        case WM_GETMINMAXINFO: {
            auto* mmi = reinterpret_cast<MINMAXINFO*>(lParam);
            mmi->ptMinTrackSize.x = Scale(720);
            mmi->ptMinTrackSize.y = Scale(480);
            return 0;
        }

        case WM_MOUSEMOVE: {
            POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
            int hotChrome = 0;
            int hotCmd = 0;
            if (PointInRect(backOrbRc_, pt)) hotChrome = 4001;
            else if (PointInRect(fwdOrbRc_, pt)) hotChrome = 4002;
            else if (PointInRect(upOrbRc_, pt)) hotChrome = 4003;
            else if (PointInRect(addrBoxRc_, pt)) hotChrome = 4010;
            else if (PointInRect(searchBoxRc_, pt)) hotChrome = 4020;
            else if (PointInRect(cmdBarRc_, pt)) {
                for (const auto& hit : chromeHits_) {
                    if (PointInRect(hit.rc, pt)) {
                        hotCmd = hit.id;
                        break;
                    }
                }
            }
            if (hotChrome != hotChromeId_ || hotCmd != hotCmdId_) {
                hotChromeId_ = hotChrome;
                hotCmdId_ = hotCmd;
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            {
                TRACKMOUSEEVENT tme = {};
                tme.cbSize = sizeof(tme);
                tme.dwFlags = TME_LEAVE;
                tme.hwndTrack = hwnd;
                TrackMouseEvent(&tme);
            }
            return 0;
        }

        case WM_MOUSELEAVE:
            if (hotChromeId_ || hotCmdId_) {
                hotChromeId_ = 0;
                hotCmdId_ = 0;
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            return 0;

        case WM_LBUTTONUP: {
            POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };

            if (PointInRect(backOrbRc_, pt)) { GoBack(); return 0; }
            if (PointInRect(fwdOrbRc_, pt)) { GoForward(); return 0; }
            if (PointInRect(upOrbRc_, pt)) { GoUp(); return 0; }

            if (PointInRect(addrBoxRc_, pt)) {
                // Clicking a breadcrumb segment navigates; clicking blank space edits the path.
                for (const auto& crumb : crumbHits_) {
                    if (PointInRect(crumb.first, pt)) {
                        NavigateTo(crumb.second, true);
                        return 0;
                    }
                }
                BeginAddressEdit();
                return 0;
            }

            if (PointInRect(cmdBarRc_, pt)) {
                for (const auto& hit : chromeHits_) {
                    if (PointInRect(hit.rc, pt)) {
                        POINT screen = pt;
                        ClientToScreen(hwnd, &screen);
                        if (hit.id == kCmdOrganize) ShowOrganizeMenu(screen);
                        else if (hit.id == kCmdViewMenu) ShowViewMenu(screen);
                        else if (hit.id == kCmdFtpMenu) ShowFtpMenu(screen);
                        else if (hit.id == kCmdNewFolderBtn) {
                            if (CurrentIsFtp()) StartFtpNewFolder();
                            else CreateNewFolderLocal();
                        }
                        return 0;
                    }
                }
            }

            if (PointInRect(searchBoxRc_, pt)) {
                SetFocus(hSearchEdit_);
                SendMessageW(hSearchEdit_, EM_SETSEL, 0, -1);
                return 0;
            }
            return 0;
        }

        case WM_RBUTTONUP: {
            POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
            ClientToScreen(hwnd, &pt);
            if (PointInRect(cmdBarRc_, { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) })) {
                ShowExplorerMenuBar(pt);
            } else {
                ShowOrganizeMenu(pt);
            }
            return 0;
        }

        case WM_COMMAND: {
            int id = LOWORD(wParam);
            int code = HIWORD(wParam);
            if (id == IDC_ADDRESS_EDIT && code == EN_KILLFOCUS && addrEditActive_) {
                // Commit unless focus moved to the address bar again.
                HWND focus = GetFocus();
                if (focus != hAddrEdit_) CommitAddressEdit(true);
                return 0;
            }
            if (id == IDC_SEARCH_EDIT && code == EN_CHANGE) {
                std::wstring text;
                int len = GetWindowTextLengthW(hSearchEdit_);
                if (len > 0) {
                    text.resize(static_cast<size_t>(len) + 1);
                    GetWindowTextW(hSearchEdit_, &text[0], len + 1);
                    text.resize(static_cast<size_t>(len));
                }
                if (text != searchText_) {
                    searchText_ = text;
                    ApplySortAndFilter();
                }
                return 0;
            }
            OnMenuCommand(id);
            return 0;
        }

        case WM_NOTIFY: {
            auto* hdr = reinterpret_cast<NMHDR*>(lParam);
            if (hdr && hdr->idFrom == IDC_NAV_TREE && hdr->code == TVN_SELCHANGEDW) {
                auto* nm = reinterpret_cast<NMTREEVIEWW*>(lParam);
                if (nm && nm->itemNew.lParam) {
                    const std::wstring* target = reinterpret_cast<const std::wstring*>(nm->itemNew.lParam);
                    // Container nodes (Favorites, FTP Servers) carry no target.
                    if (target && !target->empty() && *target != treeSelectedPath_) {
                        NavigateTo(*target, true);
                    }
                }
            }
            return 0;
        }

        case WM_DROPFILES: {
            HDROP drop = reinterpret_cast<HDROP>(wParam);
            UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
            std::vector<std::wstring> paths;
            for (UINT i = 0; i < count; ++i) {
                UINT len = DragQueryFileW(drop, i, nullptr, 0);
                if (len == 0) continue;
                std::wstring buf(static_cast<size_t>(len) + 1, L'\0');
                DragQueryFileW(drop, i, &buf[0], len + 1);
                buf.resize(len);
                if (!buf.empty()) paths.push_back(buf);
            }
            DragFinish(drop);
            HandleDroppedPaths(paths);
            return 0;
        }

        case WM_TIMER:
            if (wParam == animTimer_) {
                animPhase_ = (animPhase_ + 1) % 24;
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            return 0;

        case WM_APP_FTP_PROGRESS: {
            auto* payload = reinterpret_cast<FtpProgressPayload*>(lParam);
            if (payload) {
                std::unique_ptr<FtpProgressPayload> holder(payload);
                progressText_ = payload->statusText;
                if (payload->totalBytes > 0) {
                    progressPct_ = static_cast<int>(
                        std::min<uint64_t>(100, (payload->doneBytes * 100) / payload->totalBytes));
                } else {
                    progressPct_ = payload->percent;
                }
                if (progressPct_ >= 100) progressPct_ = 99;
                StartProgressAnimation();
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            return 0;
        }

        case WM_APP_FTP_LIST_DONE: {
            std::unique_ptr<FtpAsyncListResult> res(reinterpret_cast<FtpAsyncListResult*>(lParam));
            if (!res) return 0;
            StopProgressAnimation();
            progressPct_ = 0;
            progressText_.clear();
            navigating_ = false;

            if (!res->success) {
                lastError_ = res->errorMessage;
                MessageBoxW(hwnd_, res->errorMessage.c_str(), L"FTP Connection Error",
                            MB_ICONERROR | MB_OK);
                if (historyPos_ >= 0 && historyPos_ < static_cast<int>(history_.size())) {
                    // Roll the history pointer back to the previous folder on failure.
                    if (historyPos_ > 0) --historyPos_;
                }
                InvalidateAll();
                return 0;
            }

            lastError_.clear();
            currentPath_ = res->fullUrl;
            items_.clear();
            for (auto& entry : res->entries) {
                CachedFileVisuals vis = icons_.GetForRemoteFtpItem(entry.name, entry.isDirectory);
                entry.iconSmall = vis.iconSmall;
                entry.iconLarge = vis.iconLarge;
                entry.typeName = entry.isDirectory
                                     ? L"File folder"
                                     : (vis.typeName.empty() ? L"File" : vis.typeName);
                entry.isFtpItem = true;
                items_.push_back(std::move(entry));
            }
            SetWindowTextW(hwnd_, (res->host + L" - " + res->fullUrl +
                                   L" - Windows 7 Aero Explorer").c_str());
            ApplySortAndFilter();
            SyncTreeSelection();
            UpdateStatusFromFolder();
            return 0;
        }

        case WM_APP_FTP_OP_DONE: {
            std::unique_ptr<FtpAsyncOpResult> res(reinterpret_cast<FtpAsyncOpResult*>(lParam));
            if (!res) return 0;
            StopProgressAnimation();
            progressPct_ = 0;
            progressText_.clear();

            if (!res->success) {
                lastError_ = res->message;
                if (!res->message.empty()) {
                    MessageBoxW(hwnd_, res->message.c_str(), L"FTP Operation", MB_ICONERROR | MB_OK);
                }
            } else if (!res->message.empty()) {
                statusNote_ = res->message;
            }
            if (res->refreshAfter || res->success) Refresh();
            if (!res->openLocalFileAfter.empty()) {
                ShellExecuteW(hwnd_, L"open", res->openLocalFileAfter.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
            }
            InvalidateAll();
            return 0;
        }

        case WM_APP_ADDRESS_COMMIT:
            CommitAddressEdit(true);
            return 0;

        case WM_APP_ADDRESS_CANCEL:
            addrEditActive_ = false;
            SetWindowTextW(hAddrEdit_, L"");
            ShowWindow(hAddrEdit_, SW_HIDE);
            SetFocus(hCanvas_);
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;

        case WM_CLOSE:
            if (ftp_) ftp_->Disconnect();
            DestroyWindow(hwnd);
            return 0;

        case WM_DESTROY:
            StopProgressAnimation();
            if (alive_) alive_->store(false);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Address / search edit subclass
// ---------------------------------------------------------------------------
LRESULT CALLBACK ExplorerApp::EditSubclassProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam,
                                               UINT_PTR idSubclass, DWORD_PTR refData) {
    auto* self = reinterpret_cast<ExplorerApp*>(refData);
    if (!self) return DefSubclassProc(hwnd, msg, wParam, lParam);

    if (msg == WM_KEYDOWN) {
        if (wParam == VK_RETURN) {
            if (idSubclass == 1) self->CommitAddressEdit(true);
            else {
                wchar_t buf[512] = {};
                GetWindowTextW(hwnd, buf, 512);
                self->QuickConnectFromText(buf);
            }
            return 0;
        }
        if (wParam == VK_ESCAPE) {
            if (idSubclass == 1) self->CommitAddressEdit(false);
            else {
                SetWindowTextW(hwnd, L"");
                SetFocus(self->Canvas());
            }
            return 0;
        }
        if (wParam == VK_DOWN && idSubclass == 1) {
            // Simple shell history navigation in the address bar.
            return 0;
        }
        if (wParam == VK_TAB) {
            SetFocus(self->Canvas());
            return 0;
        }
    }
    if (msg == WM_CHAR && wParam == L'\r') return 0;

    if (msg == WM_KILLFOCUS) {
        LRESULT res = DefSubclassProc(hwnd, msg, wParam, lParam);
        if (idSubclass == 1 && self->AddressEditActive()) {
            PostMessageW(self->MainWindow(), WM_APP_ADDRESS_COMMIT, 0, 0);
        }
        return res;
    }

    return DefSubclassProc(hwnd, msg, wParam, lParam);
}

void ExplorerApp::BeginAddressEdit() {
    if (!hAddrEdit_) return;
    if (!addrEditActive_) {
        preEditPath_ = AddressText();
        addrEditActive_ = true;
        SetWindowTextW(hAddrEdit_, AddressText().c_str());
        UpdateAddressEditPosition();
    }
    SetFocus(hAddrEdit_);
    SendMessageW(hAddrEdit_, EM_SETSEL, 0, -1);
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void ExplorerApp::CommitAddressEdit(bool navigate) {
    if (!hAddrEdit_ || !addrEditActive_) return;

    std::wstring text;
    int len = GetWindowTextLengthW(hAddrEdit_);
    if (len > 0) {
        text.resize(static_cast<size_t>(len) + 1);
        GetWindowTextW(hAddrEdit_, &text[0], len + 1);
        text.resize(static_cast<size_t>(len));
    }
    text = TrimW(text);

    addrEditActive_ = false;
    ShowWindow(hAddrEdit_, SW_HIDE);
    SetFocus(hCanvas_);
    InvalidateRect(hwnd_, nullptr, FALSE);

    if (!navigate || text.empty() || text == preEditPath_) return;
    NavigateTo(text, true);
}
