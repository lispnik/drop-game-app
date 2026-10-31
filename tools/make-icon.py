#!/usr/bin/env python3
"""make-icon.py -- write res/Drop7.xcassets, the app icon: a 7×7 of coloured
discs on a dark plate, 1024x1024 with no alpha.

    python3 tools/make-icon.py
"""
import json, math, os, struct, zlib

SIZE = 1024
PALETTE = {
    1: (158, 82, 224),
    2: (56, 122, 235),
    3: (46, 184, 199),
    4: (71, 184, 82),
    5: (242, 199, 46),
    6: (245, 133, 36),
    7: (235, 66, 61),
}
GRAY = (140, 148, 158)
BG = (28, 32, 46)

# A tidy opening position for the icon.
GRID = [
    [0, 0, 0, 0, 0, 0, 0],
    [0, 0, 7, 0, 0, 0, 0],
    [0, 3, 2, 0, 0, 0, 0],
    [0, 5, 4, 1, 0, 0, 0],
    [6, 8, 3, 2, 7, 0, 0],   # 8 = solid gray
    [2, 4, 9, 5, 1, 6, 0],   # 9 = cracked gray
    [1, 3, 5, 7, 2, 4, 6],
]

pixels = [[BG] * SIZE for _ in range(SIZE)]

def shade(colour, k):
    return tuple(max(0, min(255, int(c * k))) for c in colour)

def mix(a, b, t):
    return tuple(int(x + (y - x) * t) for x, y in zip(a, b))

def fill_circle(cx, cy, radius, colour):
    r2 = radius * radius
    for y in range(max(0, int(cy - radius - 1)), min(SIZE, int(cy + radius + 2))):
        row = pixels[y]
        for x in range(max(0, int(cx - radius - 1)), min(SIZE, int(cx + radius + 2))):
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            if d2 <= r2:
                # Soft edge.
                edge = max(0.0, min(1.0, (radius - math.sqrt(d2)) * 1.5))
                # Top-left gloss.
                lit = 1.08 - 0.25 * ((y - (cy - radius * 0.4)) / (radius * 2))
                lit = max(0.7, min(1.15, lit))
                c = shade(colour, lit)
                row[x] = mix(row[x], c, edge)

# Plate.
margin = 70
fill_circle(SIZE / 2, SIZE / 2, SIZE / 2 - 20, (22, 26, 38))
for y in range(margin, SIZE - margin):
    for x in range(margin, SIZE - margin):
        pixels[y][x] = (18, 22, 34)

cell = (SIZE - 2 * margin) / 7
radius = cell * 0.38
for r, row in enumerate(GRID):
    for c, val in enumerate(row):
        if not val:
            continue
        cx = margin + (c + 0.5) * cell
        cy = margin + (r + 0.5) * cell
        if val == 8:
            colour = GRAY
            fill_circle(cx, cy, radius, colour)
            fill_circle(cx, cy, radius * 0.35, shade(GRAY, 0.7))
        elif val == 9:
            fill_circle(cx, cy, radius, shade(GRAY, 1.15))
            # Crack.
            for t in range(-int(radius * 0.55), int(radius * 0.55)):
                x = int(cx + t * 0.85)
                y = int(cy + t * 0.35)
                if 0 <= x < SIZE and 0 <= y < SIZE:
                    pixels[y][x] = shade(GRAY, 0.45)
                    if y + 1 < SIZE:
                        pixels[y + 1][x] = shade(GRAY, 0.45)
        else:
            colour = PALETTE[val]
            fill_circle(cx, cy, radius, colour)
            # Number, drawn as a blocky digit roughly centred.
            digit = str(val)
            # Simple filled bars for 1–7 readability at icon size: a disc of
            # contrasting centre is enough; the game itself draws the digit.
            ink = (20, 18, 22) if val == 5 else (255, 255, 255)
            fill_circle(cx, cy - radius * 0.05, radius * 0.22, ink)

def png(path):
    raw = b"".join(b"\x00" + bytes(round(v) for p in row for v in p) for row in pixels)
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)
    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)))
        out.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        out.write(chunk(b"IEND", b""))

here = os.path.dirname(os.path.abspath(__file__))
catalogue = os.path.join(here, "..", "res", "Drop7.xcassets")
iconset = os.path.join(catalogue, "AppIcon.appiconset")
os.makedirs(iconset, exist_ok=True)
info = {"author": "drop7-clone-app", "version": 1}
json.dump({"info": info}, open(os.path.join(catalogue, "Contents.json"), "w"), indent=2)
json.dump({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": info}, open(os.path.join(iconset, "Contents.json"), "w"), indent=2)
png(os.path.join(iconset, "icon.png"))
print("wrote", os.path.normpath(iconset))
