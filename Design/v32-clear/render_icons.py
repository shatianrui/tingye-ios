from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Tingye/Resources/Assets.xcassets/AppIcon.appiconset"
PREVIEW = Path(__file__).resolve().parent
SIZE = 1024
SCALE = 4


def cubic(p0, p1, p2, p3, steps=28):
    points = []
    for index in range(steps):
        t = index / steps
        u = 1 - t
        points.append((
            u**3*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t**3*p3[0],
            u**3*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t**3*p3[1],
        ))
    return points


def page(left=True):
    if left:
        points = [(190, 314)]
        points += cubic((190, 314), (290, 270), (410, 292), (492, 354))
        points += [(492, 742)]
        points += cubic((492, 742), (408, 684), (298, 666), (190, 700))
    else:
        points = [(834, 314)]
        points += cubic((834, 314), (734, 270), (614, 292), (532, 354))
        points += [(532, 742)]
        points += cubic((532, 742), (616, 684), (726, 666), (834, 700))
    return [(round(x*SCALE), round(y*SCALE)) for x, y in points]


def icon(name, top, bottom, pages, cutout):
    image = Image.new("RGB", (SIZE*SCALE, SIZE*SCALE), top)
    pixels = image.load()
    for y in range(SIZE*SCALE):
        for x in range(SIZE*SCALE):
            diagonal = (x + y) / (2 * (SIZE*SCALE - 1))
            glow = max(0, 1 - (((x/SIZE/SCALE)-0.2)**2 + ((y/SIZE/SCALE)-0.12)**2) ** 0.5) * 0.08
            ratio = min(1, max(0, diagonal * 0.72 - glow))
            pixels[x, y] = tuple(round(top[c]*(1-ratio) + bottom[c]*ratio) for c in range(3))
    draw = ImageDraw.Draw(image)
    shadow = (0, 0, 0)
    if sum(top) > 420:
        shadow = (20, 30, 40)
    left = page(True)
    right = page(False)
    draw.polygon([(x, y+10*SCALE) for x, y in left], fill=shadow)
    draw.polygon([(x, y+10*SCALE) for x, y in right], fill=shadow)
    draw.polygon(left, fill=pages)
    draw.polygon(right, fill=pages)
    for x, y, width, height in [(602, 450, 34, 132), (664, 402, 34, 230), (726, 464, 34, 104)]:
        draw.rounded_rectangle((x*SCALE, y*SCALE, (x+width)*SCALE, (y+height)*SCALE), radius=17*SCALE, fill=cutout)
    image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    image.save(OUT / name, optimize=True)
    return image


def rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i+2], 16) for i in (0, 2, 4))


light = icon("AppIcon.png", rgb("3B76E8"), rgb("17479F"), rgb("FFFFFF"), rgb("245FD1"))
dark = icon("AppIcon-dark.png", rgb("1B2838"), rgb("080D13"), rgb("9ABDFF"), rgb("101A28"))
tinted = icon("AppIcon-tinted.png", rgb("DDE2E8"), rgb("BEC7D1"), rgb("343C45"), rgb("C7CED6"))

canvas = Image.new("RGB", (1680, 640), rgb("F5F7FA"))
draw = ImageDraw.Draw(canvas)
for index, (image, label) in enumerate([(light, "LIGHT"), (dark, "DARK"), (tinted, "TINTED")]):
    resized = image.resize((440, 440), Image.Resampling.LANCZOS)
    mask = Image.new("L", (440, 440), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 439, 439), radius=98, fill=255)
    x = 70 + index*540
    canvas.paste(resized, (x, 70), mask)
    draw.text((x+180, 550), label, fill=rgb("465464"))
canvas.save(PREVIEW / "app-icon-overview.png", optimize=True)
print("Generated 3 RGB 1024px production icons and overview")
