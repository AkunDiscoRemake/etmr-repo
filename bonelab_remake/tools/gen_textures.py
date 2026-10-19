#!/usr/bin/env python3
"""Gera todas as texturas do BoneLab Remake (PNG) de forma procedural.
Uso: python3 tools/gen_textures.py   (escreve em images/)
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "images")
os.makedirs(OUT, exist_ok=True)

FONT_BOLD = "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf"
FONT_DISPLAY = "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf"
FONT_MED = "/usr/share/fonts/opentype/inter/InterDisplay-Medium.otf"
FONT_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

ORANGE = (255, 115, 20)
rng = np.random.default_rng(7)
random.seed(7)


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", size)


def noise(w, h, scale, octaves=4, seed=0):
    """Ruido de valor multi-oitava em [0,1]."""
    r = np.random.default_rng(seed)
    acc = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(1, int(scale / (2 ** o)))
        gw, gh = max(2, w // s + 2), max(2, h // s + 2)
        g = r.random((gh, gw)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        acc += np.asarray(img, np.float32) / 255.0 * amp
        tot += amp
        amp *= 0.5
    return acc / tot


def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def tint(gray, color):
    """gray em [0,1] (h,w) -> RGB multiplicado pela cor."""
    c = np.array(color, np.float32)[None, None, :]
    return gray[..., None] * c


def save(img, name):
    p = os.path.join(OUT, name)
    img.save(p, optimize=True)
    return p


def text_center(draw, box, text, fnt, fill, stroke=0, stroke_fill=None):
    x0, y0, x1, y1 = box
    bb = draw.textbbox((0, 0), text, font=fnt, stroke_width=stroke)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    draw.text((x0 + (x1 - x0 - tw) / 2 - bb[0], y0 + (y1 - y0 - th) / 2 - bb[1]), text, font=fnt, fill=fill,
              stroke_width=stroke, stroke_fill=stroke_fill)


def fit_font(draw, text, path, max_w, max_h, start=200):
    s = start
    while s > 8:
        f = font(path, s)
        bb = draw.textbbox((0, 0), text, font=f)
        if bb[2] - bb[0] <= max_w and bb[3] - bb[1] <= max_h:
            return f
        s -= 4
    return font(path, 8)


# ---------------------------------------------------------------------------
# Superficies do laboratorio
# ---------------------------------------------------------------------------
def floor():
    W = 1024
    n = 12
    t = W / n
    base = 0.78 + 0.08 * noise(W, W, 64, 5, 1) - 0.05 * noise(W, W, 8, 2, 2)
    arr = tint(base, (205, 208, 214))
    tile_var = rng.random((n, n)) * 0.08 - 0.04
    yy, xx = np.mgrid[0:W, 0:W]
    ti, tj = (yy // t).astype(int), (xx // t).astype(int)
    arr *= (1 + tile_var[ti % n, tj % n])[..., None]
    # rejuntes
    fx = (xx % t) / t
    fy = (yy % t) / t
    seam = (np.minimum(fx, 1 - fx) < 0.012) | (np.minimum(fy, 1 - fy) < 0.012)
    arr[seam] *= 0.45
    bevel = (np.minimum(fx, 1 - fx) < 0.03) | (np.minimum(fy, 1 - fy) < 0.03)
    arr[bevel & ~seam] *= 0.9
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    # parafusos nos cantos dos ladrilhos
    for i in range(n):
        for j in range(n):
            for (ox, oy) in ((0.08, 0.08), (0.92, 0.08), (0.08, 0.92), (0.92, 0.92)):
                cx, cy = (j + ox) * t, (i + oy) * t
                d.ellipse([cx - 2.5, cy - 2.5, cx + 2.5, cy + 2.5], fill=(120, 122, 128))
    # faixas de caminho (cinza escuro com borda laranja)
    for k in (5.5,):
        y0 = k * t
        d.rectangle([0, y0 + 8, W, y0 + t - 8], fill=(70, 72, 78))
        d.rectangle([0, y0 + 8, W, y0 + 12], fill=ORANGE)
        d.rectangle([0, y0 + t - 12, W, y0 + t - 8], fill=ORANGE)
    # sujeira
    grime = noise(W, W, 128, 4, 3)
    a = np.asarray(img, np.float32) * (0.9 + 0.1 * grime[..., None])
    save(to_img(a), "floor.png")


def wall(name, labels):
    W, H = 2048, 512
    cols, rows = 12, 3
    pw, ph = W / cols, H / rows
    base = 0.86 + 0.06 * noise(W, H, 64, 4, 11)
    arr = tint(base, (225, 227, 232))
    yy, xx = np.mgrid[0:H, 0:W]
    pv = rng.random((rows, cols)) * 0.06 - 0.03
    arr *= (1 + pv[(yy // ph).astype(int) % rows, (xx // pw).astype(int) % cols])[..., None]
    fx, fy = (xx % pw) / pw, (yy % ph) / ph
    seam = (np.minimum(fx, 1 - fx) < 0.008) | (np.minimum(fy, 1 - fy) < 0.012)
    arr[seam] *= 0.4
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    f = font(FONT_BOLD, 26)
    fm = font(FONT_MONO, 16)
    for c in range(cols):
        for r in range(rows):
            x0, y0 = c * pw, r * ph
            # parafusos
            for ox in (10, pw - 10):
                for oy in (10, ph - 10):
                    d.ellipse([x0 + ox - 3, y0 + oy - 3, x0 + ox + 3, y0 + oy + 3], fill=(150, 152, 158))
            if r == 1 and c % 3 == 1:
                # grade de ventilacao
                for k in range(8):
                    d.rectangle([x0 + 30, y0 + 40 + k * 12, x0 + pw - 30, y0 + 46 + k * 12], fill=(60, 62, 68))
            if r == 2 and c % 4 == 0:
                d.text((x0 + 18, y0 + 18), labels[(c // 4) % len(labels)], font=f, fill=(40, 42, 48))
                d.text((x0 + 18, y0 + 52), "SEC-%02d" % (c + 1), font=fm, fill=(110, 112, 118))
            if r == 0 and c % 3 == 2:
                d.rectangle([x0 + pw * 0.3, y0 + ph * 0.25, x0 + pw * 0.7, y0 + ph * 0.32], fill=ORANGE)
    grime = noise(W, H, 96, 4, 12)
    a = np.asarray(img, np.float32) * (0.92 + 0.08 * grime[..., None])
    # escurece embaixo (sujeira do chao)
    a *= (1 - 0.18 * (yy / H) ** 4)[..., None]
    save(to_img(a), name)


def ceiling():
    W = 1024
    base = 0.55 + 0.06 * noise(W, W, 64, 4, 21)
    arr = tint(base, (150, 152, 160))
    yy, xx = np.mgrid[0:W, 0:W]
    t = W / 10
    fx, fy = (xx % t) / t, (yy % t) / t
    seam = (np.minimum(fx, 1 - fx) < 0.03) | (np.minimum(fy, 1 - fy) < 0.03)
    arr[seam] *= 0.4
    save(to_img(arr), "ceiling.png")


def concrete():
    W, H = 256, 1024
    base = 0.6 + 0.2 * noise(W, H, 48, 5, 31) + 0.08 * noise(W, H, 4, 2, 32)
    arr = tint(base, (190, 188, 182))
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    for y in range(0, H, 256):
        d.line([0, y, W, y], fill=(110, 108, 104), width=3)
    d.rectangle([0, int(H * 0.82), W, int(H * 0.86)], fill=(60, 60, 64))
    f = font(FONT_BOLD, 56)
    text_center(d, (0, int(H * 0.55), W, int(H * 0.7)), "LAB", f, (45, 45, 50))
    for i in range(10):
        x = (i * 26) % W
        d.polygon([(x, int(H * 0.92)), (x + 13, int(H * 0.92)), (x + 26, H), (x + 13, H)], fill=(240, 190, 30))
    save(img, "concrete.png")


def cover():
    W, H = 1024, 512
    base = 0.45 + 0.1 * noise(W, H, 48, 4, 41)
    arr = tint(base, (120, 124, 132))
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    for i in range(0, W + 80, 80):
        d.polygon([(i, 0), (i + 40, 0), (i - 40, 90), (i - 80, 90)], fill=(245, 190, 25))
        d.polygon([(i + 40, 0), (i + 80, 0), (i, 90), (i - 40, 90)], fill=(25, 25, 28))
    d.rectangle([0, 90, W, 100], fill=(30, 30, 34))
    for x in range(64, W, 160):
        d.rectangle([x, 150, x + 96, 460], outline=(70, 72, 80), width=6)
    save(img, "cover.png")


def table(tx, sfx):
    W, H = 1024, 384
    base = 0.22 + 0.05 * noise(W, H, 32, 4, 51)
    arr = tint(base, (120, 124, 132))
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    for x in range(0, W, 32):
        d.line([x, 0, x, H], fill=(40, 42, 48), width=1)
    for y in range(0, H, 32):
        d.line([0, y, W, y], fill=(40, 42, 48), width=1)
    d.rectangle([6, 6, W - 6, H - 6], outline=ORANGE, width=6)
    f = font(FONT_BOLD, 28)
    d.text((24, H - 50), "ARSENAL  //  " + tx["table"], font=f, fill=(255, 140, 50))
    save(img, "table" + sfx)


def hazard_ring():
    W = 512
    img = Image.new("RGB", (W, W), (30, 30, 30))
    d = ImageDraw.Draw(img)
    for i in range(-W, 2 * W, 48):
        d.polygon([(i, 0), (i + 24, 0), (i + 24 - W, W), (i - W, W)], fill=(245, 190, 25))
    yy, xx = np.mgrid[0:W, 0:W]
    r = np.hypot(xx - W / 2, yy - W / 2) / (W / 2)
    a = np.asarray(img, np.float32)
    a[r < 0.7] = (40, 42, 48)
    save(to_img(a), "hazard_ring.png")


def bullethole():
    W = 64
    yy, xx = np.mgrid[0:W, 0:W]
    r = np.hypot(xx - W / 2, yy - W / 2) / (W / 2)
    v = np.clip(r * 1.4, 0, 1) ** 2
    arr = tint(0.08 + 0.4 * v, (255, 255, 255))
    save(to_img(arr), "bullethole.png")


# ---------------------------------------------------------------------------
# Armas e objetos
# ---------------------------------------------------------------------------
def brushed(W, H, base, tintc, seed):
    n = noise(W, H, 2, 1, seed)
    streak = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((W, 4)).resize((W, H)), np.float32) / 255
    g = base + 0.06 * streak + 0.04 * noise(W, H, 32, 3, seed + 1)
    return tint(g, tintc)


def gun_slide():
    W, H = 512, 128
    img = to_img(brushed(W, H, 0.38, (150, 155, 165), 61))
    d = ImageDraw.Draw(img)
    for x in range(20, 130, 12):
        d.rectangle([x, 10, x + 5, H - 10], fill=(30, 32, 36))
    d.rectangle([300, 40, 380, 88], fill=(25, 26, 30))
    d.text((395, 44), "BL-22", font=font(FONT_BOLD, 30), fill=(210, 212, 220))
    save(img, "gun_slide.png")


def gun_metal():
    W, H = 512, 256
    img = to_img(brushed(W, H, 0.33, (150, 155, 165), 71))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 6], fill=(30, 30, 34))
    d.rectangle([0, H - 6, W, H], fill=(30, 30, 34))
    for x in range(40, W, 120):
        d.ellipse([x, 30, x + 10, 40], fill=(40, 40, 46))
    d.text((300, 180), "MK-II  //  LAB", font=font(FONT_BOLD, 26), fill=(190, 192, 200))
    save(img, "gun_metal.png")


def grip():
    W = 256
    base = 0.16 + 0.06 * noise(W, W, 2, 1, 81) + 0.03 * noise(W, W, 16, 3, 82)
    arr = tint(base, (160, 160, 170))
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    for y in range(0, W, 16):
        for x in range((y // 16 % 2) * 8, W, 16):
            d.ellipse([x, y, x + 5, y + 5], fill=(18, 18, 20))
    save(img, "grip.png")


def bat():
    W, H = 512, 256
    img = to_img(brushed(W, H, 0.72, (200, 204, 212), 91))
    d = ImageDraw.Draw(img)
    d.rectangle([140, 80, 372, 176], fill=ORANGE)
    text_center(d, (140, 80, 372, 176), "SLUGGER", font(FONT_BOLD, 40), (20, 20, 24))
    save(img, "bat.png")


def bot_torso():
    W = 512
    base = 0.82 + 0.06 * noise(W, W, 48, 4, 101)
    arr = tint(base, (235, 236, 240))
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    d.rectangle([20, 20, W - 20, W - 20], outline=(90, 92, 100), width=6)
    d.line([W / 2, 20, W / 2, W - 20], fill=(90, 92, 100), width=4)
    d.line([20, W * 0.62, W - 20, W * 0.62], fill=(90, 92, 100), width=4)
    for k in range(6):
        d.rectangle([60, 360 + k * 18, 200, 368 + k * 18], fill=(70, 72, 80))
    text_center(d, (280, 330, 480, 480), "07", font(FONT_BOLD, 120), (40, 40, 46))
    d.text((60, 60), "NULL BODY", font=font(FONT_BOLD, 40), fill=(40, 40, 46))
    save(img, "bot_torso.png")


def crab_shell():
    W = 512
    base = 0.25 + 0.12 * noise(W, W, 24, 4, 111)
    arr = tint(base, (120, 140, 120))
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    for k in range(5):
        y = 60 + k * 90
        d.arc([40, y - 40, W - 40, y + 140], 200, 340, fill=(150, 255, 60), width=10)
    save(img, "crab_shell.png")


def crate(tx, sfx):
    W = 512
    planks = np.zeros((W, W), np.float32)
    for i in range(6):
        y0, y1 = int(i * W / 6), int((i + 1) * W / 6)
        planks[y0:y1] = 0.55 + 0.1 * random.random()
    grain = noise(W, W, 3, 2, 121)
    g = planks * (0.8 + 0.25 * np.asarray(Image.fromarray((grain * 255).astype(np.uint8)).resize((W, 8)).resize((W, W)), np.float32) / 255)
    arr = tint(g, (210, 150, 90))
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    for i in range(1, 6):
        d.line([0, i * W / 6, W, i * W / 6], fill=(90, 60, 30), width=4)
    d.rectangle([0, 0, W, 40], fill=(60, 62, 68))
    d.rectangle([0, W - 40, W, W], fill=(60, 62, 68))
    d.rectangle([0, 0, 40, W], fill=(60, 62, 68))
    d.rectangle([W - 40, 0, W, W], fill=(60, 62, 68))
    d.line([40, 40, W - 40, W - 40], fill=(60, 62, 68), width=34)
    text_center(d, (60, 180, W - 60, 330), tx["fragile"], fit_font(d, tx["fragile"], FONT_BOLD, W - 140, 140, 72), ORANGE, 4, (30, 20, 10))
    save(img, "crate" + sfx)


def crate_small(tx, sfx):
    W = 512
    base = 0.7 + 0.08 * noise(W, W, 32, 4, 131)
    arr = tint(base, (200, 160, 110))
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    d.rectangle([W / 2 - 40, 0, W / 2 + 40, W], fill=(180, 170, 140))
    d.text((40, 380), tx["parts"], font=font(FONT_BOLD, 60), fill=(90, 60, 30))
    d.text((40, 450), "↑ " + tx["up"], font=fit_font(d, "↑ " + tx["up"], FONT_MED, W - 80, 40, 26), fill=(90, 60, 30))
    save(img, "crate_small" + sfx)


def barrel(tx, sfx):
    W, H = 1024, 512
    base = 0.62 + 0.08 * noise(W, H, 32, 4, 141)
    arr = tint(base, (210, 40, 30))
    yy = np.mgrid[0:H, 0:W][0]
    for y in (0.15, 0.5, 0.85):
        band = np.abs(yy / H - y) < 0.025
        arr[band] *= 0.55
    img = to_img(arr)
    d = ImageDraw.Draw(img)
    for cx in (256, 768):
        d.polygon([(cx, 140), (cx + 110, 330), (cx - 110, 330)], fill=(250, 200, 30), outline=(20, 20, 20))
        d.polygon([(cx, 175), (cx + 85, 315), (cx - 85, 315)], outline=(20, 20, 20), width=6)
        text_center(d, (cx - 40, 210, cx + 40, 310), "!", font(FONT_BOLD, 90), (20, 20, 20))
        text_center(d, (cx - 200, 350, cx + 200, 420), tx["flammable"], fit_font(d, tx["flammable"], FONT_BOLD, 400, 70, 44), (250, 240, 230))
    save(img, "barrel" + sfx)


def console_tex(tx, sfx):
    W, H = 1024, 512
    base = 0.18 + 0.04 * noise(W, H, 32, 3, 151)
    img = to_img(tint(base, (140, 145, 160)))
    d = ImageDraw.Draw(img)
    d.rectangle([10, 10, W - 10, H - 10], outline=(90, 92, 100), width=8)
    d.text((40, 30), tx["console"], font=font(FONT_BOLD, 40), fill=ORANGE)
    save(img, "console" + sfx)


# ---------------------------------------------------------------------------
# Paineis de texto
# ---------------------------------------------------------------------------
def panel(name, title, sub=None, W=1600, H=400, color=ORANGE):
    img = Image.new("RGB", (W, H), (14, 15, 19))
    d = ImageDraw.Draw(img)
    # padrao hexagonal sutil
    for y in range(0, H, 40):
        for x in range((y // 40 % 2) * 23, W, 46):
            d.regular_polygon((x, y, 18), 6, outline=(26, 28, 34))
    d.rectangle([0, 0, W - 1, H - 1], outline=color, width=10)
    d.rectangle([24, 24, 140, 34], fill=color)
    d.rectangle([W - 140, H - 34, W - 24, H - 24], fill=color)
    if sub:
        f = fit_font(d, title, FONT_BOLD, W - 120, H * 0.48, 220)
        text_center(d, (0, H * 0.08, W, H * 0.62), title, f, (245, 246, 250))
        fs = fit_font(d, sub, FONT_MED, W - 160, H * 0.2, 80)
        text_center(d, (0, H * 0.64, W, H * 0.9), sub, fs, color)
    else:
        f = fit_font(d, title, FONT_BOLD, W - 120, H * 0.6, 220)
        text_center(d, (0, 0, W, H), title, f, (245, 246, 250))
    save(img, name)


def label(name, text, W=800, H=200, color=ORANGE):
    img = Image.new("RGB", (W, H), (14, 15, 19))
    d = ImageDraw.Draw(img)
    f = fit_font(d, text, FONT_BOLD, W - 60, H * 0.7, 160)
    text_center(d, (0, 0, W, H), text, f, color)
    d.rectangle([0, H - 12, W, H], fill=color)
    save(img, name)


def button_label(name, text, color):
    W, H = 512, 128
    img = Image.new("RGB", (W, H), (20, 21, 26))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=color, width=6)
    f = fit_font(d, text, FONT_BOLD, W - 40, H - 40, 90)
    text_center(d, (0, 0, W, H), text, f, (245, 246, 250))
    save(img, name)


def poster_logo():
    W, H = 1500, 600
    img = Image.new("RGB", (W, H), (12, 13, 17))
    d = ImageDraw.Draw(img)
    for y in range(0, H, 50):
        for x in range((y // 50 % 2) * 29, W, 58):
            d.regular_polygon((x, y, 24), 6, outline=(28, 30, 38))
    # titulo com gradiente laranja
    f = font(FONT_BOLD, 230)
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    text_center(md, (0, 40, W, 380), "BONELAB", f, 255)
    grad = np.zeros((H, W, 3), np.float32)
    t = np.linspace(0, 1, H)[:, None]
    grad[..., 0] = 255
    grad[..., 1] = (190 - 120 * t)
    grad[..., 2] = (60 - 50 * t)
    img.paste(to_img(grad), (0, 0), mask)
    d = ImageDraw.Draw(img)
    text_center(d, (0, 370, W, 470), "R E M A K E", font(FONT_DISPLAY, 90), (240, 242, 248))
    text_center(d, (0, 480, W, 560), "fan remake  •  EnJoyTheMR  •  VR Box", font(FONT_MED, 40), (150, 152, 160))
    d.rectangle([0, 0, W - 1, H - 1], outline=ORANGE, width=12)
    save(img, "poster_logo.png")


def poster_lab(tx, sfx):
    W, H = 1000, 500
    img = Image.new("RGB", (W, H), (235, 236, 240))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 110], fill=ORANGE)
    text_center(d, (0, 0, W, 110), tx["safety"], fit_font(d, tx["safety"], FONT_BOLD, W - 60, 90, 64), (20, 20, 24))
    lines = tx["rules"]
    for i, l in enumerate(lines):
        d.text((50, 140 + i * 80), l, font=fit_font(d, l, FONT_BOLD, W - 100, 60, 44), fill=(30, 30, 36))
    save(img, "poster_lab" + sfx)


LANG = {
    "pt": {
        "table": "PEGUE UMA ARMA", "fragile": "FRÁGIL", "parts": "PEÇAS", "up": "ESTE LADO PRA CIMA",
        "flammable": "INFLAMÁVEL", "console": "CONTROLE DO LAB", "safety": "AVISO DE SEGURANÇA",
        "rules": ["1. NÃO ALIMENTE OS CRABS", "2. CRAB NO ROSTO? ARRANQUE NA MÃO", "3. BARRIL VERMELHO = BOOM",
                  "4. RECARREGUE PELO QUADRIL"],
        "sign": "ARENA DE TESTES", "wave": "ONDA", "score": "PONTOS", "best": "RECORDE", "enemies": "INIMIGOS",
        "msg_wave": ("ONDA", "prepare-se!"),
        "msg_clear": ("ONDA COMPLETA!", "+ vida  •  bônus de pontos"),
        "msg_dead": ("VOCÊ MORREU", "voltando em instantes..."),
        "msg_gameover": ("FIM DE JOGO", "onda alcançada"),
        "msg_crab": ("CRAB NO ROSTO!", "feche a mão nele e arremesse — ou soque!"),
        "msg_record": ("NOVO RECORDE!", None),
        "msg_welcome": ("BEM-VINDO AO LAB", "pegue uma arma na mesa  •  aperte os botões do console"),
        "msg_sandbox": ("SANDBOX", "munição infinita  •  crie inimigos no console"),
        "msg_hub": ("LABORATÓRIO", "treine nos bonecos ou comece as ONDAS"),
        "msg_calib": ("CALIBRANDO JOY-CON", "siga as instruções do painel"),
        "btn": {"waves": "ONDAS", "sandbox": "SANDBOX", "hub": "LAB", "calib": "JOY-CON", "grunt": "GRUNT",
                "gunner": "ATIRADOR", "crab": "CRAB", "clear": "LIMPAR", "lang": "IDIOMA: PT"},
    },
    "en": {
        "table": "GRAB A WEAPON", "fragile": "FRAGILE", "parts": "PARTS", "up": "THIS SIDE UP",
        "flammable": "FLAMMABLE", "console": "LAB CONTROL", "safety": "SAFETY NOTICE",
        "rules": ["1. DO NOT FEED THE CRABS", "2. CRAB ON FACE? RIP IT OFF", "3. RED BARREL = BOOM",
                  "4. RELOAD FROM YOUR HIP"],
        "sign": "TEST ARENA", "wave": "WAVE", "score": "SCORE", "best": "BEST", "enemies": "ENEMIES",
        "msg_wave": ("WAVE", "get ready!"),
        "msg_clear": ("WAVE CLEARED!", "+ health  •  score bonus"),
        "msg_dead": ("YOU DIED", "respawning shortly..."),
        "msg_gameover": ("GAME OVER", "wave reached"),
        "msg_crab": ("CRAB ON YOUR FACE!", "grab it and throw it — or punch it!"),
        "msg_record": ("NEW RECORD!", None),
        "msg_welcome": ("WELCOME TO THE LAB", "grab a weapon from the table  •  press the console buttons"),
        "msg_sandbox": ("SANDBOX", "infinite ammo  •  spawn enemies at the console"),
        "msg_hub": ("LABORATORY", "train on the dummies or start the WAVES"),
        "msg_calib": ("CALIBRATING JOY-CON", "follow the instructions on the panel"),
        "btn": {"waves": "WAVES", "sandbox": "SANDBOX", "hub": "LAB", "calib": "JOY-CON", "grunt": "GRUNT",
                "gunner": "GUNNER", "crab": "CRAB", "clear": "CLEAR", "lang": "LANGUAGE: EN"},
    },
    "ru": {
        "table": "ВОЗЬМИ ОРУЖИЕ", "fragile": "ХРУПКОЕ", "parts": "ДЕТАЛИ", "up": "ВЕРХ",
        "flammable": "ОГНЕОПАСНО", "console": "ПУЛЬТ ЛАБОРАТОРИИ", "safety": "ТЕХНИКА БЕЗОПАСНОСТИ",
        "rules": ["1. НЕ КОРМИТЬ КРАБОВ", "2. КРАБ НА ЛИЦЕ? СОРВИ РУКОЙ", "3. КРАСНАЯ БОЧКА = БУМ",
                  "4. ПЕРЕЗАРЯДКА С ПОЯСА"],
        "sign": "ИСПЫТАТЕЛЬНАЯ АРЕНА", "wave": "ВОЛНА", "score": "ОЧКИ", "best": "РЕКОРД", "enemies": "ВРАГИ",
        "msg_wave": ("ВОЛНА", "приготовься!"),
        "msg_clear": ("ВОЛНА ПРОЙДЕНА!", "+ здоровье  •  бонус очков"),
        "msg_dead": ("ТЫ ПОГИБ", "возрождение..."),
        "msg_gameover": ("ИГРА ОКОНЧЕНА", "достигнутая волна"),
        "msg_crab": ("КРАБ НА ЛИЦЕ!", "схвати и брось — или ударь!"),
        "msg_record": ("НОВЫЙ РЕКОРД!", None),
        "msg_welcome": ("ДОБРО ПОЖАЛОВАТЬ", "возьми оружие со стола  •  нажимай кнопки пульта"),
        "msg_sandbox": ("ПЕСОЧНИЦА", "бесконечные патроны  •  враги — на пульте"),
        "msg_hub": ("ЛАБОРАТОРИЯ", "тренируйся на манекенах или начни ВОЛНЫ"),
        "msg_calib": ("НАСТРОЙКА JOY-CON", "следуй инструкциям на панели"),
        "btn": {"waves": "ВОЛНЫ", "sandbox": "ПЕСОЧНИЦА", "hub": "ЛАБ", "calib": "JOY-CON", "grunt": "ГРАНТ",
                "gunner": "СТРЕЛОК", "crab": "КРАБ", "clear": "ОЧИСТИТЬ", "lang": "ЯЗЫК: RU"},
    },
}

MSG_COLORS = {
    "msg_wave": ORANGE, "msg_clear": (80, 255, 130), "msg_dead": (255, 60, 50), "msg_gameover": (255, 60, 50),
    "msg_crab": (150, 255, 60), "msg_record": (255, 215, 60), "msg_welcome": ORANGE, "msg_sandbox": (60, 200, 255),
    "msg_hub": ORANGE, "msg_calib": (255, 60, 90),
}
BTN_COLORS = {
    "waves": ORANGE, "sandbox": (60, 200, 255), "hub": (220, 220, 230), "calib": (255, 60, 90),
    "grunt": ORANGE, "gunner": (60, 200, 255), "crab": (150, 255, 60), "clear": (255, 215, 60),
    "lang": (180, 130, 255),
}


def main():
    # remove texturas antigas (sem sufixo de idioma / restos)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))
    floor()
    wall("wall.png", ["LAB 01", "ARENA", "TEST-3"])
    wall("wall_side.png", ["MYTHOS", "LAB 02", "EXIT"])
    ceiling()
    concrete()
    cover()
    hazard_ring()
    bullethole()
    gun_slide()
    gun_metal()
    grip()
    bat()
    bot_torso()
    crab_shell()
    poster_logo()
    for lang, tx in LANG.items():
        sfx = "_" + lang + ".png"
        table(tx, sfx)
        crate(tx, sfx)
        crate_small(tx, sfx)
        barrel(tx, sfx)
        console_tex(tx, sfx)
        poster_lab(tx, sfx)
        label("sign_arena" + sfx, tx["sign"], 1200, 300)
        label("lbl_wave" + sfx, tx["wave"])
        label("lbl_score" + sfx, tx["score"], color=(80, 255, 130))
        label("lbl_best" + sfx, tx["best"], color=(255, 215, 60))
        label("lbl_enemies" + sfx, tx["enemies"], color=(60, 200, 255))
        for key, col in MSG_COLORS.items():
            title, sub = tx[key]
            panel(key + sfx, title, sub, color=col)
        for key, col in BTN_COLORS.items():
            button_label("btn_" + key + sfx, tx["btn"][key], col)
    print("texturas em", OUT, len(os.listdir(OUT)))


if __name__ == "__main__":
    main()
