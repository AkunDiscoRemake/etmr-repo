#!/usr/bin/env python3
"""Sintetiza os sons do SUPERHOT Remake (WAV 22 kHz mono 16-bit), incluindo a voz "SUPER HOT".
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
# Voz robotica por sintese de formantes ("SUPER" ... "HOT")
# ---------------------------------------------------------------------------
def glottal(d, f0a, f0b):
    t = T(d)
    f0 = f0a + (f0b - f0a) * (t / max(d, 1e-6))
    ph = np.cumsum(f0) / SR
    saw = 2 * (ph % 1) - 1
    return saw - 0.3 * np.sign(np.sin(2 * np.pi * ph))   # mais harmonicos


def formants(x, fs, bws=(80, 110, 160), gains=(1.0, 0.6, 0.35)):
    """Filtro de ressonancias (soma de picos gaussianos no espectro)."""
    def resp(f):
        r = np.zeros_like(f)
        for fc, bw, g in zip(fs, bws, gains):
            r += g * np.exp(-0.5 * ((f - fc) / bw) ** 2)
        return r + 0.02
    return _filt(x, resp)


def vowel(d, fs, f0a, f0b, amp=1.0):
    x = formants(glottal(d, f0a, f0b), fs)
    a = np.clip(T(d) / 0.025, 0, 1) * np.clip((d - T(d)) / 0.04, 0, 1)
    return x / (np.max(np.abs(x)) + 1e-9) * a * amp


def fric(d, lo, hi, amp=0.5):
    x = bp(noise(d), lo, hi)
    a = np.clip(T(d) / 0.02, 0, 1) * np.clip((d - T(d)) / 0.02, 0, 1)
    return x / (np.max(np.abs(x)) + 1e-9) * a * amp


def concat(*parts):
    return np.concatenate(parts)


def robot(x):
    # timbre de robo: leve ring-mod + eco curto + reverb grande
    t = np.arange(len(x)) / SR
    x = x * (0.85 + 0.15 * np.sin(2 * np.pi * 30 * t))
    d = int(SR * 0.012)
    y = x.copy()
    y[d:] += 0.45 * x[:-d]
    return reverb(soft(y, 1.6), 1.6, 0.35, 2500)


def voice_super():
    s = fric(0.16, 3800, 9000, 0.55)
    u = vowel(0.17, (300, 870, 2240), 112, 104)
    p = concat(np.zeros(int(SR * 0.05)), hp(noise(0.02), 500) * env(0.02, 0, 0.006) * 0.6)
    er = vowel(0.32, (490, 1350, 1690), 102, 82)
    return robot(concat(s, u, p, er))


def voice_hot():
    h = fric(0.08, 600, 3500, 0.25)
    o = vowel(0.36, (730, 1090, 2440), 108, 84)
    t_ = concat(np.zeros(int(SR * 0.04)), hp(noise(0.03), 2500) * env(0.03, 0, 0.008) * 0.7)
    return robot(concat(h, o, t_))


# ---------------------------------------------------------------------------
def gunshot(d, crack_tau, body_fc, body_tau, thump, thump_tau, tail_tau, room, weight=1.0):
    crack = hp(noise(d), 1500) * env(d, 0, crack_tau) * 1.1
    body = lp(noise(d), body_fc) * env(d, 0.001, body_tau)
    th = sweep(d, thump[0], thump[1], 16) * env(d, 0.001, thump_tau) * 1.3 * weight
    tail = lp(noise(d), 700) * env(d, 0.004, tail_tau) * 0.4
    return reverb(soft(mix(crack, body, th, tail), 2.4), room, 0.25)


def metal_click(freqs, d=0.12, tau=0.02, amp=1.0):
    t = T(d)
    x = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / (tau * (1 + i * 0.4))) for i, f in enumerate(freqs))
    return (x + hp(noise(d), 3000) * env(d, 0, 0.004) * 0.8) * amp


def at(x, offset, total):
    out = np.zeros(int(SR * total))
    i = int(SR * offset)
    n = min(len(x), len(out) - i)
    out[i:i + n] += x[:n]
    return out


def crystal(d=1.4, n=40, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros(int(SR * d))
    for _ in range(n):
        f = r.uniform(1800, 9000)
        st = r.uniform(0, 0.25)
        dd = r.uniform(0.05, 0.5)
        tt = T(dd)
        tone = np.sin(2 * np.pi * f * tt) * np.exp(-tt / (dd / 4)) * r.uniform(0.2, 1)
        out = mix(out, at(tone, st, d))
    burst = hp(noise(d), 2500) * env(d, 0, 0.05) * 1.2
    low = lp(noise(d), 400) * env(d, 0, 0.08) * 0.8
    return reverb(mix(out * 0.5, burst, low), 0.9, 0.3, 6000)


def main():
    write("pistol.wav", gunshot(0.9, 0.004, 2400, 0.06, (120, 45), 0.1, 0.4, 0.7))
    write("shotgun.wav", gunshot(1.3, 0.006, 1700, 0.1, (90, 35), 0.18, 0.6, 1.0, 1.6))
    write("uzi.wav", gunshot(0.5, 0.003, 3000, 0.035, (150, 60), 0.05, 0.2, 0.4, 0.8))
    write("empty.wav", metal_click((3100, 4700), 0.08, 0.008), 0.6)
    write("grab.wav", lp(noise(0.12), 1200) * env(0.12, 0.005, 0.03) + 0.3 * metal_click((900,), 0.12, 0.02), 0.5)
    write("throw.wav", bp(noise(0.35), 400, 2500) * np.sin(np.pi * T(0.35) / 0.35) ** 2, 0.6)
    write("swing.wav", bp(noise(0.4), 300, 2000) * np.sin(np.pi * T(0.4) / 0.4) ** 2, 0.6)
    write("drop.wav", metal_click((520, 1180, 1990), 0.35, 0.05), 0.6)
    write("thud.wav", mix(sweep(0.3, 160, 60, 20) * env(0.3, 0.002, 0.05) * 1.4, lp(noise(0.3), 1500) * env(0.3, 0, 0.03)))
    write("punch.wav", mix(sweep(0.3, 140, 50, 25) * env(0.3, 0.002, 0.06) * 1.4, lp(noise(0.3), 1500) * env(0.3, 0, 0.03)))
    sh = mix(sweep(0.6, 5200, 2600, 6) * env(0.6, 0.002, 0.25) * 0.5, bp(noise(0.6), 3000, 9000) * env(0.6, 0, 0.12))
    write("slash.wav", reverb(sh, 0.5, 0.2, 7000), 0.8)
    write("ping.wav", reverb(mix(np.sin(2 * np.pi * 3400 * T(0.4)) * env(0.4, 0, 0.09), hp(noise(0.4), 4000) * env(0.4, 0, 0.01)), 0.4, 0.2), 0.7)
    t = T(0.6)
    whz = bp(noise(0.6), 1500, 6000) * np.exp(-((t - 0.3) / 0.09) ** 2)
    write("whiz.wav", whz * (1 + 0.3 * np.sin(2 * np.pi * 40 * t)), 0.7)
    write("impact.wav", mix(lp(noise(0.25), 3000) * env(0.25, 0, 0.03), metal_click((2900, 4300), 0.25, 0.02, 0.5)), 0.6)
    write("shatter.wav", crystal(1.4, 50, 1))
    write("glass.wav", crystal(1.0, 30, 7), 0.8)
    d = 1.0
    t = T(d)
    sh2 = sum(np.sin(2 * np.pi * np.cumsum(f * (1 + 0.5 * t)) / SR) for f in (330, 495, 660, 990))
    write("spawn.wav", reverb(sh2 * env(d, 0.25, 0.35) * 0.4 + bp(noise(d), 3000, 9000) * env(d, 0.3, 0.2) * 0.25, 0.8, 0.3), 0.6)
    d = 2.2
    t = T(d)
    drone = sum(np.sin(2 * np.pi * f * (1 - 0.4 * t / d) * t) for f in (55, 82.4, 110))
    rev = lp(noise(d), 900) * np.clip(t / d, 0, 1) ** 3 * 0.8
    write("player_die.wav", reverb(mix(drone * env(d, 0.01, 0.9), rev, sweep(d, 300, 40, 2) * env(d, 0, 0.3)), 1.2, 0.35))
    write("super.wav", voice_super(), 0.95)
    write("hot.wav", voice_hot(), 0.95)
    notes = (523.3, 784, 1046.5)
    arp = mix(*[at(np.sin(2 * np.pi * f * T(0.6)) * env(0.6, 0.005, 0.2), i * 0.07, 1.0) for i, f in enumerate(notes)])
    write("level_start.wav", reverb(arp, 0.8, 0.3), 0.7)
    write("ui_click.wav", metal_click((2000, 3000), 0.08, 0.01), 0.6)
    write("ui_confirm.wav", mix(at(np.sin(2 * np.pi * 880 * T(0.12)) * env(0.12, 0.002, 0.04), 0, 0.3),
                                at(np.sin(2 * np.pi * 1320 * T(0.15)) * env(0.15, 0.002, 0.05), 0.08, 0.3)), 0.6)
    # ambiente: drone grave + pad lento (o tom acompanha o tempo do jogo)
    d = 24.0
    t = T(d)
    pad = np.zeros(len(t))
    for f, ph in ((55, 0), (82.4, 1.0), (110, 2.0), (164.8, 0.5), (220, 1.7)):
        pad += np.sin(2 * np.pi * f * t + ph) * (0.6 + 0.4 * np.sin(2 * np.pi * t / d * 2 + ph))
    air = lp(noise(d), 600) * 0.25
    amb = pad / 5 + air
    # emenda sem clique: crossfade circular
    n = int(SR * 1.0)
    amb[:n] = amb[:n] * np.linspace(0, 1, n) + amb[-n:] * np.linspace(1, 0, n)
    amb = amb[:-n]
    write("ambience.wav", reverb(amb, 2.0, 0.3, 1500)[:len(amb)], 0.55)
    print("sons em", OUT, len(os.listdir(OUT)))


if __name__ == "__main__":
    main()
