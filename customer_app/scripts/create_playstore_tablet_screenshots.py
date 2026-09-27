"""
Create Play Store 7-inch tablet screenshots (same app UI as phone, scaled).
9:16 portrait: 1440x2560 px. PNG, under 8 MB. 2-8 images.

Output: playstore_assets/screenshots_tablet/
Requires: pip install Pillow
Run from repo root: python customer_app/scripts/create_playstore_tablet_screenshots.py
"""

import os
import sys

# 9:16 tablet portrait (7-inch class), within 320-3840
W, H = 1440, 2560

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

APP_BAR_H = 72
NAV_H = 72
CONTENT_TOP = APP_BAR_H
CONTENT_BOTTOM = H - NAV_H
MARGIN = 48

SCREENS = [
    {"nav_index": 0, "title": "Upload", "filename": "01_upload.png",
     "bubble": "Select files, set copies & paper, choose a shop, and pay. No queue—order from your device.",
     "draw_content": "upload"},
    {"nav_index": 1, "title": "My Files", "filename": "02_my_files.png",
     "bubble": "Track every print. See status, get directions to the shop, and collect with your code.",
     "draw_content": "my_files"},
    {"nav_index": 4, "title": "Map", "filename": "03_map.png",
     "bubble": "Find print shops nearby. Open/closed status and distance. Save favorites.",
     "draw_content": "map"},
    {"nav_index": 0, "title": "Wallet", "filename": "04_wallet.png",
     "bubble": "Pay with card, UPI, or wallet. Top up in-app and see all transactions.",
     "draw_content": "wallet"},
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
    draw.text((56, 16), "Q", fill=WHITE, font=font_title)
    draw.text((100, 16), "print", fill=PINK400, font=font_title)
    draw.rounded_rectangle([W - 200, 18, W - 32, APP_BAR_H - 18], radius=24, fill=CARD_BG, outline=WHITE20)
    draw.text((W - 185, 22), wallet_text, fill=PINK400, font=font_small)


def draw_bottom_nav(draw, font_small, selected_index):
    y0 = H - NAV_H
    draw.rectangle([0, y0, W, H], fill=CARD_BG)
    draw.line([(0, y0), (W, y0)], fill=WHITE20)
    labels = ["Upload", "My Files", "Favorites", "Expenses", "Map"]
    for i in range(len(labels)):
        x = (i + 0.5) * (W / 5)
        col = PINK500 if i == selected_index else WHITE50
        lw = draw.textlength(labels[i], font=font_small) if hasattr(draw, "textlength") else len(labels[i]) * 14
        draw.text((x - lw / 2, y0 + 34), labels[i], fill=col, font=font_small)


def draw_upload_content(draw, fonts):
    ft, fs = fonts[0], fonts[1]
    m = MARGIN
    draw.rounded_rectangle([m, CONTENT_TOP + 56, W - m, CONTENT_TOP + 168], radius=20, fill=CARD_BG, outline=WHITE20)
    draw.text((m + 36, CONTENT_TOP + 78), "Select file to print", fill=WHITE, font=ft)
    draw.text((m + 36, CONTENT_TOP + 118), "PDF, images (PNG, JPG)", fill=WHITE50, font=fs)
    draw.rounded_rectangle([m, CONTENT_TOP + 188, W - m, CONTENT_TOP + 292], radius=20, fill=CARD_BG, outline=WHITE20)
    draw.text((m + 36, CONTENT_TOP + 210), "Copies: 1   |   Single-sided   |   A4   |   B&W", fill=WHITE, font=fs)
    draw.rounded_rectangle([m, CONTENT_TOP + 312, W - m, CONTENT_TOP + 416], radius=20, fill=CARD_BG, outline=WHITE20)
    draw.text((m + 36, CONTENT_TOP + 340), "Choose shop", fill=PINK400, font=ft)
    draw.text((m + 36, CONTENT_TOP + 380), "Nearest shops with open/closed status", fill=WHITE50, font=fs)
    draw.rounded_rectangle([m, CONTENT_TOP + 456, W - m, CONTENT_TOP + 560], radius=28, fill=PINK500, outline=None)
    draw.text((W // 2 - 120, CONTENT_TOP + 488), "Upload & Pay", fill=WHITE, font=ft)


def draw_my_files_content(draw, fonts):
    ft, fs = fonts[0], fonts[1]
    m = MARGIN
    for i, (name, status) in enumerate([("document.pdf", "Pending"), ("report.docx", "Ready for pickup"), ("photo.jpg", "Downloaded")]):
        y = CONTENT_TOP + 56 + i * 200
        draw.rounded_rectangle([m, y, W - m, y + 168], radius=20, fill=CARD_BG, outline=WHITE20)
        draw.text((m + 36, y + 28), name, fill=WHITE, font=ft)
        draw.text((m + 36, y + 72), status, fill=PINK400 if status == "Ready for pickup" else WHITE50, font=fs)
        draw.text((m + 36, y + 112), "Code: 8A2F · Shop: Central Print", fill=WHITE50, font=fs)


def draw_map_content(draw, fonts):
    ft, fs = fonts[0], fonts[1]
    m = MARGIN
    draw.rounded_rectangle([m, CONTENT_TOP + 56, W - m, CONTENT_TOP + 720], radius=20, fill=(45, 42, 80), outline=WHITE20)
    for i in range(5):
        y = CONTENT_TOP + 100 + i * 130
        draw.line([(m + 56, y), (W - m - 56, y)], fill=WHITE20)
    for i in range(4):
        x = m + 160 + i * 340
        draw.line([(x, CONTENT_TOP + 100), (x, CONTENT_TOP + 680)], fill=WHITE20)
    draw.ellipse([W // 2 - 40, CONTENT_TOP + 300, W // 2 + 40, CONTENT_TOP + 380], fill=PINK500, outline=WHITE)
    draw.text((W // 2 - 120, CONTENT_TOP + 740), "Shops nearby · Tap for directions", fill=WHITE50, font=fs)
    draw.rounded_rectangle([m, CONTENT_TOP + 780, W - m, CONTENT_TOP + 940], radius=16, fill=CARD_BG, outline=WHITE20)
    draw.text((m + 36, CONTENT_TOP + 808), "Central Print  ·  0.5 km  ·  Open", fill=WHITE, font=fs)
    draw.text((m + 36, CONTENT_TOP + 868), "Quick Copy  ·  1.2 km  ·  Closed", fill=WHITE50, font=fs)


def draw_wallet_content(draw, fonts):
    ft, fs = fonts[0], fonts[1]
    m = MARGIN
    draw.rounded_rectangle([m, CONTENT_TOP + 56, W - m, CONTENT_TOP + 240], radius=24, fill=CARD_BG, outline=WHITE20)
    draw.text((m + 36, CONTENT_TOP + 68), "Wallet balance", fill=WHITE50, font=fs)
    draw.text((m + 36, CONTENT_TOP + 128), "₹ 250.00", fill=WHITE, font=ft)
    draw.rounded_rectangle([W - m - 200, CONTENT_TOP + 148, W - m - 32, CONTENT_TOP + 228], radius=24, fill=PINK500, outline=None)
    draw.text((W - m - 178, CONTENT_TOP + 178), "Top up", fill=WHITE, font=fs)
    draw.text((m, CONTENT_TOP + 268), "Recent transactions", fill=WHITE, font=fs)
    for i, (desc, amt) in enumerate([("Print payment", "-₹45"), ("Top up", "+₹200"), ("Print payment", "-₹30")]):
        y = CONTENT_TOP + 320 + i * 96
        draw.line([(m, y), (W - m, y)], fill=WHITE20)
        draw.text((m + 36, y + 18), desc, fill=WHITE, font=fs)
        draw.text((W - m - 140, y + 18), amt, fill=PINK400 if amt.startswith("+") else WHITE50, font=fs)


def wrap_bubble(draw, text, font, max_w):
    words = text.split()
    lines = []
    cur = []
    for w in words:
        test = " ".join(cur + [w])
        lw = draw.textlength(test, font=font) if hasattr(draw, "textlength") else len(test) * 14
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
    pad = 36
    max_w = 420
    lines = wrap_bubble(draw, bubble_text, font_bubble, max_w - 2 * pad)
    line_h = 38
    bw = max_w
    bh = len(lines) * line_h + 2 * pad
    bx = (W - bw - 56) if right_side else 56
    by = CONTENT_BOTTOM - bh - 240
    draw.rounded_rectangle([bx, by, bx + bw, by + bh], radius=20, fill=BUBBLE_BG, outline=(220, 200, 255))
    if right_side:
        draw.polygon([(bx + bw - 40, by + bh), (bx + bw + 14, by + bh + 24), (bx + bw - 14, by + bh)], fill=BUBBLE_BG)
    else:
        draw.polygon([(bx + 40, by + bh), (bx + 14, by + bh + 24), (bx + 66, by + bh)], fill=BUBBLE_BG)
    ty = by + pad
    for line in lines:
        lw = draw.textlength(line, font=font_bubble) if hasattr(draw, "textlength") else len(line) * 14
        tx = bx + (bw - lw) // 2
        draw.text((tx, ty), line, fill=BUBBLE_TEXT, font=font_bubble)
        ty += line_h


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    customer_app = os.path.dirname(script_dir)
    out_dir = os.path.join(customer_app, "playstore_assets", "screenshots_tablet")
    os.makedirs(out_dir, exist_ok=True)

    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Install Pillow first: pip install Pillow")
        sys.exit(1)

    font_title = get_font(36)
    font_small = get_font(28)
    font_bubble = get_font(24)
    fonts = (font_title, font_small)

    content_drawers = {
        "upload": draw_upload_content,
        "my_files": draw_my_files_content,
        "map": draw_map_content,
        "wallet": draw_wallet_content,
    }

    for s in SCREENS:
        img = Image.new("RGB", (W, H), INDIGO900)
        draw = ImageDraw.Draw(img)
        draw_gradient(draw, CONTENT_TOP, CONTENT_BOTTOM)
        draw_app_bar(draw, font_title, font_small, "₹ 250")
        draw_bottom_nav(draw, font_small, s["nav_index"])
        content_drawers[s["draw_content"]](draw, fonts)
        draw_bubble(draw, s["bubble"], font_bubble, right_side=(s["filename"] != "02_my_files.png"))

        out_path = os.path.join(out_dir, s["filename"])
        img.save(out_path, "PNG")
        print(f"Saved: {out_path}")

    print(f"\nUpload up to 8 images from playstore_assets/screenshots_tablet/ in Play Console -> 7-inch tablet screenshots (9:16).")


if __name__ == "__main__":
    main()
