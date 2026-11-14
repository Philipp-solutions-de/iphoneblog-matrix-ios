#!/usr/bin/env python3
"""Render the asset catalog from brand/source and brand.env.

Run it after changing the logo or a colour, then commit App/Resources/Assets.xcassets.
Needs Pillow (pip install pillow).

  scripts/make-assets.py
"""

import json
import pathlib
import shlex

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "brand/source/logo-512.png"
CAT = ROOT / "App/Resources/Assets.xcassets"
INFO = {"author": "xcode", "version": 1}


def env():
    out = {}
    for line in (ROOT / "brand.env").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            k, _, v = line.partition("=")
            out[k] = shlex.split(v)[0]
    return out


def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2) + "\n")


def logo(size):
    return Image.open(SRC).convert("RGBA").resize((size, size), Image.LANCZOS)


def components(hex_color):
    c = hex_color.lstrip("#")
    return {"red": f"0x{c[0:2]}", "green": f"0x{c[2:4]}", "blue": f"0x{c[4:6]}", "alpha": "1.000"}


def color(name, light, dark=None):
    colors = [{"color": {"color-space": "srgb", "components": components(light)}, "idiom": "universal"}]
    if dark:
        colors.append({"appearances": [{"appearance": "luminosity", "value": "dark"}],
                       "color": {"color-space": "srgb", "components": components(dark)}, "idiom": "universal"})
    write(CAT / f"{name}.colorset/Contents.json", {"colors": colors, "info": INFO})


def main():
    e = env()
    write(CAT / "Contents.json", {"info": INFO})

    # App icon: white square, logo at 78 %, as on the blog's touch icon. iOS rounds the corners.
    icon = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255))
    icon.alpha_composite(logo(800), (112, 112))
    d = CAT / "AppIcon.appiconset"
    d.mkdir(parents=True, exist_ok=True)
    icon.convert("RGB").save(d / "AppIcon.png", optimize=True)
    write(d / "Contents.json", {"images": [{"filename": "AppIcon.png", "idiom": "universal",
                                            "platform": "ios", "size": "1024x1024"}], "info": INFO})

    # The logo on the sign-in screen, drawn at 112 pt.
    d = CAT / "Logo.imageset"
    images = []
    for scale in (1, 2, 3):
        name = f"logo@{scale}x.png"
        d.mkdir(parents=True, exist_ok=True)
        logo(112 * scale).save(d / name, optimize=True)
        images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})
    write(d / "Contents.json", {"images": images, "info": INFO})

    # Colours: teal dark enough for white text in light mode, light enough for black text in dark mode.
    color("AccentColor", e["BRAND_TEAL_TEXT"], e["BRAND_TEAL_ON_DARK"])
    color("BrandTeal", e["BRAND_TEAL_TEXT"], e["BRAND_TEAL_ON_DARK"])
    color("BrandCoral", e["BRAND_CORAL"], e["BRAND_CORAL"])
    color("Background", "#FAFAFA", "#111315")
    color("LaunchBackground", "#FFFFFF", "#111315")
    print("make-assets.py: done")


if __name__ == "__main__":
    main()
