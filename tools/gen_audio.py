"""Procedural placeholder audio (SFX + two looping music beds)."""
from __future__ import annotations

import struct
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)

SR = 44100
MSR = 22050


def t(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def env(n, attack=0.005, decay=0.2, sr=SR):
    a = max(1, int(attack * sr))
    d = max(1, int(decay * sr))
    e = np.ones(n)
    if a < n:
        e[:a] = np.linspace(0, 1, a)
    if d < n:
        e[-d:] *= np.linspace(1, 0, d) ** 2
    return e


def fade(x, ms=6, sr=SR):
    n = int(ms / 1000 * sr)
    if n < 1 or len(x) < 2 * n:
        return x
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def lowpass(x, alpha):
    out = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        out[i] = acc
    return out


def norm(x, peak=0.7):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 1e-6 else x


def write(name, x, sr=SR):
    x = np.clip(x, -1, 1)
    pcm = (x * 32767).astype(np.int16)
    with wave.open(str(OUT / name), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes(pcm.tobytes())
    print("  ", name, f"{len(x)/sr:.2f}s")


# --------------------------------------------------------------------------- #
# SFX
# --------------------------------------------------------------------------- #
def step(seed):
    rng = np.random.default_rng(seed)
    n = int(0.10 * SR)
    tt = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (95 - 30 * tt) * tt) * np.exp(-tt * 55) * 0.5
    noise = rng.normal(0, 1, n) * np.exp(-tt * 90) * 0.18
    noise = lowpass(noise, 0.25)
    return fade(norm(thump + noise, 0.45), 4)


def push():
    n = int(0.22 * SR)
    tt = np.arange(n) / SR
    rng = np.random.default_rng(9)
    creak = np.sin(2 * np.pi * (170 + 90 * tt) * tt) * np.exp(-tt * 14) * 0.25
    grain = lowpass(rng.normal(0, 1, n), 0.12) * np.exp(-tt * 9) * 0.5
    thump = np.sin(2 * np.pi * 70 * tt) * np.exp(-tt * 22) * 0.45
    return fade(norm(creak + grain + thump, 0.5), 8)


def goal():
    n = int(0.55 * SR)
    tt = np.arange(n) / SR
    x = (np.sin(2 * np.pi * 880 * tt) * np.exp(-tt * 7) * 0.35
         + np.sin(2 * np.pi * 1320 * tt) * np.exp(-tt * 9) * 0.2
         + np.sin(2 * np.pi * 1760 * tt) * np.exp(-tt * 12) * 0.1)
    x += np.sin(2 * np.pi * 660 * tt) * np.exp(-tt * 4) * 0.12
    return fade(norm(x, 0.5), 10)


def ungoal():
    n = int(0.28 * SR)
    tt = np.arange(n) / SR
    x = np.sin(2 * np.pi * (190 - 60 * tt) * tt) * np.exp(-tt * 16) * 0.5
    return fade(norm(x, 0.42), 8)


def win():
    dur = 2.2
    n = int(dur * SR)
    tt = np.arange(n) / SR
    out = np.zeros(n)
    notes = [(523.25, 0.0), (659.25, 0.12), (783.99, 0.24), (1046.5, 0.36),
             (1318.5, 0.52), (1567.98, 0.68)]
    for f, delay in notes:
        s = int(delay * SR)
        m = n - s
        x = np.arange(m) / SR
        voice = (np.sin(2 * np.pi * f * x) * np.exp(-x * 2.2) * 0.4
                 + np.sin(2 * np.pi * f * 2 * x) * np.exp(-x * 3.5) * 0.12
                 + np.sin(2 * np.pi * f * 3 * x) * np.exp(-x * 5.5) * 0.05)
        out[s:] += voice
    # soft shimmer
    rng = np.random.default_rng(3)
    sh = lowpass(rng.normal(0, 1, n), 0.05) * np.exp(-tt * 1.2)
    out += sh * 0.03
    return fade(norm(out, 0.72), 20)


def click():
    n = int(0.06 * SR)
    tt = np.arange(n) / SR
    x = (np.sin(2 * np.pi * 1200 * tt) * np.exp(-tt * 80) * 0.35
         + np.sin(2 * np.pi * 2400 * tt) * np.exp(-tt * 120) * 0.1)
    return fade(norm(x, 0.3), 3)


def undo():
    n = int(0.16 * SR)
    tt = np.arange(n) / SR
    f = 660 - 220 * (tt / tt[-1])
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 18) * 0.4
    return fade(norm(x, 0.32), 5)


def error():
    n = int(0.16 * SR)
    tt = np.arange(n) / SR
    x = (np.sign(np.sin(2 * np.pi * 110 * tt)) * np.exp(-tt * 14) * 0.12
         + np.sin(2 * np.pi * 82 * tt) * np.exp(-tt * 10) * 0.35)
    x = lowpass(x, 0.4)
    return fade(norm(x, 0.36), 6)


def locked():
    n = int(0.30 * SR)
    tt = np.arange(n) / SR
    a = np.sin(2 * np.pi * 220 * tt) * np.exp(-tt * 16) * 0.3
    b = np.zeros(n)
    s = int(0.12 * SR)
    b[s:] = np.sin(2 * np.pi * 165 * np.arange(n - s) / SR) * np.exp(-np.arange(n - s) / SR * 14) * 0.3
    return fade(norm(a + b, 0.38), 8)


def hint():
    n = int(0.4 * SR)
    tt = np.arange(n) / SR
    x = (np.sin(2 * np.pi * 1046 * tt) * np.exp(-tt * 8) * 0.2
         + np.sin(2 * np.pi * 1568 * tt) * np.exp(-tt * 11) * 0.12)
    return fade(norm(x, 0.3), 10)


def start():
    n = int(0.7 * SR)
    tt = np.arange(n) / SR
    rng = np.random.default_rng(21)
    whoosh = lowpass(rng.normal(0, 1, n), 0.02) * np.sin(np.pi * np.clip(tt / 0.5, 0, 1)) * 0.25
    chime = np.sin(2 * np.pi * 784 * tt) * np.exp(-tt * 4) * 0.12
    return fade(norm(whoosh + chime, 0.36), 15)


def boom():
    n = int(0.55 * SR)
    tt = np.arange(n) / SR
    rng = np.random.default_rng(77)
    body = lowpass(rng.normal(0, 1, n), 0.06) * np.exp(-tt * 9)
    thump = np.sin(2 * np.pi * 62 * np.exp(-tt * 3) * tt) * np.exp(-tt * 12) * 0.7
    crack = rng.normal(0, 1, n) * np.exp(-tt * 60) * 0.3
    return fade(norm(body * 0.8 + thump + crack, 0.62), 8)


# --------------------------------------------------------------------------- #
# Music
# --------------------------------------------------------------------------- #
def note(buf, freq, start, dur, amp=0.2, kind="pad", sr=MSR):
    """Add a note with wrap-around so the loop stays seamless."""
    n = int(dur * sr)
    if n <= 0:
        return
    x = np.arange(n) / sr
    if kind == "pad":
        att = np.clip(x / (dur * 0.35), 0, 1) ** 1.6
        rel = np.clip((dur - x) / (dur * 0.45), 0, 1) ** 1.4
        e = att * rel
        wave_ = (np.sin(2 * np.pi * freq * x)
                 + 0.22 * np.sin(2 * np.pi * freq * 1.003 * x + 0.5)
                 + 0.14 * np.sin(2 * np.pi * freq * 0.997 * x - 0.4)
                 + 0.10 * np.sin(2 * np.pi * freq * 2 * x)
                 + 0.04 * np.sin(2 * np.pi * freq * 3.01 * x))
        voice = wave_ * e * amp
    elif kind == "pluck":
        e = np.exp(-x * 4.2) * np.minimum(1, x / 0.004)
        voice = (np.sin(2 * np.pi * freq * x) * e
                 + 0.28 * np.sin(2 * np.pi * freq * 2.001 * x) * np.exp(-x * 6)
                 + 0.08 * np.sin(2 * np.pi * freq * 3.99 * x) * np.exp(-x * 9)) * amp
    else:  # bass
        e = np.clip(x / 0.02, 0, 1) * np.exp(-x * 1.2)
        voice = (np.sin(2 * np.pi * freq * x) + 0.15 * np.sin(2 * np.pi * freq * 2 * x)) * e * amp
    idx = (np.arange(n) + int(start * sr)) % len(buf)
    np.add.at(buf, idx, voice)


def music(path, bpm, bars, chord_sets, melody, arp_step):
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * bars
    n = int(total * MSR)
    buf = np.zeros(n)
    for b, chords in enumerate(chord_sets):
        if b >= bars:
            break
        start = b * bar
        for i, freq in enumerate(chords):
            note(buf, freq, start + i * 0.02, bar * 1.02, amp=0.055, kind="pad")
        note(buf, chords[0] / 2, start, bar * 0.9, amp=0.09, kind="bass")
    # arpeggio
    tcur = 0.0
    k = 0
    while tcur < total - 0.1:
        chord = chord_sets[int(tcur // bar) % len(chord_sets)]
        f = chord[melody[k % len(melody)] % len(chord)] * (
            2 if melody[k % len(melody)] >= len(chord) else 1)
        note(buf, f, tcur, 1.1, amp=0.085, kind="pluck")
        tcur += arp_step
        k += 1
    # gentle air
    rng = np.random.default_rng(4)
    air = lowpass(rng.normal(0, 1, n), 0.008) * 0.05
    buf += air
    # simple reverb (circular delay network) keeps loop seamless
    wet = np.copy(buf)
    for delay_ms, gain in ((97, 0.25), (173, 0.18), (311, 0.1)):
        d = int(delay_ms / 1000 * MSR)
        wet += np.roll(buf, d) * gain
    buf = buf * 0.75 + wet * 0.35
    buf = norm(buf, 0.34)
    fade(buf, 30, MSR)
    write(path, buf, MSR)


def main():
    print("sfx")
    for i in range(4):
        write(f"step_{i}.wav", step(10 + i))
    write("push.wav", push())
    write("goal.wav", goal())
    write("ungoal.wav", ungoal())
    write("win.wav", win())
    write("click.wav", click())
    write("undo.wav", undo())
    write("error.wav", error())
    write("locked.wav", locked())
    write("hint.wav", hint())
    write("start.wav", start())
    write("boom.wav", boom())

    C, D, E, F, G, A, B = (261.63, 293.66, 329.63, 349.23, 392.0, 440.0, 493.88)
    print("music")
    music("music_menu.wav", 62, 8,
          [[C * 2, E * 2, G * 2, B * 2, D * 3],
           [A * 2, C * 3, E * 3, G * 3, B * 3],
           [F * 2, A * 2, C * 3, E * 3, G * 3],
           [G * 2, B * 2, D * 3, F * 3, A * 3],
           [C * 2, E * 2, G * 2, B * 2, D * 3],
           [A * 2, C * 3, E * 3, G * 3, B * 3],
           [D * 2, F * 2, A * 2, C * 3, E * 3],
           [G * 2, B * 2, D * 3, F * 3, A * 3]],
          [0, 2, 4, 3, 1, 3, 4, 2], arp_step=0.75)
    music("music_game.wav", 76, 8,
          [[D * 2, F * 2, A * 2, C * 3, E * 3],
           [B * 1.5, D * 2, F * 2, A * 2, C * 3],
           [G * 1.5, B * 2, D * 3, F * 3, A * 3],
           [A * 1.5, C * 3, E * 3, G * 3, B * 3],
           [D * 2, F * 2, A * 2, C * 3, E * 3],
           [B * 1.5, D * 2, F * 2, A * 2, C * 3],
           [G * 1.5, B * 2, D * 3, F * 3, A * 3],
           [A * 1.5, C * 3, E * 3, G * 3, B * 3]],
          [0, 1, 2, 4, 2, 3, 1, 2], arp_step=0.5)


if __name__ == "__main__":
    main()
