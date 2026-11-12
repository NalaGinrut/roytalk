#!/usr/bin/env python3
"""Render pub/img/og-default.webp, the Open Graph card used by every page.

The site has no per-article covers: all pages share this one card (1200x630,
the size X, Slack and Facebook want for summary_large_image). Change the
strings below and re-run when the site name or tagline changes:

    python3 tools/make-og-image.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "pub" / "fonts"
OUT = ROOT / "pub" / "img" / "og-default.webp"

W, H = 1200, 630
MARGIN = 96

PAPER = (243, 240, 232)   # --paper
INK = (23, 32, 28)        # --ink
MUTED = (74, 82, 76)      # --muted
RULE = (201, 194, 176)    # --rule
BRASS = (106, 82, 35)     # --brass
GREEN = (30, 63, 48)      # --green

SITE = "Roy on next generation software"
TAGLINE = "no matter if there will be."
KICKER = "INFERENCE ENGINES · LANGUAGE THEORY · COMPILERS · OPERATING SYSTEMS"
DOMAIN = "roytalk.com"


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size)


def tracked(draw, xy, text, fnt, fill, tracking):
    """Draw TEXT one glyph at a time, adding TRACKING pixels between glyphs."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + tracking


def main():
    img = Image.new("RGB", (W, H), PAPER)
    draw = ImageDraw.Draw(img)

    kicker_font = font("source-serif-4-latin-400-normal.woff2", 17)
    title_font = font("cormorant-garamond-latin-500-normal.woff2", 104)
    tagline_font = font("source-serif-4-latin-400-italic.woff2", 30)
    domain_font = font("source-serif-4-latin-400-normal.woff2", 19)

    # A hairline of racing green down the left edge, then the kicker.
    draw.rectangle([MARGIN, 88, MARGIN + 3, 104], fill=GREEN)
    tracked(draw, (MARGIN + 18, 86), KICKER, kicker_font, BRASS, 2.2)

    # Title, two lines, tight leading; Cormorant is a light display face and
    # looks right larger than the body copy would.
    draw.text((MARGIN - 4, 150), "Roy on next", font=title_font, fill=INK)
    draw.text((MARGIN - 4, 250), "generation software", font=title_font, fill=INK)

    draw.text((MARGIN, 404), TAGLINE, font=tagline_font, fill=MUTED)

    # Footer rule and domain, bottom-aligned.
    draw.line([MARGIN, 512, W - MARGIN, 512], fill=RULE, width=2)
    draw.text((MARGIN, 536), DOMAIN, font=domain_font, fill=MUTED)

    # Lossless keeps the type crisp at the card's small display sizes and is
    # still tiny, since the picture is flat colour and text.
    img.save(OUT, "WEBP", lossless=True, method=6)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
