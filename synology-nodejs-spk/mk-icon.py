#!/usr/bin/env python3
"""Generate a Synology package icon (PNG) with no third-party dependencies.

Draws the Node.js brand mark: a green rounded tile with a white hexagon.
Usage: mk-icon.py <output.png> <size>
"""
import math
import struct
import sys
import zlib

BG = (67, 133, 61)      # Node.js brand green
FG = (255, 255, 255)
SS = 4                  # supersampling factor per axis


def rounded_tile_cov(px, py, size):
    """Coverage of a rounded square that fills the whole icon."""
    half = size / 2.0
    r = 0.22 * size
    qx = abs(px - half) - (half - r)
    qy = abs(py - half) - (half - r)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return (outside + inside - r) <= 0.0


def hexagon(cx, cy, r):
    return [
        (cx + r * math.cos(math.radians(60 * i - 90)),
         cy + r * math.sin(math.radians(60 * i - 90)))
        for i in range(6)
    ]


def point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


def render(size):
    cx = cy = size / 2.0
    hex_poly = hexagon(cx, cy, 0.30 * size)
    step = 1.0 / SS
    out = bytearray()
    inv = 1.0 / (SS * SS)
    for y in range(size):
        for x in range(size):
            sr = sg = sb = sa = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    px = x + (sx + 0.5) * step
                    py = y + (sy + 0.5) * step
                    if point_in_poly(px, py, hex_poly):
                        cr, cg, cb = FG
                    elif rounded_tile_cov(px, py, size):
                        cr, cg, cb = BG
                    else:
                        continue
                    sr += cr * inv
                    sg += cg * inv
                    sb += cb * inv
                    sa += inv
            if sa > 0.0:
                out += bytes((int(round(sr / sa)), int(round(sg / sa)),
                              int(round(sb / sa)), int(round(sa * 255))))
            else:
                out += b"\x00\x00\x00\x00"
    return bytes(out)


def write_png(path, size, rgba):
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data +
                struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))

    stride = size * 4
    raw = b"".join(b"\x00" + rgba[y * stride:(y + 1) * stride] for y in range(size))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: mk-icon.py <output.png> <size>")
    path, size = sys.argv[1], int(sys.argv[2])
    write_png(path, size, render(size))


if __name__ == "__main__":
    main()