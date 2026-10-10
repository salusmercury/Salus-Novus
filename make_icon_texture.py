"""Draw the AddOn List icon: salusnovus/Textures/icon.tga.

Pink 'SN' in Prototype on a dark panel inside a pink gradient square
(Alex picked variant 8, 2026-10-10). Drawn at 512 and downsampled to
64 x 64; uncompressed 32-bit TGA, top-left origin. The TOC points at it
with ## IconTexture. Prototype comes from SharedMediaAdditionalFonts in
the game folder (the font isn't shipped, only this picture of it).

    python make_icon_texture.py
"""
import io, os, struct
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "salusnovus", "Textures", "icon.tga")
FONT = (r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface"
        r"\AddOns\SharedMediaAdditionalFonts\fonts\Prototype.ttf")
SIZE, S = 64, 512
PINK = (255, 92, 168)
PINK_DK = (176, 34, 106)
INK = (22, 16, 24)


def draw():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # pink square, top to bottom gradient
    grad = Image.new("RGBA", (S, S))
    g = ImageDraw.Draw(grad)
    for y in range(S):
        k = y / (S - 1)
        g.line([(0, y), (S, y)], fill=tuple(int(PINK[i] + (PINK_DK[i] - PINK[i]) * k) for i in range(3)) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([12, 12, S - 12, S - 12], radius=40, fill=255)
    im.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(im)
    # dark panel
    d.rounded_rectangle([56, 56, S - 56, S - 56], radius=28, fill=INK + (255,))
    # letters, centred on their ink
    f = ImageFont.truetype(FONT, 250)
    l, t, r, b = d.textbbox((0, 0), "SN", font=f)
    d.text(((S - (r - l)) / 2 - l, (S - (b - t)) / 2 - t), "SN", font=f, fill=PINK)
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    im = draw()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    with io.open(OUT, "wb") as fh:
        fh.write(header)
        for y in range(SIZE):
            row = bytearray()
            for x in range(SIZE):
                r, g, b, a = im.getpixel((x, y))
                row += bytes((b, g, r, a))          # TGA stores BGRA
            fh.write(bytes(row))
    print("wrote %s (%d x %d)" % (os.path.relpath(OUT, HERE), SIZE, SIZE))


if __name__ == "__main__":
    main()
