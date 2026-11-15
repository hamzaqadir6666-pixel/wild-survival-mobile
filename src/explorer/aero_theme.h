#pragma once

#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <algorithm>
#include <cmath>
#include <string>

namespace aero {
namespace theme {

using Gdiplus::Color;
using Gdiplus::Font;
using Gdiplus::FontFamily;
using Gdiplus::Graphics;
using Gdiplus::GraphicsPath;
using Gdiplus::LinearGradientBrush;
using Gdiplus::Pen;
using Gdiplus::PointF;
using Gdiplus::RectF;
using Gdiplus::SolidBrush;
using Gdiplus::StringAlignment;
using Gdiplus::StringFormat;
using Gdiplus::StringTrimming;

inline void AeAddRoundedRect(GraphicsPath& path, const RectF& r, float radius) {
    if (radius <= 0.5f || r.Width <= 1.0f || r.Height <= 1.0f) {
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

// Top Windows 7 Aero Glass Navigation Band
inline void DrawAeroNavBand(Graphics& g, const RectF& rc) {
    LinearGradientBrush bg(
        PointF(rc.X, rc.Y),
        PointF(rc.X, rc.GetBottom()),
        Color(255, 221, 236, 252),
        Color(255, 207, 226, 247));
    g.FillRectangle(&bg, rc);

    // Subtle glass top highlight
    RectF topGlow(rc.X, rc.Y, rc.Width, rc.Height * 0.48f);
    LinearGradientBrush sheen(
        PointF(topGlow.X, topGlow.Y),
        PointF(topGlow.X, topGlow.GetBottom()),
        Color(145, 255, 255, 255),
        Color(15, 255, 255, 255));
    g.FillRectangle(&sheen, topGlow);

    Pen bottomBorder(Color(255, 164, 187, 214), 1.0f);
    g.DrawLine(&bottomBorder, rc.X, rc.GetBottom() - 1.0f, rc.GetRight(), rc.GetBottom() - 1.0f);
}

// Iconic Windows 7 Circular Back / Forward / Up Aero Glass Orb Button
// direction: 0 = back (left arrow), 1 = forward (right arrow), 2 = up
inline void DrawWin7NavOrb(Graphics& g, const RectF& rc, int direction, bool enabled, bool hovered, bool pressed) {
    g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);

    // Outer recessed capsule ring shadow
    RectF outerShadow = rc;
    outerShadow.Inflate(1.0f, 1.0f);
    SolidBrush ringShadow(Color(enabled ? 55 : 28, 18, 52, 96));
    g.FillEllipse(&ringShadow, outerShadow);

    if (enabled) {
        if (hovered && !pressed) {
            RectF glow = rc;
            glow.Inflate(2.5f, 2.5f);
            SolidBrush cyanBloom(Color(85, 92, 202, 255));
            g.FillEllipse(&cyanBloom, glow);
        }

        Color topCol = pressed ? Color(255, 29, 108, 186)
                     : hovered ? Color(255, 94, 188, 252)
                               : Color(255, 62, 152, 228);
        Color botCol = pressed ? Color(255, 16, 70, 138)
                     : hovered ? Color(255, 25, 108, 198)
                               : Color(255, 20, 88, 172);

        LinearGradientBrush fill(PointF(rc.X, rc.Y), PointF(rc.X, rc.GetBottom()), topCol, botCol);
        g.FillEllipse(&fill, rc);

        // Top-half curved glass specular reflection
        RectF spec(rc.X + rc.Width * 0.14f, rc.Y + rc.Height * 0.07f,
                   rc.Width * 0.72f, rc.Height * 0.44f);
        LinearGradientBrush specBrush(
            PointF(spec.X, spec.Y),
            PointF(spec.X, spec.GetBottom()),
            Color(pressed ? 95 : 185, 255, 255, 255),
            Color(10, 255, 255, 255));
        g.FillEllipse(&specBrush, spec);

        Pen rimOuter(Color(255, 15, 66, 132), 1.15f);
        g.DrawEllipse(&rimOuter, rc);

        RectF innerRim = rc;
        innerRim.Inflate(-1.1f, -1.1f);
        Pen rimInner(Color(125, 210, 242, 255), 1.0f);
        g.DrawEllipse(&rimInner, innerRim);
    } else {
        LinearGradientBrush disFill(
            PointF(rc.X, rc.Y),
            PointF(rc.X, rc.GetBottom()),
            Color(160, 232, 241, 251),
            Color(160, 198, 215, 235));
        g.FillEllipse(&disFill, rc);
        Pen disRim(Color(165, 152, 174, 198), 1.0f);
        g.DrawEllipse(&disRim, rc);
    }

    // Crisp arrow glyph inside the orb
    float cx = rc.X + rc.Width * 0.5f;
    float cy = rc.Y + rc.Height * 0.5f + (pressed ? 0.8f : 0.0f);
    float r = rc.Width * 0.24f;

    Color arrowCol = enabled ? Color(255, 255, 255, 255) : Color(170, 132, 152, 175);
    Pen arrowPen(arrowCol, std::max(2.0f, rc.Width * 0.095f));
    arrowPen.SetStartCap(Gdiplus::LineCapRound);
    arrowPen.SetEndCap(Gdiplus::LineCapRound);
    arrowPen.SetLineJoin(Gdiplus::LineJoinRound);

    if (direction == 2) {
        // Up arrow
        g.DrawLine(&arrowPen, cx, cy + r * 0.85f, cx, cy - r * 0.85f);
        PointF headUp[3] = {
            PointF(cx - r * 0.78f, cy - r * 0.10f),
            PointF(cx, cy - r * 0.90f),
            PointF(cx + r * 0.78f, cy - r * 0.10f)
        };
        g.DrawLines(&arrowPen, headUp, 3);
    } else {
        float dir = (direction == 0) ? -1.0f : 1.0f;
        g.DrawLine(&arrowPen, cx - dir * r * 0.85f, cy, cx + dir * r * 0.85f, cy);
        PointF head[3] = {
            PointF(cx + dir * r * 0.10f, cy - r * 0.78f),
            PointF(cx + dir * r * 0.90f, cy),
            PointF(cx + dir * r * 0.10f, cy + r * 0.78f)
        };
        g.DrawLines(&arrowPen, head, 3);
    }
}

// Windows 7 Sunken Glass Address/Search Box Frame (with optional Windows 7 Green Progress Fill!)
inline void DrawWin7GlassBox(Graphics& g, const RectF& rc, bool hovered, bool focused, int progressPct = 0) {
    GraphicsPath path;
    AeAddRoundedRect(path, rc, 2.5f);

    SolidBrush whiteBg(Color(246, 255, 255, 255));
    g.FillPath(&whiteBg, &path);

    if (progressPct > 0) {
        float fillW = std::clamp(rc.Width * (progressPct / 100.0f), 4.0f, rc.Width - 2.0f);
        RectF progRc(rc.X + 1.0f, rc.Y + 1.0f, fillW, rc.Height - 2.0f);
        LinearGradientBrush greenTop(
            PointF(progRc.X, progRc.Y),
            PointF(progRc.X, progRc.GetBottom()),
            Color(135, 146, 238, 166),
            Color(155, 62, 198, 92));
        g.FillRectangle(&greenTop, progRc);

        RectF glossRc(progRc.X, progRc.Y, progRc.Width, progRc.Height * 0.45f);
        SolidBrush gloss(Color(80, 255, 255, 255));
        g.FillRectangle(&gloss, glossRc);
    }

    // Inner top shadow for recessed feel
    Pen innerTop(Color(40, 20, 45, 80), 1.0f);
    g.DrawLine(&innerTop, rc.X + 2.0f, rc.Y + 1.0f, rc.GetRight() - 2.0f, rc.Y + 1.0f);

    Color borderCol = focused ? Color(255, 43, 122, 196)
                    : hovered ? Color(255, 86, 152, 212)
                              : Color(255, 138, 158, 182);
    Pen borderPen(borderCol, 1.0f);
    g.DrawPath(&borderPen, &path);
}

// Signature Windows 7 Glossy Two-Tone Command Bar
inline void DrawWin7CommandBar(Graphics& g, const RectF& rc) {
    float midY = rc.Y + std::floor(rc.Height * 0.48f);

    RectF upper(rc.X, rc.Y, rc.Width, midY - rc.Y);
    RectF lower(rc.X, midY, rc.Width, rc.GetBottom() - midY);

    LinearGradientBrush bUpper(
        PointF(upper.X, upper.Y),
        PointF(upper.X, upper.GetBottom()),
        Color(255, 247, 251, 255),
        Color(255, 229, 240, 252));
    LinearGradientBrush bLower(
        PointF(lower.X, lower.Y),
        PointF(lower.X, lower.GetBottom()),
        Color(255, 213, 230, 248),
        Color(255, 224, 238, 252));

    g.FillRectangle(&bUpper, upper);
    g.FillRectangle(&bLower, lower);

    // Top inner crisp white line & bottom steel-blue separator
    Pen topHi(Color(220, 255, 255, 255), 1.0f);
    g.DrawLine(&topHi, rc.X, rc.Y, rc.GetRight(), rc.Y);

    Pen botBorder(Color(255, 160, 181, 211), 1.0f);
    g.DrawLine(&botBorder, rc.X, rc.GetBottom() - 1.0f, rc.GetRight(), rc.GetBottom() - 1.0f);
}

// Raised Windows 7 Command Bar Hover / Pressed Button Bezel
inline void DrawWin7ToolbarButtonBezel(Graphics& g, const RectF& rc, bool hovered, bool pressed) {
    if (!hovered && !pressed) return;

    GraphicsPath path;
    AeAddRoundedRect(path, rc, 3.0f);

    LinearGradientBrush fill(
        PointF(rc.X, rc.Y),
        PointF(rc.X, rc.GetBottom()),
        pressed ? Color(210, 198, 222, 248) : Color(215, 244, 250, 255),
        pressed ? Color(210, 174, 206, 242) : Color(215, 209, 229, 251));
    g.FillPath(&fill, &path);

    RectF inner = rc;
    inner.Inflate(-1.0f, -1.0f);
    GraphicsPath innerPath;
    AeAddRoundedRect(innerPath, inner, 2.2f);
    Pen innerWhite(Color(pressed ? 90 : 200, 255, 255, 255), 1.0f);
    g.DrawPath(&innerWhite, &innerPath);

    Pen outerBorder(Color(255, 125, 162, 206), 1.0f);
    g.DrawPath(&outerBorder, &path);
}

// Signature Windows 7 Item Selection & Hover Rounded Rectangle
inline void DrawWin7ItemSelection(Graphics& g, const RectF& rc, bool selected, bool hovered) {
    if (!selected && !hovered) return;

    RectF box = rc;
    box.Width -= 1.0f;
    box.Height -= 1.0f;

    GraphicsPath path;
    AeAddRoundedRect(path, box, 2.5f);

    Color cTop = (selected && hovered) ? Color(255, 219, 237, 254)
               : selected              ? Color(255, 232, 243, 253)
                                       : Color(255, 244, 249, 254);
    Color cBot = (selected && hovered) ? Color(255, 184, 216, 251)
               : selected              ? Color(255, 199, 225, 252)
                                       : Color(255, 229, 241, 253);

    LinearGradientBrush fill(PointF(box.X, box.Y), PointF(box.X, box.GetBottom()), cTop, cBot);
    g.FillPath(&fill, &path);

    RectF inner = box;
    inner.Inflate(-1.0f, -1.0f);
    GraphicsPath innerPath;
    AeAddRoundedRect(innerPath, inner, 2.0f);
    Pen innerHi(Color(190, 255, 255, 255), 1.0f);
    g.DrawPath(&innerHi, &innerPath);

    Color borderCol = selected ? Color(255, 125, 162, 206) : Color(255, 184, 214, 251);
    Pen borderPen(borderCol, 1.0f);
    g.DrawPath(&borderPen, &path);
}

// Iconic Windows 7 Computer Drive Capacity Bar (Aqua-Blue or Warning Crimson)
inline void DrawWin7DriveCapacityBar(Graphics& g, const RectF& rc, double usedRatio) {
    usedRatio = std::clamp(usedRatio, 0.0, 1.0);

    // Sunken trough background
    LinearGradientBrush trough(
        PointF(rc.X, rc.Y),
        PointF(rc.X, rc.GetBottom()),
        Color(255, 224, 228, 234),
        Color(255, 244, 246, 249));
    g.FillRectangle(&trough, rc);

    // Glossy filled bar
    float fillW = static_cast<float>((rc.Width - 2.0f) * usedRatio);
    if (fillW > 1.0f) {
        RectF bar(rc.X + 1.0f, rc.Y + 1.0f, fillW, rc.Height - 2.0f);
        bool critical = (usedRatio >= 0.90);

        Color topCol = critical ? Color(255, 246, 108, 94) : Color(255, 74, 194, 242);
        Color botCol = critical ? Color(255, 188, 30, 20)  : Color(255, 20, 130, 188);

        LinearGradientBrush fill(PointF(bar.X, bar.Y), PointF(bar.X, bar.GetBottom()), topCol, botCol);
        g.FillRectangle(&fill, bar);

        // Top glass specular stripe
        RectF sheen(bar.X, bar.Y, bar.Width, bar.Height * 0.45f);
        LinearGradientBrush sheenBr(
            PointF(sheen.X, sheen.Y),
            PointF(sheen.X, sheen.GetBottom()),
            Color(145, 255, 255, 255),
            Color(25, 255, 255, 255));
        g.FillRectangle(&sheenBr, sheen);
    }

    Pen troughBorder(Color(255, 168, 178, 190), 1.0f);
    g.DrawRectangle(&troughBorder, rc.X, rc.Y, rc.Width - 1.0f, rc.Height - 1.0f);
}

// Windows 7 Computer Group Header ("Hard Disk Drives (2)" + horizontal rule)
inline void DrawWin7GroupHeader(Graphics& g, const RectF& rc, const std::wstring& title, Font* font) {
    SolidBrush titleBrush(Color(255, 30, 57, 91));
    StringFormat sf;
    sf.SetLineAlignment(StringAlignment::StringAlignmentCenter);
    sf.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);

    RectF measured;
    g.MeasureString(title.c_str(), -1, font, PointF(rc.X, rc.Y), &sf, &measured);

    RectF textRc(rc.X + 4.0f, rc.Y, measured.Width + 8.0f, rc.Height);
    g.DrawString(title.c_str(), -1, font, textRc, &sf, &titleBrush);

    float lineX = textRc.GetRight() + 4.0f;
    float lineY = rc.Y + rc.Height * 0.54f;
    if (lineX < rc.GetRight() - 8.0f) {
        LinearGradientBrush ruleBrush(
            PointF(lineX, lineY),
            PointF(rc.GetRight(), lineY),
            Color(255, 194, 214, 238),
            Color(40, 194, 214, 238));
        Pen rulePen(&ruleBrush, 1.0f);
        g.DrawLine(&rulePen, lineX, lineY, rc.GetRight() - 6.0f, lineY);
    }
}

// Bottom Windows 7 Details Pane Background
inline void DrawWin7DetailsPaneBg(Graphics& g, const RectF& rc) {
    LinearGradientBrush bg(
        PointF(rc.X, rc.Y),
        PointF(rc.X, rc.GetBottom()),
        Color(255, 241, 246, 253),
        Color(255, 218, 231, 246));
    g.FillRectangle(&bg, rc);

    Pen topGroove(Color(255, 182, 201, 224), 1.0f);
    g.DrawLine(&topGroove, rc.X, rc.Y, rc.GetRight(), rc.Y);

    Pen innerHi(Color(210, 255, 255, 255), 1.0f);
    g.DrawLine(&innerHi, rc.X, rc.Y + 1.0f, rc.GetRight(), rc.Y + 1.0f);
}

} // namespace theme
} // namespace aero
