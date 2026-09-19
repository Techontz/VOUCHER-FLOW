#!/usr/bin/env python3
"""Draws the VouchFlow app icon and writes every size Android and iOS need.

    python3 tool/app_icon.py          # from the app/ directory

The mark is the web client's white V on the accent gradient, with its right
arm carried up past the top of the V so it also reads as a tick: VouchFlow,
and approved. One round-capped stroke, so it survives a 48px launcher.

Nothing here is generated at build time — the PNGs are committed. Run this
again only when the mark or the palette changes.

Requires Pillow (pip3 install Pillow); it is not a dependency of the app.
"""

from pathlib import Path

from PIL import Image, ImageDraw

# The accent gradient, matching VfColors.gradient and the web's brand blue.
STOPS = [(0.0, (0x2F, 0x7B, 0xF6)), (0.55, (0x22, 0xA7, 0xE8)), (1.0, (0x22, 0xD3, 0xEE))]

# The mark, on a 1024 grid: left arm down to the vertex, then up and past it.
MARK_POINTS = [(288, 300), (470, 690), (748, 232)]
MARK_WIDTH = 112

# Supersampling factor for every shape we draw.
SS = 4

ROOT = Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android/app/src/main/res"
IOS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

# Android buckets, as multiples of the baseline density.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

# iOS, from the set's Contents.json: filename -> pixel size.
IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def gradient(size: int) -> Image.Image:
    """The accent gradient, corner to corner."""
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1)) if size > 1 else 0
            for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
                if t0 <= t <= t1:
                    k = (t - t0) / (t1 - t0)
                    pixels[x, y] = tuple(round(c0[i] + (c1[i] - c0[i]) * k) for i in range(3))
                    break
    return image


def mark_layer(size: int, scale: float) -> Image.Image:
    """The white mark on a transparent square, drawn large and reduced."""
    canvas = size * SS
    layer = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    k = canvas / 1024 * scale
    offset = (canvas - 1024 * k) / 2
    points = [(x * k + offset, y * k + offset) for x, y in MARK_POINTS]
    width = max(2, round(MARK_WIDTH * k))

    # Round caps and joins: segments, then a disc at every vertex.
    for start, end in zip(points, points[1:]):
        draw.line([start, end], fill=(255, 255, 255, 255), width=width)
    for x, y in points:
        r = width / 2
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 255))

    return layer.resize((size, size), Image.LANCZOS)


def rounded_mask(size: int, ratio: float = 0.2234) -> Image.Image:
    """The legacy Android launcher shape; iOS and adaptive icons mask their own."""
    canvas = size * SS
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, canvas - 1, canvas - 1], radius=canvas * ratio, fill=255
    )
    return mask.resize((size, size), Image.LANCZOS)


def square(size: int, scale: float = 0.98) -> Image.Image:
    """Full-bleed icon: gradient with the mark on it."""
    image = gradient(size).convert("RGBA")
    image.alpha_composite(mark_layer(size, scale))
    return image


def write(image: Image.Image, path: Path, *, alpha: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGBA" if alpha else "RGB").save(path)
    print(f"  {path.relative_to(ROOT)}  {image.size[0]}px")


def main() -> None:
    print("iOS")
    for name, size in IOS_SIZES.items():
        # No alpha channel anywhere in an iOS app icon; the App Store refuses it.
        write(square(size), IOS / name, alpha=False)

    print("Android — legacy launcher icons")
    for bucket, factor in DENSITIES.items():
        size = round(48 * factor)
        icon = square(size)
        icon.putalpha(rounded_mask(size))
        write(icon, ANDROID / f"mipmap-{bucket}/ic_launcher.png", alpha=True)

    print("Android — adaptive icon layers (108dp canvas, mark inside the 72dp safe zone)")
    for bucket, factor in DENSITIES.items():
        size = round(108 * factor)
        write(gradient(size), ANDROID / f"mipmap-{bucket}/ic_launcher_background.png", alpha=False)
        foreground = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        # 0.667 keeps the mark the same visual size as on the legacy icon once
        # the launcher has masked the outer third away.
        foreground.alpha_composite(mark_layer(size, 0.98 * 0.667))
        write(foreground, ANDROID / f"mipmap-{bucket}/ic_launcher_foreground.png", alpha=True)

    print("Store artwork")
    write(square(1024), ROOT / "assets/brand/app-icon-1024.png", alpha=False)


if __name__ == "__main__":
    main()
