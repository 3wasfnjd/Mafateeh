"""The QR code of the studio's site for the thank-you panel (scanned with a phone, so the
player never has to leave the game for the headset's browser).
python3 tools/art/make_site_qr.py      (needs: pip install qrcode)
"""
import os

import qrcode
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "ui", "site_qr.png")
URL = "https://abodengames.com"

qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=16, border=2)
qr.add_data(URL)
qr.make(fit=True)
# dark brown on the menu's cream, like the rest of the plaque
img = qr.make_image(fill_color=(79, 56, 38), back_color=(251, 243, 228)).convert("RGB")
img = img.resize((512, 512), Image.NEAREST)
img.save(OUT)
print("wrote", os.path.abspath(OUT), img.size)
