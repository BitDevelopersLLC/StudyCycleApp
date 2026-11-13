#!/usr/bin/env python3
"""Make every store and website image for Study Cycle from the raw screenshots and the icon.

Usage:
    python tools/store_graphics.py icons     app icon sources + Android notification icon, from the logo
    python tools/store_graphics.py android   Google Play: framed screenshots, feature graphic, icon
    python tools/store_graphics.py iphone    App Store: framed iPhone 6.9" and 6.3" screenshots, icon
    python tools/store_graphics.py ipad      App Store: framed iPad 13" screenshots
    python tools/store_graphics.py website   studycycle.app: phone images, social card, favicons
    python tools/store_graphics.py all       all of the above (skips raw shots that don't exist)

Inputs (private, not in git; see docs/store-media.md):
    media/brand/Study-Cycle-Logo-2000x2000.png   the Study Cycle logo (owl in the cycle ring), 2023
    media/icon/icon-master.png                   1024 x 1024 icon, no transparency (made by "icons")
    media/screenshots/android/raw/<shot>.png     Pixel 7 emulator, 1080 x 2400
    media/screenshots/ios/iphone-raw/<shot>.png  iPhone 17 Pro Max Simulator (6.9")
    media/screenshots/ios/ipad-raw/<shot>.png    iPad Pro 13-inch Simulator

Every output goes under media/store/ or website/assets/img/. Captions avoid price and ranking
words such as "free", "best" or "#1", which both stores reject in screenshots and graphics.
Requires Pillow. The font is Roboto from the Flutter SDK, so Windows and the Mac draw the same.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "media"
RAW = {
    "android": MEDIA / "screenshots" / "android" / "raw",
    "iphone": MEDIA / "screenshots" / "ios" / "iphone-raw",
    "ipad": MEDIA / "screenshots" / "ios" / "ipad-raw",
}
STORE = MEDIA / "store"
SITE_IMG = ROOT / "website" / "assets" / "img"

#: Output size for each set: Google Play 9:16, iPhone 6.9", iPad 13".
SIZES = {"android": (1080, 1920), "iphone": (1320, 2868), "ipad": (2064, 2752)}
OUT_DIRS = {
    "android": STORE / "google-play" / "screenshots",
    "iphone": STORE / "app-store" / "iphone-6.9",
    "ipad": STORE / "app-store" / "ipad-13",
}

#: (raw file name without .png, caption), in store order. The same names on every platform.
SHOTS = [
    ("01-focus", "Focus for 90 minutes.\nThen take a real break."),
    ("02-alert", "An alert when it's time\nto switch, even when\nyour phone is locked"),
    ("03-break", "Break ideas that get\nyou away from the screen"),
    ("04-progress", "See your study time\nand your streak"),
    ("05-settings", "90/20, 50/10, 25/5,\nor your own lengths"),
    ("06-about", "No ads. No account.\nNothing collected."),
]

BLUE = (0x1F, 0x6F, 0xA8)    # BrandColors.restDark
GREEN = (0x2F, 0x7A, 0x4A)   # BrandColors.focusDark
BEZEL = (18, 22, 26)


def roboto(weight: str, size: int) -> ImageFont.FreeTypeFont:
    """Roboto from the Flutter SDK's font cache (the same file on Windows and macOS)."""
    flutter = shutil.which("flutter")
    if flutter is None:
        raise SystemExit("flutter is not on PATH (needed for the Roboto font)")
    sdk = Path(flutter).resolve().parent.parent
    path = sdk / "bin" / "cache" / "artifacts" / "material_fonts" / f"roboto-{weight}.ttf"
    if not path.exists():
        raise SystemExit(f"{path} not found; run `flutter precache` once")
    return ImageFont.truetype(str(path), size)


def gradient(size: tuple[int, int], diagonal: bool = False) -> Image.Image:
    """Brand blue to brand green, top to bottom (or top-left to bottom-right)."""
    w, h = size
    vertical = Image.linear_gradient("L").resize((w, h))
    mask = vertical
    if diagonal:
        horizontal = Image.linear_gradient("L").rotate(90).transpose(Image.FLIP_LEFT_RIGHT).resize((w, h))
        mask = ImageChops.add(vertical, horizontal, scale=2)
    return Image.composite(Image.new("RGB", size, GREEN), Image.new("RGB", size, BLUE), mask)


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def device(shot: Path, height: int, tablet: bool = False) -> Image.Image:
    """A screenshot inside a simple dark bezel, on a transparent background."""
    image = Image.open(shot).convert("RGB")
    bezel = round(height * (0.018 if tablet else 0.012))
    inner_h = height - 2 * bezel
    image = image.resize((round(image.width * inner_h / image.height), inner_h), Image.LANCZOS)
    outer_r = round(height * (0.035 if tablet else 0.06))
    body = rounded(Image.new("RGB", (image.width + 2 * bezel, height), BEZEL), outer_r)
    body.alpha_composite(rounded(image, outer_r - bezel), (bezel, bezel))
    return body


def paste_with_shadow(canvas: Image.Image, item: Image.Image, xy: tuple[int, int], blur: int) -> None:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    x, y = xy
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x, y + blur, x + item.width, y + item.height + blur), blur * 2, fill=(0, 0, 0, 100))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(item, xy)


def frame_set(platform: str) -> None:
    """Caption on top, the screenshot in a bezel below, on the brand gradient."""
    w, h = SIZES[platform]
    out_dir = OUT_DIRS[platform]
    out_dir.mkdir(parents=True, exist_ok=True)
    tablet = platform == "ipad"
    # Design units: the 1080 x 1920 Google Play canvas. Phones scale by width, the iPad by height.
    s = h / 1920 if tablet else w / 1080
    caption_font = roboto("bold", round((64 if tablet else 70) * s))
    caption_top = round(h * 0.045)
    caption_area = round(h * 0.19)
    base = gradient((w, h)).convert("RGBA")
    for name, caption in SHOTS:
        source = RAW[platform] / f"{name}.png"
        if not source.exists():
            print(f"  skipping {source.relative_to(ROOT)} (not found)")
            continue
        canvas = base.copy()
        draw = ImageDraw.Draw(canvas)
        spacing = round(16 * s)
        box = draw.multiline_textbbox((0, 0), caption, font=caption_font, spacing=spacing, align="center")
        tw, th = box[2] - box[0], box[3] - box[1]
        draw.multiline_text(((w - tw) / 2 - box[0], caption_top + (caption_area - th) / 2 - box[1]),
                            caption, font=caption_font, fill="white", spacing=spacing, align="center")
        top = caption_top + caption_area + round(h * 0.02)
        phone = device(source, h - top - round(h * 0.035), tablet)
        paste_with_shadow(canvas, phone, ((w - phone.width) // 2, top), round(24 * s))
        target = out_dir / f"{name}.png"
        canvas.convert("RGB").save(target, optimize=True)
        print(f"  {target.relative_to(ROOT)}  {canvas.size[0]}x{canvas.size[1]}")
        if platform == "iphone":
            save_medium_iphone(canvas, name)


#: App Store Connect (2026) requires the iPhone "medium display" set (6.1"/6.3"); 6.9" is optional.
#: 1206 x 2622 has the same aspect as 1320 x 2868 to within 0.1%, so the 6.9" frame is resized.
IPHONE_MEDIUM_SIZE = (1206, 2622)
IPHONE_MEDIUM_DIR = STORE / "app-store" / "iphone-6.3"


def save_medium_iphone(canvas: Image.Image, name: str) -> None:
    """Saves a framed 6.9" shot again at the required 6.3" iPhone size."""
    IPHONE_MEDIUM_DIR.mkdir(parents=True, exist_ok=True)
    target = IPHONE_MEDIUM_DIR / f"{name}.png"
    canvas.convert("RGB").resize(IPHONE_MEDIUM_SIZE, Image.LANCZOS).save(target, optimize=True)
    print(f"  {target.relative_to(ROOT)}  {IPHONE_MEDIUM_SIZE[0]}x{IPHONE_MEDIUM_SIZE[1]}")


LOGO = MEDIA / "brand" / "Study-Cycle-Logo-2000x2000.png"
ICON_DIR = MEDIA / "icon"
ANDROID_RES = ROOT / "mobile" / "android" / "app" / "src" / "main" / "res"
#: Android notification icon sizes (24 dp) per density.
NOTIFICATION_SIZES = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}


def logo(size: int) -> Image.Image:
    """The logo (transparent background) scaled to fit a size x size square."""
    mark = Image.open(LOGO).convert("RGBA")
    mark = mark.crop(mark.getbbox())
    scale = size / max(mark.size)
    mark = mark.resize((round(mark.width * scale), round(mark.height * scale)), Image.LANCZOS)
    square = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    square.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return square


def on_canvas(mark: Image.Image, size: int, background: tuple[int, int, int, int]) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), background)
    canvas.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return canvas


def silhouette(mark: Image.Image, color: tuple[int, int, int] = (255, 255, 255)) -> Image.Image:
    """The logo's shape in one color, for themed icons and the notification icon."""
    solid = Image.new("RGBA", mark.size, (*color, 255))
    solid.putalpha(mark.getchannel("A"))
    return solid


def icons() -> None:
    """Icon sources for flutter_launcher_icons, and the Android notification icon.

    - icon-master: the logo at 80% on white (the stores and iOS round the corners themselves).
    - icon-foreground / icon-monochrome: Android adaptive icon layers. The logo is a ring, so at
      64% it stays inside the 66% circle that every launcher shape keeps.
    - drawable-*/ic_notification.png: the logo's silhouette, 24 dp. Android draws it in one color.
    After this, run `dart run flutter_launcher_icons` in mobile/ (see CLAUDE.md for the pbxproj fix).
    """
    print("Icons")
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    white = (255, 255, 255, 255)
    master = on_canvas(logo(820), 1024, white).convert("RGB")
    master.save(ICON_DIR / "icon-master.png", optimize=True)
    master.resize((512, 512), Image.LANCZOS).save(ICON_DIR / "icon-512.png", optimize=True)
    clear = (0, 0, 0, 0)
    on_canvas(logo(655), 1024, clear).save(ICON_DIR / "icon-foreground.png", optimize=True)
    on_canvas(silhouette(logo(655)), 1024, clear).save(ICON_DIR / "icon-monochrome.png", optimize=True)
    for name in ("icon-master", "icon-512", "icon-foreground", "icon-monochrome"):
        print(f"  {(ICON_DIR / name).relative_to(ROOT)}.png")
    for density, size in NOTIFICATION_SIZES.items():
        out = ANDROID_RES / f"drawable-{density}" / "ic_notification.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        # Android keeps a 2 dp margin inside the 24 dp notification icon.
        mark = silhouette(logo(round(size * 22 / 24)))
        on_canvas(mark, size, clear).save(out, optimize=True)
        print(f"  {out.relative_to(ROOT)}  {size}x{size}")


def icon_master() -> Image.Image:
    icon = Image.open(MEDIA / "icon" / "icon-master.png")
    if icon.mode != "RGB":
        raise SystemExit("icon-master.png must have no transparency (the App Store rejects it)")
    return icon


def save_square(img: Image.Image, size: int, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(out, optimize=True)
    print(f"  {out.relative_to(ROOT)}  {size}x{size}")


def banner(size: tuple[int, int], lines: list[str], footnote: str, shot: Path, out: Path) -> None:
    """Icon, name and tagline on the left; a phone on the right, running off the bottom edge."""
    w, h = size
    canvas = gradient(size, diagonal=True).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    s = h / 500
    left = round(56 * s)
    icon = rounded(icon_master().resize((round(96 * s),) * 2, Image.LANCZOS), round(22 * s))
    paste_with_shadow(canvas, icon, (left, round(70 * s)), round(8 * s))
    draw.text((left, round(186 * s)), "Study Cycle", font=roboto("bold", round(64 * s)), fill="white")
    draw.multiline_text((left, round(276 * s)), "\n".join(lines), font=roboto("medium", round(29 * s)),
                        fill="white", spacing=round(8 * s))
    draw.text((left, round(392 * s)), footnote, font=roboto("regular", round(21 * s)),
              fill=(255, 255, 255, 225))
    phone = device(shot, round(560 * s))
    paste_with_shadow(canvas, phone, (w - phone.width - round(80 * s), round(36 * s)), round(16 * s))
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out, optimize=True)
    print(f"  {out.relative_to(ROOT)}  {w}x{h}")


def android_assets() -> None:
    print("Google Play")
    frame_set("android")
    focus = RAW["android"] / "01-focus.png"
    if focus.exists():
        banner((1024, 500), ["Focus for 90 minutes.", "Then take a real break."],
               "No ads  ·  No account  ·  Nothing collected", focus,
               STORE / "google-play" / "feature-graphic.png")
    save_square(icon_master(), 512, STORE / "google-play" / "icon-512.png")


def website_assets() -> None:
    """Phone images for the gallery, the social card and the icons. Prefers iPhone shots."""
    print("Website")
    raw = RAW["android"]
    for name, site_name in [("01-focus", "screen-focus"), ("03-break", "screen-break"),
                            ("04-progress", "screen-progress"), ("05-settings", "screen-settings"),
                            ("02-alert", "screen-alert")]:
        source = raw / f"{name}.png"
        if source.exists():
            out = SITE_IMG / f"{site_name}.png"
            Image.open(source).convert("RGB").resize((540, 1200), Image.LANCZOS).save(out, optimize=True)
            print(f"  {out.relative_to(ROOT)}  540x1200")
    focus = raw / "01-focus.png"
    if focus.exists():
        banner((1200, 630), ["A study timer for focus", "and real breaks."],
               "No ads  ·  No account  ·  studycycle.app", focus, SITE_IMG / "social-card.png")
    master = icon_master()
    save_square(master, 180, SITE_IMG / "apple-touch-icon.png")
    save_square(master, 512, SITE_IMG / "icon-512.png")
    save_square(master, 32, SITE_IMG / "favicon-32.png")
    master.save(SITE_IMG / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", choices=["icons", "android", "iphone", "ipad", "website", "all"])
    target = parser.parse_args().target
    if target == "icons":
        icons()
        return
    if target in ("android", "all"):
        android_assets()
    if target in ("iphone", "all"):
        print("App Store: iPhone 6.9\"")
        frame_set("iphone")
        save_square(icon_master(), 1024, STORE / "app-store" / "icon-1024.png")
    if target in ("ipad", "all"):
        print("App Store: iPad 13\"")
        frame_set("ipad")
    if target in ("website", "all"):
        website_assets()


if __name__ == "__main__":
    main()
