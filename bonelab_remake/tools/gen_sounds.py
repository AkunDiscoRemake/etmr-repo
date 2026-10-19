#!/usr/bin/env python3
"""Sintetiza todos os sons do BoneLab Remake (WAV 22 kHz mono 16-bit).
Uso: python3 tools/gen_sounds.py   (escreve em sounds/)
Nada de samples externos: tudo gerado com numpy (ruido, senoides, filtros via FFT).
"""
import os
import wave

import numpy as np

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "sounds")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1234)


def T(d):
    return np.arange(int(SR * d)) / SR


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def _filt(x, resp):
    n = len(x)
    N = 1 << int(np.ceil(np.log2(max(2, n * 2))))
    X = np.fft.rfft(x, N)
    f = np.fft.rfftfreq(N, 1 / SR)
    y = np.fft.irfft(X * resp(f), N)[:n]
    return y


def lp(x, fc, order=4):
    return _filt(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def hp(x, fc, order=4):
    return _filt(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bp(x, lo, hi):
    return hp(lp(x, hi), lo)


def env(d, a, decay):
    t = T(d)
    e = np.exp(-t / decay)
    if a > 0:
        e *= np.clip(t / a, 0, 1)
    return e


def sweep(d, f0, f1, curve=4.0):
    t = T(d)
    f = f1 + (f0 - f1) * np.exp(-t * curve)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def pad(x, d):
    n = int(SR * d)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def reverb(x, size=0.6, mix=0.25, damp=3000):
    ir_len = int(SR * size)
    ir = rng.uniform(-1, 1, ir_len) * np.exp(-np.arange(ir_len) / (SR * size / 5))
    ir = lp(ir, damp)
    ir[0] = 0
    n = len(x) + ir_len
    N = 1 << int(np.ceil(np.log2(n)))
    y = np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(ir, N), N)[:n]
    y /= (np.max(np.abs(y)) + 1e-9)
    out = np.concatenate([x, np.zeros(ir_len)]) * (1 - mix) + y * mix * np.max(np.abs(x))
    return out


def norm(x, peak=0.92):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def soft(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def fade(x, ms=8):
    n = min(len(x) // 2, int(SR * ms / 1000))
    if n > 0:
        x = x.copy()
        x[-n:] *= np.linspace(1, 0, n)
    return x


def write(name, x, peak=0.92):
    x = fade(norm(x, peak))
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


# ---------------------------------------------------------------------------
# Armas
# ---------------------------------------------------------------------------
def gunshot(d=0.7, crack_tau=0.004, body_fc=2600, body_tau=0.05, thump_f=(130, 48), thump_tau=0.08, tail_tau=0.35,
            tail_fc=900, room=0.5, weight=1.0):
    crack = hp(noise(d), 1800) * env(d, 0, crack_tau) * 1.2
    body = lp(noise(d), body_fc) * env(d, 0.001, body_tau)
    thump = sweep(d, thump_f[0], thump_f[1], 18) * env(d, 0.001, thump_tau) * 1.1 * weight
    tail = lp(noise(d), tail_fc) * env(d, 0.004, tail_tau) * 0.45
    x = soft(mix(crack, body, thump, tail), 2.2)
    return reverb(x, room, 0.22)


def metal_click(freqs=(2400, 3700, 5200), d=0.12, tau=0.02, amp=1.0):
    t = T(d)
    x = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / (tau * (1 + i * 0.4))) for i, f in enumerate(freqs))
    x += hp(noise(d), 3000) * env(d, 0, 0.004) * 0.8
    return x * amp


def at(x, offset, total):
    out = np.zeros(int(SR * total))
    i = int(SR * offset)
    n = min(len(x), len(out) - i)
    out[i:i + n] += x[:n]
    return out


def weapons():
    write("pistol.wav", gunshot())
    write("smg.wav", gunshot(0.45, 0.003, 3200, 0.035, (160, 60), 0.05, 0.18, 1200, 0.35, 0.8))
    write("shotgun.wav", gunshot(1.2, 0.006, 1800, 0.09, (95, 38), 0.16, 0.6, 700, 0.9, 1.6))
    write("empty.wav", metal_click((3100, 4700), 0.08, 0.008), 0.6)
    tot = 0.35
    write("mag_out.wav", mix(at(metal_click((1800, 2900, 4100), 0.1, 0.015), 0, tot),
                             at(lp(noise(0.2), 2500) * env(0.2, 0.01, 0.06) * 0.4, 0.04, tot)))
    write("mag_in.wav", mix(at(metal_click((1500, 2600, 3900), 0.1, 0.012), 0, tot),
                            at(metal_click((2100, 3300), 0.1, 0.02, 1.2), 0.09, tot)))
    sl = bp(noise(0.25), 1500, 6000) * env(0.25, 0.02, 0.06)
    write("slide.wav", mix(at(sl, 0, 0.4), at(metal_click((1700, 2500, 3600), 0.12, 0.02, 1.3), 0.12, 0.4)))
    write("pump_back.wav", mix(at(bp(noise(0.2), 800, 4000) * env(0.2, 0.01, 0.05), 0, 0.3),
                               at(metal_click((1200, 2100), 0.1, 0.02), 0.08, 0.3)))
    write("pump_fwd.wav", mix(at(bp(noise(0.2), 900, 4500) * env(0.2, 0.01, 0.04), 0, 0.3),
                              at(metal_click((1400, 2300, 3300), 0.1, 0.025, 1.4), 0.06, 0.3)))
    write("drop.wav", metal_click((620, 1340, 2210, 3170), 0.4, 0.06), 0.7)
    write("grab.wav", lp(noise(0.12), 1200) * env(0.12, 0.005, 0.03) + 0.3 * metal_click((900,), 0.12, 0.02), 0.5)
    v = noise(0.35) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 45 * T(0.35))))
    write("pouch.wav", bp(v, 1500, 7000) * env(0.35, 0.01, 0.12), 0.6)
    write("bat_hit.wav", reverb(mix(metal_click((420, 980, 1730, 2650), 0.5, 0.07, 1.5),
                                    lp(noise(0.5), 600) * env(0.5, 0, 0.05) * 1.5), 0.3, 0.2))
    write("punch.wav", mix(sweep(0.3, 140, 50, 25) * env(0.3, 0.002, 0.06) * 1.4,
                           lp(noise(0.3), 1500) * env(0.3, 0, 0.03)))
    write("swing.wav", bp(noise(0.4), 300, 2000) * np.sin(np.pi * T(0.4) / 0.4) ** 2, 0.6)
    write("impact_metal.wav", mix(metal_click((2900, 4300, 6100), 0.25, 0.03),
                                  sweep(0.25, 5200, 2600, 10) * env(0.25, 0, 0.08) * 0.4), 0.6)
    write("impact_concrete.wav", lp(noise(0.25), 3000) * env(0.25, 0, 0.03) + hp(noise(0.25), 4000) * env(0.25, 0, 0.01), 0.6)
    boom_d = 2.2
    boom = mix(lp(noise(boom_d), 300) * env(boom_d, 0.005, 0.5) * 1.5,
               sweep(boom_d, 90, 28, 3) * env(boom_d, 0.005, 0.4) * 1.3,
               hp(noise(boom_d), 2000) * env(boom_d, 0, 0.03) * 0.6,
               lp(noise(boom_d), 1200) * env(boom_d, 0.02, 0.25) * 0.5)
    write("explosion.wav", reverb(soft(boom, 2.5), 1.2, 0.3, 1500))


# ---------------------------------------------------------------------------
# Bots
# ---------------------------------------------------------------------------
def bots():
    d = 1.0
    t = T(d)
    f = 520 * np.exp(-t * 2.2) + 40
    saw = 2 * ((np.cumsum(f) / SR) % 1) - 1
    crunch = lp(noise(d), 2000) * env(d, 0, 0.08)
    write("bot_die.wav", reverb(mix(lp(saw, 1800) * env(d, 0.005, 0.35), crunch,
                                    metal_click((700, 1500, 2600), 0.6, 0.06, 0.8)), 0.5, 0.2))
    d = 0.6
    t = T(d)
    scr = np.sin(2 * np.pi * np.cumsum(1800 + 600 * np.sin(2 * np.pi * 38 * t)) / SR) * env(d, 0.01, 0.15)
    write("crab_die.wav", mix(scr * 0.7, lp(noise(d), 900) * env(d, 0, 0.1)))
    d = 0.7
    t = T(d)
    mod = np.sin(2 * np.pi * 31 * t) * 700
    scream = np.sin(2 * np.pi * np.cumsum(2400 + mod + 900 * np.sin(2 * np.pi * 7 * t)) / SR)
    write("crab_screech.wav", hp(scream * env(d, 0.02, 0.3) + 0.3 * hp(noise(d), 3000) * env(d, 0.02, 0.2), 600), 0.7)
    d = 0.6
    t = T(d)
    write("headshot.wav", mix(sum(np.sin(2 * np.pi * f * t) * np.exp(-t / (0.25 / (i + 1))) * (0.8 ** i)
                                  for i, f in enumerate((1760, 3520, 5280, 2640))),
                              hp(noise(d), 2500) * env(d, 0, 0.01) * 1.2))
    write("hit_bot.wav", mix(sweep(0.25, 260, 90, 20) * env(0.25, 0.001, 0.05),
                             metal_click((1900, 3100), 0.25, 0.02, 0.7)), 0.8)
    d = 0.5
    zap = sweep(d, 1800, 200, 9) * env(d, 0.002, 0.15)
    write("plasma.wav", mix(zap, bp(noise(d), 2000, 6000) * env(d, 0, 0.05) * 0.5), 0.75)
    write("plasma_pop.wav", mix(sweep(0.3, 900, 120, 15) * env(0.3, 0, 0.06), hp(noise(0.3), 1500) * env(0.3, 0, 0.03)), 0.7)
    d = 0.75
    t = T(d)
    ch = np.sin(2 * np.pi * np.cumsum(300 + 900 * (t / d) ** 2) / SR) * np.clip(t / d, 0, 1) ** 1.5
    write("charge.wav", ch + 0.2 * np.sin(2 * np.pi * np.cumsum(600 + 1800 * (t / d) ** 2) / SR) * (t / d), 0.6)
    d = 1.3
    t = T(d)
    shimmer = sum(np.sin(2 * np.pi * np.cumsum(f * (1 + 0.6 * t)) / SR) for f in (220, 331, 442, 663))
    write("spawn.wav", reverb(shimmer * env(d, 0.3, 0.5) * 0.5 + bp(noise(d), 2000, 8000) * env(d, 0.4, 0.3) * 0.3, 0.8, 0.3))
    write("respawn.wav", reverb(sum(np.sin(2 * np.pi * f * T(0.5)) for f in (880, 1320, 1760)) * env(0.5, 0.01, 0.12), 0.4, 0.2), 0.5)


# ---------------------------------------------------------------------------
# Jogador / UI
# ---------------------------------------------------------------------------
def player_ui():
    write("player_hurt.wav", mix(sweep(0.45, 110, 45, 10) * env(0.45, 0.002, 0.12) * 1.3,
                                 lp(noise(0.45), 700) * env(0.45, 0, 0.06),
                                 np.sin(2 * np.pi * 3100 * T(0.45)) * env(0.45, 0.01, 0.2) * 0.12))
    d = 2.5
    t = T(d)
    drone = sum(np.sin(2 * np.pi * f * (1 - 0.35 * t / d) * t) for f in (55, 82.4, 110))
    write("player_die.wav", reverb(drone * env(d, 0.05, 1.0) + lp(noise(d), 300) * env(d, 0, 0.4), 1.0, 0.3))
    beat = sweep(0.2, 70, 40, 12) * env(0.2, 0.004, 0.05)
    write("heartbeat.wav", mix(at(beat, 0, 0.6), at(beat * 0.7, 0.22, 0.6)), 0.8)
    d = 1.6
    t = T(d)
    horn = np.zeros(len(t))
    for f in (110, 164.8, 220, 277.2):
        ph = np.cumsum(f * (1 + 0.003 * np.sin(2 * np.pi * 5 * t))) / SR
        horn += 2 * (ph % 1) - 1
    horn = lp(horn, 1600) * env(d, 0.05, 0.7)
    write("wave_start.wav", reverb(soft(horn, 1.5), 0.9, 0.25))
    notes = (523.3, 659.3, 784, 1046.5)
    arp = mix(*[at(np.sin(2 * np.pi * f * T(0.5)) * env(0.5, 0.005, 0.18), i * 0.09, 1.0) for i, f in enumerate(notes)])
    write("wave_clear.wav", reverb(arp, 0.6, 0.25))
    notes = (784, 987.8, 1174.7, 1568, 1975.5)
    arp = mix(*[at(np.sin(2 * np.pi * f * T(0.4)) * env(0.4, 0.003, 0.12), i * 0.06, 1.0) for i, f in enumerate(notes)])
    write("record.wav", reverb(arp, 0.6, 0.3))
    write("ui_click.wav", metal_click((2000, 3000), 0.08, 0.01), 0.6)
    write("ui_confirm.wav", mix(at(np.sin(2 * np.pi * 880 * T(0.12)) * env(0.12, 0.002, 0.04), 0, 0.3),
                                at(np.sin(2 * np.pi * 1320 * T(0.15)) * env(0.15, 0.002, 0.05), 0.08, 0.3)), 0.6)
    write("step.wav", lp(noise(0.15), 500) * env(0.15, 0.004, 0.03) + 0.4 * sweep(0.15, 90, 50, 30) * env(0.15, 0.002, 0.03), 0.5)


# ---------------------------------------------------------------------------
# Musica (loops sem emenda: eventos somados de forma circular)
# ---------------------------------------------------------------------------
def note_freq(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def add_circ(buf, x, start):
    n = len(buf)
    i = int(start) % n
    end = i + len(x)
    if end <= n:
        buf[i:end] += x
    else:
        k = n - i
        buf[i:] += x[:k]
        rest = x[k:]
        while len(rest) > 0:
            m = min(len(rest), n)
            buf[:m] += rest[:m]
            rest = rest[m:]


def saw(f, d, detune=0.0):
    t = T(d)
    return 2 * ((t * f * (1 + detune)) % 1) - 1


def music_lab():
    bpm = 96
    beat = 60 / bpm
    bars = 8
    L = int(SR * beat * 4 * bars)
    buf = np.zeros(L)
    # Am9 - Fmaj7 - Cmaj7 - G6 (2 compassos cada)
    chords = [(57, 60, 64, 67, 71), (53, 57, 60, 64), (48, 55, 59, 64), (55, 59, 62, 64)]
    for ci, ch in enumerate(chords):
        start = ci * 2 * 4 * beat
        d = 2 * 4 * beat + 2.0
        t = T(d)
        a = np.clip(t / 1.2, 0, 1) * np.clip((d - t) / 1.8, 0, 1)
        p = np.zeros(len(t))
        for n in ch:
            f = note_freq(n - 12)
            p += saw(f, d, 0.003) + saw(f, d, -0.004) * 0.8
        p = lp(p, 1100) * a * 0.12
        add_circ(buf, p, start * SR)
        # baixo
        bass = np.sin(2 * np.pi * note_freq(ch[0] - 24) * t) * a * 0.35
        add_circ(buf, bass, start * SR)
        # arpejo
        for k in range(16):
            n = ch[(k * 2 + (k // 4)) % len(ch)] + 12
            dd = 0.6
            pl = np.sin(2 * np.pi * note_freq(n) * T(dd)) * env(dd, 0.003, 0.18) * 0.16
            pl += np.sin(2 * np.pi * note_freq(n) * 2 * T(dd)) * env(dd, 0.003, 0.08) * 0.05
            add_circ(buf, pl, (start + k * beat / 2) * SR)
    # chimbal suave
    for k in range(bars * 8):
        h = hp(noise(0.05), 7000) * env(0.05, 0, 0.012) * (0.05 if k % 2 else 0.03)
        add_circ(buf, h, k * beat / 2 * SR)
    buf = reverb(buf, 1.5, 0.35, 2500)[:L] + 0
    write("music_lab.wav", buf, 0.7)


def music_combat():
    bpm = 128
    beat = 60 / bpm
    bars = 8
    L = int(SR * beat * 4 * bars)
    buf = np.zeros(L)
    kick = sweep(0.35, 160, 42, 22) * env(0.35, 0.001, 0.12)
    clap = bp(noise(0.25), 900, 5000) * env(0.25, 0.001, 0.06)
    hat = hp(noise(0.06), 8000) * env(0.06, 0, 0.015)
    roots = [45, 45, 41, 43, 45, 45, 48, 43]   # A A F G A A C G
    for b in range(bars):
        for q in range(4):
            tq = (b * 4 + q) * beat
            add_circ(buf, kick * 0.9, tq * SR)
            if q % 2 == 1:
                add_circ(buf, clap * 0.45, tq * SR)
            for s in range(4):
                add_circ(buf, hat * (0.22 if s == 2 else 0.1), (tq + s * beat / 4) * SR)
        # baixo em colcheias com "sidechain"
        r = roots[b]
        for e in range(8):
            d = beat / 2
            t = T(d)
            f = note_freq(r - 12 + (12 if e % 4 == 3 else 0))
            x = lp(saw(f, d) + saw(f, d, 0.01), 700) * np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.18) * 0.33
            x *= np.clip((t + 0.02) / (beat / 2), 0.3, 1) if e % 2 == 0 else 1
            add_circ(buf, x, (b * 4 * beat + e * d) * SR)
        # acorde stab no contratempo
        for q in (0.5, 2.5):
            d = 0.3
            st = sum(saw(note_freq(n), d, 0.004) for n in (r + 24, r + 27, r + 31))
            st = lp(st, 2600) * env(d, 0.003, 0.08) * 0.09
            add_circ(buf, st, (b * 4 + q) * beat * SR)
    # riser a cada 4 compassos
    for b in (3, 7):
        d = beat * 4
        add_circ(buf, hp(noise(d), 2000) * np.linspace(0, 1, int(SR * d)) ** 2 * 0.12, b * 4 * beat * SR)
    write("music_combat.wav", soft(buf, 1.3), 0.75)


def main():
    weapons()
    bots()
    player_ui()
    music_lab()
    music_combat()
    print("sons em", OUT, len(os.listdir(OUT)))


if __name__ == "__main__":
    main()
