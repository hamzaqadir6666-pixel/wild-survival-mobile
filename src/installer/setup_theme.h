#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0a00
#endif

#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <algorithm>
#include <string>

// Windows 7 (Aero) Setup Wizard visual language rendered with GDI+:
//   * transparent wizards are layered windows (UpdateLayeredWindow)
//   * classic resource wizards are drawn into the client DC.
namespace setup_theme {

using namespace Gdiplus;

constexpr int kBannerWidth = 168;
constexpr int kFooterHeight = 58;
constexpr int kHeaderHeight = 58;

struct WizardFonts {
    Font* title = nullptr;
    Font* subtitle = nullptr;
    Font* body = nullptr;
    Font* bodyBold = nullptr;
    Font* small = nullptr;
    Font* link = nullptr;
    FontFamily* family = nullptr;

    void Create(int dpi) {
        family = new FontFamily(L"Segoe UI");
        title = new Font(family, static_cast<REAL>(MulDiv(19, dpi, 96)), FontStyleRegular, UnitPixel);
        subtitle = new Font(family, static_cast<REAL>(MulDiv(13, dpi, 96)), FontStyleBold, UnitPixel);
        body = new Font(family, static_cast<REAL>(MulDiv(13, dpi, 96)), FontStyleRegular, UnitPixel);
        bodyBold = new Font(family, static_cast<REAL>(MulDiv(13, dpi, 96)), FontStyleBold, UnitPixel);
        small = new Font(family, static_cast<REAL>(MulDiv(11, dpi, 96)), FontStyleRegular, UnitPixel);
        link = new Font(family, static_cast<REAL>(MulDiv(12, dpi, 96)), FontStyleRegular, UnitPixel);
    }

    void Destroy() {
        delete title;
        delete subtitle;
        delete body;
        delete bodyBold;
        delete small;
        delete link;
        delete family;
        title = subtitle = body = bodyBold = small = link = nullptr;
        family = nullptr;
    }
};

inline void RoundedRect(GraphicsPath& path, const RectF& r, float radius) {
    if (radius <= 0.5f) {
        path.AddRectangle(r);
        return;
    }
    float d = std::min({ radius * 2.0f, r.Width, r.Height });
    path.AddArc(r.X, r.Y, d, d, 180.0f, 90.0f);
    path.AddArc(r.GetRight() - d, r.Y, d, d, 270.0f, 90.0f);
    path.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0.0f, 90.0f);
    path.AddArc(r.X, r.GetBottom() - d, d, d, 90.0f, 90.0f);
    path.CloseFigure();
}

inline void DrawText(Graphics& g, const std::wstring& text, Font* font, const RectF& rc,
                     Color color, StringAlignment align = StringAlignmentNear,
                     bool wrap = true, bool ellipsis = false) {
    SolidBrush brush(color);
    StringFormat sf;
    sf.SetAlignment(align);
    sf.SetLineAlignment(StringAlignmentNear);
    sf.SetTrimming(ellipsis ? StringTrimmingEllipsisCharacter : StringTrimmingNone);
    sf.SetFormatFlags(wrap ? 0 : StringFormatFlagsNoWrap);
    g.DrawString(text.c_str(), -1, font, rc, &sf, &brush);
}

// Faint vertical watermark printed down the banner (echoes the Windows 7 setup art)
inline void DrawBannerOverlay(Graphics& g, const RectF& banner, Font* tinyFont) {
    SolidBrush white(Color(150, 255, 255, 255));
    StringFormat sf;
    sf.SetFormatFlags(StringFormatFlagsNoWrap | StringFormatFlagsDirectionVertical);
    sf.SetAlignment(StringAlignmentCenter);
    RectF rc(banner.X, banner.Y + 20.0f, banner.Width, banner.Height - 40.0f);
    g.DrawString(L"W I N D O W S   7   A E R O   E X P L O R E R", -1, tinyFont, rc, &sf, &white);
}

// Windows 7 style wizard body: white page, banner on the left, footer strip and
// a subtle top highlight.
inline void PaintPageChrome(Graphics& g, const RectF& page, HDC dcForBits, HBITMAP banner,
                            HBITMAP headerArt, Font* tinyFont) {
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.SetPixelOffsetMode(PixelOffsetModeHalf);
    g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);

    // Page background
    LinearGradientBrush pageBg(
        PointF(page.X, page.Y + static_cast<REAL>(kBannerWidth) * 0.0f),
        PointF(page.X, page.GetBottom()),
        Color(255, 252, 253, 255),
        Color(255, 244, 248, 253));
    g.FillRectangle(&pageBg, page);

    // Left banner image
    if (banner) {
        Bitmap bmp(banner, nullptr);
        if (bmp.GetLastStatus() == Ok) {
            RectF dest(page.X, page.Y, static_cast<REAL>(kBannerWidth), page.Height);
            g.DrawImage(&bmp, dest);
            DrawBannerOverlay(g, dest, tinyFont);
        }
    }

    // Footer strip with the Windows 7 blue glass gradient
    RectF footer(page.X, page.GetBottom() - static_cast<REAL>(kFooterHeight),
                 page.Width, static_cast<REAL>(kFooterHeight));
    RectF footerUpper(footer.X, footer.Y, footer.Width, static_cast<REAL>(kFooterHeight) * 0.5f);
    RectF footerLower(footer.X, footerUpper.GetBottom(), footer.Width,
                      footer.GetBottom() - footerUpper.GetBottom());
    LinearGradientBrush fu(footerUpper, Color(255, 236, 244, 252), Color(255, 214, 230, 248), LinearGradientModeVertical);
    LinearGradientBrush fl(footerLower, Color(255, 200, 221, 244), Color(255, 214, 230, 248), LinearGradientModeVertical);
    g.FillRectangle(&fu, footerUpper);
    g.FillRectangle(&fl, footerLower);

    Pen footerTop(Color(255, 160, 186, 216), 1.0f);
    g.DrawLine(&footerTop, footer.X, footer.Y, footer.GetRight(), footer.Y);
    Pen footerHi(Color(210, 255, 255, 255), 1.0f);
    g.DrawLine(&footerHi, footer.X, footer.Y + 1.0f, footer.GetRight(), footer.Y + 1.0f);

    // small logo in the footer
    if (headerArt) {
        Bitmap logo(headerArt, nullptr);
        if (logo.GetLastStatus() == Ok) {
            g.DrawImage(&logo, RectF(footer.X + 10.0f, footer.Y + 6.0f,
                                     static_cast<REAL>(32), static_cast<REAL>(32)));
        }
    }
    (void)dcForBits;
}

// Windows 7 style group box / etched separator used under the page subtitle
inline void PaintSeparator(Graphics& g, float x, float y, float w) {
    Pen p1(Color(255, 202, 216, 234), 1.0f);
    g.DrawLine(&p1, x, y, x + w, y);
    Pen p2(Color(255, 255, 255, 255), 1.0f);
    g.DrawLine(&p2, x, y + 1.0f, x + w, y + 1.0f);
}

} // namespace setup_theme
