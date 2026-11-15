#!/usr/bin/env python3
"""
Generates high-DPI multi-resolution Windows .ico files and Setup Wizard .bmp graphics
inspired by Windows 7 Aero Explorer iconography.
"""
import os
from PIL import Image, ImageDraw, ImageFilter


def lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(len(c1)))


def draw_vertical_gradient(img, box, top_color, bottom_color):
    x0, y0, x1, y1 = [int(v) for v in box]
    h = max(1, y1 - y0)
    px = img.load()
    w_img, h_img = img.size
    for y in range(max(0, y0), min(h_img, y1)):
        t = (y - y0) / float(h)
        col = lerp_color(top_color, bottom_color, t)
        for x in range(max(0, x0), min(w_img, x1)):
            px[x, y] = col


def composite_highlight_rounded(base, box, radius, alpha=90):
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(overlay).rounded_rectangle(box, radius=radius, fill=(255, 255, 255, alpha))
    return Image.alpha_composite(base, overlay)


def composite_highlight_ellipse(base, box, alpha=95):
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(overlay).ellipse(box, fill=(255, 255, 255, alpha))
    return Image.alpha_composite(base, overlay)


def render_explorer_master(size=512, variant="explorer"):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Drop shadow
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle(
        (int(size * 0.12), int(size * 0.18), int(size * 0.88), int(size * 0.89)),
        radius=int(size * 0.06),
        fill=(10, 28, 56, 115),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(size * 0.035)))
    img = Image.alpha_composite(img, shadow)

    # Back folder tab (rich warm amber-gold)
    back_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(back_layer)
    tab_poly = [
        (int(size * 0.12), int(size * 0.24)),
        (int(size * 0.12), int(size * 0.12)),
        (int(size * 0.42), int(size * 0.12)),
        (int(size * 0.49), int(size * 0.20)),
        (int(size * 0.86), int(size * 0.20)),
        (int(size * 0.86), int(size * 0.82)),
        (int(size * 0.12), int(size * 0.82)),
    ]
    bdraw.polygon(tab_poly, fill=(219, 158, 38, 255), outline=(162, 106, 14, 255))
    img = Image.alpha_composite(img, back_layer)

    # Inner crisp paper sheet peeking out
    paper = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(paper)
    pdraw.rounded_rectangle(
        (int(size * 0.18), int(size * 0.18), int(size * 0.81), int(size * 0.76)),
        radius=int(size * 0.03),
        fill=(246, 251, 255, 255),
        outline=(142, 184, 224, 255),
        width=max(2, size // 96),
    )
    for frac in (0.24, 0.30):
        y = int(size * frac)
        pdraw.line(
            (int(size * 0.24), y, int(size * 0.74), y),
            fill=(186, 214, 242, 255),
            width=max(2, size // 115),
        )
    img = Image.alpha_composite(img, paper)

    # Front glossy golden folder flap with gradient + proper alpha-composited glass sheen
    flap_box = (int(size * 0.10), int(size * 0.30), int(size * 0.88), int(size * 0.85))
    flap_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(flap_mask).rounded_rectangle(flap_box, radius=int(size * 0.055), fill=255)

    flap_grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_vertical_gradient(flap_grad, flap_box, (255, 232, 134, 255), (230, 162, 32, 255))
    flap_grad = composite_highlight_rounded(
        flap_grad,
        (int(size * 0.12), int(size * 0.315), int(size * 0.86), int(size * 0.50)),
        radius=int(size * 0.04),
        alpha=82,
    )
    flap_comp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    flap_comp.paste(flap_grad, (0, 0), flap_mask)
    ImageDraw.Draw(flap_comp).rounded_rectangle(
        flap_box,
        radius=int(size * 0.055),
        outline=(172, 112, 14, 255),
        width=max(3, size // 72),
    )
    img = Image.alpha_composite(img, flap_comp)

    # Iconic Windows 7 Explorer Blue Aero Clasp at bottom-center
    clasp_box = (int(size * 0.23), int(size * 0.63), int(size * 0.75), int(size * 0.87))
    clasp_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(clasp_mask).rounded_rectangle(clasp_box, radius=int(size * 0.045), fill=255)

    clasp_grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_vertical_gradient(clasp_grad, clasp_box, (66, 176, 248, 255), (16, 92, 180, 255))
    clasp_grad = composite_highlight_rounded(
        clasp_grad,
        (int(size * 0.25), int(size * 0.645), int(size * 0.73), int(size * 0.73)),
        radius=int(size * 0.03),
        alpha=90,
    )
    ImageDraw.Draw(clasp_grad).rounded_rectangle(
        (int(size * 0.36), int(size * 0.735), int(size * 0.62), int(size * 0.81)),
        radius=int(size * 0.02),
        fill=(244, 192, 72, 255),
        outline=(12, 68, 138, 255),
        width=max(2, size // 96),
    )
    clasp_comp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    clasp_comp.paste(clasp_grad, (0, 0), clasp_mask)
    ImageDraw.Draw(clasp_comp).rounded_rectangle(
        clasp_box,
        radius=int(size * 0.045),
        outline=(12, 68, 138, 255),
        width=max(3, size // 80),
    )
    img = Image.alpha_composite(img, clasp_comp)

    if variant == "explorer":
        gx0, gy0, gx1, gy1 = (
            int(size * 0.56),
            int(size * 0.12),
            int(size * 0.92),
            int(size * 0.48),
        )
        badge_mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(badge_mask).ellipse((gx0, gy0, gx1, gy1), fill=255)

        badge_grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw_vertical_gradient(
            badge_grad, (gx0, gy0, gx1, gy1), (86, 204, 255, 255), (12, 92, 188, 255)
        )
        lines_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ld = ImageDraw.Draw(lines_layer)
        cx, cy = (gx0 + gx1) // 2, (gy0 + gy1) // 2
        r = (gx1 - gx0) // 2
        lw = max(2, size // 95)
        ld.arc((cx - int(r * 0.55), gy0 + lw, cx + int(r * 0.55), gy1 - lw), 0, 360, fill=(230, 248, 255, 220), width=lw)
        ld.arc((gx0 + lw, cy - int(r * 0.45), gx1 - lw, cy + int(r * 0.45)), 0, 360, fill=(230, 248, 255, 180), width=lw)
        ld.line((gx0 + lw, cy, gx1 - lw, cy), fill=(230, 248, 255, 220), width=lw)
        ld.line((cx, gy0 + lw, cx, gy1 - lw), fill=(230, 248, 255, 220), width=lw)
        badge_grad = Image.alpha_composite(badge_grad, lines_layer)
        badge_grad = composite_highlight_ellipse(
            badge_grad,
            (gx0 + int(r * 0.20), gy0 + int(r * 0.08), gx1 - int(r * 0.20), cy - int(r * 0.05)),
            alpha=95,
        )
        badge_comp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        badge_comp.paste(badge_grad, (0, 0), badge_mask)
        ImageDraw.Draw(badge_comp).ellipse(
            (gx0, gy0, gx1, gy1), outline=(10, 58, 124, 255), width=max(3, size // 75)
        )
        img = Image.alpha_composite(img, badge_comp)

    elif variant == "setup":
        bx0, by0, bx1, by1 = (
            int(size * 0.53),
            int(size * 0.51),
            int(size * 0.93),
            int(size * 0.91),
        )
        bmask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(bmask).ellipse((bx0, by0, bx1, gy1 := by1), fill=255)
        bgrad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw_vertical_gradient(
            bgrad, (bx0, by0, bx1, by1), (86, 218, 104, 255), (18, 132, 44, 255)
        )
        cx, cy = (bx0 + bx1) // 2, (by0 + by1) // 2
        r = (bx1 - bx0) // 2
        bgrad = composite_highlight_ellipse(
            bgrad,
            (bx0 + int(r * 0.20), by0 + int(r * 0.08), bx1 - int(r * 0.20), cy - int(r * 0.05)),
            alpha=90,
        )
        arrow_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        arrow = [
            (cx - int(r * 0.21), cy - int(r * 0.44)),
            (cx + int(r * 0.21), cy - int(r * 0.44)),
            (cx + int(r * 0.21), cy + int(r * 0.02)),
            (cx + int(r * 0.46), cy + int(r * 0.02)),
            (cx, cy + int(r * 0.50)),
            (cx - int(r * 0.46), cy + int(r * 0.02)),
            (cx - int(r * 0.21), cy + int(r * 0.02)),
        ]
        ImageDraw.Draw(arrow_layer).polygon(arrow, fill=(255, 255, 255, 255))
        bgrad = Image.alpha_composite(bgrad, arrow_layer)

        bcomp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        bcomp.paste(bgrad, (0, 0), bmask)
        ImageDraw.Draw(bcomp).ellipse(
            (bx0, by0, bx1, by1), outline=(12, 88, 28, 255), width=max(3, size // 75)
        )
        img = Image.alpha_composite(img, bcomp)

    elif variant == "uninstall":
        bx0, by0, bx1, by1 = (
            int(size * 0.54),
            int(size * 0.52),
            int(size * 0.93),
            int(size * 0.91),
        )
        bmask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(bmask).ellipse((bx0, by0, bx1, by1), fill=255)
        bgrad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw_vertical_gradient(
            bgrad, (bx0, by0, bx1, by1), (246, 102, 90, 255), (182, 26, 20, 255)
        )
        cx, cy = (bx0 + bx1) // 2, (by0 + by1) // 2
        r = (bx1 - bx0) // 2
        bgrad = composite_highlight_ellipse(
            bgrad,
            (bx0 + int(r * 0.20), by0 + int(r * 0.08), bx1 - int(r * 0.20), cy - int(r * 0.05)),
            alpha=85,
        )
        xlayer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        xd = ImageDraw.Draw(xlayer)
        lw = max(4, int(r * 0.25))
        off = int(r * 0.34)
        xd.line((cx - off, cy - off, cx + off, cy + off), fill=(255, 255, 255, 255), width=lw)
        xd.line((cx - off, cy + off, cx + off, cy - off), fill=(255, 255, 255, 255), width=lw)
        bgrad = Image.alpha_composite(bgrad, xlayer)

        bcomp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        bcomp.paste(bgrad, (0, 0), bmask)
        ImageDraw.Draw(bcomp).ellipse(
            (bx0, by0, bx1, by1), outline=(124, 16, 12, 255), width=max(3, size // 75)
        )
        img = Image.alpha_composite(img, bcomp)

    return img


def save_ico_and_png(master_img, ico_path, png_path=None):
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (256, 256)]
    master_256 = master_img.resize((256, 256), Image.Resampling.LANCZOS)
    master_256.save(ico_path, format="ICO", sizes=sizes)
    if png_path:
        master_256.save(png_path, format="PNG")


def generate_wizard_graphics(explorer_master, assets_dir):
    w, h = 168, 314
    banner = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    draw_vertical_gradient(banner, (0, 0, w, h), (15, 76, 146, 255), (8, 34, 76, 255))

    aurora = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    adraw = ImageDraw.Draw(aurora)
    adraw.polygon([(0, 40), (w, 0), (w, 120), (0, 190)], fill=(76, 184, 255, 58))
    adraw.polygon([(0, 150), (w, 85), (w, 175), (0, 260)], fill=(120, 232, 216, 42))
    adraw.ellipse((-40, -30, 150, 150), fill=(135, 210, 255, 50))
    aurora = aurora.filter(ImageFilter.GaussianBlur(12))
    banner = Image.alpha_composite(banner, aurora)

    emblem = explorer_master.resize((108, 108), Image.Resampling.LANCZOS)
    banner.alpha_composite(emblem, ((w - 108) // 2, 34))

    line_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(line_layer).line((w - 1, 0, w - 1, h), fill=(128, 176, 224, 180), width=1)
    banner = Image.alpha_composite(banner, line_layer)
    banner.convert("RGB").save(os.path.join(assets_dir, "wizard_banner.bmp"), format="BMP")

    hdr = Image.new("RGBA", (48, 48), (255, 255, 255, 255))
    small = explorer_master.resize((44, 44), Image.Resampling.LANCZOS)
    hdr.alpha_composite(small, (2, 2))
    hdr.convert("RGB").save(os.path.join(assets_dir, "wizard_header.bmp"), format="BMP")


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assets_dir = os.path.join(repo_root, "assets")
    preview_dir = os.path.join(repo_root, "preview", "public")
    os.makedirs(assets_dir, exist_ok=True)
    os.makedirs(preview_dir, exist_ok=True)

    exp_master = render_explorer_master(512, "explorer")
    setup_master = render_explorer_master(512, "setup")
    uninst_master = render_explorer_master(512, "uninstall")

    save_ico_and_png(
        exp_master,
        os.path.join(assets_dir, "aero_explorer.ico"),
        os.path.join(preview_dir, "aero_explorer.png"),
    )
    save_ico_and_png(
        setup_master,
        os.path.join(assets_dir, "setup_icon.ico"),
        os.path.join(preview_dir, "setup_icon.png"),
    )
    save_ico_and_png(
        uninst_master,
        os.path.join(assets_dir, "uninstall_icon.ico"),
    )
    generate_wizard_graphics(exp_master, assets_dir)
    print("Generated icons & wizard graphics successfully.")


if __name__ == "__main__":
    main()
