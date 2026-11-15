// Aero chrome, file canvas and details pane painting for Aero Explorer.
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0a00
#endif

#include "app.h"
#include "aero_theme.h"

#include <algorithm>
#include <memory>

using namespace aero;
using namespace Gdiplus;

namespace {

struct BufDC {
    HDC dc = nullptr;
    HBITMAP bmp = nullptr;
    HGDIOBJ oldBmp = nullptr;
    void* bits = nullptr;

    bool Begin(HDC target, int w, int h) {
        if (w <= 0 || h <= 0) return false;
        BITMAPINFO bi = {};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = w;
        bi.bmiHeader.biHeight = -h;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        dc = CreateCompatibleDC(target);
        if (!dc) return false;
        bmp = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
        if (!bmp) {
            DeleteDC(dc);
            dc = nullptr;
            return false;
        }
        oldBmp = SelectObject(dc, bmp);
        return true;
    }

    void End(HDC target, int w, int h) {
        if (!dc) return;
        BitBlt(target, 0, 0, w, h, dc, 0, 0, SRCCOPY);
        if (oldBmp) SelectObject(dc, oldBmp);
        if (bmp) DeleteObject(bmp);
        DeleteDC(dc);
        dc = nullptr;
        bmp = nullptr;
    }
};

void FillSolid(Graphics& g, const RECT& rc, Color c) {
    SolidBrush b(c);
    g.FillRectangle(&b, RectF(static_cast<REAL>(rc.left), static_cast<REAL>(rc.top),
                              static_cast<REAL>(rc.right - rc.left), static_cast<REAL>(rc.bottom - rc.top)));
}

void DrawTextGp(Graphics& g, const std::wstring& text, Font* font, const RectF& rc,
                Color color, StringAlignment hAlign = StringAlignmentNear,
                bool wrap = false, bool ellipsis = false) {
    SolidBrush brush(color);
    StringFormat sf;
    sf.SetLineAlignment(StringAlignmentCenter);
    sf.SetAlignment(hAlign);
    sf.SetTrimming(ellipsis ? StringTrimmingEllipsisCharacter : StringTrimmingNone);
    sf.SetFormatFlags(wrap ? 0 : StringFormatFlagsNoWrap);
    g.DrawString(text.c_str(), -1, font, rc, &sf, &brush);
}

std::wstring ColumnHeaderLabel(SortColumn c) {
    switch (c) {
        case SortColumn::DateModified: return L"Date modified";
        case SortColumn::Type: return L"Type";
        case SortColumn::Size: return L"Size";
        case SortColumn::Name:
        default: return L"Name";
    }
}

} // namespace

// ---------------------------------------------------------------------------
// Layout of the file canvas items
// ---------------------------------------------------------------------------
void ExplorerApp::RelayoutItems() {
    itemRects_.clear();
    groupHeaders_.clear();
    if (!hCanvas_) return;

    RECT client = {};
    GetClientRect(hCanvas_, &client);
    const int width = std::max(1, static_cast<int>(client.right));
    const int pad = Scale(8);

    const int nameCol = std::max(Scale(160), width - Scale(150 + 130 + 90) - pad * 2);
    const int colMod = Scale(150);
    const int colType = Scale(130);

    // Column geometry shared by Details and Content views.
    auto columns = [&](int& xName, int& xMod, int& xType, int& xSize) {
        xName = pad;
        xMod = pad + nameCol;
        xType = xMod + colMod;
        xSize = xType + colType;
    };

    int y = 0;
    int xName = 0, xMod = 0, xType = 0, xSize = 0;
    columns(xName, xMod, xType, xSize);
    (void)xSize;

    switch (view_) {
        case ViewMode::Details: {
            if (IsComputerRoot()) {
                y = Scale(6);
            } else {
                y = Scale(kDetailsHeaderH);
            }
            const int rowH = Scale(kDetailsRowH);
            ComputerGroup lastGroup = ComputerGroup::None;
            for (size_t pos = 0; pos < display_.size(); ++pos) {
                const FileEntry& item = items_[display_[pos]];
                if (IsComputerRoot() && item.group != lastGroup) {
                    lastGroup = item.group;
                    std::wstring title;
                    if (item.group == ComputerGroup::HardDisk) title = L"Hard Disk Drives";
                    else if (item.group == ComputerGroup::RemovableOrOptical) title = L"Devices with Removable Storage";
                    else title = L"Network Locations & FTP Sites";
                    RECT rc = { pad, y, width - pad, y + Scale(26) };
                    groupHeaders_.push_back({ title, rc });
                    y += Scale(28);
                }
                RECT rc = { 0, y, width, y + rowH };
                itemRects_.push_back(rc);
                y += rowH;
            }
            break;
        }
        case ViewMode::Tiles: {
            const int cellW = Scale(210);
            const int cellH = Scale(58);
            const int perRow = std::max(1, (width - pad) / cellW);
            y = Scale(6);
            ComputerGroup lastGroup = ComputerGroup::None;
            size_t pos = 0;
            while (pos < display_.size()) {
                const FileEntry& first = items_[display_[pos]];
                if (IsComputerRoot() && first.group != lastGroup) {
                    lastGroup = first.group;
                    std::wstring title;
                    if (first.group == ComputerGroup::HardDisk) title = L"Hard Disk Drives";
                    else if (first.group == ComputerGroup::RemovableOrOptical) title = L"Devices with Removable Storage";
                    else title = L"Network Locations & FTP Sites";
                    RECT rc = { pad, y, width - pad, y + Scale(26) };
                    groupHeaders_.push_back({ title, rc });
                    y += Scale(28);
                }
                int countInRun = perRow;
                for (int i = 0; i < countInRun && pos < display_.size(); ++i, ++pos) {
                    RECT rc = { pad + i * cellW, y, pad + i * cellW + cellW - Scale(6), y + cellH };
                    itemRects_.push_back(rc);
                }
                y += cellH;
            }
            break;
        }
        case ViewMode::LargeIcons: {
            const int cellW = Scale(104);
            const int cellH = Scale(98);
            const int perRow = std::max(1, (width - pad) / cellW);
            y = Scale(6);
            ComputerGroup lastGroup = ComputerGroup::None;
            size_t pos = 0;
            while (pos < display_.size()) {
                const FileEntry& first = items_[display_[pos]];
                if (IsComputerRoot() && first.group != lastGroup) {
                    lastGroup = first.group;
                    std::wstring title;
                    if (first.group == ComputerGroup::HardDisk) title = L"Hard Disk Drives";
                    else if (first.group == ComputerGroup::RemovableOrOptical) title = L"Devices with Removable Storage";
                    else title = L"Network Locations & FTP Sites";
                    RECT rc = { pad, y, width - pad, y + Scale(26) };
                    groupHeaders_.push_back({ title, rc });
                    y += Scale(28);
                }
                int countInRun = perRow;
                for (int i = 0; i < countInRun && pos < display_.size(); ++i, ++pos) {
                    RECT rc = { pad + i * cellW, y, pad + i * cellW + cellW, y + cellH };
                    itemRects_.push_back(rc);
                }
                y += cellH;
            }
            break;
        }
        case ViewMode::List: {
            const int cellW = Scale(190);
            const int cellH = Scale(22);
            const int viewH = std::max(1, static_cast<int>(client.bottom));
            const int perCol = std::max(1, (viewH - Scale(10)) / cellH);
            const int cols = std::max(1, (width - pad) / cellW);
            for (size_t i = 0; i < display_.size(); ++i) {
                int col = static_cast<int>(i) / perCol;
                int row = static_cast<int>(i) % perCol;
                int cx = pad + col * cellW;
                int cy = Scale(4) + row * cellH;
                itemRects_.push_back(RECT{ cx, cy, cx + cellW - Scale(4), cy + cellH });
            }
            // Enough virtual height for the column that wraps past the viewport.
            const int usedCols = std::max(1, static_cast<int>((display_.size() + perCol - 1) / perCol));
            int extras = std::max(0, usedCols - cols);
            contentHeight_ = Scale(4) + (perCol + extras * perCol) * cellH + Scale(10);
            break;
        }
        case ViewMode::Content: {
            y = Scale(kDetailsHeaderH);
            const int rowH = Scale(42);
            for (size_t pos = 0; pos < display_.size(); ++pos) {
                RECT rc = { 0, y, width, y + rowH };
                itemRects_.push_back(rc);
                y += rowH;
            }
            break;
        }
    }

    contentHeight_ = y + Scale(10);
    for (size_t pos = 0; pos < itemRects_.size(); ++pos) {
        RECT rc = itemRects_[pos];
        rc.top -= scrollY_;
        rc.bottom -= scrollY_;
        items_[display_[pos]].hitRect = rc;
    }
}

void ExplorerApp::ScrollBy(int delta) {
    RECT client = {};
    GetClientRect(hCanvas_, &client);
    const int page = std::max(1, static_cast<int>(client.bottom));
    int maxScroll = std::max(0, contentHeight_ - page);
    int target = scrollY_ + delta;
    target = std::max(0, std::min(maxScroll, target));
    if (target == scrollY_) return;
    scrollY_ = target;
    RelayoutItems();
    UpdateScrollBar();
    InvalidateCanvas();
}

void ExplorerApp::EnsureVisible(int displayIndex) {
    if (displayIndex < 0 || displayIndex >= static_cast<int>(display_.size())) return;
    if (displayIndex >= static_cast<int>(itemRects_.size())) return;
    const FileEntry& item = items_[display_[displayIndex]];
    RECT client = {};
    GetClientRect(hCanvas_, &client);
    const int viewH = static_cast<int>(client.bottom);

    RECT logical = item.hitRect;
    logical.top += scrollY_;
    logical.bottom += scrollY_;

    if (logical.top < scrollY_ + Scale(4)) {
        ScrollBy(logical.top - scrollY_ - Scale(4));
    } else if (logical.bottom > scrollY_ + viewH - Scale(4)) {
        ScrollBy(logical.bottom - (scrollY_ + viewH - Scale(4)));
    }
}

// ---------------------------------------------------------------------------
// Main window chrome
// ---------------------------------------------------------------------------
void ExplorerApp::PaintChrome(HDC dc, const RECT& client) {
    const int w = client.right;
    const int h = client.bottom;
    BufDC buf;
    if (!buf.Begin(dc, w, h)) return;

    Graphics g(buf.dc);
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.SetPixelOffsetMode(PixelOffsetModeHalf);
    g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

    FontFamily uiFamily(L"Segoe UI");
    Font uiFont(&uiFamily, static_cast<REAL>(Scale(12)), FontStyleRegular, UnitPixel);
    Font boldFont(&uiFamily, static_cast<REAL>(Scale(12)), FontStyleBold, UnitPixel);
    Font smallFont(&uiFamily, static_cast<REAL>(Scale(11)), FontStyleRegular, UnitPixel);
    Font headerFont(&uiFamily, static_cast<REAL>(Scale(12)), FontStyleBold, UnitPixel);
    Font bigFont(&uiFamily, static_cast<REAL>(Scale(16)), FontStyleRegular, UnitPixel);

    // Base background (nav pane / middle band).
    FillSolid(g, RECT{ 0, 0, w, h }, Color(255, 255, 255, 255));

    // --- Navigation band -----------------------------------------------------
    theme::DrawAeroNavBand(g, RectF(0.0f, 0.0f, static_cast<REAL>(w), static_cast<REAL>(navBandRc_.bottom)));

    auto rectF = [](const RECT& r) {
        return RectF(static_cast<REAL>(r.left), static_cast<REAL>(r.top),
                     static_cast<REAL>(r.right - r.left), static_cast<REAL>(r.bottom - r.top));
    };

    bool canBack = historyPos_ > 0;
    bool canFwd = historyPos_ + 1 < static_cast<int>(history_.size());
    bool canUp = currentPath_ != L"computer://";

    struct OrbSpec { RECT rc; int id; int dir; bool enabled; };
    const OrbSpec orbs[] = {
        { backOrbRc_, 4001, 0, canBack },
        { fwdOrbRc_, 4002, 1, canFwd },
        { upOrbRc_, 4003, 2, canUp },
    };
    for (const auto& orb : orbs) {
        bool hover = (hotChromeId_ == orb.id);
        theme::DrawWin7NavOrb(g, rectF(orb.rc), orb.dir, orb.enabled, hover, false);
    }

    // --- Address bar (breadcrumbs + green progress) --------------------------
    bool addrHot = (hotChromeId_ == 4010);
    theme::DrawWin7GlassBox(g, rectF(addrBoxRc_), addrHot, addrEditActive_, AddressProgress());

    crumbHits_.clear();
    if (!addrEditActive_) {
        std::vector<BreadcrumbPart> crumbs = BuildBreadcrumbs(currentPath_);
        float x = static_cast<REAL>(addrBoxRc_.left) + static_cast<REAL>(Scale(6));
        float cy = static_cast<REAL>(addrBoxRc_.top) + static_cast<REAL>(Scale(11));
        const float maxX = static_cast<REAL>(addrBoxRc_.right) - static_cast<REAL>(Scale(8));

        SolidBrush textBrush(Color(255, 24, 45, 74));
        SolidBrush sepBrush(Color(255, 130, 150, 178));
        StringFormat sf;
        sf.SetLineAlignment(StringAlignmentCenter);
        sf.SetFormatFlags(StringFormatFlagsNoWrap);

        for (size_t i = 0; i < crumbs.size(); ++i) {
            const auto& part = crumbs[i];
            RectF measured;
            g.MeasureString(part.label.c_str(), -1, &uiFont, PointF(0, 0), &sf, &measured);
            float labelW = measured.Width;
            if (x + labelW > maxX) {
                // Truncate gracefully with an ellipsis.
                RectF box(x, cy - static_cast<REAL>(Scale(9)),
                          std::max(static_cast<REAL>(Scale(20)), maxX - x),
                          static_cast<REAL>(Scale(18)));
                DrawTextGp(g, part.label, &uiFont, box, Color(255, 24, 45, 74),
                           StringAlignmentNear, false, true);
                crumbHits_.push_back({ RECT{ static_cast<LONG>(box.X),
                                             static_cast<LONG>(addrBoxRc_.top),
                                             static_cast<LONG>(box.GetRight()),
                                             static_cast<LONG>(addrBoxRc_.bottom) },
                                      part.target });
                break;
            }

            RectF textRc(x, cy - static_cast<REAL>(Scale(9)), labelW + 4.0f, static_cast<REAL>(Scale(18)));
            g.DrawString(part.label.c_str(), -1, &uiFont, textRc, &sf, &textBrush);
            crumbHits_.push_back({ RECT{ static_cast<LONG>(x) - Scale(3),
                                         static_cast<LONG>(addrBoxRc_.top),
                                         static_cast<LONG>(x + labelW) + Scale(3),
                                         static_cast<LONG>(addrBoxRc_.bottom) },
                                  part.target });
            x += labelW + static_cast<REAL>(Scale(4));

            if (i + 1 < crumbs.size()) {
                // Windows 7 breadcrumb chevron separator
                PointF p1(x + 1.0f, cy - 3.5f);
                PointF p2(x + 4.5f, cy);
                PointF p3(x + 1.0f, cy + 3.5f);
                Pen sep(&sepBrush, 1.4f);
                g.DrawLine(&sep, p1, p2);
                g.DrawLine(&sep, p2, p3);
                x += static_cast<REAL>(Scale(11));
            }
        }
    }

    // --- Search box ---------------------------------------------------------
    bool searchHot = (hotChromeId_ == 4020);
    theme::DrawWin7GlassBox(g, rectF(searchBoxRc_), searchHot, false, 0);
    {
        float cx = static_cast<REAL>(searchBoxRc_.left) + static_cast<REAL>(Scale(11));
        float cy = static_cast<REAL>(searchBoxRc_.top) + static_cast<REAL>(Scale(11));
        float r = static_cast<REAL>(Scale(4));
        Pen magPen(Color(255, 96, 122, 152), 1.6f);
        g.DrawEllipse(&magPen, cx - r, cy - r - 1.0f, r * 2.0f, r * 2.0f);
        g.DrawLine(&magPen, cx + r * 0.7f, cy + r * 0.7f, cx + r * 1.7f, cy + r * 1.7f);
    }

    // --- Command bar --------------------------------------------------------
    theme::DrawWin7CommandBar(g, RectF(0.0f, static_cast<REAL>(cmdBarRc_.top),
                                       static_cast<REAL>(w),
                                       static_cast<REAL>(cmdBarRc_.bottom - cmdBarRc_.top)));
    for (const auto& hit : chromeHits_) {
        bool hover = (hotCmdId_ == hit.id);
        RECT rc = hit.rc;
        theme::DrawWin7ToolbarButtonBezel(g, rectF(rc), hover, false);

        std::wstring label;
        bool hasArrow = false;
        if (hit.id == kCmdOrganize) label = L"Organize";
        else if (hit.id == kCmdViewMenu) label = L"View";
        else if (hit.id == kCmdFtpMenu) label = L"FTP";
        else if (hit.id == kCmdNewFolderBtn) label = L"New folder";

        RectF textRc(static_cast<REAL>(rc.left) + static_cast<REAL>(Scale(10)),
                     static_cast<REAL>(rc.top),
                     static_cast<REAL>(rc.right - rc.left) - static_cast<REAL>(Scale(hasArrow ? 22 : 20)),
                     static_cast<REAL>(rc.bottom - rc.top));
        DrawTextGp(g, label, &uiFont, textRc, Color(255, 26, 46, 74), StringAlignmentNear);

        if (hasArrow) {
            float ax = static_cast<REAL>(rc.right) - static_cast<REAL>(Scale(11));
            float ay = static_cast<REAL>(rc.top) + static_cast<REAL>(Scale(11));
            PointF pts[3] = { PointF(ax - 3.5f, ay - 1.8f), PointF(ax + 3.5f, ay - 1.8f), PointF(ax, ay + 2.4f) };
            SolidBrush sb(Color(255, 40, 62, 92));
            g.FillPolygon(&sb, pts, 3);
        }
    }

    // "Include in library / Share with / Burn" dropdowns (Windows 7 look)
    {
        float bx = static_cast<REAL>(w) - static_cast<REAL>(Scale(196));
        float by = static_cast<REAL>(cmdBarRc_.top) + static_cast<REAL>(Scale(4));
        float bh = static_cast<REAL>(Scale(22));
        const wchar_t* rightLabels[] = { L"Include in library", L"Share with" };
        for (const wchar_t* lbl : rightLabels) {
            RectF measured;
            StringFormat mf;
            g.MeasureString(lbl, -1, &smallFont, PointF(0, 0), &mf, &measured);
            if (bx + measured.Width > static_cast<REAL>(w) - static_cast<REAL>(Scale(10))) break;
            DrawTextGp(g, lbl, &smallFont, RectF(bx, by, measured.Width + 2.0f, bh),
                       Color(255, 46, 70, 104), StringAlignmentNear);
            bx += measured.Width + static_cast<REAL>(Scale(18));
        }
    }

    // --- Left navigation pane background ------------------------------------
    FillSolid(g, RECT{ navPaneRc_.left, navPaneRc_.top, navPaneRc_.right, navPaneRc_.bottom },
              Color(255, 255, 255, 255));
    {
        RectF paneF = rectF(navPaneRc_);
        LinearGradientBrush paneBg(paneF, Color(255, 250, 252, 255), Color(255, 235, 242, 251), LinearGradientModeVertical);
        g.FillRectangle(&paneBg, paneF);
        Pen sep(Color(255, 205, 218, 235), 1.0f);
        g.DrawLine(&sep, static_cast<REAL>(navPaneRc_.right) - 1.0f, static_cast<REAL>(navPaneRc_.top),
                   static_cast<REAL>(navPaneRc_.right) - 1.0f, static_cast<REAL>(navPaneRc_.bottom));
    }


    // --- Details pane -------------------------------------------------------
    if (detailsRc_.bottom > detailsRc_.top) {
        RectF det = rectF(detailsRc_);
        LinearGradientBrush detBg(det, Color(255, 243, 248, 255), Color(255, 219, 232, 247), LinearGradientModeVertical);
        g.FillRectangle(&detBg, det);
        Pen detTop(Color(255, 178, 198, 222), 1.0f);
        g.DrawLine(&detTop, det.X, det.Y, det.GetRight(), det.Y);
        Pen detHi(Color(220, 255, 255, 255), 1.0f);
        g.DrawLine(&detHi, det.X, det.Y + 1.0f, det.GetRight(), det.Y + 1.0f);

        int selDisplay = -1;
        int selCount = 0;
        for (size_t pos = 0; pos < display_.size(); ++pos) {
            if (items_[display_[pos]].selected) {
                if (selDisplay < 0) selDisplay = static_cast<int>(pos);
                ++selCount;
            }
        }

        float detPad = static_cast<REAL>(Scale(12));
        float detTopF = static_cast<REAL>(detailsRc_.top) + static_cast<REAL>(Scale(9));
        float iconSize = static_cast<REAL>(Scale(48));

        if (selCount == 1 && selDisplay >= 0) {
            const FileEntry& item = items_[display_[selDisplay]];
            HICON big = item.iconLarge ? item.iconLarge : icons_.GetForVirtualFolder().iconLarge;
            if (big) {
                std::unique_ptr<Gdiplus::Bitmap> bigBmp(Gdiplus::Bitmap::FromHICON(big));
                if (bigBmp && bigBmp->GetLastStatus() == Ok) {
                    g.DrawImage(bigBmp.get(), RectF(detPad, detTopF, iconSize, iconSize));
                }
            }
            float textX = detPad + iconSize + static_cast<REAL>(Scale(14));
            DrawTextGp(g, item.displayName, &headerFont,
                       RectF(textX, detTopF - 2.0f, static_cast<REAL>(w) - textX - detPad,
                             static_cast<REAL>(Scale(20))),
                       Color(255, 20, 47, 82), StringAlignmentNear, false, true);

            std::wstring typeLine = item.typeName;
            if (item.isDrive && item.hasCapacity && item.totalBytes > 0) {
                double used = 1.0 - (static_cast<double>(item.freeBytes) / static_cast<double>(item.totalBytes));
                RectF bar(textX, detTopF + static_cast<REAL>(Scale(22)),
                          static_cast<REAL>(Scale(170)), static_cast<REAL>(Scale(11)));
                theme::DrawWin7DriveCapacityBar(g, bar, used);
                DrawTextGp(g, FormatDriveSpaceWin7(item.freeBytes, item.totalBytes), &smallFont,
                           RectF(bar.GetRight() + static_cast<REAL>(Scale(8)), bar.Y - 1.0f,
                                 static_cast<REAL>(w) - bar.GetRight() - static_cast<REAL>(Scale(20)),
                                 static_cast<REAL>(Scale(14))),
                           Color(255, 46, 70, 104), StringAlignmentNear, false, true);
                typeLine = item.typeName + L"   " + FormatBytesWin7(item.totalBytes);
            }

            DrawTextGp(g, typeLine, &smallFont,
                       RectF(textX, detTopF + static_cast<REAL>(Scale(38)),
                             static_cast<REAL>(w) / 2.0f, static_cast<REAL>(Scale(15))),
                       Color(255, 62, 86, 120), StringAlignmentNear, false, true);
            if (!item.modifiedText.empty()) {
                DrawTextGp(g, L"Date modified: " + item.modifiedText, &smallFont,
                           RectF(textX, detTopF + static_cast<REAL>(Scale(54)),
                                 static_cast<REAL>(w) / 2.0f, static_cast<REAL>(Scale(15))),
                           Color(255, 62, 86, 120), StringAlignmentNear, false, true);
            }
            if (!item.isFtpBookmark) {
                std::wstring loc = item.fullPath;
                DrawTextGp(g, loc, &smallFont,
                           RectF(textX, detTopF + static_cast<REAL>(Scale(70)),
                                 static_cast<REAL>(w) - textX - detPad, static_cast<REAL>(Scale(15))),
                           Color(255, 92, 112, 142), StringAlignmentNear, false, true);
            }
        } else if (selCount > 1) {
            uint64_t bytes = 0;
            for (const auto& item : items_) {
                if (item.selected && !item.isDirectory) bytes += item.sizeBytes;
            }
            DrawTextGp(g, std::to_wstring(selCount) + L" items selected", &bigFont,
                       RectF(detPad, detTopF, static_cast<REAL>(w) - detPad * 2, static_cast<REAL>(Scale(24))),
                       Color(255, 20, 47, 82), StringAlignmentNear, false, true);
            DrawTextGp(g, FormatBytesWin7(bytes), &smallFont,
                       RectF(detPad, detTopF + static_cast<REAL>(Scale(26)),
                             static_cast<REAL>(w) - detPad * 2, static_cast<REAL>(Scale(16))),
                       Color(255, 62, 86, 120), StringAlignmentNear);
        } else {
            std::wstring title = currentPath_ == L"computer://" ? L"Computer" : currentPath_;
            DrawTextGp(g, title, &bigFont,
                       RectF(detPad, detTopF, static_cast<REAL>(w) - detPad * 2, static_cast<REAL>(Scale(24))),
                       Color(255, 20, 47, 82), StringAlignmentNear, false, true);
            std::wstring line = CurrentIsFtp()
                                    ? L"FTP connection active - drag files here to upload"
                                    : L"Select an item to view details";
            DrawTextGp(g, line, &smallFont,
                       RectF(detPad, detTopF + static_cast<REAL>(Scale(27)),
                             static_cast<REAL>(w) - detPad * 2, static_cast<REAL>(Scale(16))),
                       Color(255, 62, 86, 120), StringAlignmentNear, false, true);
        }
        (void)detailsButton2ndRc_;
    }

    // --- Status bar ---------------------------------------------------------
    {
        RectF st = rectF(statusRc_);
        LinearGradientBrush stBg(st, Color(255, 240, 246, 253), Color(255, 220, 233, 247), LinearGradientModeVertical);
        g.FillRectangle(&stBg, st);
        Pen stTop(Color(255, 180, 200, 224), 1.0f);
        g.DrawLine(&stTop, st.X, st.Y, st.GetRight(), st.Y);

        DrawTextGp(g, StatusText(), &smallFont,
                   RectF(st.X + static_cast<REAL>(Scale(10)), st.Y,
                         st.Width * 0.62f, st.Height),
                   Color(255, 40, 64, 98), StringAlignmentNear, false, true);

        std::wstring right = CurrentIsFtp() ? L"FTP" : (currentPath_ == L"computer://" ? L"Computer" : L"Local");
        DrawTextGp(g, right, &smallFont,
                   RectF(st.GetRight() - static_cast<REAL>(Scale(120)), st.Y,
                         static_cast<REAL>(Scale(110)), st.Height),
                   Color(255, 40, 64, 98), StringAlignmentFar);
    }

    // --- Thick Aero frame line around the client ----------------------------
    Pen frame(Color(255, 160, 182, 210), 1.0f);
    g.DrawRectangle(&frame, 0, 0, w - 1, h - 1);

    buf.End(dc, w, h);
}

// ---------------------------------------------------------------------------
// File canvas painting
// ---------------------------------------------------------------------------
void ExplorerApp::PaintCanvas(HDC dc, const RECT& client) {
    const int w = static_cast<int>(client.right);
    const int h = static_cast<int>(client.bottom);
    if (w <= 0 || h <= 0) return;

    BufDC buf;
    if (!buf.Begin(dc, w, h)) return;

    Graphics g(buf.dc);
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.SetPixelOffsetMode(PixelOffsetModeHalf);
    g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

    FontFamily uiFamily(L"Segoe UI");
    Font uiFont(&uiFamily, static_cast<REAL>(Scale(12)), FontStyleRegular, UnitPixel);
    Font smallFont(&uiFamily, static_cast<REAL>(Scale(11)), FontStyleRegular, UnitPixel);
    Font boldFont(&uiFamily, static_cast<REAL>(Scale(12)), FontStyleBold, UnitPixel);
    Font headerFont(&uiFamily, static_cast<REAL>(Scale(12)), FontStyleBold, UnitPixel);

    // White canvas
    FillSolid(g, RECT{ 0, 0, w, h }, Color(255, 255, 255, 255));

    const int pad = Scale(8);
    const int nameCol = std::max(Scale(160), w - Scale(150 + 130 + 90) - pad * 2);
    const int colMod = Scale(150);
    const int colType = Scale(130);
    const int colSize = Scale(90);
    const int xName = pad;
    const int xMod = pad + nameCol;
    const int xType = xMod + colMod;
    const int xSize = xType + colType;

    // Column header strip for Details view.
    if (view_ == ViewMode::Details && !IsComputerRoot()) {
        RectF hdr(0, 0, static_cast<REAL>(w), static_cast<REAL>(Scale(kDetailsHeaderH)));
        LinearGradientBrush hdrBg(hdr, Color(255, 250, 252, 255), Color(255, 235, 242, 251), LinearGradientModeVertical);
        g.FillRectangle(&hdrBg, hdr);

        struct ColSpec { int x; int width; SortColumn col; };
        const ColSpec cols[] = {
            { xName, nameCol, SortColumn::Name },
            { xMod, colMod, SortColumn::DateModified },
            { xType, colType, SortColumn::Type },
            { xSize, colSize, SortColumn::Size },
        };
        for (const auto& c : cols) {
            if (c.x > w) continue;
            RectF textRc(static_cast<REAL>(c.x) + static_cast<REAL>(Scale(6)), 0,
                         static_cast<REAL>(std::min(c.width, w - c.x) - Scale(10)),
                         static_cast<REAL>(Scale(kDetailsHeaderH)));
            Color textColor = (sortCol_ == c.col) ? Color(255, 18, 52, 96) : Color(255, 52, 78, 112);
            DrawTextGp(g, ColumnHeaderLabel(c.col), &smallFont, textRc, textColor,
                       StringAlignmentNear, false, true);

            if (sortCol_ == c.col) {
                float ax = static_cast<REAL>(c.x) + static_cast<REAL>(Scale(6)) + 4.0f;
                HDC tmp = buf.dc;
                SIZE sz = {};
                HGDIOBJ old = SelectObject(tmp, hFontSmall_);
                GetTextExtentPoint32W(tmp, ColumnHeaderLabel(c.col).c_str(),
                                      static_cast<int>(ColumnHeaderLabel(c.col).size()), &sz);
                SelectObject(tmp, old);
                ax += static_cast<REAL>(sz.cx) + 6.0f;
                float ay = static_cast<REAL>(Scale(kDetailsHeaderH)) * 0.5f;
                PointF pts[3];
                if (sortAsc_) {
                    pts[0] = PointF(ax, ay + 2.0f);
                    pts[1] = PointF(ax + 7.0f, ay + 2.0f);
                    pts[2] = PointF(ax + 3.5f, ay - 3.0f);
                } else {
                    pts[0] = PointF(ax, ay - 3.0f);
                    pts[1] = PointF(ax + 7.0f, ay - 3.0f);
                    pts[2] = PointF(ax + 3.5f, ay + 2.0f);
                }
                SolidBrush arrow(Color(255, 40, 74, 120));
                g.FillPolygon(&arrow, pts, 3);
            }
            // Column separator
            Pen sep(Color(255, 208, 220, 236), 1.0f);
            if (c.col != SortColumn::Name) {
                g.DrawLine(&sep, static_cast<REAL>(c.x) - 2.0f, static_cast<REAL>(Scale(5)),
                           static_cast<REAL>(c.x) - 2.0f, static_cast<REAL>(Scale(kDetailsHeaderH) - 5));
            }
        }
        Pen hdrLine(Color(255, 186, 202, 222), 1.0f);
        g.DrawLine(&hdrLine, 0.0f, static_cast<REAL>(Scale(kDetailsHeaderH) - 1),
                   static_cast<REAL>(w), static_cast<REAL>(Scale(kDetailsHeaderH) - 1));
    }

    if (view_ == ViewMode::Content) {
        // Content view header line
        RectF hdr(0, 0, static_cast<REAL>(w), static_cast<REAL>(Scale(kDetailsHeaderH)));
        LinearGradientBrush hdrBg(hdr, Color(255, 250, 252, 255), Color(255, 235, 242, 251), LinearGradientModeVertical);
        g.FillRectangle(&hdrBg, hdr);
        DrawTextGp(g, L"Name", &headerFont,
                   RectF(static_cast<REAL>(Scale(34)), 0,
                         static_cast<REAL>(w) - Scale(200), static_cast<REAL>(Scale(kDetailsHeaderH))),
                   Color(255, 18, 52, 96), StringAlignmentNear);
        DrawTextGp(g, L"Date modified", &headerFont,
                   RectF(static_cast<REAL>(w) - static_cast<REAL>(Scale(300)), 0,
                         static_cast<REAL>(Scale(140)), static_cast<REAL>(Scale(kDetailsHeaderH))),
                   Color(255, 18, 52, 96), StringAlignmentNear);
        DrawTextGp(g, L"Size", &headerFont,
                   RectF(static_cast<REAL>(w) - static_cast<REAL>(Scale(150)), 0,
                         static_cast<REAL>(Scale(120)), static_cast<REAL>(Scale(kDetailsHeaderH))),
                   Color(255, 18, 52, 96), StringAlignmentNear);
    }

    // Group headers (Computer root).
    for (const auto& gh : groupHeaders_) {
        RECT r = gh.rc;
        r.top -= scrollY_;
        r.bottom -= scrollY_;
        if (r.bottom < 0 || r.top > h) continue;
        theme::DrawWin7GroupHeader(g,
                                   RectF(static_cast<REAL>(r.left), static_cast<REAL>(r.top),
                                         static_cast<REAL>(r.right - r.left), static_cast<REAL>(r.bottom - r.top)),
                                   gh.title, &headerFont);
    }

    // Clip drawing to the visible canvas rect (avoids drawing over header).
    const int clipTop = (view_ == ViewMode::Details && !IsComputerRoot()) ? Scale(kDetailsHeaderH)
                     : (view_ == ViewMode::Content ? Scale(kDetailsHeaderH) : 0);
    g.SetClip(RectF(0.0f, static_cast<REAL>(clipTop), static_cast<REAL>(w), static_cast<REAL>(h - clipTop)));

    if (display_.empty()) {
        std::wstring msg = navigating_
                               ? L"Connecting to the server..."
                               : (searchText_.empty() ? L"This folder is empty." :
                                                        L"No items match your search.");
        DrawTextGp(g, msg, &uiFont,
                   RectF(static_cast<REAL>(pad), static_cast<REAL>(clipTop) + static_cast<REAL>(Scale(24)),
                         static_cast<REAL>(w) - Scale(30), static_cast<REAL>(Scale(24))),
                   Color(255, 120, 138, 162), StringAlignmentNear);
    }

    for (size_t pos = 0; pos < display_.size() && pos < itemRects_.size(); ++pos) {
        const FileEntry& item = items_[display_[pos]];
        RECT r = itemRects_[pos];
        r.top -= scrollY_;
        r.bottom -= scrollY_;
        if (r.bottom < -Scale(20) || r.top > h + Scale(20)) continue;

        const bool selected = item.selected;
        const bool hovered = (hotItem_ == static_cast<int>(pos)) && !rubberBand_;
        RectF rf(static_cast<REAL>(r.left), static_cast<REAL>(r.top),
                 static_cast<REAL>(r.right - r.left), static_cast<REAL>(r.bottom - r.top));

        switch (view_) {
            case ViewMode::Details: {
                if (selected || hovered) {
                    theme::DrawWin7ItemSelection(g, rf, selected, hovered);
                }
                HICON icon = item.iconSmall;
                if (icon) {
                    std::unique_ptr<Gdiplus::Bitmap> bmp(Gdiplus::Bitmap::FromHICON(icon));
                    if (bmp && bmp->GetLastStatus() == Ok) {
                        g.DrawImage(bmp.get(),
                                    RectF(static_cast<REAL>(r.left) + static_cast<REAL>(Scale(6)),
                                          static_cast<REAL>(r.top) + static_cast<REAL>(Scale(3)),
                                          static_cast<REAL>(Scale(16)), static_cast<REAL>(Scale(16))));
                    }
                }
                float textLeft = static_cast<REAL>(r.left) + static_cast<REAL>(Scale(28));
                float textW = static_cast<REAL>(xMod) - textLeft - static_cast<REAL>(Scale(4));
                DrawTextGp(g, item.displayName, &uiFont,
                           RectF(textLeft, rf.Y, std::max(20.0f, textW), rf.Height),
                           Color(255, 22, 40, 66), StringAlignmentNear, false, true);
                DrawTextGp(g, item.modifiedText, &smallFont,
                           RectF(static_cast<REAL>(xMod) + static_cast<REAL>(Scale(6)), rf.Y,
                                 static_cast<REAL>(colMod) - Scale(12), rf.Height),
                           Color(255, 54, 76, 106), StringAlignmentNear, false, true);
                DrawTextGp(g, item.typeName, &smallFont,
                           RectF(static_cast<REAL>(xType) + static_cast<REAL>(Scale(6)), rf.Y,
                                 static_cast<REAL>(colType) - Scale(12), rf.Height),
                           Color(255, 54, 76, 106), StringAlignmentNear, false, true);
                std::wstring sizeText = item.isDrive || item.isDirectory ? L""
                                       : (item.isFtpItem && item.sizeBytes == 0 ? L"" : FormatBytesWin7(item.sizeBytes));
                DrawTextGp(g, sizeText, &smallFont,
                           RectF(static_cast<REAL>(xSize) + static_cast<REAL>(Scale(6)), rf.Y,
                                 static_cast<REAL>(colSize) - Scale(12), rf.Height),
                           Color(255, 54, 76, 106), StringAlignmentFar, false, true);
                break;
            }
            case ViewMode::Tiles: {
                if (selected || hovered) {
                    theme::DrawWin7ItemSelection(g, rf, selected, hovered);
                }
                HICON icon = item.iconLarge ? item.iconLarge : item.iconSmall;
                if (icon) {
                    std::unique_ptr<Gdiplus::Bitmap> bmp(Gdiplus::Bitmap::FromHICON(icon));
                    if (bmp && bmp->GetLastStatus() == Ok) {
                        g.DrawImage(bmp.get(),
                                    RectF(rf.X + static_cast<REAL>(Scale(6)),
                                          rf.Y + static_cast<REAL>(Scale(5)),
                                          static_cast<REAL>(Scale(48)), static_cast<REAL>(Scale(48))));
                    }
                }
                float textLeft = rf.X + static_cast<REAL>(Scale(60));
                float textW = rf.Width - static_cast<REAL>(Scale(64));
                DrawTextGp(g, item.displayName, &uiFont,
                           RectF(textLeft, rf.Y + static_cast<REAL>(Scale(3)),
                                 std::max(20.0f, textW), static_cast<REAL>(Scale(34))),
                           Color(255, 22, 40, 66), StringAlignmentNear, true);
                DrawTextGp(g, ItemSubtitle(item), &smallFont,
                           RectF(textLeft, rf.Y + static_cast<REAL>(Scale(36)),
                                 std::max(20.0f, textW), static_cast<REAL>(Scale(16))),
                           Color(255, 88, 108, 136), StringAlignmentNear, false, true);
                break;
            }
            case ViewMode::LargeIcons: {
                if (selected || hovered) {
                    theme::DrawWin7ItemSelection(g, rf, selected, hovered);
                }
                HICON icon = item.iconLarge ? item.iconLarge : item.iconSmall;
                if (icon) {
                    std::unique_ptr<Gdiplus::Bitmap> bmp(Gdiplus::Bitmap::FromHICON(icon));
                    if (bmp && bmp->GetLastStatus() == Ok) {
                        g.DrawImage(bmp.get(),
                                    RectF(rf.X + (rf.Width - static_cast<REAL>(Scale(48))) / 2.0f,
                                          rf.Y + static_cast<REAL>(Scale(6)),
                                          static_cast<REAL>(Scale(48)), static_cast<REAL>(Scale(48))));
                    }
                }
                DrawTextGp(g, item.displayName, &smallFont,
                           RectF(rf.X + static_cast<REAL>(Scale(4)),
                                 rf.Y + static_cast<REAL>(Scale(57)),
                                 rf.Width - static_cast<REAL>(Scale(8)),
                                 static_cast<REAL>(Scale(34))),
                           Color(255, 22, 40, 66), StringAlignmentCenter, true);
                break;
            }
            case ViewMode::List: {
                if (selected || hovered) {
                    theme::DrawWin7ItemSelection(g, rf, selected, hovered);
                }
                HICON icon = item.iconSmall;
                if (icon) {
                    std::unique_ptr<Gdiplus::Bitmap> bmp(Gdiplus::Bitmap::FromHICON(icon));
                    if (bmp && bmp->GetLastStatus() == Ok) {
                        g.DrawImage(bmp.get(),
                                    RectF(rf.X + static_cast<REAL>(Scale(5)),
                                          rf.Y + static_cast<REAL>(Scale(3)),
                                          static_cast<REAL>(Scale(16)), static_cast<REAL>(Scale(16))));
                    }
                }
                DrawTextGp(g, item.displayName, &uiFont,
                           RectF(rf.X + static_cast<REAL>(Scale(26)), rf.Y,
                                 rf.Width - static_cast<REAL>(Scale(30)), rf.Height),
                           Color(255, 22, 40, 66), StringAlignmentNear, false, true);
                break;
            }
            case ViewMode::Content: {
                if (selected || hovered) {
                    theme::DrawWin7ItemSelection(g, rf, selected, hovered);
                }
                HICON icon = item.iconLarge ? item.iconLarge : item.iconSmall;
                if (icon) {
                    std::unique_ptr<Gdiplus::Bitmap> bmp(Gdiplus::Bitmap::FromHICON(icon));
                    if (bmp && bmp->GetLastStatus() == Ok) {
                        g.DrawImage(bmp.get(),
                                    RectF(rf.X + static_cast<REAL>(Scale(8)),
                                          rf.Y + static_cast<REAL>(Scale(5)),
                                          static_cast<REAL>(Scale(32)), static_cast<REAL>(Scale(32))));
                    }
                }
                DrawTextGp(g, item.displayName, &uiFont,
                           RectF(rf.X + static_cast<REAL>(Scale(48)), rf.Y + static_cast<REAL>(Scale(4)),
                                 static_cast<REAL>(w) - Scale(380), static_cast<REAL>(Scale(18))),
                           Color(255, 22, 40, 66), StringAlignmentNear, false, true);
                DrawTextGp(g, ItemSubtitle(item), &smallFont,
                           RectF(rf.X + static_cast<REAL>(Scale(48)), rf.Y + static_cast<REAL>(Scale(22)),
                                 static_cast<REAL>(w) - Scale(380), static_cast<REAL>(Scale(16))),
                           Color(255, 88, 108, 136), StringAlignmentNear, false, true);
                DrawTextGp(g, item.modifiedText, &smallFont,
                           RectF(static_cast<REAL>(w) - Scale(300), rf.Y,
                                 static_cast<REAL>(Scale(140)), rf.Height),
                           Color(255, 54, 76, 106), StringAlignmentNear, false, true);
                DrawTextGp(g, item.isDirectory ? L"" : FormatBytesWin7(item.sizeBytes), &smallFont,
                           RectF(static_cast<REAL>(w) - Scale(150), rf.Y,
                                 static_cast<REAL>(Scale(120)), rf.Height),
                           Color(255, 54, 76, 106), StringAlignmentFar, false, true);
                break;
            }
        }
    }

    // Rubber-band selection
    if (rubberBand_ && (rubberRc_.right - rubberRc_.left) > 1) {
        RectF rb(static_cast<REAL>(rubberRc_.left), static_cast<REAL>(rubberRc_.top),
                 static_cast<REAL>(rubberRc_.right - rubberRc_.left),
                 static_cast<REAL>(rubberRc_.bottom - rubberRc_.top));
        SolidBrush rbFill(Color(48, 74, 160, 240));
        g.FillRectangle(&rbFill, rb);
        Pen rbPen(Color(255, 74, 160, 240), 1.0f);
        g.DrawRectangle(&rbPen, rb);
    }

    g.ResetClip();

    // Drop-target highlight (drag & drop upload/copy).
    if (dropHighlight_) {
        Pen dropPen(Color(255, 60, 160, 90), 2.0f);
        dropPen.SetDashStyle(DashStyleDash);
        g.DrawRectangle(&dropPen, 2.0f, 2.0f, static_cast<REAL>(w) - 4.0f, static_cast<REAL>(h) - 4.0f);
        SolidBrush band(Color(30, 60, 160, 90));
        g.FillRectangle(&band, RectF(0.0f, 0.0f, static_cast<REAL>(w), static_cast<REAL>(Scale(4))));
    }

    buf.End(dc, w, h);
}
