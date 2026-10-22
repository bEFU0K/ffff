#!/usr/bin/env python3
"""Генерирует patches/GfpramIconImages.swift: превью иконок (base64) для окна выбора иконок и шапки Premium.
Запуск: python3 tools/gen_icon_images.py  (нужен Pillow)."""
import base64, io, os
from PIL import Image

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(root, "assets")
# ключ -> (файл, сторона превью в px)
ICONS = [
    ("main", os.path.join(A, "icon.png"), 132),
    ("red", os.path.join(A, "icons", "red.jpg"), 132),
    ("black", os.path.join(A, "icons", "black.jpg"), 132),
    ("anime", os.path.join(A, "icons", "anime.jpg"), 132),
    ("ocean", os.path.join(A, "icons", "ocean.jpg"), 132),
    ("sponge", os.path.join(A, "icons", "sponge.jpg"), 132),
    ("gold", os.path.join(A, "icons", "gold.jpg"), 330),
    ("turbo", os.path.join(A, "icons", "turbo.jpg"), 330),
    ("night", os.path.join(A, "icons", "night.jpg"), 330),
    ("duck", os.path.join(A, "icons", "duck.jpg"), 330),
]
out = ["// Автогенерация: tools/gen_icon_images.py. Превью иконок GFPGRAM (JPEG, base64).",
       "let gfpramIconPreviews: [String: String] = ["]
for i, (key, path, px) in enumerate(ICONS):
    im = Image.open(path).convert("RGB").resize((px, px), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=80, optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode()
    chunks = [b64[j:j + 8000] for j in range(0, len(b64), 8000)]
    out.append('    "%s": [' % key)
    for c in chunks:
        out.append('        "%s",' % c)
    out.append("    ].joined()" + ("," if i < len(ICONS) - 1 else ""))
out.append("]")
dst = os.path.join(root, "patches", "GfpramIconImages.swift")
with open(dst, "w") as f:
    f.write("\n".join(out) + "\n")
print("OK", dst, os.path.getsize(dst) // 1024, "KB")
