#!/usr/bin/env python3
"""Draw the Pocket Arcade app icons (a pixel snake on a green LCD) into src/."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")

LCD = (155, 188, 15)
MID = (48, 98, 48)
INK = (15, 56, 15)

GRID = 16
body = []
body += [(x, 4) for x in range(3, 11)]
body += [(10, y) for y in range(5, 9)]
body += [(x, 8) for x in range(9, 4, -1)]
body += [(5, y) for y in range(9, 12)]
body += [(x, 11) for x in range(6, 13)]
food = (13, 4)


def draw(size):
    cell = size / GRID
    img = Image.new("RGB", (size, size), LCD)
    d = ImageDraw.Draw(img)
    inset = cell * 0.08

    def rect(cx, cy, color, grow=0.0):
        x0 = cx * cell + inset - grow
        y0 = cy * cell + inset - grow
        x1 = (cx + 1) * cell - inset + grow
        y1 = (cy + 1) * cell - inset + grow
        d.rectangle([round(x0), round(y0), round(x1) - 1, round(y1) - 1], fill=color)

    for i, (cx, cy) in enumerate(body):
        rect(cx, cy, INK)
        if i != len(body) - 1:
            rect(cx, cy, MID)
            d.rectangle(
                [round(cx * cell + cell * 0.28), round(cy * cell + cell * 0.28),
                 round((cx + 1) * cell - cell * 0.28) - 1, round((cy + 1) * cell - cell * 0.28) - 1],
                fill=INK,
            )
    hx, hy = body[-1]
    rect(hx, hy, INK, grow=cell * 0.04)
    # eye
    ex, ey = hx * cell + cell * 0.55, hy * cell + cell * 0.2
    d.rectangle([round(ex), round(ey), round(ex + cell * 0.2) - 1, round(ey + cell * 0.2) - 1], fill=LCD)
    # food: a small plus
    fx, fy = food
    cx0, cy0 = fx * cell, fy * cell
    d.rectangle([round(cx0 + cell * 0.4), round(cy0 + cell * 0.12), round(cx0 + cell * 0.6) - 1, round(cy0 + cell * 0.88) - 1], fill=INK)
    d.rectangle([round(cx0 + cell * 0.12), round(cy0 + cell * 0.4), round(cx0 + cell * 0.88) - 1, round(cy0 + cell * 0.6) - 1], fill=INK)
    return img


for size, name in ((180, "icon-180.png"), (192, "icon-192.png"), (512, "icon-512.png")):
    draw(size).save(os.path.join(SRC, name), optimize=True)
print("icons written")
