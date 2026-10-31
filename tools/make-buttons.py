#!/usr/bin/env python3
"""make-buttons.py -- draw the settings and restart buttons: a glossy coloured
disc with a white symbol.  Each is 150x150 with alpha, a 50x50 point button
at 3x.

    python3 tools/make-buttons.py
"""
import math, os, struct, zlib

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, ".."))
SIZE = 150
CX, CY = 75, 72
RADIUS = 58
OUTLINE = (28, 14, 16)

PALETTE = {"B": (51, 115, 230), "R": (232, 61, 56)}

def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))

def circle(x, y, cx, cy, radius):
    return math.hypot(x - cx, y - cy) - radius

def gear(x, y):
    dx, dy = x - CX, y - CY
    r = math.hypot(dx, dy)
    a = math.atan2(dy, dx)
    tooth = clamp((math.cos(8 * a + math.pi / 8) - 0.05) * 2.2)
    body = r - (23 + 9 * tooth)
    hole = 9.5 - r
    return max(body, hole)

def triangle(px, py, a, b, c):
    def edge(p, q):
        ex, ey = q[0] - p[0], q[1] - p[1]
        wx, wy = px - p[0], py - p[1]
        t = clamp((wx * ex + wy * ey) / (ex * ex + ey * ey))
        return math.hypot(wx - ex * t, wy - ey * t), ex * wy - ey * wx
    d = min(edge(a, b)[0], edge(b, c)[0], edge(c, a)[0])
    signs = [edge(a, b)[1], edge(b, c)[1], edge(c, a)[1]]
    inside = all(s >= 0 for s in signs) or all(s <= 0 for s in signs)
    return -d if inside else d

def restart_arrow(x, y):
    dx, dy = x - CX, y - CY
    R, w = 25, 6.5
    a = math.degrees(math.atan2(dy, dx))
    start, end = -35, -105
    in_gap = end < a < start
    if in_gap:
        ends = [(CX + R * math.cos(math.radians(t)), CY + R * math.sin(math.radians(t))) for t in (start, end)]
        ring = min(math.hypot(x - ex, y - ey) for ex, ey in ends) - w
    else:
        ring = abs(math.hypot(dx, dy) - R) - w
    t = math.radians(end)
    px, py = CX + R * math.cos(t), CY + R * math.sin(t)
    tx, ty = -math.sin(t), math.cos(t)
    nx, ny = math.cos(t), math.sin(t)
    tip = (px + tx * 17, py + ty * 17)
    back = (px - tx * 5, py - ty * 5)
    head = triangle(x, y, tip, (back[0] + nx * 15, back[1] + ny * 15), (back[0] - nx * 15, back[1] - ny * 15))
    return min(ring, head)

def over(dst, colour, alpha):
    if alpha <= 0:
        return dst
    r, g, b, a = dst
    out_a = alpha + a * (1 - alpha)
    if out_a <= 0:
        return (0, 0, 0, 0)
    mixc = [(c * alpha + d * a * (1 - alpha)) / out_a for c, d in zip(colour, (r, g, b))]
    return (*mixc, out_a)

def draw(colour, symbol):
    pixels = [[(0, 0, 0, 0)] * SIZE for _ in range(SIZE)]
    light = tuple(min(255, c * 1.25 + 25) for c in colour)
    dark = tuple(c * 0.62 for c in colour)
    for y in range(SIZE):
        for x in range(SIZE):
            p = pixels[y][x]
            d = circle(x - 4, y - 7, CX, CY, RADIUS)
            p = over(p, (0, 0, 0), 0.42 * clamp((8 - d) / 16))
            d = circle(x, y, CX, CY, RADIUS)
            p = over(p, OUTLINE, clamp(0.5 - (d - 3.5)))
            body = clamp(0.5 - d)
            if body > 0:
                t = (y - (CY - RADIUS)) / (2 * RADIUS)
                base = tuple(l + (k - l) * clamp(t * 1.15) for l, k in zip(light, dark))
                gloss = 0.3 * clamp(1 - t / 0.5) ** 1.5 * clamp(-d / 8)
                base = tuple(c + (255 - c) * gloss for c in base)
                p = over(p, base, body)
                if symbol:
                    sd = symbol(x - 2, y - 3)
                    p = over(p, OUTLINE, 0.35 * clamp(0.5 - sd / 2.5) * body)
                    p = over(p, (255, 255, 255), clamp(0.5 - symbol(x, y)) * body)
            pixels[y][x] = p
    return pixels

def png(pixels, path):
    raw = b"".join(b"\x00" + bytes(round(clamp(v / 255 if i < 3 else v) * 255)
                                   for p in row for i, v in enumerate(p)) for row in pixels)
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)
    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)))
        out.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        out.write(chunk(b"IEND", b""))

out = os.path.join(root, "res", "buttons")
os.makedirs(out, exist_ok=True)
png(draw(PALETTE["B"], gear), os.path.join(out, "button-settings.png"))
png(draw(PALETTE["R"], restart_arrow), os.path.join(out, "button-restart.png"))
print("wrote", os.path.relpath(out, root))
