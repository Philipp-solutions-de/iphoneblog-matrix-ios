#!/usr/bin/env python3
"""Render the app's images from brand/source into overlay/.

Run it after changing the logo or the brand colours, then commit overlay/.
Needs Pillow (pip install pillow).

  scripts/make-assets.py
"""

import json
import pathlib
import shlex

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "brand/source/logo-512.png"
RES = ROOT / "overlay/ElementX/Resources"
IMAGES = RES / "Assets.xcassets/images"


def env():
    out = {}
    for line in (ROOT / "brand.env").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            k, _, v = line.partition("=")
            out[k] = shlex.split(v)[0]
    return out


def rgb(hex_color):
    c = hex_color.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def logo(size):
    return Image.open(SRC).convert("RGBA").resize((size, size), Image.LANCZOS)


def app_icon():
    # White square, logo at 78 %, as on the blog's touch icon. iOS rounds the corners.
    icon = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255))
    mark = logo(800)
    icon.alpha_composite(mark, (112, 112))
    out = RES / "AppIcon.icon/Assets/AppIcon.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    icon.convert("RGB").save(out, optimize=True)
    (RES / "AppIcon.icon/icon.json").write_text(json.dumps({
        "fill": "automatic",
        "groups": [{
            "layers": [{"glass": False, "image-name": "AppIcon.png", "name": "AppIcon"}],
            "name": "Background",
            "shadow": {"kind": "none", "opacity": 0.5},
            "specular": False,
            "translucency": {"enabled": False, "value": 0.5},
        }],
        "supported-platforms": {"squares": "shared"},
    }, indent=2) + "\n")


def app_logo():
    # The start screen draws the logo at 110 pt inside a rounded card.
    d = IMAGES / "app-logo.imageset"
    d.mkdir(parents=True, exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        name = f"app-logo@{scale}x.png"
        logo(110 * scale).save(d / name, optimize=True)
        images.append({"filename": name, "idiom": "universal", "scale": f"{scale}x"})
    (d / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def gradient(size, color, top_alpha, bottom_alpha, base):
    """A vertical fade from the brand colour into the page background."""
    w, h = size
    img = Image.new("RGBA", size, base + (255,))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        a = top_alpha + (bottom_alpha - top_alpha) * (t ** 1.4)
        r, g, b = (int(base[i] + (color[i] - base[i]) * a) for i in range(3))
        draw.line([(0, y), (w, y)], fill=(r, g, b, 255))
    return img


def backgrounds(e):
    brand = rgb(e["BRAND_COLOR"])
    white, black = (255, 255, 255), (16, 18, 20)

    d = IMAGES / "launch-background.imageset"
    d.mkdir(parents=True, exist_ok=True)
    files = {
        "iphone-light.png": gradient((377, 838), brand, 0.55, 0.0, white),
        "iphone-dark.png": gradient((377, 838), brand, 0.45, 0.0, black),
        "ipad-light.png": gradient((1024, 1366), brand, 0.55, 0.0, white),
        "ipad-dark.png": gradient((1024, 1366), brand, 0.45, 0.0, black),
    }
    for name, img in files.items():
        img.save(d / name, optimize=True)
    (d / "Contents.json").write_text(json.dumps({
        "images": [
            {"filename": "ipad-light.png", "idiom": "universal"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "ipad-dark.png", "idiom": "universal"},
            {"filename": "iphone-light.png", "idiom": "iphone"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "iphone-dark.png", "idiom": "iphone"},
        ],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")

    d = IMAGES / "background-bottom.imageset"
    d.mkdir(parents=True, exist_ok=True)
    gradient((393, 250), brand, 0.0, 0.35, white).save(d / "background-bottom-light.png", optimize=True)
    gradient((393, 250), brand, 0.0, 0.30, black).save(d / "background-bottom-dark.png", optimize=True)
    (d / "Contents.json").write_text(json.dumps({
        "images": [
            {"filename": "background-bottom-light.png", "idiom": "universal"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "background-bottom-dark.png", "idiom": "universal"},
        ],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


if __name__ == "__main__":
    e = env()
    app_icon()
    app_logo()
    backgrounds(e)
    print("make-assets.py: done")
