"""Generates the addon's textures as uncompressed 32-bit TGA files."""
import math
import os
import struct

OUT = os.path.join(os.path.dirname(__file__), "..", "Beatcraft", "Media")
SS = 4


def write_tga(path, w, h, pixels):
    """pixels: list of rows (top to bottom) of (r, g, b, a) floats 0..1."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    body = bytearray()
    for row in reversed(pixels):
        for r, g, b, a in row:
            body += bytes((
                int(max(0, min(1, b)) * 255 + 0.5),
                int(max(0, min(1, g)) * 255 + 0.5),
                int(max(0, min(1, r)) * 255 + 0.5),
                int(max(0, min(1, a)) * 255 + 0.5),
            ))
    with open(path, "wb") as f:
        f.write(header + bytes(body))


def render(w, h, shader):
    """shader(x, y) -> (r, g, b, a) in texture units 0..w, 0..h; supersampled."""
    rows = []
    for py in range(h):
        row = []
        for px in range(w):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    r, g, b, a = shader(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                    acc[0] += r * a
                    acc[1] += g * a
                    acc[2] += b * a
                    acc[3] += a
            n = SS * SS
            a = acc[3] / n
            if a > 0:
                row.append((acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], a))
            else:
                row.append((1, 1, 1, 0))
        rows.append(row)
    return rows


def save(name, w, h, shader):
    write_tga(os.path.join(OUT, name + ".tga"), w, h, render(w, h, shader))
    print("wrote", name)


def polar(x, y, size):
    c = size / 2
    dx, dy = x - c, y - c
    return math.hypot(dx, dy), math.atan2(dy, dx)


def circle(x, y):
    d, _ = polar(x, y, 128)
    if d > 60:
        return (1, 1, 1, 0)
    shade = 1.0 - 0.25 * (d / 60) ** 2
    return (shade, shade, shade, 1)


def circle_overlay(x, y):
    d, _ = polar(x, y, 128)
    if 54 <= d <= 61:
        return (1, 1, 1, 1)
    if 49 <= d < 54:
        return (0, 0, 0, 0.35 * (d - 49) / 5)
    return (1, 1, 1, 0)


def approach(x, y):
    d, _ = polar(x, y, 128)
    return (1, 1, 1, 1 if 57 <= d <= 62 else 0)


def glow(x, y):
    d, _ = polar(x, y, 128)
    a = math.exp(-((d / 30.0) ** 2))
    return (1, 1, 1, a if d < 63 else 0)


def dot(x, y):
    d, _ = polar(x, y, 64)
    return (1, 1, 1, 1 if d <= 30 else 0)


def ring(x, y):
    d, _ = polar(x, y, 256)
    return (1, 1, 1, 1 if 112 <= d <= 124 else 0)


def cursor(x, y):
    d, _ = polar(x, y, 64)
    if d <= 9:
        return (1, 1, 1, 1)
    if d <= 13:
        return (1, 0.85, 0.95, 1)
    a = math.exp(-(((d - 13) / 9.0) ** 2)) * 0.8
    return (1, 0.6, 0.85, a if d < 31 else 0)


def rounded_rect(size, radius, border):
    def shader(x, y):
        m = 2
        lo, hi = m + radius, size - m - radius
        cx = min(max(x, lo), hi)
        cy = min(max(y, lo), hi)
        d = math.hypot(x - cx, y - cy)
        if d > radius:
            return (1, 1, 1, 0)
        if border and d > radius - border:
            return (1, 1, 1, 1)
        if border:
            return (0.75, 0.75, 0.75, 0.0)
        return (1, 1, 1, 1)
    return shader


def lane_grad(x, y):
    t = y / 128.0
    return (1, 1, 1, t ** 1.6)


def logo(x, y):
    d, ang = polar(x, y, 128)
    if d > 62:
        return (1, 1, 1, 0)
    if d > 55:
        return (1, 1, 1, 1)
    px, py = x - 64, y - 64
    if -16 <= px <= 24 and abs(py) <= (24 - px) * 0.75 and abs(py) <= 22:
        return (1, 1, 1, 1)
    return (1.0, 0.40, 0.67, 1)


def arrow(x, y):
    px, py = x - 32, y - 32
    t = 7
    on = abs(abs(py) - (14 - px * 1.0)) < t and -10 <= px <= 16 and abs(py) <= 22
    return (1, 1, 1, 1 if on else 0)


def main():
    os.makedirs(OUT, exist_ok=True)
    save("circle", 128, 128, circle)
    save("circleoverlay", 128, 128, circle_overlay)
    save("approach", 128, 128, approach)
    save("glow", 128, 128, glow)
    save("dot", 64, 64, dot)
    save("ring", 256, 256, ring)
    save("cursor", 64, 64, cursor)
    save("note", 64, 64, rounded_rect(64, 12, 0))
    save("noteborder", 64, 64, rounded_rect(64, 12, 5))
    save("lane", 32, 128, lane_grad)
    save("logo", 128, 128, logo)
    save("arrow", 64, 64, arrow)


if __name__ == "__main__":
    main()
