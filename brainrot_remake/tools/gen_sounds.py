#!/usr/bin/env python3
"""Gera os sons do RE:Steal A Brainrot VR (sounds/).

* efeitos sintetizados (numpy): comprar, dinheiro, roubar, alarme, tacada, pulo...
* 4 musicas em loop: dia, noite de Halloween, evento Candy, evento de Lava
* vozes: cada brainrot diz o proprio nome em ITALIANO (Piper TTS, vozes it_IT
  riccardo/paola). Os modelos .onnx ficam fora do repositorio: passe a pasta em
  PIPER_VOICES (padrao: ./tts). Sem eles, as vozes existentes sao mantidas.
"""
import io
import math
import os
import re
import subprocess
import sys
import wave

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SND = os.path.join(ROOT, "sounds")
SR = 22050
rng = np.random.default_rng(3)


def write(name, x, sr=SR):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) if len(x) else 1
    if peak > 0.98:
        x = x / peak * 0.98
    p = os.path.join(SND, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with wave.open(p, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def t_(d): return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.1, sus=None):
    e = np.ones(n)
    na = max(1, int(SR * a))
    e[:na] = np.linspace(0, 1, na)
    nr = max(1, int(SR * r))
    if nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def expdec(n, k): return np.exp(-np.arange(n) / SR * k)


def sine(f, d, ph=0):
    t = t_(d)
    if callable(f):
        return np.sin(2 * np.pi * np.cumsum(f(t)) / SR + ph)
    return np.sin(2 * np.pi * f * t + ph)


def square(f, d, duty=0.5):
    t = t_(d)
    return np.where((t * f) % 1 < duty, 1.0, -1.0)


def tri(f, d):
    t = t_(d)
    return 2 * np.abs(2 * ((t * f) % 1) - 1) - 1


def noise(d): return rng.uniform(-1, 1, int(SR * d))


def lp(x, k=0.2):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc)
        y[i] = acc
    return y


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, start, total):
    out = np.zeros(int(SR * total))
    s = int(SR * start)
    e = min(len(out), s + len(x))
    out[s:e] += x[:e - s]
    return out


def note(n):  # midi -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)


# ---------------------------------------------------------------------------
# Efeitos
# ---------------------------------------------------------------------------
def coin(f1=988, f2=1319, d=0.35):
    a = square(f1, 0.07, 0.25) * 0.35
    b = square(f2, d, 0.25) * 0.35 * expdec(int(SR * d), 9)
    return np.concatenate([a, b])


def gen_sfx():
    write("buy.wav", mix(coin(784, 1175, 0.3), at(sine(1568, 0.2) * expdec(int(SR * 0.2), 14) * 0.3, 0.12, 0.42)))
    write("cash.wav", mix(coin(1319, 1760, 0.25), at(noise(0.08) * expdec(int(SR * 0.08), 40) * 0.25, 0, 0.35)))
    # colocar na base: "plop" + brilho
    write("place.wav", mix(sine(lambda t: 300 + 500 * t / 0.15, 0.15) * expdec(int(SR * 0.15), 18) * 0.7,
                           at(sine(1760, 0.25) * expdec(int(SR * 0.25), 12) * 0.25, 0.08, 0.4)))
    # roubar: arpejo rapido "malandro"
    s = np.concatenate([square(note(n), 0.07, 0.3) * 0.3 * expdec(int(SR * 0.07), 10) for n in (72, 75, 79, 84)])
    write("steal.wav", s)
    # sucesso: fanfarra curta
    parts = []
    for i, n in enumerate((72, 76, 79, 84)):
        d = 0.12 if i < 3 else 0.5
        parts.append(at((square(note(n), d, 0.25) * 0.25 + tri(note(n) / 2, d) * 0.25) * env(int(SR * d), 0.005, 0.08), i * 0.11, 0.9))
    write("success.wav", mix(*parts))
    write("drop.wav", sine(lambda t: 600 - 450 * t / 0.35, 0.35) * expdec(int(SR * 0.35), 7) * 0.6)
    write("recover.wav", np.concatenate([sine(note(n), 0.09) * 0.5 * expdec(int(SR * 0.09), 12) for n in (67, 71, 74, 79)]))
    # alarme: sirene 2 tons
    al = np.concatenate([square(880 if i % 2 == 0 else 660, 0.18, 0.5) * 0.3 for i in range(8)])
    write("alarm.wav", lp(al, 0.35) * env(len(al), 0.01, 0.1))
    write("tick.wav", sine(1800, 0.04) * expdec(int(SR * 0.04), 60) * 0.5)
    # tacada "bonk"
    b = sine(lambda t: 220 - 120 * t / 0.25, 0.25) * expdec(int(SR * 0.25), 16)
    write("bonk.wav", mix(b * 0.9, lp(noise(0.06), 0.4) * expdec(int(SR * 0.06), 50) * 0.6))
    write("slap.wav", mix(lp(noise(0.12), 0.6) * expdec(int(SR * 0.12), 35) * 0.9, sine(180, 0.1) * expdec(int(SR * 0.1), 30) * 0.4))
    sw = lp(noise(0.25), 0.15) * np.sin(np.linspace(0, np.pi, int(SR * 0.25))) * 0.6
    write("swing.wav", sw)
    write("hurt.wav", mix(sine(lambda t: 500 - 300 * t / 0.3, 0.3) * expdec(int(SR * 0.3), 9) * 0.6, square(140, 0.15, 0.4) * 0.2 * expdec(int(SR * 0.15), 20)))
    write("jump.wav", sine(lambda t: 300 + 700 * t / 0.18, 0.18) * env(int(SR * 0.18), 0.005, 0.08) * 0.45)
    write("equip.wav", mix(lp(noise(0.06), 0.5) * expdec(int(SR * 0.06), 40) * 0.4, at(sine(1200, 0.1) * expdec(int(SR * 0.1), 30) * 0.3, 0.03, 0.15)))
    lk = np.concatenate([square(note(n), 0.08, 0.5) * 0.25 for n in (60, 67, 72)])
    write("lock.wav", mix(lp(lk, 0.3), at(sine(lambda t: 1500 + 2000 * t, 0.6) * env(int(SR * 0.6), 0.01, 0.3) * 0.15, 0.2, 0.8)))
    write("unlock.wav", np.concatenate([square(note(n), 0.09, 0.5) * 0.25 for n in (72, 67, 60)]))
    write("trap_set.wav", mix(sine(300, 0.08) * expdec(int(SR * 0.08), 30), at(lp(noise(0.05), 0.5) * 0.4, 0.05, 0.15)))
    write("trap_snap.wav", mix(lp(noise(0.1), 0.7) * expdec(int(SR * 0.1), 30) * 0.9, sine(90, 0.2) * expdec(int(SR * 0.2), 12) * 0.6))
    write("cloak.wav", sine(lambda t: 1200 - 900 * t / 0.6, 0.6) * env(int(SR * 0.6), 0.02, 0.3) * 0.35 + lp(noise(0.6), 0.1) * 0.15)
    write("candy.wav", np.concatenate([sine(note(n), 0.06) * 0.45 * expdec(int(SR * 0.06), 15) for n in (84, 88, 91)]))
    m = lp(noise(1.4), 0.08) * expdec(int(SR * 1.4), 3) * 1.2 + sine(lambda t: 60 - 30 * t, 1.4) * expdec(int(SR * 1.4), 4) * 0.8
    write("meteor.wav", m)
    rb = []
    for i, n in enumerate((60, 64, 67, 72, 76, 79, 84)):
        rb.append(at(tri(note(n), 0.5) * expdec(int(SR * 0.5), 5) * 0.3, i * 0.08, 1.4))
    write("rebirth.wav", mix(*rb, at(sine(lambda t: 200 + 800 * t, 1.0) * env(int(SR * 1.0), 0.3, 0.5) * 0.2, 0.2, 1.4)))
    ch = mix(*[at((sine(note(n), 1.8) + 0.4 * sine(note(n) * 2, 1.8)) * env(int(SR * 1.8), 0.15, 0.9) * 0.16, 0, 2.0) for n in (60, 64, 67, 72, 76)])
    sp = mix(*[at(sine(note(n), 0.25) * expdec(int(SR * 0.25), 10) * 0.2, 0.1 + i * 0.09, 2.0) for i, n in enumerate((84, 88, 91, 96, 100))])
    write("rare.wav", mix(ch, sp))
    write("ui_click.wav", sine(1400, 0.03) * expdec(int(SR * 0.03), 80) * 0.5)
    write("ui_confirm.wav", np.concatenate([sine(988, 0.06) * 0.4, sine(1319, 0.12) * 0.4 * expdec(int(SR * 0.12), 15)]))
    # eventos
    org = mix(*[at(sine(note(n), 1.6) * env(int(SR * 1.6), 0.05, 0.6) * 0.18 + sine(note(n) * 2, 1.6) * 0.06, 0, 1.8) for n in (57, 60, 64, 68)])
    laugh = np.concatenate([sine(lambda t: 600 + 80 * np.sin(t * 60), 0.12) * env(int(SR * 0.12), 0.01, 0.05) * 0.3 * (1 - i * 0.12) for i in range(6)])
    write("ev_halloween.wav", mix(org, at(laugh, 0.6, 1.8)))
    write("ev_candy.wav", np.concatenate([tri(note(n), 0.1) * 0.4 * expdec(int(SR * 0.1), 8) for n in (77, 81, 84, 89, 84, 89, 93)]))
    rumble = lp(noise(1.6), 0.03) * env(int(SR * 1.6), 0.2, 0.6) * 1.5
    siren = np.concatenate([square(440 if i % 2 == 0 else 349, 0.2, 0.5) * 0.15 for i in range(8)])
    write("ev_lava.wav", mix(rumble, lp(siren, 0.25)))


# ---------------------------------------------------------------------------
# Musicas (loops perfeitos)
# ---------------------------------------------------------------------------
def drum_kick(d=0.25):
    return sine(lambda t: 120 * np.exp(-t * 18) + 45, d) * expdec(int(SR * d), 12)


def drum_snare(d=0.18):
    return lp(noise(d), 0.5) * expdec(int(SR * d), 22) * 0.6 + sine(190, d) * expdec(int(SR * d), 30) * 0.3


def drum_hat(d=0.05):
    x = noise(d)
    return (x - lp(x, 0.3)) * expdec(int(SR * d), 70) * 0.35


def song(bpm, bars, chords, melody, lead="square", bass_wave="tri", drums="pop", pad=None, swing=0.0, lead_vol=0.22):
    beat = 60 / bpm
    total = bars * 4 * beat
    n = int(SR * total)
    out = np.zeros(n + SR * 2)

    def place(x, start):
        s = int(SR * start)
        out[s:s + len(x)] += x

    # acordes / pad
    for b in range(bars):
        ch = chords[b % len(chords)]
        if pad == "organ":
            for k in ch:
                f = note(k)
                x = (sine(f, beat * 4) + 0.5 * sine(f * 2, beat * 4) + 0.25 * sine(f * 3, beat * 4)) * env(int(SR * beat * 4), 0.08, 0.3) * 0.05
                place(x, b * 4 * beat)
        else:
            for beatn in range(4):
                for k in ch:
                    f = note(k)
                    x = tri(f, beat * 0.9) * env(int(SR * beat * 0.9), 0.01, 0.2) * 0.045
                    place(x, (b * 4 + beatn) * beat + (beat * 0.5 if drums != "lava" else 0))
        # baixo
        root = note(ch[0] - 12)
        nb = 8 if drums in ("pop", "lava", "bounce") else 4
        step = 4 * beat / nb
        for k in range(nb):
            d = step
            f = root if (k % 4) != 3 else root * 1.5
            if bass_wave == "square":
                x = square(f, d * 0.9, 0.5) * 0.12
            else:
                x = tri(f, d * 0.9) * 0.22
            x *= env(len(x), 0.005, 0.05)
            place(x, b * 4 * beat + k * step)
    # melodia: lista (nota midi | None, duracao em batidas)
    tpos = 0.0
    while tpos < bars * 4 - 1e-6:
        for (m, d) in melody:
            if tpos >= bars * 4 - 1e-6:
                break
            dur = d * beat
            if m is not None:
                f = note(m)
                if lead == "square":
                    x = square(f, dur * 0.92, 0.25)
                elif lead == "tri":
                    x = tri(f, dur * 0.92)
                elif lead == "bell":
                    s2 = sine(f * 2.01, dur * 0.95)
                    x = sine(f, dur * 0.95) * 0.7 + s2 * 0.3 * expdec(len(s2), 6)
                else:
                    x = sine(f, dur * 0.92)
                x *= env(len(x), 0.008, min(0.12, dur * 0.4)) * lead_vol
                if lead == "bell":
                    x *= expdec(len(x), 3)
                st = tpos * beat
                if swing and int(tpos * 2) % 2 == 1:
                    st += swing * beat * 0.5
                place(x, st)
            tpos += d
    # bateria
    for b in range(bars * 4):
        t0 = b * beat
        if drums == "pop":
            if b % 4 in (0, 2):
                place(drum_kick() * 0.7, t0)
            if b % 4 in (1, 3):
                place(drum_snare() * 0.5, t0)
            place(drum_hat(), t0 + beat / 2)
        elif drums == "bounce":
            place(drum_kick() * 0.6, t0)
            place(drum_hat() * 1.2, t0 + beat / 2)
            if b % 2 == 1:
                place(drum_snare() * 0.35, t0)
        elif drums == "spooky":
            if b % 4 == 0:
                place(drum_kick(0.4) * 0.6, t0)
            if b % 8 == 6:
                place(drum_snare(0.3) * 0.3, t0)
            place(drum_hat() * 0.5, t0 + beat / 2)
        elif drums == "lava":
            place(drum_kick() * 0.8, t0)
            place(drum_kick() * 0.5, t0 + beat / 2)
            if b % 2 == 1:
                place(drum_snare() * 0.6, t0)
            for k in range(4):
                place(drum_hat() * 0.6, t0 + k * beat / 4)
    # cauda volta para o inicio (loop sem estalo)
    tail = out[n:].copy()
    out = out[:n]
    out[:len(tail)] += tail[:n]
    return out * 0.9


def gen_music():
    C, D, E, F, G, A, B = 60, 62, 64, 65, 67, 69, 71
    # DIA: alegre (C G Am F), 124 bpm
    mel_day = [(E + 12, 0.5), (G + 12, 0.5), (C + 24, 1), (B + 12, 0.5), (G + 12, 0.5), (E + 12, 1),
               (D + 12, 0.5), (E + 12, 0.5), (G + 12, 0.5), (A + 12, 0.5), (G + 12, 1), (None, 1),
               (C + 12, 0.5), (E + 12, 0.5), (A + 12, 1), (G + 12, 0.5), (E + 12, 0.5), (C + 12, 1),
               (D + 12, 0.5), (F + 12, 0.5), (E + 12, 0.5), (D + 12, 0.5), (C + 12, 2)]
    write("music_day.wav", song(124, 8, [[C, E, G], [G - 12, B - 12, D], [A - 12, C, E], [F - 12, A - 12, C]], mel_day, lead="square"))
    # NOITE (Halloween): Am F E, 96 bpm, sinos + orgao
    mel_night = [(A + 12, 1), (C + 24, 0.5), (B + 12, 0.5), (A + 12, 1), (E + 12, 1),
                 (F + 12, 1), (E + 12, 0.5), (D + 12, 0.5), (E + 12, 2),
                 (A + 12, 1), (C + 24, 0.5), (D + 24, 0.5), (E + 24, 1), (D + 24, 0.5), (C + 24, 0.5),
                 (B + 12, 1), (G + 12 + 1, 1), (A + 12, 2)]
    write("music_night.wav", song(96, 8, [[A - 12, C, E], [F - 12, A - 12, C], [E - 12, G - 12 + 1, B - 12], [A - 12, C, E]], mel_night, lead="bell", drums="spooky", pad="organ", lead_vol=0.28))
    # CANDY: saltitante, 140 bpm, xilofone
    mel_candy = [(F + 12, 0.5), (A + 12, 0.5), (C + 24, 0.5), (A + 12, 0.5), (D + 24, 1), (C + 24, 1),
                 (A + 12, 0.5), (C + 24, 0.5), (F + 24, 1), (E + 24, 0.5), (D + 24, 0.5), (C + 24, 1),
                 (G + 12, 0.5), (A + 12, 0.5), (B + 12 - 1, 0.5), (C + 24, 0.5), (D + 24, 1), (B + 12 - 1, 1),
                 (A + 12, 0.5), (G + 12, 0.5), (F + 12, 2), (None, 0.5)]
    write("music_candy.wav", song(140, 8, [[F - 12, A - 12, C], [B - 13, D, F], [C, E, G], [F - 12, A - 12, C]], mel_candy, lead="bell", drums="bounce", swing=0.3, lead_vol=0.3))
    # LAVA: intenso, Dm, 150 bpm
    mel_lava = [(D + 12, 0.5), (D + 12, 0.5), (F + 12, 0.5), (D + 12, 0.5), (A + 12, 1), (G + 12, 0.5), (F + 12, 0.5),
                (E + 12, 0.5), (E + 12, 0.5), (G + 12, 0.5), (E + 12, 0.5), (C + 24, 1), (A + 12, 1),
                (D + 24, 0.5), (C + 24, 0.5), (A + 12, 0.5), (F + 12, 0.5), (G + 12, 1), (E + 12, 1),
                (D + 12, 2), (None, 2)]
    write("music_lava.wav", song(150, 8, [[D - 12, F - 12, A - 12], [B - 25, D - 12, F - 12], [C - 12, E - 12, G - 12], [A - 24, C - 12 + 1, E - 12]], mel_lava, lead="square", bass_wave="square", drums="lava", lead_vol=0.2))


# ---------------------------------------------------------------------------
# Vozes italianas (Piper)
# ---------------------------------------------------------------------------
FEMALE = {"lirili", "ballerina", "tralaleritas", "espresso", "bambini", "bananita", "strawberry", "fluriflura", "gattatino", "vacca"}


def gen_voices():
    vdir = os.environ.get("PIPER_VOICES", os.path.join(os.getcwd(), "tts"))
    male = os.path.join(vdir, "it_IT-riccardo-x_low.onnx")
    female = os.path.join(vdir, "it_IT-paola-medium.onnx")
    if not (os.path.isfile(male) and os.path.isfile(female)):
        print("vozes: modelos Piper nao encontrados em", vdir, "(mantendo as existentes)")
        return
    src = open(os.path.join(ROOT, "scripts", "catalog.lua"), encoding="utf8").read()
    items = re.findall(r'\{ "(\w+)",\s+"([^"]+)",\s+"\w+"', src)
    for bid, name in items:
        model = female if bid in FEMALE else male
        text = name.replace("Lirilì", "Lirilì").replace("3000", "tremila") + "!"
        tmp = os.path.join(SND, "voice", "_tmp.wav")
        os.makedirs(os.path.dirname(tmp), exist_ok=True)
        subprocess.run([sys.executable, "-m", "piper", "-m", model, "-f", tmp, "--length-scale", "0.9"],
                       input=text.encode("utf8"), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with wave.open(tmp) as w:
            sr = w.getframerate()
            x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32767
        os.remove(tmp)
        # reamostra para 22050 e corta silencio
        n = int(len(x) * SR / sr)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
        idx = np.where(np.abs(x) > 0.02)[0]
        if len(idx):
            x = x[max(0, idx[0] - 200): idx[-1] + 600]
        # um pouco de "radio" e eco curto (estilo video de brainrot)
        echo = np.zeros(len(x) + int(SR * 0.09))
        echo[:len(x)] += x
        echo[int(SR * 0.09):] += x * 0.22
        write("voice/%s.wav" % bid, echo * 0.95)
    print("vozes:", len(items))


def main():
    os.makedirs(SND, exist_ok=True)
    gen_sfx()
    gen_music()
    gen_voices()
    print("sons:", sum(len(f) for _, _, f in os.walk(SND)))


if __name__ == "__main__":
    main()
