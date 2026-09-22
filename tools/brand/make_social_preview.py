#!/usr/bin/env python3
"""Generate the GitHub social-preview image (1280x640) from the Straighter logo.

    python3 tools/brand/make_social_preview.py [--font PATH]

GitHub cannot take this from the repository: upload tools/brand/social-preview.png under
the repo's Settings > General > Social preview. It is shown when the repo is linked on
social sites and in chat previews. Uses the same logo and font (Poppins Regular) as
make_assets.py.
"""
import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_assets as ma  # noqa: E402

W, H = 1280, 640
OUT = Path(__file__).with_name("social-preview.png")
TITLE = "Straighter"
TAGLINE = ["The privacy-first, user-first,", "secure Android web browser"]
INK = (20, 20, 28)
MUTED = (96, 96, 110)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", help="path to Poppins-Regular.ttf")
    args = ap.parse_args()
    font_path = ma.find_font(args.font)

    img = Image.new("RGB", (W, H), (255, 255, 255))
    logo = ma.Logo(ma.SRC).place(400, 0.49)
    tile = Image.new("RGBA", logo.size, (255, 255, 255, 255))
    tile.alpha_composite(logo)
    img.paste(tile.convert("RGB"), (110, (H - 400) // 2))

    d = ImageDraw.Draw(img)
    title_font = ImageFont.truetype(font_path, 132)
    tag_font = ImageFont.truetype(font_path, 44)

    tb = d.textbbox((0, 0), TITLE, font=title_font)
    line_h = d.textbbox((0, 0), "Ag", font=tag_font)[3] + 14
    block_h = (tb[3] - tb[1]) + 36 + line_h * len(TAGLINE)
    x = 570
    y = (H - block_h) // 2 - tb[1]
    d.text((x, y), TITLE, font=title_font, fill=INK)
    y += tb[3] + 36
    for line in TAGLINE:
        d.text((x, y), line, font=tag_font, fill=MUTED)
        y += line_h

    img.save(OUT, optimize=True)
    print(f"wrote {OUT.name} ({W}x{H}, font: {Path(font_path).name})")


if __name__ == "__main__":
    main()
