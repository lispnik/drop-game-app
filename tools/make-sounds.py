#!/usr/bin/env python3
"""make-sounds.py -- write res/sounds/*.wav, synthesised with the standard
library alone: 16-bit mono at 44.1kHz.

    python3 tools/make-sounds.py

tap    a disc is dropped: a short soft knock
plop   discs clear: a falling bubble
won    a rise or a board clear: a bell arpeggio
lost   the game ends: two falling notes
"""
import math, os, struct, wave

RATE = 44100

def tone(freq, seconds, volume=0.5, decay=8.0, glide=None, harmonics=((1, 1.0),)):
    out = []
    phase = 0.0
    n = int(seconds * RATE)
    for i in range(n):
        t = i / RATE
        f = freq if glide is None else freq + (glide - freq) * (i / n)
        phase += 2 * math.pi * f / RATE
        envelope = math.exp(-decay * t) * min(1.0, i / 40)
        out.append(volume * envelope * sum(a * math.sin(k * phase) for k, a in harmonics))
    return out

def mix(*parts):
    length = max(int(offset * RATE) + len(samples) for offset, samples in parts)
    out = [0.0] * length
    for offset, samples in parts:
        start = int(offset * RATE)
        for i, v in enumerate(samples):
            out[start + i] += v
    return out

BELL = ((1, 1.0), (2, 0.35), (3, 0.12))

SOUNDS = {
    "tap": tone(180, 0.07, 0.6, decay=60, glide=110, harmonics=((1, 1.0), (2, 0.2))),
    "plop": tone(520, 0.09, 0.22, decay=30, glide=240),
    "won": mix(*[(0.11 * k, tone(f, 0.9, 0.28, decay=5, harmonics=BELL))
                 for k, f in enumerate((523.25, 659.25, 783.99, 1046.5))]),
    "lost": mix((0, tone(392, 0.3, 0.3, decay=7, harmonics=((1, 1.0), (2, 0.25)))),
                (0.22, tone(311.13, 0.55, 0.3, decay=5, harmonics=((1, 1.0), (2, 0.25))))),
}

here = os.path.dirname(os.path.abspath(__file__))
folder = os.path.normpath(os.path.join(here, "..", "res", "sounds"))
os.makedirs(folder, exist_ok=True)
for name, samples in SOUNDS.items():
    peak = max(1.0, max(abs(v) for v in samples))
    with wave.open(os.path.join(folder, name + ".wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(32767 * v / peak)) for v in samples))
    print("wrote", os.path.join(folder, name + ".wav"))
