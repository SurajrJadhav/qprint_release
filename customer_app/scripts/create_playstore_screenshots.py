"""
Create Play Store phone screenshots that match the qprint customer app UI:
app bar (Qprint + wallet), gradient background, bottom nav, and screen-specific
content with a small explanation bubble.

Output: playstore_assets/screenshots/ (4 images, 1080x1920, 9:16).
Requires: pip install Pillow
Run from repo root: python customer_app/scripts/create_playstore_screenshots.py
"""

import os
import sys

W, H = 1080, 1920  # 9:16 phone

# App colors (from app_colors.dart)
INDIGO900 = (30, 27, 75)
PURPLE900 = (88, 28, 135)
PINK800 = (159, 18, 57)
PINK400 = (244, 114, 182)
PINK500 = (236, 72, 153)
WHITE = (255, 255, 255)
WHITE50 = (180, 180, 200)
WHITE20 = (200, 200, 220)
CARD_BG = (55, 50, 95)
BUBBLE_BG = (255, 255, 255)
BUBBLE_TEXT = (40, 25, 70)

APP_BAR_H = 56
NAV_H = 56
CONTENT_TOP = APP_BAR_H
CONTENT_BOTTOM = H - NAV_H

SCREENS = [
    {
        "nav_index": 0,
        "title": "Upload",
        "filename": "01_upload.png",
        "bubble": "Select files, set copies & paper, choose a shop, and pay. No queue—order from your phone.",
        "draw_content": lambda draw, f: draw_upload_content(draw, f),
    },
    {
        "nav_index": 1,
        "title": "My Files",
        "filename": "02_my_files.png",
        "bubble": "Track every print. See status, get directions to the shop, and collect with your code.",
        "draw_content": lambda draw, f: draw_my_files_content(draw, f),
    },
    {
        "nav_index": 4,
        "title": "Map",
        "filename": "03_map.png",
        "bubble": "Find print shops nearby. Open/closed status and distance. Save favorites.",
        "draw_content": lambda draw, f: draw_map_content(draw, f),
    },
    {
        "nav_index": 0,
        "title": "Wallet",
        "filename": "04_wallet.png",
        "bubble": "Pay with card, UPI, or wallet. Top up in-app and see all transactions.",
        "draw_content": lambda draw, f: draw_wallet_content(draw, f),
    },
]


def get_font(size):
    try:
        return __import__("PIL.ImageFont").ImageFont.truetype("C:/Windows/Fonts/arial.ttf", size)
    except Exception:
        try:
            return __import__("PIL.ImageFont").ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size)
        except Exception:
            return __import__("PIL.ImageFont").ImageFont.load_default()


def draw_gradient(draw, y1, y2):
    for y in range(y1, min(y2, H)):
        t = (y - y1) / max(1, y2 - y1)
        r = int(INDIGO900[0] + (PURPLE900[0] - INDIGO900[0]) * t + (PINK800[0] - PURPLE900[0]) * t * t)
        g = int(INDIGO900[1] + (PURPLE900[1] - INDIGO900[1]) * t + (PINK800[1] - PURPLE900[1]) * t * t)
        b = int(INDIGO900[2] + (PURPLE900[2] - INDIGO900[2]) * t + (PINK800[2] - PURPLE900[2]) * t * t)
        r, g, b = max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b))
        draw.line([(0, y), (W, y)], fill=(r, g, b))


def draw_app_bar(draw, font_title, font_small, wallet_text="₹ 250"):
    draw.rectangle([0, 0, W, APP_BAR_H], fill=INDIGO900)
    draw.line([(0, APP_BAR_H - 1), (W, APP_BAR_H - 1)], fill=WHITE20)
    draw.text((40, 14), "Q", fill=WHITE, font=font_title)
    draw.text((72, 14), "print", fill=PINK400, font=font_title)
    # Wallet chip
    draw.rounded_rectangle([W - 140, 14, W - 24, APP_BAR_H - 14], radius=20, fill=CARD_BG, outline=WHITE20)
    draw.text((W - 128, 16), wallet_text, fill=PINK400, font=font_small)


def draw_bottom_nav(draw, font_small, selected_index):
    y0 = H - NAV_H
    draw.rectangle([0, y0, W, H], fill=CARD_BG)
    draw.line([(0, y0), (W, y0)], fill=WHITE20)
    labels = ["Upload", "My Files", "Favorites", "Expenses", "Map"]
    n = len(labels)
    for i in range(n):
        x = (i + 0.5) * (W / n)
        col = PINK500 if i == selected_index else WHITE50
        lw = draw.textlength(labels[i], font=font_small) if hasattr(draw, "textlength") else len(labels[i]) * 10
        draw.text((x - lw / 2, y0 + 28), labels[i], fill=col, font=font_small)


def draw_upload_content(draw, fonts):
    ft, fs = fonts[0], fonts[1]
    margin = 24
    # Card: "Select file"
    draw.rounded_rectangle([margin, CONTENT_TOP + 40, W - margin, CONTENT_TOP + 120], radius=16, fill=CARD_BG, outline=WHITE20)
    draw.text((margin + 24, CONTENT_TOP + 58), "Select file to print", fill=WHITE, font=ft)
    draw.text((margin + 24, CONTENT_TOP + 88), "PDF, images (PNG, JPG)", fill=WHITE50, font=fs)
    # Card: options row
    draw.rounded_rectangle([margin, CONTENT_TOP + 140, W - margin, CONTENT_TOP + 220], radius=16, fill=CARD_BG, outline=WHITE20)
    draw.text((margin + 24, CONTENT_TOP + 158), "Copies: 1   |   Single-sided   |   A4   |   B&W", fill=WHITE, font=fs)
    # Card: "Choose shop"
    draw.rounded_rectangle([margin, CONTENT_TOP + 240, W - margin, CONTENT_TOP + 320], radius=16, fill=CARD_BG, outline=WHITE20)
    draw.text((margin + 24, CONTENT_TOP + 268), "Choose shop", fill=PINK400, font=ft)
    draw.text((margin + 24, CONTENT_TOP + 298), "Nearest shops with open/closed status", fill=WHITE50, font=fs)
    # Button
    draw.rounded_rectangle([margin, CONTENT_TOP + 360, W - margin, CONTENT_TOP + 440], radius=24, fill=PINK500, outline=None)
    draw.text((W // 2 - 80, CONTENT_TOP + 378), "Upload & Pay", fill=WHITE, font=ft)


def draw_my_files_content(draw, fonts):
    ft, fs = fonts[0], fonts[1]
    margin = 24
    # File cards
    for i, (name, status) in enumerate([("document.pdf", "Pending"), ("report.docx", "Ready for pickup"), ("photo.jpg", "Downloaded")]):
        y = CONTENT_TOP + 40 + i * 140
        draw.rounded_rectangle([margin, y, W - margin, y + 120], radius=16, fill=CARD_BG, outline=WHITE20)
        draw.text((margin + 24, y + 20), name, fill=WHITE, font=ft)
        draw.text((margin + 24, y + 52), status, fill=PINK400 if status == "Ready for pickup" else WHITE50, font=fs)
        draw.text((margin + 24, y + 82), "Code: 8A2F · Shop: Central Print", fill=WHITE50, font=fs)


def draw_map_content(draw, fonts):
    ft, fs = fonts[0], fonts[1]
    margin = 24
    # Map placeholder (large card)
    draw.rounded_rectangle([margin, CONTENT_TOP + 40, W - margin, CONTENT_TOP + 520], radius=16, fill=(45, 42, 80), outline=WHITE20)
    # Grid lines like a map
    for i in range(4):
        y = CONTENT_TOP + 80 + i * 110
        draw.line([(margin + 40, y), (W - margin - 40, y)], fill=WHITE20)
    for i in range(3):
        x = margin + 120 + i * 280
        draw.line([(x, CONTENT_TOP + 80), (x, CONTENT_TOP + 480)], fill=WHITE20)
    # Pin / "You are here"
    draw.ellipse([W // 2 - 28, CONTENT_TOP + 220, W // 2 + 28, CONTENT_TOP + 276], fill=PINK500, outline=WHITE)
    draw.text((W // 2 - 50, CONTENT_TOP + 540), "Shops nearby · Tap for directions", fill=WHITE50, font=fs)
    # Small list below
    draw.rounded_rectangle([margin, CONTENT_TOP + 580, W - margin, CONTENT_TOP + 700], radius=12, fill=CARD_BG, outline=WHITE20)
    draw.text((margin + 24, CONTENT_TOP + 600), "Central Print  ·  0.5 km  ·  Open", fill=WHITE, font=fs)
    draw.text((margin + 24, CONTENT_TOP + 638), "Quick Copy  ·  1.2 km  ·  Closed", fill=WHITE50, font=fs)


def draw_wallet_content(draw, fonts):
    ft, fs = fonts[0], fonts[1]
    margin = 24
    # Balance card
    draw.rounded_rectangle([margin, CONTENT_TOP + 40, W - margin, CONTENT_TOP + 180], radius=20, fill=CARD_BG, outline=WHITE20)
    draw.text((margin + 24, CONTENT_TOP + 50), "Wallet balance", fill=WHITE50, font=fs)
    draw.text((margin + 24, CONTENT_TOP + 95), "₹ 250.00", fill=WHITE, font=ft)
    draw.rounded_rectangle([W - margin - 140, CONTENT_TOP + 115, W - margin - 24, CONTENT_TOP + 165], radius=20, fill=PINK500, outline=None)
    draw.text((W - margin - 128, CONTENT_TOP + 128), "Top up", fill=WHITE, font=fs)
    # Transactions
    draw.text((margin, CONTENT_TOP + 200), "Recent transactions", fill=WHITE, font=fs)
    for i, (desc, amt) in enumerate([("Print payment", "-₹45"), ("Top up", "+₹200"), ("Print payment", "-₹30")]):
        y = CONTENT_TOP + 240 + i * 72
        draw.line([(margin, y), (W - margin, y)], fill=WHITE20)
        draw.text((margin + 24, y + 12), desc, fill=WHITE, font=fs)
        draw.text((W - margin - 100, y + 12), amt, fill=PINK400 if amt.startswith("+") else WHITE50, font=fs)


def wrap_bubble(draw, text, font, max_w):
    words = text.split()
    lines = []
    cur = []
    for w in words:
        test = " ".join(cur + [w])
        lw = draw.textlength(test, font=font) if hasattr(draw, "textlength") else len(test) * 12
        if lw <= max_w:
            cur.append(w)
        else:
            if cur:
                lines.append(" ".join(cur))
            cur = [w]
    if cur:
        lines.append(" ".join(cur))
    return lines


def draw_bubble(draw, bubble_text, font_bubble, right_side=True):
    pad = 28
    max_w = 320
    lines = wrap_bubble(draw, bubble_text, font_bubble, max_w - 2 * pad)
    line_h = 30
    bw = max_w
    bh = len(lines) * line_h + 2 * pad
    if right_side:
        bx = W - bw - 40
    else:
        bx = 40
    by = CONTENT_BOTTOM - bh - 180
    draw.rounded_rectangle([bx, by, bx + bw, by + bh], radius=16, fill=BUBBLE_BG, outline=(220, 200, 255))
    # Pointer
    if right_side:
        draw.polygon([(bx + bw - 30, by + bh), (bx + bw + 10, by + bh + 20), (bx + bw - 10, by + bh)], fill=BUBBLE_BG)
    else:
        draw.polygon([(bx + 30, by + bh), (bx + 10, by + bh + 20), (bx + 50, by + bh)], fill=BUBBLE_BG)
    ty = by + pad
    for line in lines:
        lw = draw.textlength(line, font=font_bubble) if hasattr(draw, "textlength") else len(line) * 12
        tx = bx + (bw - lw) // 2
        draw.text((tx, ty), line, fill=BUBBLE_TEXT, font=font_bubble)
        ty += line_h


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    customer_app = os.path.dirname(script_dir)
    out_dir = os.path.join(customer_app, "playstore_assets", "screenshots")
    os.makedirs(out_dir, exist_ok=True)

    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Install Pillow first: pip install Pillow")
        sys.exit(1)

    font_title = get_font(28)
    font_small = get_font(22)
    font_bubble = get_font(20)
    fonts = (font_title, font_small)

    for s in SCREENS:
        img = Image.new("RGB", (W, H), INDIGO900)
        draw = ImageDraw.Draw(img)

        draw_gradient(draw, CONTENT_TOP, CONTENT_BOTTOM)
        draw_app_bar(draw, font_title, font_small, "₹ 250" if "Wallet" in s["title"] else "₹ 250")
        draw_bottom_nav(draw, font_small, s["nav_index"])
        s["draw_content"](draw, fonts)
        draw_bubble(draw, s["bubble"], font_bubble, right_side=(s["filename"] != "02_my_files.png"))

        out_path = os.path.join(out_dir, s["filename"])
        img.save(out_path, "PNG")
        print(f"Saved: {out_path}")

    print(f"\nUpload the {len(SCREENS)} images from playstore_assets/screenshots/ in Play Console -> Phone screenshots (9:16).")


if __name__ == "__main__":
    main()
