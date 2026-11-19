"""Genera el icono de la app (reloj + check sobre azul) para Windows y macOS.

Uso (desde la raíz del proyecto):
    python -m pip install pillow
    python tool/generate_icon.py

Escribe:
  - assets/icon/app_icon.png                      (maestro 1024x1024, también se usa en la UI)
  - windows/runner/resources/app_icon.ico         (16..256 px)
  - macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{16..1024}.png

Dibujo propio: no reproduce el logo de Jira ni de Flutter.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
MASTER = 1024
SS = 2  # supersampling para bordes suaves
S = MASTER * SS


def px(v: float) -> int:
    return round(v * SS)


def gradient(size, top, bottom):
    """Degradado vertical de `top` a `bottom` (colores RGB)."""
    mask = Image.linear_gradient("L").resize((size, size))
    return Image.composite(
        Image.new("RGB", (size, size), bottom), Image.new("RGB", (size, size), top), mask
    )


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius, fill=255)
    return m


def line(draw, p1, p2, width, fill):
    draw.line([p1, p2], fill=fill, width=width)
    r = width / 2
    for x, y in (p1, p2):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def build_master() -> Image.Image:
    # Fondo: cuadrado redondeado con degradado azul.
    bg = gradient(S, (0x4A, 0x9B, 0xFF), (0x0B, 0x4F, 0xC9)).convert("RGBA")
    bg.putalpha(rounded_mask(S, px(230)))
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.alpha_composite(bg)

    # Brillo suave arriba para dar volumen.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((px(-200), px(-520), px(1224), px(380)), fill=(255, 255, 255, 30))
    glow = glow.filter(ImageFilter.GaussianBlur(px(110)))
    glow.putalpha(Image.composite(glow.getchannel("A"), Image.new("L", (S, S), 0), rounded_mask(S, px(230))))
    img.alpha_composite(glow)

    d = ImageDraw.Draw(img)
    cx, cy, R = px(488), px(488), px(318)

    # Sombra del reloj.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((cx - R, cy - R + px(26), cx + R, cy + R + px(26)), fill=(6, 30, 90, 110))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(px(28))))

    # Esfera: aro claro + cara blanca.
    d.ellipse((cx - R, cy - R, cx + R, cy + R), fill=(255, 255, 255, 255))
    ring = px(26)
    d.ellipse((cx - R + ring, cy - R + ring, cx + R - ring, cy + R - ring), fill=(238, 245, 255, 255))

    navy = (11, 46, 115, 255)
    # Marcas de las 12, 3, 6 y 9.
    for ang_x, ang_y in ((0, -1), (1, 0), (0, 1), (-1, 0)):
        a = (cx + ang_x * px(232), cy + ang_y * px(232))
        b = (cx + ang_x * px(262), cy + ang_y * px(262))
        line(d, a, b, px(20), navy)

    # Manecillas (≈ 10:10) y centro.
    line(d, (cx, cy), (cx, cy - px(200)), px(34), navy)  # minutero
    line(d, (cx, cy), (cx + px(130), cy - px(78)), px(34), navy)  # horario
    d.ellipse((cx - px(30), cy - px(30), cx + px(30), cy + px(30)), fill=(0x2B, 0x7B, 0xFF, 255))

    # Insignia de "tarea hecha": check verde con borde blanco.
    bx, by, br = px(748), px(748), px(190)
    badge_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(badge_shadow).ellipse((bx - br, by - br + px(18), bx + br, by + br + px(18)), fill=(4, 24, 70, 120))
    img.alpha_composite(badge_shadow.filter(ImageFilter.GaussianBlur(px(20))))
    d = ImageDraw.Draw(img)
    d.ellipse((bx - br - px(24), by - br - px(24), bx + br + px(24), by + br + px(24)), fill=(255, 255, 255, 255))
    inner = gradient(2 * br, (0x34, 0xD3, 0x99), (0x0F, 0x9D, 0x58)).convert("RGBA")
    circle = Image.new("L", (2 * br, 2 * br), 0)
    ImageDraw.Draw(circle).ellipse((0, 0, 2 * br - 1, 2 * br - 1), fill=255)
    inner.putalpha(circle)
    img.alpha_composite(inner, (bx - br, by - br))
    d = ImageDraw.Draw(img)
    check = [(bx - px(84), by + px(4)), (bx - px(22), by + px(68)), (bx + px(92), by - px(62))]
    line(d, check[0], check[1], px(40), (255, 255, 255, 255))
    line(d, check[1], check[2], px(40), (255, 255, 255, 255))

    return img.resize((MASTER, MASTER), Image.LANCZOS)


def main():
    master = build_master()

    assets = ROOT / "assets" / "icon"
    assets.mkdir(parents=True, exist_ok=True)
    master.save(assets / "app_icon.png")

    ico = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    master.save(ico, format="ICO", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])

    mac = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        master.resize((size, size), Image.LANCZOS).save(mac / f"app_icon_{size}.png")

    print("Iconos generados:", assets / "app_icon.png", ico, mac, sep="\n  ")


if __name__ == "__main__":
    main()
