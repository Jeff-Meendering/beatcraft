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


def smooth(edge0, edge1, v):
    t = min(max((v - edge0) / (edge1 - edge0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def band(d, inner, outer, soft=1.0):
    return smooth(inner - soft, inner + soft, d) * (1 - smooth(outer - soft, outer + soft, d))


def circle(x, y):
    d, _ = polar(x, y, 256)
    if d > 121:
        return (1, 1, 1, 0)
    shade = 0.45 + 0.32 * (1 - (d / 120) ** 2) + 0.12 * (1 - y / 256)
    return (shade, shade, shade, 1 - smooth(119, 121, d))


def circle_overlay(x, y):
    d, _ = polar(x, y, 256)
    rim = band(d, 111, 119)
    edge = band(d, 119, 123) * 0.55
    shadow = band(d, 104, 110) * 0.28
    if rim > 0.01:
        return (1, 1, 1, rim)
    if edge > 0.01:
        return (0, 0, 0, edge)
    return (0, 0, 0, shadow)


def approach(x, y):
    d, _ = polar(x, y, 256)
    return (1, 1, 1, band(d, 117, 122))


def ball(x, y):
    d, _ = polar(x, y, 256)
    if d > 104:
        return (1, 1, 1, 0)
    if d > 92:
        return (1, 1, 1, 1 - smooth(102, 104, d))
    shade = 0.75 + 0.25 * (1 - d / 92)
    return (shade, shade, shade, 1)


def follow(x, y):
    d, _ = polar(x, y, 256)
    ring_a = band(d, 117, 122)
    fill = 0.06 if d < 117 else 0
    return (1, 1, 1, max(ring_a, fill))


def glow(x, y):
    d, _ = polar(x, y, 128)
    a = math.exp(-((d / 30.0) ** 2))
    return (1, 1, 1, a if d < 63 else 0)


def dot(x, y):
    d, _ = polar(x, y, 128)
    return (1, 1, 1, 1 - smooth(59, 61, d))


def followpoint(x, y):
    px, py = abs(x - 32), abs(y - 32)
    dx = max(px - 14, 0)
    d = math.hypot(dx, py)
    return (1, 1, 1, 1 - smooth(3, 5, d))


def spinner(x, y):
    d, ang = polar(x, y, 256)
    outer = band(d, 118, 124)
    notch = (math.degrees(ang) % 30) < 4
    inner = band(d, 70, 73) * 0.45
    if outer > 0.01:
        return (1, 1, 1, outer * (0.35 if notch else 1))
    return (1, 1, 1, inner)


def ring(x, y):
    d, _ = polar(x, y, 256)
    return (1, 1, 1, band(d, 112, 124))


def cursor(x, y):
    d, _ = polar(x, y, 64)
    ring_a = band(d, 19, 24, 0.8)
    center = 1 - smooth(3, 5, d)
    glow_a = math.exp(-(((d - 21) / 7.0) ** 2)) * 0.25
    return (1, 1, 1, max(ring_a, center, glow_a if d < 31 else 0))


def trail(x, y):
    d, _ = polar(x, y, 32)
    return (1, 1, 1, math.exp(-((d / 7.0) ** 2)) if d < 15 else 0)

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

    def seg(ax, ay, bx, by):
        vx, vy = bx - ax, by - ay
        t = min(max(((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy), 0), 1)
        return math.hypot(px - (ax + vx * t), py - (ay + vy * t))

    d = min(seg(-10, -18, 12, 0), seg(12, 0, -10, 18))
    return (1, 1, 1, 1 - smooth(5, 7, d))

def main():
    os.makedirs(OUT, exist_ok=True)
    save("circle", 256, 256, circle)
    save("circleoverlay", 256, 256, circle_overlay)
    save("approach", 256, 256, approach)
    save("ball", 256, 256, ball)
    save("follow", 256, 256, follow)
    save("glow", 128, 128, glow)
    save("dot", 128, 128, dot)
    save("followpoint", 64, 64, followpoint)
    save("spinner", 256, 256, spinner)
    save("ring", 256, 256, ring)
    save("cursor", 64, 64, cursor)
    save("blank", 32, 32, lambda x, y: (1, 1, 1, 0))
    save("trail", 32, 32, trail)
    save("note", 64, 64, rounded_rect(64, 12, 0))
    save("noteborder", 64, 64, rounded_rect(64, 12, 5))
    save("lane", 32, 128, lane_grad)
    save("logo", 128, 128, logo)
    save("arrow", 64, 64, arrow)


if __name__ == "__main__":
    main()
