#!/usr/bin/env python3
"""Regenerate Straighter's branding assets from tools/brand/straighter-logo.png.

Writes, in place, the Android launcher/wordmark images in the Fenix overlay and the
about-page images in the Gecko branding overlays, plus the small XML wrappers that
point the adaptive icon at the new artwork. Needs only Pillow and the Poppins font.

    python3 tools/brand/make_assets.py [--font PATH] [--preview DIR]

The wordmark is set in Poppins Regular (400), an SIL Open Font License font from Google
Fonts. The font file is not stored in this repository: it is looked up in the usual
font folders, in $STRAIGHTER_FONT, or given with --font.
"""
import argparse
import base64
import io
import math
import os
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).with_name("straighter-logo.png")
RES = ROOT / "patches/fenix-overlay/app/src/release/res"
BRANDING = [
    ROOT / "patches/gecko-overlay/ironfox/branding/ironfox/content",
    ROOT / "patches/gecko-overlay/ironfox/branding/ironfox-nightly/content",
]
FONT_CANDIDATES = [
    os.environ.get("STRAIGHTER_FONT"),
    Path.home() / "Library/Fonts/Poppins-Regular.ttf",
    Path("/Library/Fonts/Poppins-Regular.ttf"),
    Path("/usr/share/fonts/truetype/poppins/Poppins-Regular.ttf"),
    Path.home() / ".fonts/Poppins-Regular.ttf",
]

NAME = "Straighter"
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
PRIVATE_BG = (117, 66, 229, 255)  # #7542e5: the logo's outer ring is black, so private mode gets purple
PRIVATE_BG_HEX = "#7542e5"

FONT_PATH = None  # set in main()


def find_font(explicit):
    for cand in [explicit] + FONT_CANDIDATES:
        if cand and Path(cand).is_file():
            font = ImageFont.truetype(str(cand), 100)
            if font.getname() != ("Poppins", "Regular"):
                sys.exit(f"{cand} is {font.getname()}, expected Poppins Regular (400)")
            return str(cand)
    sys.exit("Poppins Regular not found. Install it (fonts.google.com/specimen/Poppins) or pass --font PATH.")


class Logo:
    """The source logo, ready to be placed at any size with its centre on the canvas centre."""

    def __init__(self, path):
        im = Image.open(path).convert("RGBA")
        px = im.load()
        self.bbox = im.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
        # Centre of the artwork. For this circular logo the bounding box centre is the
        # circle's centre; the check below refuses a logo whose box is clearly off-centre.
        self.center = ((self.bbox[0] + self.bbox[2]) / 2, (self.bbox[1] + self.bbox[3]) / 2)
        far2 = 0.0
        for y in range(self.bbox[1], self.bbox[3]):
            for x in range(self.bbox[0], self.bbox[2]):
                if px[x, y][3] > 16:
                    d2 = (x - self.center[0]) ** 2 + (y - self.center[1]) ** 2
                    if d2 > far2:
                        far2 = d2
        self.far = math.sqrt(far2)
        w, h = im.size
        if abs(self.center[0] - w / 2) > 2 or abs(self.center[1] - h / 2) > 2:
            sys.exit("logo is not centred in its own image; centre it or update Logo.center")
        self.crop = im.crop(self.bbox)

    def place(self, size, radius_frac):
        """Square RGBA canvas with the logo's centre at the exact centre; the farthest
        point of the artwork sits radius_frac * size from it."""
        s = radius_frac * size / self.far
        w = max(1, round(self.crop.width * s))
        h = max(1, round(self.crop.height * s))
        scaled = self.crop.resize((w, h), Image.LANCZOS)
        x = round(size / 2 - (self.center[0] - self.bbox[0]) * s)
        y = round(size / 2 - (self.center[1] - self.bbox[1]) * s)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        canvas.alpha_composite(scaled, (x, y))
        return canvas


def monochrome(img):
    """Themed-icon layer (only alpha matters): keep the dark and red rings, drop the light
    ones, so the bullseye pattern survives instead of becoming a solid disk."""
    lum = img.convert("RGB").convert("L")
    ink = lum.point(lambda v: max(0, min(255, round((225 - v) * 255 / 65))))
    out = Image.new("RGBA", img.size, BLACK)
    out.putalpha(ImageChops.multiply(img.getchannel("A"), ink))
    return out


def text_image(w, h, color, pad=0.04):
    """NAME in Poppins Regular, as large as fits inside (w, h), centred, on transparency."""
    ss = 3
    W, H = w * ss, h * ss
    box_w, box_h = W * (1 - 2 * pad), H * (1 - 2 * pad)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    lo, hi, best = 8, H * 2, None
    while lo <= hi:
        mid = (lo + hi) // 2
        font = ImageFont.truetype(FONT_PATH, mid)
        b = probe.textbbox((0, 0), NAME, font=font)
        if b[2] - b[0] <= box_w and b[3] - b[1] <= box_h:
            best, lo = (font, b), mid + 1
        else:
            hi = mid - 1
    font, b = best
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = (W - (b[2] - b[0])) / 2 - b[0]
    y = (H - (b[3] - b[1])) / 2 - b[1]
    ImageDraw.Draw(img).text((x, y), NAME, font=font, fill=color)
    return img.resize((w, h), Image.LANCZOS)


def legacy_icon(logo, size, round_shape, private):
    """Pre-Android-8 launcher icon: a card (rounded square or circle) with a soft shadow."""
    ss = 4
    S = size * ss
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    card = int(S * 0.80)
    off = (S - card) // 2
    drop = int(S * 0.012)

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sbox = (off, off + drop, off + card, off + card + drop)
    if round_shape:
        sd.ellipse(sbox, fill=(0, 0, 0, 90))
    else:
        sd.rounded_rectangle(sbox, radius=int(card * 0.2), fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.012)))

    d = ImageDraw.Draw(canvas)
    box = (off, off, off + card, off + card)
    fill = PRIVATE_BG if private else WHITE
    if round_shape:
        d.ellipse(box, fill=fill)
    else:
        d.rounded_rectangle(box, radius=int(card * 0.2), fill=fill)

    canvas.alpha_composite(logo.place(card, 0.40), (off, off))
    return canvas.resize((size, size), Image.LANCZOS)


def save(img, path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == ".webp":
        img.save(path, "WEBP", lossless=True, quality=100, method=6)
    else:
        img.save(path, optimize=True)


def write_text(path, text):
    Path(path).write_text(text, encoding="utf-8")


BITMAP_XML = """<?xml version="1.0" encoding="utf-8"?>
<bitmap xmlns:android="http://schemas.android.com/apk/res/android"
    android:src="@drawable/{src}" />
"""

COLOR_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="{name}">{value}</color>
</resources>
"""


def main():
    global FONT_PATH
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", help="path to Poppins-Regular.ttf")
    ap.add_argument("--preview", help="also write a contact sheet PNG into this directory")
    args = ap.parse_args()
    FONT_PATH = find_font(args.font)

    logo = Logo(SRC)
    written = []

    def out(img, path):
        save(img, path)
        written.append(path)

    # ---- Adaptive icon artwork (108dp canvas at 4x = 432 px). Launchers show only the
    # inner 72dp (288 px) through their mask, and Android advises keeping key content inside
    # a 66dp circle (radius 132 px), so the logo's circle has a radius of 125 px.
    fg = logo.place(432, 0.29)
    out(fg, RES / "drawable/straighter_logo_fg.webp")
    out(monochrome(fg), RES / "drawable/straighter_logo_mono.webp")

    write_text(RES / "drawable/ic_launcher_foreground.xml", BITMAP_XML.format(src="straighter_logo_fg"))
    write_text(RES / "drawable/ic_launcher_private_foreground.xml", BITMAP_XML.format(src="straighter_logo_fg"))
    write_text(RES / "drawable/ic_launcher_monochrome.xml", BITMAP_XML.format(src="straighter_logo_mono"))
    write_text(RES / "drawable/animated_splash_screen.xml", BITMAP_XML.format(src="straighter_logo_fg"))
    write_text(RES / "values/ic_launcher_background.xml", COLOR_XML.format(name="ic_launcher_background", value="#ffffff"))
    write_text(RES / "values/ic_launcher_private_background.xml", COLOR_XML.format(name="ic_launcher_private_background", value=PRIVATE_BG_HEX))

    # ---- Legacy launcher icons, same pixel size as the files they replace
    for f in sorted(RES.glob("mipmap-*dpi/ic_launcher*.webp")):
        size = Image.open(f).size[0]
        out(legacy_icon(logo, size, f.stem.endswith("_round"), "private" in f.name), f)

    # ---- Wordmarks and logo mark, at every density that already exists
    for d in sorted(RES.glob("drawable*")):
        if not d.is_dir():
            continue
        for f in sorted(d.glob("ic_*wordmark*.webp")):
            w, h = Image.open(f).size
            if f.stem == "ic_wordmark_logo":
                img = logo.place(w, 0.49)
            else:
                img = text_image(w, h, WHITE if f.stem.endswith("_private") else BLACK)
            out(img, f)

    # ---- Gecko branding (about pages, small icons), both channels
    for b in BRANDING:
        out(logo.place(192, 0.49), b / "about-logo.png")
        out(logo.place(384, 0.49), b / "about-logo@2x.png")
        for n in (16, 32, 64):
            out(logo.place(n, 0.5), b / f"icon{n}.png")
        buf = io.BytesIO()
        logo.place(512, 0.49).save(buf, "PNG", optimize=True)
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")
        write_text(
            b / "about-logo.svg",
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            'width="512" height="512" viewBox="0 0 512 512">\n'
            f'<image width="512" height="512" xlink:href="data:image/png;base64,{b64}"/>\n</svg>\n',
        )
        card = Image.new("RGBA", (203, 99), WHITE)
        card.alpha_composite(logo.place(64, 0.49), (18, 17))
        card.alpha_composite(text_image(104, 30, BLACK), (88, 34))
        out(card.convert("RGB"), b / "about-if.png")
        written.append(b / "about-logo.svg")

    if args.preview:
        sheet = Image.new("RGB", (1500, 900), (110, 110, 110))
        x = 20
        for bg in (WHITE, PRIVATE_BG):
            tile = Image.new("RGBA", (432, 432), bg)
            tile.alpha_composite(fg)
            mask = Image.new("L", (432, 432), 0)
            # what a round launcher really shows: the inner 72dp (288 px) of the 108dp canvas
            ImageDraw.Draw(mask).ellipse((72, 72, 359, 359), fill=255)
            sheet.paste(tile.convert("RGB"), (x, 20), mask)
            x += 452
        # themed (monochrome) icon: tinted single colour on a plain tile
        tile = Image.new("RGBA", (432, 432), (208, 226, 255, 255))
        tint = Image.new("RGBA", (432, 432), (23, 55, 128, 255))
        tint.putalpha(monochrome(fg).getchannel("A"))
        tile.alpha_composite(tint)
        mask = Image.new("L", (432, 432), 0)
        ImageDraw.Draw(mask).ellipse((72, 72, 359, 359), fill=255)
        sheet.paste(tile.convert("RGB"), (x, 20), mask)
        x = 20
        for shape, private in ((False, False), (True, False), (False, True)):
            icon = legacy_icon(logo, 192, shape, private)
            sheet.paste(icon, (x, 480), icon)
            x += 212
        y = 700
        for color, bg in ((BLACK, (235, 235, 235)), (WHITE, PRIVATE_BG[:3])):
            t = Image.new("RGB", (626, 150), bg)
            ti = text_image(626, 150, color)
            t.paste(ti, (0, 0), ti)
            sheet.paste(t, (20 if color == BLACK else 666, y))
        sheet.paste(Image.open(BRANDING[0] / "about-if.png").convert("RGB"), (1250, 480))
        Path(args.preview).mkdir(parents=True, exist_ok=True)
        sheet.save(Path(args.preview) / "straighter-assets-preview.png")

    print(f"wrote {len(written)} files (font: {Path(FONT_PATH).name})")


if __name__ == "__main__":
    main()
