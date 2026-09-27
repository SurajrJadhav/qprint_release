"""
Create a 1024x500 feature graphic for Google Play Store.
Uses app colors (indigo/purple/pink gradient) and text: qprint + tagline.
Output: customer_app/playstore_assets/feature_graphic.png

Requires: pip install Pillow
Run from repo root: python customer_app/scripts/create_feature_graphic.py
"""

import os
import sys

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    customer_app = os.path.dirname(script_dir)
    assets_dir = os.path.join(customer_app, "playstore_assets")
    os.makedirs(assets_dir, exist_ok=True)
    out = os.path.join(assets_dir, "feature_graphic.png")

    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Install Pillow first: pip install Pillow")
        sys.exit(1)

    w, h = 1024, 500
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)

    # Gradient: indigo -> purple -> pink (app colors)
    for x in range(w):
        r = int(30 + (88 - 30) * (x / w) ** 0.5 + (159 - 88) * (x / w))
        g = int(27 + (28 - 27) * (x / w) + (18 - 28) * (x / w) ** 2)
        b = int(75 + (135 - 75) * (x / w) + (57 - 135) * (x / w) ** 2)
        r, g, b = max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b))
        draw.line([(x, 0), (x, h)], fill=(r, g, b))

    # Try a nice font; fallback to default
    try:
        font_large = ImageFont.truetype("arial.ttf", 72)
        font_small = ImageFont.truetype("arial.ttf", 32)
    except Exception:
        try:
            font_large = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 72)
            font_small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 32)
        except Exception:
            font_large = ImageFont.load_default()
            font_small = ImageFont.load_default()

    title = "qprint"
    tagline = "Print without the queue"
    # Approximate center (Pillow 10 has textlength; older use bbox or fixed offset)
    if hasattr(draw, "textlength"):
        tw = draw.textlength(title, font=font_large)
        sw = draw.textlength(tagline, font=font_small)
    else:
        bbox = draw.textbbox((0, 0), title, font=font_large) if hasattr(draw, "textbbox") else (0, 0, len(title) * 36, 80)
        tw = bbox[2] - bbox[0] if hasattr(draw, "textbbox") else 200
        sw = 320
    draw.text(((w - tw) / 2, h / 2 - 60), title, fill=(255, 255, 255), font=font_large)
    draw.text(((w - sw) / 2, h / 2 + 10), tagline, fill=(230, 230, 255), font=font_small)

    img.save(out, "PNG")
    print(f"Saved: {out}")
    print("Upload playstore_assets/feature_graphic.png in Play Console as Feature graphic (1024x500).")

if __name__ == "__main__":
    main()
