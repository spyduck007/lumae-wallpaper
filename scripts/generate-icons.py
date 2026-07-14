#!/usr/bin/env python3
"""Generate Lumae's macOS app icon and menu-bar template assets.

The PNGs are committed to the asset catalog, so Pillow is only needed when
regenerating the artwork—not when building Lumae in Xcode.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Sources/LumaeApp/Resources/Assets.xcassets"
APP_ICON_DIR = ASSETS / "AppIcon.appiconset"
MENU_ICON_DIR = ASSETS / "MenuBarIcon.imageset"
MASTER_SIZE = 1024


def rounded_mask(size: int, inset: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1),
        radius=radius,
        fill=255,
    )
    return mask


def create_app_icon() -> Image.Image:
    """Create a quiet, minimal macOS icon with one memorable mark."""
    size = MASTER_SIZE
    inset = 48
    radius = 224
    icon_mask = rounded_mask(size, inset, radius)

    # Flat charcoal tile. Keeping the background uniform makes the icon read
    # clearly in the Dock, Finder, Spotlight, and the app switcher.
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile = Image.new("RGBA", (size, size), (27, 30, 36, 255))
    tile.putalpha(icon_mask)
    icon.alpha_composite(tile)

    draw = ImageDraw.Draw(icon)

    # A single rounded geometric L. The proportions deliberately mirror the
    # menu-bar mark while remaining bold enough at 16 px.
    stroke = 124
    x = 360
    top = 286
    bottom = 694
    right = 706
    white = (245, 247, 250, 255)
    draw.line(
        (x, top, x, bottom, right, bottom),
        fill=white,
        width=stroke,
        joint="curve",
    )
    cap = stroke // 2
    draw.ellipse((x - cap, top - cap, x + cap, top + cap), fill=white)
    draw.ellipse((right - cap, bottom - cap, right + cap, bottom + cap), fill=white)

    # One restrained accent is enough to suggest light without making the icon
    # busy. It is intentionally smaller than the previous sparkle.
    cx, cy = 704, 302
    long_arm = 66
    short_arm = 20
    accent = (150, 220, 255, 255)
    draw.polygon(
        [
            (cx, cy - long_arm),
            (cx + short_arm, cy - short_arm),
            (cx + long_arm, cy),
            (cx + short_arm, cy + short_arm),
            (cx, cy + long_arm),
            (cx - short_arm, cy + short_arm),
            (cx - long_arm, cy),
            (cx - short_arm, cy - short_arm),
        ],
        fill=accent,
    )

    # A very subtle inner keyline preserves the macOS tile edge on both light
    # and dark backgrounds without introducing another visual element.
    draw.rounded_rectangle(
        (inset + 4, inset + 4, size - inset - 5, size - inset - 5),
        radius=radius - 4,
        outline=(255, 255, 255, 22),
        width=4,
    )

    icon.putalpha(icon_mask)
    return icon


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
