import io
import secrets

import qrcode
from qrcode.constants import ERROR_CORRECT_H
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"  # no 0/O/1/I/L - safe to read aloud and type


def new_code() -> str:
    return "KSV-" + "".join(secrets.choice(ALPHABET) for _ in range(6))


def sheet_pdf(codes: list[str]) -> bytes:
    """A4 sheet, 4 x 5 tags per page, 45 mm QR (error correction H) + code printed under it."""
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    W, H = A4
    cols, rows = 4, 5
    cw, ch, size = W / cols, H / rows, 45 * mm
    per_page = cols * rows
    for i, code in enumerate(codes):
        if i and i % per_page == 0:
            c.showPage()
        j = i % per_page
        col, row = j % cols, j // cols
        x0, y0 = col * cw, H - (row + 1) * ch
        qr = qrcode.QRCode(error_correction=ERROR_CORRECT_H, box_size=10, border=2)
        qr.add_data(code)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white").get_image()
        c.setStrokeGray(0.7)
        c.rect(x0 + 2 * mm, y0 + 2 * mm, cw - 4 * mm, ch - 4 * mm)  # cut guide
        c.drawImage(ImageReader(img), x0 + (cw - size) / 2, y0 + 9 * mm, size, size)
        c.setFont("Helvetica-Bold", 12)
        c.drawCentredString(x0 + cw / 2, y0 + 4.5 * mm, code)
    c.save()
    return buf.getvalue()
