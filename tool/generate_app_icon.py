"""產生「智慧水杯」App 圖示，並寫入各平台的圖示檔。

用法（在專案根目錄）：
    python tool/generate_app_icon.py

需要 Pillow（只有產生圖示時才需要，不是 App 的相依套件）：
    pip install pillow==11.3.0

圖示內容：青綠色漸層底、白色水杯、杯內的水與上方一滴水。
顏色取自 lib/ui/theme.dart 的 AppColors.teal。
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
MASTER = 2048  # 先畫大圖再縮小，邊緣才會平滑

BG_TOP = (30, 176, 167)
BG_BOTTOM = (9, 104, 99)
WATER_TOP = (52, 196, 186)
WATER_BOTTOM = (14, 138, 132)  # AppColors.teal
WHITE = (255, 255, 255)

ANDROID_DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
WINDOWS_ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    ramp = Image.linear_gradient("L").resize((size, size))
    return Image.composite(Image.new("RGB", (size, size), bottom), Image.new("RGB", (size, size), top), ramp)


def soften(mask: Image.Image, radius: float) -> Image.Image:
    """把多邊形的尖角變圓：模糊後再取門檻。"""
    blurred = mask.filter(ImageFilter.GaussianBlur(radius))
    return blurred.point(lambda v: 255 if v >= 128 else 0)


def glyph_masks(size: int, height_frac: float) -> tuple[Image.Image, Image.Image]:
    """回傳 (白色部分, 水的部分) 兩張遮罩；圖案高度為畫布的 height_frac。"""
    h = size * height_frac
    cx = size / 2
    top = (size - h) / 2

    cup_top, cup_bottom = top + 0.30 * h, top + h
    half_top, half_bottom = 0.36 * h, 0.27 * h

    def half_width(y: float) -> float:
        t = (y - cup_top) / (cup_bottom - cup_top)
        return half_top + (half_bottom - half_top) * t

    cup = Image.new("L", (size, size), 0)
    ImageDraw.Draw(cup).polygon(
        [
            (cx - half_top, cup_top),
            (cx + half_top, cup_top),
            (cx + half_bottom, cup_bottom),
            (cx - half_bottom, cup_bottom),
        ],
        fill=255,
    )
    cup = soften(cup, 0.035 * h)

    drop_cy, drop_r = top + 0.155 * h, 0.082 * h
    theta = math.acos(drop_r / (drop_cy - top))
    drop = Image.new("L", (size, size), 0)
    drop_draw = ImageDraw.Draw(drop)
    drop_draw.ellipse([cx - drop_r, drop_cy - drop_r, cx + drop_r, drop_cy + drop_r], fill=255)
    drop_draw.polygon(
        [
            (cx, top),
            (cx + drop_r * math.sin(theta), drop_cy - drop_r * math.cos(theta)),
            (cx - drop_r * math.sin(theta), drop_cy - drop_r * math.cos(theta)),
        ],
        fill=255,
    )
    drop = soften(drop, 0.010 * h)

    wall = 0.07 * h
    water_top, water_bottom = top + 0.58 * h, cup_bottom - 0.075 * h
    amplitude = 0.024 * h
    left, right = cx - (half_width(water_top) - wall), cx + (half_width(water_top) - wall)
    steps = 64
    wave = [
        (left + (right - left) * i / steps, water_top + amplitude * math.sin(2 * math.pi * i / steps))
        for i in range(steps + 1)
    ]
    water = Image.new("L", (size, size), 0)
    ImageDraw.Draw(water).polygon(
        wave
        + [
            (cx + half_width(water_bottom) - wall, water_bottom),
            (cx - (half_width(water_bottom) - wall), water_bottom),
        ],
        fill=255,
    )
    water = soften(water, 0.022 * h)

    return ImageChops.lighter(cup, drop), water


def render_glyph(base: Image.Image, height_frac: float) -> Image.Image:
    size = base.size[0]
    white, water = glyph_masks(size, height_frac)
    out = base.copy()
    out.paste(Image.new("RGBA", (size, size), WHITE + (255,)), (0, 0), white)
    out.paste(vertical_gradient(size, WATER_TOP, WATER_BOTTOM).convert("RGBA"), (0, 0), water)
    return out


def rounded_mask(size: int, inset_frac: float, radius_frac: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    inset = size * inset_frac
    side = size - 2 * inset
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, size - inset, size - inset], radius=side * radius_frac, fill=255
    )
    return mask


def build_masters() -> dict[str, Image.Image]:
    background = vertical_gradient(MASTER, BG_TOP, BG_BOTTOM).convert("RGBA")
    transparent = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))

    square = render_glyph(background, 0.60)

    rounded = square.copy()
    rounded.putalpha(rounded_mask(MASTER, 0.0, 0.22))

    # macOS 慣例：圓角方塊四周留白。
    mac_inner = int(MASTER * 0.82)
    mac = transparent.copy()
    mac_tile = square.resize((mac_inner, mac_inner), Image.LANCZOS)
    mac_tile.putalpha(rounded_mask(mac_inner, 0.0, 0.225))
    mac.paste(mac_tile, ((MASTER - mac_inner) // 2,) * 2, mac_tile)

    # Android adaptive icon：圖案要落在中央 66/108 的安全區內。
    white, water = glyph_masks(MASTER, 0.42)
    mono = Image.new("RGBA", (MASTER, MASTER), WHITE + (0,))
    mono.putalpha(ImageChops.subtract(white, water))

    return {
        "square": square,
        "rounded": rounded,
        "mac": mac,
        "background": background,
        "foreground": render_glyph(transparent, 0.42),
        "monochrome": mono,
        # Web maskable：安全區是中央 80% 的圓。
        "maskable": render_glyph(background, 0.50),
    }


def save(image: Image.Image, relative: str, size: int, *, opaque: bool = False) -> None:
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.LANCZOS)
    if opaque:
        resized = resized.convert("RGB")
    resized.save(path, optimize=True)
    print(f"  {relative} ({size}x{size})")


def main() -> int:
    masters = build_masters()

    print("Android")
    for density, scale in ANDROID_DENSITIES.items():
        folder = f"android/app/src/main/res/mipmap-{density}"
        save(masters["rounded"], f"{folder}/ic_launcher.png", round(48 * scale))
        for layer in ("foreground", "background", "monochrome"):
            save(masters[layer], f"{folder}/ic_launcher_{layer}.png", round(108 * scale), opaque=layer == "background")

    print("iOS")
    ios_dir = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for existing in sorted(ios_dir.glob("Icon-App-*.png")):
        with Image.open(existing) as current:
            size = current.size[0]
        # iOS 圖示不可有透明度，圓角由系統裁切。
        save(masters["square"], existing.relative_to(ROOT).as_posix(), size, opaque=True)

    print("macOS")
    for size in MACOS_SIZES:
        save(masters["mac"], f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png", size)

    print("Windows")
    ico_path = ROOT / "windows/runner/resources/app_icon.ico"
    masters["rounded"].resize((256, 256), Image.LANCZOS).save(
        ico_path, format="ICO", sizes=[(s, s) for s in WINDOWS_ICO_SIZES]
    )
    print(f"  {ico_path.relative_to(ROOT).as_posix()} {WINDOWS_ICO_SIZES}")

    print("Web")
    save(masters["rounded"], "web/favicon.png", 32)
    for size in (192, 512):
        save(masters["square"], f"web/icons/Icon-{size}.png", size, opaque=True)
        save(masters["maskable"], f"web/icons/Icon-maskable-{size}.png", size)

    return 0


if __name__ == "__main__":
    sys.exit(main())
