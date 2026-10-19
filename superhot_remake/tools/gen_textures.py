#!/usr/bin/env python3
"""Gera as texturas do SUPERHOT Remake (PNG) de forma procedural.
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

RED = (235, 25, 18)
BLACK = (12, 12, 14)
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
# Superficies brancas (estilo SUPERHOT: tudo branco, sombras suaves)
# ---------------------------------------------------------------------------
def white_panels(name, W, H, cols, rows, base=0.95, seam=0.82, edge_ao=0.1, seed=1):
    yy, xx = np.mgrid[0:H, 0:W]
    g = base + 0.015 * noise(W, H, 64, 3, seed) - 0.01 * noise(W, H, 6, 2, seed + 1)
    pw, ph = W / cols, H / rows
    fx, fy = (xx % pw) / pw, (yy % ph) / ph
    d = np.minimum(np.minimum(fx, 1 - fx) * pw, np.minimum(fy, 1 - fy) * ph)
    g = g - edge_ao * np.exp(-d / 10.0)          # leve "AO" perto das juntas
    g[d < 1.6] = seam
    g = g * (1 - 0.06 * (yy / H) ** 3)
    save(to_img(tint(np.clip(g, 0, 1), (255, 255, 255))), name)


def floor_white():
    white_panels("floor_white.png", 1024, 1024, 8, 8, base=0.93, seam=0.78, edge_ao=0.06, seed=3)


def wall_white():
    white_panels("wall_white.png", 1024, 512, 6, 2, base=0.97, seam=0.84, edge_ao=0.05, seed=5)


def ceiling_white():
    white_panels("ceiling_white.png", 1024, 1024, 6, 6, base=0.96, seam=0.86, edge_ao=0.04, seed=7)


def panel_white():
    W = 512
    white_panels("panel_white.png", W, W, 4, 2, base=0.96, seam=0.8, edge_ao=0.08, seed=9)


def rack():
    W, H = 512, 1024
    img = Image.new("RGB", (W, H), (226, 228, 233))
    d = ImageDraw.Draw(img)
    for i in range(14):
        y0 = 30 + i * 70
        d.rectangle([24, y0, W - 24, y0 + 56], fill=(205, 207, 213), outline=(170, 172, 178), width=3)
        for k in range(10):
            d.rectangle([44 + k * 24, y0 + 16, 58 + k * 24, y0 + 40], fill=(150, 152, 158))
        d.ellipse([W - 70, y0 + 20, W - 56, y0 + 34], fill=RED if i % 3 == 0 else (90, 92, 98))
    save(img, "rack.png")


def bullethole():
    W = 64
    yy, xx = np.mgrid[0:W, 0:W]
    r = np.hypot(xx - W / 2, yy - W / 2) / (W / 2)
    v = np.clip(r * 1.3, 0, 1) ** 2
    save(to_img(tint(0.1 + 0.8 * v, (255, 255, 255))), "bullethole.png")


def logo():
    W, H = 2000, 500
    img = Image.new("RGB", (W, H), (245, 245, 247))
    d = ImageDraw.Draw(img)
    # cacos vermelhos decorativos
    random.seed(11)
    for _ in range(40):
        cx, cy = random.randint(0, W), random.randint(0, H)
        s = random.randint(10, 46)
        pts = [(cx + random.randint(-s, s), cy + random.randint(-s, s)) for _ in range(3)]
        d.polygon(pts, fill=(235, 30 + random.randint(0, 30), 20))
    f = font(FONT_BOLD, 300)
    t1, t2 = "SUPER", "HOT"
    b1 = d.textbbox((0, 0), t1, font=f)
    b2 = d.textbbox((0, 0), t2, font=f)
    gap = 40
    total = (b1[2] - b1[0]) + gap + (b2[2] - b2[0])
    x = (W - total) / 2
    y = (H - (b1[3] - b1[1])) / 2 - b1[1] - 30
    d.text((x - b1[0], y), t1, font=f, fill=BLACK)
    d.text((x + (b1[2] - b1[0]) + gap - b2[0], y), t2, font=f, fill=RED)
    text_center(d, (0, H - 110, W, H - 30), "R E M A K E   •   fan remake for EnJoyTheMR", font(FONT_MED, 46), (90, 90, 96))
    save(img, "logo.png")


def panel(name, title, sub=None, W=1600, H=400, accent=RED, dark=False):
    bg = (14, 14, 16) if dark else (247, 247, 249)
    fg = (245, 245, 247) if dark else BLACK
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=accent, width=12)
    d.rectangle([0, H - 26, W, H], fill=accent)
    if sub:
        f = fit_font(d, title, FONT_BOLD, W - 140, H * 0.48, 220)
        text_center(d, (0, H * 0.06, W, H * 0.6), title, f, fg)
        fs = fit_font(d, sub, FONT_MED, W - 160, H * 0.18, 80)
        text_center(d, (0, H * 0.62, W, H * 0.88), sub, fs, accent if not dark else (220, 220, 225))
    else:
        f = fit_font(d, title, FONT_BOLD, W - 140, H * 0.58, 220)
        text_center(d, (0, 0, W, H - 26), title, f, fg)
    save(img, name)


def label(name, text, W=800, H=200, color=BLACK, bg=(247, 247, 249)):
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    f = fit_font(d, text, FONT_BOLD, W - 60, H * 0.62, 160)
    text_center(d, (0, 0, W, H - 14), text, f, color)
    d.rectangle([0, H - 14, W, H], fill=RED)
    save(img, name)


LANG = {
    "en": {
        "msg_level": ("LEVEL", "time moves only when you move"),
        "msg_dead": ("YOU DIED", "restarting..."),
        "msg_endless": ("ENDLESS", "survive as long as you can"),
        "msg_wave": ("WAVE", None),
        "msg_record": ("NEW RECORD!", None),
        "msg_complete": ("ALL LEVELS CLEARED", "SUPERHOT is the most innovative shooter"),
        "msg_locked": ("LOCKED", "beat the previous level first"),
        "msg_lobby": ("SUPERHOT", "grab a red cube to start a level"),
        "msg_welcome": ("SUPERHOT", "grab a red cube to start a level"),
        "msg_calib": ("JOY-CON", "follow the instructions on the panel"),
        "hint": "TIME MOVES ONLY WHEN YOU MOVE", "endless": "ENDLESS", "next": "NEXT", "lobby": "LOBBY",
    },
    "ru": {
        "msg_level": ("УРОВЕНЬ", "время движется, только когда движешься ты"),
        "msg_dead": ("ТЫ ПОГИБ", "перезапуск..."),
        "msg_endless": ("БЕСКОНЕЧНЫЙ", "продержись как можно дольше"),
        "msg_wave": ("ВОЛНА", None),
        "msg_record": ("НОВЫЙ РЕКОРД!", None),
        "msg_complete": ("ВСЕ УРОВНИ ПРОЙДЕНЫ", "SUPERHOT — самый инновационный шутер"),
        "msg_locked": ("ЗАКРЫТО", "сначала пройди предыдущий уровень"),
        "msg_lobby": ("SUPERHOT", "возьми красный куб, чтобы начать уровень"),
        "msg_welcome": ("SUPERHOT", "возьми красный куб, чтобы начать уровень"),
        "msg_calib": ("JOY-CON", "следуй инструкциям на панели"),
        "hint": "ВРЕМЯ ДВИЖЕТСЯ, ТОЛЬКО КОГДА ДВИЖЕШЬСЯ ТЫ", "endless": "БЕСКОНЕЧНЫЙ", "next": "ДАЛЬШЕ", "lobby": "ЛОББИ",
    },
    "pt": {
        "msg_level": ("FASE", "o tempo só anda quando você se move"),
        "msg_dead": ("VOCÊ MORREU", "recomeçando..."),
        "msg_endless": ("INFINITO", "sobreviva o máximo que puder"),
        "msg_wave": ("ONDA", None),
        "msg_record": ("NOVO RECORDE!", None),
        "msg_complete": ("TODAS AS FASES VENCIDAS", "SUPERHOT é o shooter mais inovador"),
        "msg_locked": ("BLOQUEADA", "vença a fase anterior primeiro"),
        "msg_lobby": ("SUPERHOT", "pegue um cubo vermelho para começar uma fase"),
        "msg_welcome": ("SUPERHOT", "pegue um cubo vermelho para começar uma fase"),
        "msg_calib": ("JOY-CON", "siga as instruções do painel"),
        "hint": "O TEMPO SÓ ANDA QUANDO VOCÊ SE MOVE", "endless": "INFINITO", "next": "PRÓXIMA", "lobby": "SAGUÃO",
    },
}


def main():
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))
    floor_white()
    wall_white()
    ceiling_white()
    panel_white()
    rack()
    bullethole()
    logo()
    for lang, tx in LANG.items():
        sfx = "_" + lang + ".png"
        for key in ("msg_level", "msg_dead", "msg_endless", "msg_wave", "msg_record", "msg_complete", "msg_locked",
                    "msg_lobby", "msg_welcome", "msg_calib"):
            title, sub = tx[key]
            panel(key + sfx, title, sub, dark=key in ("msg_dead",))
        label("lbl_hint" + sfx, tx["hint"], 1600, 200)
        label("lbl_endless" + sfx, tx["endless"])
        label("btn_next" + sfx, tx["next"], 800, 200, color=RED)
        label("btn_lobby" + sfx, tx["lobby"])
    print("texturas em", OUT, len(os.listdir(OUT)))


if __name__ == "__main__":
    main()
