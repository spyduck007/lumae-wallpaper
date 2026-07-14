#!/usr/bin/env python3
"""Generate Lumae's macOS app icon and menu-bar template assets.

The PNGs are committed to the asset catalog, so Pillow is only needed when
regenerating the artwork—not when building Lumae in Xcode.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Sources/LumaeApp/Resources/Assets.xcassets"
APP_ICON_DIR = ASSETS / "AppIcon.appiconset"
MENU_ICON_DIR = ASSETS / "MenuBarIcon.imageset"
MASTER_SIZE = 1024


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def blend(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(lerp(a, b, t) for a, b in zip(c1, c2))


def rounded_mask(size: int, inset: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1),
        radius=radius,
        fill=255,
    )
    return mask


def radial_glow(
    size: int,
    center: tuple[float, float],
    radius: float,
    color: tuple[int, int, int],
    strength: int,
) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()
    cx, cy = center
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x - cx, y - cy)
            if distance >= radius:
                continue
            falloff = (1 - distance / radius) ** 2
            pixels[x, y] = (*color, round(strength * falloff))
    return image


def create_app_icon() -> Image.Image:
    size = MASTER_SIZE
    inset = 48
    radius = 224
    icon_mask = rounded_mask(size, inset, radius)

    # Diagonal midnight-to-violet base gradient.
    background = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = background.load()
    top_left = (10, 20, 46)
    bottom_right = (56, 21, 102)
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            r, g, b = blend(top_left, bottom_right, t)
            pixels[x, y] = (r, g, b, 255)
    background.putalpha(icon_mask)

    # Atmospheric glows suggest an illuminated desktop without adding tiny details.
    background.alpha_composite(
        radial_glow(size, (760, 230), 520, (91, 223, 255), 160)
    )
    background.alpha_composite(
        radial_glow(size, (270, 780), 620, (154, 83, 255), 150)
    )
    background.putalpha(icon_mask)

    # Subtle layered wallpaper panes.
    panes = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pane_draw = ImageDraw.Draw(panes)
    pane_specs = [
        ((190, 230, 790, 680), 55, (255, 255, 255, 20)),
        ((225, 265, 825, 715), 55, (255, 255, 255, 30)),
        ((260, 300, 860, 750), 55, (255, 255, 255, 42)),
    ]
    for box, pane_radius, fill in pane_specs:
        pane_draw.rounded_rectangle(box, radius=pane_radius, fill=fill)
        pane_draw.rounded_rectangle(
            box,
            radius=pane_radius,
            outline=(255, 255, 255, min(fill[3] + 18, 80)),
            width=4,
        )
    panes.putalpha(Image.composite(panes.getchannel("A"), Image.new("L", (size, size), 0), icon_mask))
    background.alpha_composite(panes)

    # Luminous geometric "L" mark.
    mark_mask = Image.new("L", (size, size), 0)
    mark_draw = ImageDraw.Draw(mark_mask)
    stroke = 112
    mark_draw.line((390, 300, 390, 660, 690, 660), fill=255, width=stroke, joint="curve")
    mark_draw.ellipse((390 - stroke // 2, 300 - stroke // 2, 390 + stroke // 2, 300 + stroke // 2), fill=255)
    mark_draw.ellipse((690 - stroke // 2, 660 - stroke // 2, 690 + stroke // 2, 660 + stroke // 2), fill=255)

    glow = Image.new("RGBA", (size, size), (88, 225, 255, 0))
    glow.putalpha(mark_mask.filter(ImageFilter.GaussianBlur(42)))
    background.alpha_composite(glow)

    mark_gradient = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mark_pixels = mark_gradient.load()
    cyan = (119, 238, 255)
    violet = (205, 143, 255)
    for y in range(size):
        for x in range(size):
            t = min(max((x + y - 500) / 700, 0), 1)
            r, g, b = blend(cyan, violet, t)
            mark_pixels[x, y] = (r, g, b, 255)
    mark_gradient.putalpha(mark_mask)
    background.alpha_composite(mark_gradient)

    # Bright four-point sparkle: readable even at 16 px.
    sparkle = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sparkle_draw = ImageDraw.Draw(sparkle)
    cx, cy = 706, 280
    sparkle_draw.polygon(
        [(cx, cy - 92), (cx + 24, cy - 24), (cx + 92, cy), (cx + 24, cy + 24),
         (cx, cy + 92), (cx - 24, cy + 24), (cx - 92, cy), (cx - 24, cy - 24)],
        fill=(246, 251, 255, 255),
    )
    sparkle_glow = sparkle.filter(ImageFilter.GaussianBlur(28))
    background.alpha_composite(sparkle_glow)
    background.alpha_composite(sparkle)

    # Gentle inner highlight and lower shadow for depth.
    detail = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    detail_draw = ImageDraw.Draw(detail)
    detail_draw.rounded_rectangle(
        (inset + 3, inset + 3, size - inset - 4, size - inset - 4),
        radius=radius - 3,
        outline=(255, 255, 255, 42),
        width=5,
    )
    lower_shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    lower_shadow_draw = ImageDraw.Draw(lower_shadow)
    lower_shadow_draw.rounded_rectangle(
        (inset + 12, inset + 25, size - inset - 13, size - inset - 5),
        radius=radius - 12,
        outline=(0, 0, 0, 72),
        width=12,
    )
    background.alpha_composite(lower_shadow)
    background.alpha_composite(detail)
    background.putalpha(icon_mask)
    return background


def create_menu_icon(size: int) -> Image.Image:
    # Exact-pixel template silhouette: a compact L plus one sparkle.
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    scale = size / 18
    stroke = max(2, round(2.2 * scale))

    def p(value: float) -> int:
        return round(value * scale)

    draw.line(
        (p(5.0), p(3.0), p(5.0), p(13.0), p(11.5), p(13.0)),
        fill=(0, 0, 0, 255),
        width=stroke,
        joint="curve",
    )
    r = stroke // 2
    draw.ellipse((p(5.0) - r, p(3.0) - r, p(5.0) + r, p(3.0) + r), fill=(0, 0, 0, 255))
    draw.ellipse((p(11.5) - r, p(13.0) - r, p(11.5) + r, p(13.0) + r), fill=(0, 0, 0, 255))

    cx, cy = p(12.8), p(5.1)
    long_arm = p(2.7)
    short_arm = p(0.9)
    draw.polygon(
        [(cx, cy - long_arm), (cx + short_arm, cy - short_arm),
         (cx + long_arm, cy), (cx + short_arm, cy + short_arm),
         (cx, cy + long_arm), (cx - short_arm, cy + short_arm),
         (cx - long_arm, cy), (cx - short_arm, cy - short_arm)],
        fill=(0, 0, 0, 255),
    )
    return image


def write_assets() -> None:
    APP_ICON_DIR.mkdir(parents=True, exist_ok=True)
    MENU_ICON_DIR.mkdir(parents=True, exist_ok=True)

    master = create_app_icon()
    master.save(APP_ICON_DIR / "AppIcon-1024.png", optimize=True)

    icon_specs = [
        (16, "1x", "AppIcon-16.png"),
        (16, "2x", "AppIcon-32.png"),
        (32, "1x", "AppIcon-32.png"),
        (32, "2x", "AppIcon-64.png"),
        (128, "1x", "AppIcon-128.png"),
        (128, "2x", "AppIcon-256.png"),
        (256, "1x", "AppIcon-256.png"),
        (256, "2x", "AppIcon-512.png"),
        (512, "1x", "AppIcon-512.png"),
        (512, "2x", "AppIcon-1024.png"),
    ]

    generated_sizes: set[int] = {1024}
    for logical_size, scale, filename in icon_specs:
        pixel_size = logical_size * int(scale[0])
        if pixel_size not in generated_sizes:
            master.resize((pixel_size, pixel_size), Image.Resampling.LANCZOS).save(
                APP_ICON_DIR / filename,
                optimize=True,
            )
            generated_sizes.add(pixel_size)

    app_contents = {
        "images": [
            {
                "filename": filename,
                "idiom": "mac",
                "scale": scale,
                "size": f"{logical_size}x{logical_size}",
            }
            for logical_size, scale, filename in icon_specs
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (APP_ICON_DIR / "Contents.json").write_text(json.dumps(app_contents, indent=2) + "\n")

    create_menu_icon(18).save(MENU_ICON_DIR / "MenuBarIcon.png", optimize=True)
    create_menu_icon(36).save(MENU_ICON_DIR / "MenuBarIcon@2x.png", optimize=True)
    menu_contents = {
        "images": [
            {
                "filename": "MenuBarIcon.png",
                "idiom": "mac",
                "scale": "1x",
            },
            {
                "filename": "MenuBarIcon@2x.png",
                "idiom": "mac",
                "scale": "2x",
            },
        ],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    }
    (MENU_ICON_DIR / "Contents.json").write_text(json.dumps(menu_contents, indent=2) + "\n")


if __name__ == "__main__":
    write_assets()
    print(f"Generated {APP_ICON_DIR.relative_to(ROOT)}")
    print(f"Generated {MENU_ICON_DIR.relative_to(ROOT)}")
