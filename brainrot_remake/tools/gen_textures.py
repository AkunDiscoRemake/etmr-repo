#!/usr/bin/env python3
"""Gera todas as texturas do RE:Steal A Brainrot VR (images/).

Letras (font/*), placas dos brainrots (names/*), raridades/mutacoes/prompts/avisos
em EN/RU/PT, ceu, chao estilo Roblox (com "studs"), paredes, rostos dos avatares, icones.
Fontes: Rubik (OFL, tem cirilico) e Luckiest Guy (Apache) em tools/fonts/.
"""
import math
import os
import random
import re

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
IMG = os.path.join(ROOT, "images")
FONTS = os.path.join(ROOT, "tools", "fonts")
LANGS = ["en", "ru", "pt"]
random.seed(7)


def font(size, kind="rubik"):
    if kind == "lucky":
        return ImageFont.truetype(os.path.join(FONTS, "LuckiestGuy.ttf"), size)
    f = ImageFont.truetype(os.path.join(FONTS, "Rubik.ttf"), size)
    try:
        f.set_variation_by_name("Black")
    except Exception:
        pass
    return f


def save(img, rel):
    p = os.path.join(IMG, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.convert("RGB").save(p, optimize=True)


def grad(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    return img


def fit_font(draw, text, maxw, maxh, size, kind="rubik"):
    while size > 10:
        f = font(size, kind)
        b = draw.multiline_textbbox((0, 0), text, font=f, align="center", spacing=size // 6, stroke_width=max(2, size // 12))
        if b[2] - b[0] <= maxw and b[3] - b[1] <= maxh:
            return f
        size -= 2
    return font(size, kind)


def text_center(img, text, size, fill=(255, 255, 255), stroke=(0, 0, 0), kind="rubik", box=None, sw=None):
    d = ImageDraw.Draw(img)
    W, H = img.size
    x0, y0, x1, y1 = box or (0, 0, W, H)
    f = fit_font(d, text, (x1 - x0) * 0.94, (y1 - y0) * 0.86, size, kind)
    sw = sw if sw is not None else max(2, f.size // 12)
    b = d.multiline_textbbox((0, 0), text, font=f, align="center", spacing=f.size // 6, stroke_width=sw)
    tx = x0 + ((x1 - x0) - (b[2] - b[0])) / 2 - b[0]
    ty = y0 + ((y1 - y0) - (b[3] - b[1])) / 2 - b[1]
    # sombra
    d.multiline_text((tx + sw * 0.6, ty + sw * 0.9), text, font=f, fill=(0, 0, 0), align="center", spacing=f.size // 6, stroke_width=sw, stroke_fill=(0, 0, 0))
    d.multiline_text((tx, ty), text, font=f, fill=fill, align="center", spacing=f.size // 6, stroke_width=sw, stroke_fill=stroke)


def gradient_text(img, text, size, colors, kind="rubik", box=None):
    """texto com degrade (arco-iris etc.) e contorno preto"""
    W, H = img.size
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    x0, y0, x1, y1 = box or (0, 0, W, H)
    f = fit_font(d, text, (x1 - x0) * 0.94, (y1 - y0) * 0.86, size, kind)
    sw = max(2, f.size // 12)
    b = d.textbbox((0, 0), text, font=f, stroke_width=sw)
    tx = x0 + ((x1 - x0) - (b[2] - b[0])) / 2 - b[0]
    ty = y0 + ((y1 - y0) - (b[3] - b[1])) / 2 - b[1]
    dd = ImageDraw.Draw(img)
    dd.text((tx + sw * 0.6, ty + sw * 0.9), text, font=f, fill=(0, 0, 0), stroke_width=sw, stroke_fill=(0, 0, 0))
    dd.text((tx, ty), text, font=f, fill=(0, 0, 0), stroke_width=sw, stroke_fill=(0, 0, 0))
    d.text((tx, ty), text, font=f, fill=255)
    g = Image.new("RGB", (W, H))
    gd = ImageDraw.Draw(g)
    n = len(colors)
    for x in range(W):
        t = x / max(1, W - 1) * (n - 1)
        i = min(n - 2, int(t))
        k = t - i
        c = tuple(int(colors[i][j] + (colors[i + 1][j] - colors[i][j]) * k) for j in range(3))
        gd.line([(x, 0), (x, H)], fill=c)
    img.paste(g, (0, 0), mask)


def card(w, h, top=(40, 44, 70), bottom=(18, 20, 36), border=(255, 255, 255), bw=0):
    img = grad(w, h, top, bottom)
    if bw:
        ImageDraw.Draw(img).rectangle([bw // 2, bw // 2, w - bw // 2 - 1, h - bw // 2 - 1], outline=border, width=bw)
    return img


def tiles(tile_fn, n=8, ts=64):
    img = Image.new("RGB", (n * ts, n * ts))
    for j in range(n):
        for i in range(n):
            img.paste(tile_fn(i, j, ts), (i * ts, j * ts))
    return img


# ---------------------------------------------------------------------------
# Textos traduzidos (texturas)
# ---------------------------------------------------------------------------
TOASTS = {
    "alert_steal": ("SOMEONE IS STEALING\nYOUR BRAINROT!", "КТО-ТО ВОРУЕТ\nТВОЙ БРЕЙНРОТ!", "ESTÃO ROUBANDO\nSEU BRAINROT!", "red"),
    "alert_stolen": ("YOUR BRAINROT WAS TAKEN!\nHIT THE THIEF!", "ТВОЙ БРЕЙНРОТ УНЕСЛИ!\nУДАРЬ ВОРА!", "LEVARAM SEU BRAINROT!\nBATE NO LADRÃO!", "red"),
    "alert_lost": ("YOUR BRAINROT\nWAS STOLEN...", "ТВОЙ БРЕЙНРОТ\nУКРАДЕН...", "SEU BRAINROT\nFOI ROUBADO...", "red"),
    "recovered": ("BRAINROT RECOVERED!", "БРЕЙНРОТ ВОЗВРАЩЁН!", "BRAINROT RECUPERADO!", "green"),
    "base_locked": ("BASE LOCKED!\nLASERS ON", "БАЗА ЗАКРЫТА!\nЛАЗЕРЫ ВКЛЮЧЕНЫ", "BASE TRANCADA!\nLASERS LIGADOS", "blue"),
    "base_unlocked": ("YOUR BASE IS\nUNLOCKED!", "ТВОЯ БАЗА\nОТКРЫТА!", "SUA BASE\nDESTRANCOU!", "orange"),
    "stolen_ok": ("GOT IT!\nRUN TO YOUR BASE!", "ЕСТЬ!\nБЕГИ НА СВОЮ БАЗУ!", "PEGOU!\nCORRE PRA SUA BASE!", "green"),
    "stolen_home": ("STOLEN!\n+1 BRAINROT", "УКРАДЕНО!\n+1 БРЕЙНРОТ", "ROUBADO!\n+1 BRAINROT", "gold"),
    "cloak_on": ("YOU ARE INVISIBLE!", "ТЫ НЕВИДИМ!", "VOCÊ ESTÁ INVISÍVEL!", "purple"),
    "calib": ("CALIBRATING JOY-CON\n(follow the menu)", "НАСТРОЙКА JOY-CON\n(смотри меню)", "CALIBRANDO JOY-CON\n(siga o menu)", "blue"),
    "diff_easy": ("BOTS: EASY", "БОТЫ: ЛЕГКО", "BOTS: FÁCIL", "green"),
    "diff_normal": ("BOTS: NORMAL", "БОТЫ: НОРМАЛЬНО", "BOTS: NORMAL", "blue"),
    "diff_hard": ("BOTS: HARD", "БОТЫ: СЛОЖНО", "BOTS: DIFÍCIL", "red"),
    "av_bacon": ("AVATAR: BACON HAIR", "АВАТАР: BACON HAIR", "AVATAR: BACON HAIR", "orange"),
    "av_acorn": ("AVATAR: ACORN GIRL", "АВАТАР: ACORN GIRL", "AVATAR: ACORN GIRL", "pink"),
    "ev_halloween": ("HALLOWEEN NIGHT!\nLUCK x2", "НОЧЬ ХЭЛЛОУИНА!\nУДАЧА x2", "NOITE DE HALLOWEEN!\nSORTE x2", "halloween"),
    "ev_candy": ("CANDY EVENT!\nMONEY x2 - GRAB THE CANDY!", "КОНФЕТНЫЙ ИВЕНТ!\nДЕНЬГИ x2 - СОБИРАЙ КОНФЕТЫ!", "EVENTO CANDY!\nDINHEIRO x2 - PEGUE OS DOCES!", "candy"),
    "ev_lava": ("LAVA EVENT! LUCK x3\nDODGE THE METEORS!", "ЛАВОВЫЙ ИВЕНТ! УДАЧА x3\nУВОРАЧИВАЙСЯ ОТ МЕТЕОРОВ!", "EVENTO DE LAVA! SORTE x3\nDESVIE DOS METEOROS!", "lava"),
    "ev_day": ("A NEW DAY BEGINS", "НАСТУПИЛ НОВЫЙ ДЕНЬ", "UM NOVO DIA COMEÇOU", "blue"),
    "offline_money": ("MONEY EARNED\nWHILE YOU WERE AWAY", "ДЕНЬГИ, ЗАРАБОТАННЫЕ\nПОКА ТЕБЯ НЕ БЫЛО", "DINHEIRO GANHO\nENQUANTO VOCÊ ESTAVA FORA", "green"),
    "online_connecting": ("CONNECTING...", "ПОДКЛЮЧЕНИЕ...", "CONECTANDO...", "blue"),
    "online_ok": ("YOU ARE ONLINE!", "ТЫ В СЕТИ!", "VOCÊ ESTÁ ONLINE!", "green"),
    "online_fail": ("COULD NOT CONNECT", "НЕ УДАЛОСЬ ПОДКЛЮЧИТЬСЯ", "NÃO FOI POSSÍVEL CONECTAR", "red"),
    "online_lost": ("CONNECTION LOST\nBACK TO SOLO", "СВЯЗЬ ПОТЕРЯНА\nОДИНОЧНАЯ ИГРА", "CONEXÃO PERDIDA\nVOLTANDO AO SOLO", "red"),
    "online_noperm": ("ONLINE IS NOT AVAILABLE\nON THIS DEVICE", "ОНЛАЙН НЕДОСТУПЕН\nНА ЭТОМ УСТРОЙСТВЕ", "ONLINE INDISPONÍVEL\nNESTE APARELHO", "red"),
    "rebirth_done": ("REBIRTH!\nMONEY MULTIPLIER UP", "ПЕРЕРОЖДЕНИЕ!\nМНОЖИТЕЛЬ ДЕНЕГ ВЫРОС", "RENASCEU!\nMULTIPLICADOR SUBIU", "purple"),
    "tut_welcome": ("WELCOME!\nWalk with the stick and BUY\nbrainrots on the RED CARPET\n(hold R)",
                    "ПРИВЕТ!\nХоди стиком и ПОКУПАЙ\nбрейнроты на КРАСНОЙ ДОРОЖКЕ\n(держи R)",
                    "BEM-VINDO!\nAnde com o analógico e COMPRE\nbrainrots no TAPETE VERMELHO\n(segure R)", "blue"),
    "tut_collect": ("Your brainrot makes money!\nStep on the GREEN PAD\nto collect it",
                    "Твой брейнрот приносит деньги!\nВстань на ЗЕЛЁНУЮ ПЛИТУ,\nчтобы забрать",
                    "Seu brainrot gera dinheiro!\nPise na PLACA VERDE\npara coletar", "green"),
    "tut_steal": ("Want more?\nSTEAL from other bases:\nhold R for 5 s and RUN HOME!",
                  "Хочешь больше?\nВОРУЙ с других баз:\nдержи R 5 секунд и БЕГИ ДОМОЙ!",
                  "Quer mais?\nROUBE das outras bases:\nsegure R por 5 s e CORRA PRA CASA!", "gold"),
    "tut_defend": ("Hit thieves with your BAT (ZR)!\nStep on the RED BUTTON\nto lock your base",
                   "Бей воров БИТОЙ (ZR)!\nВстань на КРАСНУЮ КНОПКУ,\nчтобы закрыть базу",
                   "Bata nos ladrões com o TACO (ZR)!\nPise no BOTÃO VERMELHO\npara trancar a base", "red"),
}

THEMES = {
    "red": ((235, 60, 60), (150, 20, 30)), "green": ((70, 200, 90), (25, 110, 50)), "blue": ((60, 140, 255), (25, 60, 160)),
    "orange": ((255, 160, 40), (190, 80, 10)), "gold": ((255, 210, 60), (200, 120, 10)), "purple": ((170, 90, 255), (80, 30, 160)),
    "pink": ((255, 120, 190), (180, 50, 120)), "halloween": ((255, 120, 20), (60, 15, 70)), "candy": ((255, 140, 210), (120, 200, 255)),
    "lava": ((255, 90, 20), (90, 10, 5)),
}

PROMPTS = {
    "buy": ("BUY", "КУПИТЬ", "COMPRAR", (60, 200, 90)),
    "steal": ("STEAL", "УКРАСТЬ", "ROUBAR", (230, 60, 60)),
    "sell": ("SELL", "ПРОДАТЬ", "VENDER", (240, 170, 40)),
    "shop": ("BUY ITEM", "КУПИТЬ", "COMPRAR ITEM", (60, 150, 255)),
    "equip": ("EQUIP", "ВЗЯТЬ", "EQUIPAR", (60, 150, 255)),
    "rebirth": ("REBIRTH", "ПЕРЕРОДИТЬСЯ", "RENASCER", (170, 90, 255)),
}
HOLD = ("HOLD", "ДЕРЖИ", "SEGURE")

WHY = {
    "money": ("NOT ENOUGH MONEY", "НЕ ХВАТАЕТ ДЕНЕГ", "DINHEIRO INSUFICIENTE"),
    "full": ("YOUR BASE IS FULL", "БАЗА ЗАПОЛНЕНА", "SUA BASE ESTÁ CHEIA"),
    "carry": ("ALREADY CARRYING", "РУКИ ЗАНЯТЫ", "JÁ ESTÁ CARREGANDO"),
}

RARITIES = {
    "common": ("COMMON", "ОБЫЧНЫЙ", "COMUM", [(210, 212, 218), (160, 162, 170)]),
    "rare": ("RARE", "РЕДКИЙ", "RARO", [(90, 160, 255), (40, 100, 240)]),
    "epic": ("EPIC", "ЭПИЧЕСКИЙ", "ÉPICO", [(190, 110, 255), (130, 50, 230)]),
    "legendary": ("LEGENDARY", "ЛЕГЕНДАРНЫЙ", "LENDÁRIO", [(255, 230, 80), (255, 170, 20)]),
    "mythic": ("MYTHIC", "МИФИЧЕСКИЙ", "MÍTICO", [(255, 90, 90), (220, 30, 50)]),
    "god": ("BRAINROT GOD", "БОГ БРЕЙНРОТА", "DEUS BRAINROT", [(255, 80, 80), (255, 200, 60), (90, 230, 120), (80, 170, 255), (200, 100, 255)]),
    "secret": ("SECRET", "СЕКРЕТНЫЙ", "SECRETO", [(20, 20, 20), (255, 255, 255), (20, 20, 20)]),
}

MUTS = {
    "gold": ("GOLD", "ЗОЛОТО", "OURO", [(255, 240, 140), (230, 170, 30)]),
    "diamond": ("DIAMOND", "АЛМАЗ", "DIAMANTE", [(200, 250, 255), (90, 200, 255)]),
    "halloween": ("HALLOWEEN", "ХЭЛЛОУИН", "HALLOWEEN", [(255, 140, 20), (160, 60, 220)]),
    "candy": ("CANDY", "КОНФЕТНЫЙ", "DOCE", [(255, 130, 200), (130, 230, 255)]),
    "lava": ("LAVA", "ЛАВА", "LAVA", [(255, 220, 60), (255, 70, 10)]),
    "rainbow": ("RAINBOW", "РАДУГА", "ARCO-ÍRIS", [(255, 70, 70), (255, 200, 60), (90, 230, 120), (80, 170, 255), (200, 100, 255)]),
}

SIGNS = {
    "sign_shop": ("GEAR SHOP", "МАГАЗИН", "LOJA DE ITENS", (60, 150, 255)),
    "sign_rebirth": ("REBIRTH", "ПЕРЕРОЖДЕНИЕ", "RENASCER", (170, 90, 255)),
    "lbl_lock": ("LOCK BASE", "ЗАКРЫТЬ БАЗУ", "TRANCAR BASE", (230, 60, 60)),
    "hud_carry": ("RUN TO YOUR BASE!", "БЕГИ НА СВОЮ БАЗУ!", "CORRE PRA SUA BASE!", (230, 60, 60)),
}

ITEMS = {
    "bat": ("BAT  (FREE)", "БИТА", "TACO"),
    "slap": ("SLAP HAND", "ЛАДОНЬ-ШЛЁП", "MÃO DE TAPA"),
    "coil": ("SPEED COIL", "СКОРОСТНАЯ ПРУЖИНА", "MOLA DE VELOCIDADE"),
    "trap": ("TRAP x3", "ЛОВУШКА x3", "ARMADILHA x3"),
    "cloak": ("INVISIBILITY CLOAK", "ПЛАЩ-НЕВИДИМКА", "CAPA DA INVISIBILIDADE"),
}


def gen_localized():
    for key, v in TOASTS.items():
        top, bot = THEMES[v[3]]
        for li, lang in enumerate(LANGS):
            H = 512 if key.startswith("tut_") else 256
            img = card(1024, H, top, bot, (255, 255, 255), 10)
            text_center(img, v[li], 104, box=(30, 16, 994, H - 16))
            save(img, "%s_%s.png" % (key, lang))
    for key, v in PROMPTS.items():
        for li, lang in enumerate(LANGS):
            img = card(512, 128, (30, 34, 56), (12, 14, 26), (255, 255, 255), 4)
            d = ImageDraw.Draw(img)
            # tecla "R"
            d.rounded_rectangle([14, 22, 98, 106], radius=14, fill=(240, 240, 245), outline=(0, 0, 0), width=4)
            f = font(56)
            d.text((56, 64), "R", font=f, fill=(20, 20, 30), anchor="mm")
            text_center(img, HOLD[li], 30, fill=(200, 205, 220), box=(108, 8, 504, 46), sw=2)
            text_center(img, v[li], 64, fill=v[3], box=(108, 40, 504, 122))
            save(img, "prompt_%s_%s.png" % (key, lang))
    for key, v in WHY.items():
        for li, lang in enumerate(LANGS):
            img = card(512, 128, (120, 20, 25), (70, 8, 12), (255, 120, 120), 4)
            text_center(img, v[li], 56)
            save(img, "why_%s_%s.png" % (key, lang))
    for key, v in RARITIES.items():
        for li, lang in enumerate(LANGS):
            img = card(512, 128, (26, 28, 44), (10, 11, 20))
            if key == "secret":
                img = card(512, 128, (230, 230, 235), (150, 150, 160))
            gradient_text(img, v[li], 84, v[3])
            save(img, "rar_%s_%s.png" % (key, lang))
    for key, v in MUTS.items():
        for li, lang in enumerate(LANGS):
            img = card(512, 128, (26, 28, 44), (10, 11, 20))
            gradient_text(img, v[li], 80, v[3])
            save(img, "mut_%s_%s.png" % (key, lang))
    for key, v in SIGNS.items():
        for li, lang in enumerate(LANGS):
            w, h = (1024, 256) if key.startswith("sign") else (512, 128) if key == "lbl_lock" else (1024, 192)
            c = v[3]
            img = card(w, h, tuple(min(255, int(x * 1.15)) for x in c), tuple(int(x * 0.55) for x in c), (255, 255, 255), max(4, h // 26))
            text_center(img, v[li], int(h * 0.62), kind="rubik")
            save(img, "%s_%s.png" % (key, lang))
    for key, v in ITEMS.items():
        for li, lang in enumerate(LANGS):
            img = card(512, 128, (40, 70, 140), (16, 28, 70), (255, 255, 255), 4)
            text_center(img, v[li], 60)
            save(img, "itemname_%s_%s.png" % (key, lang))


# ---------------------------------------------------------------------------
# Letras (text3d)
# ---------------------------------------------------------------------------
GLYPHS = {
    "dollar": "$", "dot": ".", "comma": ",", "colon": ":", "slash": "/", "plus": "+", "minus": "-",
    "under": "_", "excl": "!", "quest": "?", "x": "x", "pct": "%", "hash": "#", "lpar": "(", "rpar": ")", "space": " ",
}


def gen_font():
    chars = {str(i): str(i) for i in range(10)}
    for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        chars[c] = c
    chars.update(GLYPHS)
    f = font(76)
    for name, ch in chars.items():
        # fundo transparente com cor escura (sem shader unlit a plataforma mostra o RGB = fundo escuro)
        img = Image.new("RGBA", (64, 96), (22, 24, 36, 0))
        d = ImageDraw.Draw(img)
        if ch != " ":
            d.text((32, 50), ch, font=f, fill=(255, 255, 255, 255), anchor="mm", stroke_width=5, stroke_fill=(0, 0, 0, 255))
        p = os.path.join(IMG, "font", "%s.png" % name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        img.save(p, optimize=True)


# ---------------------------------------------------------------------------
# Placas com o nome de cada brainrot
# ---------------------------------------------------------------------------
def gen_names():
    src = open(os.path.join(ROOT, "scripts", "catalog.lua"), encoding="utf8").read()
    for m in re.finditer(r'\{ "(\w+)",\s+"([^"]+)",\s+"(\w+)"', src):
        bid, name, rar = m.group(1), m.group(2), m.group(3)
        img = card(512, 128, (34, 38, 62), (14, 15, 28))
        text_center(img, name, 70, box=(10, 6, 502, 122))
        save(img, "names/%s.png" % bid)


# ---------------------------------------------------------------------------
# Mundo
# ---------------------------------------------------------------------------
def stud_tile(base, ts, var=10, studs=2):
    def fn(i, j, _ts):
        r = random.Random(i * 31 + j * 7)
        c = tuple(max(0, min(255, base[k] + r.randint(-var, var))) for k in range(3))
        img = Image.new("RGB", (ts, ts), c)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, ts - 1, ts - 1], outline=tuple(int(x * 0.86) for x in c), width=max(1, ts // 48))
        step = ts / studs
        for a in range(studs):
            for b in range(studs):
                cx, cy = (a + 0.5) * step, (b + 0.5) * step
                rr = step * 0.26
                d.ellipse([cx - rr + 2, cy - rr + 3, cx + rr + 2, cy + rr + 3], fill=tuple(int(x * 0.8) for x in c))
                d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=tuple(min(255, int(x * 1.1)) for x in c))
        return img
    return fn


def gen_world():
    save(tiles(stud_tile((86, 178, 72), 128), 8, 128), "grass.png")

    def stone(i, j, ts):
        r = random.Random(i * 13 + j * 17)
        g = r.randint(150, 175)
        img = Image.new("RGB", (ts, ts), (g, g, g + 6))
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, ts - 1, ts - 1], outline=(110, 110, 118), width=3)
        for _ in range(6):
            x, y = r.randint(4, ts - 8), r.randint(4, ts - 8)
            d.point((x, y), fill=(g - 25, g - 25, g - 20))
        return img
    save(tiles(stone, 8, 64), "path.png")

    def carpet(i, j, ts):
        img = Image.new("RGB", (ts, ts), (200, 30, 40))
        d = ImageDraw.Draw(img)
        for y in range(0, ts, 4):
            d.line([(0, y), (ts, y)], fill=(185, 25, 35))
        d.rectangle([0, 0, 5, ts], fill=(240, 190, 60))
        d.rectangle([ts - 6, 0, ts, ts], fill=(240, 190, 60))
        cx, cy = ts / 2, ts / 2
        d.polygon([(cx, cy - 12), (cx + 9, cy), (cx, cy + 12), (cx - 9, cy)], outline=(240, 190, 60))
        return img
    save(tiles(carpet, 8, 64), "carpet.png")

    def floor(i, j, ts):
        img = Image.new("RGB", (ts, ts), (236, 236, 240))
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, ts - 1, ts - 1], outline=(200, 200, 208), width=3)
        d.rectangle([6, 6, ts - 7, ts - 7], outline=(248, 248, 252), width=1)
        return img
    save(tiles(floor, 8, 64), "floor_base.png")

    def brick(i, j, ts):
        img = Image.new("RGB", (ts, ts), (180, 180, 186))
        d = ImageDraw.Draw(img)
        rows = 4
        bh = ts // rows
        for rr in range(rows):
            off = (bh if rr % 2 else 0)
            for x in range(-off, ts, bh * 2):
                c = 236 + random.Random(i * 7 + j * 3 + rr * 11 + x).randint(-8, 6)
                d.rectangle([x + 2, rr * bh + 2, x + bh * 2 - 2, rr * bh + bh - 2], fill=(c, c, c + 3))
        return img
    save(tiles(brick, 8, 64), "wall_base.png")

    def wood(i, j, ts):
        img = Image.new("RGB", (ts, ts), (150, 100, 55))
        d = ImageDraw.Draw(img)
        for k in range(4):
            c = 150 + random.Random(i * 5 + j * 9 + k).randint(-18, 12)
            d.rectangle([0, k * ts // 4 + 1, ts, (k + 1) * ts // 4 - 1], fill=(c, int(c * 0.66), int(c * 0.36)))
            for _ in range(3):
                y = k * ts // 4 + random.randint(3, ts // 4 - 3)
                d.line([(random.randint(0, ts // 2), y), (random.randint(ts // 2, ts), y)], fill=(int(c * 0.85), int(c * 0.55), int(c * 0.3)))
        return img
    save(tiles(wood, 8, 64), "wood.png")

    def bld(i, j, ts):
        img = Image.new("RGB", (ts, ts), (225, 225, 230))
        d = ImageDraw.Draw(img)
        for a in range(2):
            for b in range(2):
                x, y = 8 + a * 28, 8 + b * 28
                d.rectangle([x, y, x + 20, y + 20], fill=(120, 170, 220), outline=(90, 90, 100), width=2)
                d.line([(x + 3, y + 3), (x + 9, y + 3)], fill=(220, 240, 255), width=2)
        return img
    save(tiles(bld, 8, 64), "building.png")

    # seta da esteira
    img = Image.new("RGB", (128, 128), (200, 30, 40))
    d = ImageDraw.Draw(img)
    d.polygon([(64, 14), (110, 60), (84, 60), (84, 112), (44, 112), (44, 60), (18, 60)], fill=(255, 215, 80), outline=(140, 80, 0))
    save(img, "arrow.png")
    # placa de coletar
    img = grad(256, 256, (110, 235, 120), (40, 160, 60))
    d = ImageDraw.Draw(img)
    d.rectangle([6, 6, 249, 249], outline=(255, 255, 255), width=10)
    text_center(img, "$", 190, fill=(255, 255, 255), stroke=(20, 90, 30))
    save(img, "pad.png")
    # faixa do logo (arcos)
    img = grad(1024, 102, (255, 255, 255), (220, 228, 240))
    logo_text(img, (0, 0, 1024, 102), 80)
    save(img, "logo_strip.png")


def logo_text(img, box, size):
    """'RE:' vermelho + 'Steal A Brainrot' branco com contorno (como o banner)"""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    f = font(size, "lucky")
    while True:
        w1 = d.textlength("RE:", font=f)
        w2 = d.textlength(" Steal A Brainrot", font=f)
        if w1 + w2 < (x1 - x0) * 0.94 or f.size < 12:
            break
        f = font(f.size - 2, "lucky")
    sw = max(2, f.size // 10)
    tx = x0 + ((x1 - x0) - (w1 + w2)) / 2
    ty = y0 + (y1 - y0) / 2
    for dx, col in ((0, (235, 40, 40)),):
        d.text((tx + sw * 0.6, ty + sw), "RE:", font=f, fill=(0, 0, 0), anchor="lm", stroke_width=sw, stroke_fill=(0, 0, 0))
        d.text((tx, ty), "RE:", font=f, fill=col, anchor="lm", stroke_width=sw, stroke_fill=(90, 0, 0))
    d.text((tx + w1 + sw * 0.6, ty + sw), " Steal A Brainrot", font=f, fill=(0, 0, 0), anchor="lm", stroke_width=sw, stroke_fill=(0, 0, 0))
    d.text((tx + w1, ty), " Steal A Brainrot", font=f, fill=(255, 255, 255), anchor="lm", stroke_width=sw, stroke_fill=(20, 60, 140))


# ---------------------------------------------------------------------------
# Ceus (quads laterais: parte de baixo = horizonte)
# ---------------------------------------------------------------------------
def gen_sky():
    W, H = 512, 512
    # o quad vai de y=-30 a y=110; horizonte (y=0) fica a ~79% da altura (de cima)
    hz = int(H * (110 / 140))

    def sky(top, mid, bottom, name, stars=False, clouds=None, glow=None):
        img = Image.new("RGB", (W, H))
        d = ImageDraw.Draw(img)
        for y in range(H):
            if y < hz:
                t = y / hz
                c = tuple(int(top[k] + (mid[k] - top[k]) * (t ** 1.6)) for k in range(3))
            else:
                t = (y - hz) / (H - hz)
                c = tuple(int(mid[k] + (bottom[k] - mid[k]) * t) for k in range(3))
            d.line([(0, y), (W, y)], fill=c)
        r = random.Random(name)
        if stars:
            for _ in range(260):
                x, y = r.randint(0, W), r.randint(0, int(hz * 0.95))
                b = r.randint(150, 255)
                d.point((x, y), fill=(b, b, min(255, b + 20)))
                if r.random() < 0.08:
                    d.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(b, b, 255))
        if clouds:
            for _ in range(10):
                x, y = r.randint(-40, W), r.randint(int(hz * 0.45), int(hz * 0.9))
                w = r.randint(60, 140)
                d.ellipse([x, y, x + w, y + w // 4], fill=clouds)
        if glow:
            g = Image.new("RGB", (W, H), glow)
            m = Image.new("L", (W, H), 0)
            md = ImageDraw.Draw(m)
            for y in range(H):
                a = max(0, 1 - abs(y - hz) / (H * 0.18))
                md.line([(0, y), (W, y)], fill=int(170 * a))
            img = Image.composite(g, img, m)
        save(img, "sky_%s.png" % name)

    sky((70, 140, 245), (190, 225, 255), (150, 190, 120), "day", clouds=(250, 252, 255))
    sky((8, 6, 30), (60, 30, 90), (20, 15, 30), "night", stars=True, glow=(120, 50, 130))
    sky((60, 8, 6), (255, 110, 30), (80, 20, 10), "lava", glow=(255, 80, 20))
    sky((255, 150, 210), (255, 230, 245), (200, 170, 230), "candy", clouds=(255, 255, 255))


# ---------------------------------------------------------------------------
# Rostos (fundo = cor da pele do avatar)
# ---------------------------------------------------------------------------
def gen_faces():
    def face(skin, name, lashes=False, blush=False):
        S = 256
        img = Image.new("RGB", (S, S), skin)
        d = ImageDraw.Draw(img)
        # olhos (estilo "smile" classico)
        for x in (88, 168):
            d.ellipse([x - 13, 82, x + 13, 126], fill=(20, 20, 20))
            d.ellipse([x - 6, 88, x + 2, 100], fill=(255, 255, 255))
            if lashes:
                d.line([(x - 12, 86), (x - 22, 76)], fill=(20, 20, 20), width=5)
                d.line([(x + 12, 86), (x + 22, 76)], fill=(20, 20, 20), width=5)
        # boca aberta sorrindo
        d.chord([70, 120, 186, 214], 0, 180, fill=(40, 10, 10))
        d.chord([90, 160, 166, 212], 0, 180, fill=(220, 90, 100))
        d.rectangle([84, 140, 172, 152], fill=(255, 255, 255))
        if blush:
            for x in (62, 194):
                d.ellipse([x - 18, 132, x + 18, 150], fill=(255, 160, 160))
        save(img, "face_%s.png" % name)
    face((245, 204, 158), "bacon")
    face((250, 209, 173), "acorn", lashes=True, blush=True)


# ---------------------------------------------------------------------------
# Icones (HUD)
# ---------------------------------------------------------------------------
def gen_icons():
    def icon(name, draw_fn, bg=((50, 60, 110), (20, 24, 50))):
        img = grad(128, 128, bg[0], bg[1])
        d = ImageDraw.Draw(img)
        d.rectangle([2, 2, 125, 125], outline=(255, 255, 255), width=4)
        draw_fn(d)
        save(img, name)

    icon("item_bat.png", lambda d: (d.line([(30, 100), (96, 26)], fill=(40, 40, 40), width=14), d.line([(30, 100), (96, 26)], fill=(200, 140, 70), width=10), d.line([(58, 68), (100, 22)], fill=(215, 155, 80), width=20)))
    icon("item_slap.png", lambda d: (d.rounded_rectangle([34, 40, 94, 100], radius=10, fill=(255, 215, 80), outline=(0, 0, 0), width=4), [d.rounded_rectangle([36 + k * 15, 16, 48 + k * 15, 48], radius=5, fill=(255, 215, 80), outline=(0, 0, 0), width=3) for k in range(4)]))
    icon("item_coil.png", lambda d: [d.ellipse([28, 20 + k * 16, 100, 40 + k * 16], outline=(90, 170, 255), width=6) for k in range(5)])
    icon("item_trap.png", lambda d: (d.ellipse([18, 60, 110, 100], fill=(130, 130, 140), outline=(0, 0, 0), width=4), [d.polygon([(26 + k * 13, 66), (32 + k * 13, 40), (38 + k * 13, 66)], fill=(220, 220, 230), outline=(0, 0, 0)) for k in range(6)]))
    icon("item_cloak.png", lambda d: d.polygon([(64, 16), (104, 108), (64, 92), (24, 108)], fill=(130, 80, 220), outline=(255, 255, 255)))
    icon("boost_halloween.png", lambda d: (d.ellipse([22, 34, 106, 106], fill=(255, 130, 20), outline=(0, 0, 0), width=4), d.rectangle([58, 20, 70, 38], fill=(60, 120, 30)), d.polygon([(40, 60), (56, 60), (48, 74)], fill=(40, 20, 0)), d.polygon([(72, 60), (88, 60), (80, 74)], fill=(40, 20, 0)), d.chord([40, 70, 88, 98], 0, 180, fill=(40, 20, 0))), bg=((60, 20, 80), (20, 6, 30)))
    icon("boost_candy.png", lambda d: (d.ellipse([36, 36, 92, 92], fill=(255, 100, 180), outline=(0, 0, 0), width=4), d.polygon([(36, 64), (12, 44), (12, 84)], fill=(255, 255, 255), outline=(0, 0, 0)), d.polygon([(92, 64), (116, 44), (116, 84)], fill=(255, 255, 255), outline=(0, 0, 0))), bg=((255, 170, 220), (160, 90, 200)))
    icon("boost_lava.png", lambda d: (d.ellipse([30, 40, 98, 108], fill=(255, 100, 20), outline=(60, 10, 0), width=5), d.polygon([(46, 44), (64, 8), (82, 44)], fill=(255, 200, 60))), bg=((120, 20, 10), (40, 6, 2)))
    icon("boost_sugar.png", lambda d: (d.polygon([(70, 12), (34, 70), (60, 70), (48, 116), (96, 52), (68, 52)], fill=(255, 230, 60), outline=(0, 0, 0))), bg=((255, 140, 200), (150, 60, 140)))


def main():
    os.makedirs(IMG, exist_ok=True)
    gen_font()
    gen_names()
    gen_localized()
    gen_world()
    gen_sky()
    gen_faces()
    gen_icons()
    n = sum(len(f) for _, _, f in os.walk(IMG))
    print("texturas:", n)


if __name__ == "__main__":
    main()
