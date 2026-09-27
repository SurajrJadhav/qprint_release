"""
Resize customer_app/assets/logo.png to 512x512 for Google Play Store.
Output: customer_app/playstore_assets/app_icon_512.png

Requires: pip install Pillow
Run from repo root: python customer_app/scripts/resize_logo_playstore.py
"""

import os
import sys

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    customer_app = os.path.dirname(script_dir)
    assets_dir = os.path.join(customer_app, "playstore_assets")
    os.makedirs(assets_dir, exist_ok=True)
    src = os.path.join(customer_app, "assets", "logo.png")
    out = os.path.join(assets_dir, "app_icon_512.png")

    if not os.path.isfile(src):
        print(f"Error: Logo not found at {src}")
        sys.exit(1)

    try:
        from PIL import Image
    except ImportError:
        print("Install Pillow first: pip install Pillow")
        sys.exit(1)

    img = Image.open(src)
    img = img.convert("RGBA")  # 32-bit with alpha
    img_resized = img.resize((512, 512), Image.Resampling.LANCZOS)
    img_resized.save(out, "PNG")
    print(f"Saved: {out}")
    print("Upload playstore_assets/app_icon_512.png in Play Console as the 512x512 app icon.")

if __name__ == "__main__":
    main()
