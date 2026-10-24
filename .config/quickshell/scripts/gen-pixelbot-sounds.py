#!/usr/bin/env python3
"""Generate PixelBot's sine-only state sounds.

The definitions mirror the "Sine waves only" page: each state is built from
sine oscillators, with the same pitch, glide, envelope and vibrato values.
WAVs are mono 44.1 kHz/16-bit so paplay can launch them instantly.
"""

import math
import struct
import wave
from pathlib import Path

SR = 44100
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "pixelbot"

N = {
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "G4": 392.0,
    "A4": 440.0, "F4": 349.23, "C5": 523.25, "E5": 659.25,
    "G5": 783.99, "A5": 880.0, "C6": 1046.5,
}


def tone(freq, start=0.0, dur=0.2, vol=0.3, to=None, atk=0.01, vib=None):
    return {
        "freq": float(freq), "start": float(start), "dur": float(dur),
        "vol": float(vol), "to": to, "atk": float(atk), "vib": vib,
    }


def make_sound(events, length):
    frames = int(round(length * SR))
    buf = [0.0] * frames
    for ev in events:
        n0 = int(round(ev["start"] * SR))
        dur = ev["dur"]
        atk = min(ev["atk"], dur)
        count = min(frames - n0, int(round((dur + 0.015) * SR)))
        if count <= 0:
            continue
        phase = 0.0
        vibrato_phase = 0.0
        freq = ev["freq"]
        target = ev["to"]
        for j in range(count):
            t = j / SR
            if t <= dur:
                ft = t / dur
                base = freq * ((target / freq) ** ft) if target else freq
                if ev["vib"]:
                    vf, vg = ev["vib"]
                    base += vg * math.sin(2.0 * math.pi * vf * t)
                if t < atk:
                    gain = 1e-4 * ((ev["vol"] / 1e-4) ** (t / atk))
                else:
                    u = min(1.0, (t - atk) / max(1e-6, dur - atk))
                    gain = ev["vol"] * ((1e-4 / ev["vol"]) ** u)
                phase += 2.0 * math.pi * base / SR
                buf[n0 + j] += math.sin(phase) * gain
            else:
                # The oscillator stops just after the envelope reaches its tail.
                tail = max(0.0, 1.0 - (t - dur) / 0.015)
                buf[n0 + j] += math.sin(phase) * 1e-4 * tail
    peak = max(1e-9, max(abs(x) for x in buf))
    scale = min(1.0, 0.92 / peak)
    pcm = bytearray()
    for x in buf:
        x = max(-1.0, min(1.0, x * scale))
        pcm += struct.pack("<h", int(round(x * 32767)))
    return pcm


def save(name, events, length):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(make_sound(events, length))
    print(f"{path.relative_to(ROOT)}  {path.stat().st_size} bytes")


def main():
    sounds = {}

    sounds["idle"] = ([tone(660, 0, 0.09, 0.25, to=880)], 0.12)
    sounds["walk"] = ([
        tone(190 if i % 2 == 0 else 150, i * 0.14, 0.07, 0.5, to=70)
        for i in range(4)
    ], 0.62)
    dance = []
    arp = [N["C5"], N["E5"], N["G5"], N["E5"], N["C5"], N["E5"], N["G5"], N["C6"]]
    for i in range(16):
        dance.append(tone(arp[i % 8], i * 0.125, 0.10, 0.18))
        if i % 4 == 0:
            dance.append(tone(98 if i % 8 < 4 else 110, i * 0.125, 0.30, 0.5))
    sounds["dance"] = (dance, 2.12)
    sounds["happy"] = ([
        tone(n, i * 0.07, 0.14, 0.3)
        for i, n in enumerate([N["C5"], N["E5"], N["G5"], N["C6"]])
    ], 0.52)
    sounds["hello"] = ([
        tone(N["G5"], 0, 0.12, 0.3, to=N["A5"]),
        tone(N["C6"], 0.13, 0.20, 0.3),
    ], 0.42)
    sounds["alert"] = ([
        tone(988 if i % 2 == 0 else 784, i * 0.12, 0.10, 0.3)
        for i in range(4)
    ], 0.52)
    sounds["busy"] = ([
        tone(400 + i * 50, i * 0.07, 0.05, 0.2)
        for i in range(8)
    ], 0.62)
    sounds["recording"] = ([
        tone(1000, 0, 0.12, 0.25),
        tone(1000, 0.22, 0.12, 0.25),
    ], 0.42)
    sounds["lowbat"] = ([
        tone(N["E4"], 0, 0.3, 0.3, to=N["D4"], vib=(6, 4)),
        tone(N["C4"], 0.3, 0.3, 0.3, vib=(6, 4)),
        tone(220, 0.6, 0.5, 0.3, to=196, vib=(5, 5)),
    ], 1.12)
    sounds["charging"] = ([
        tone(300, 0, 0.35, 0.25, to=900),
        tone(1318, 0.38, 0.25, 0.25),
    ], 0.67)
    sounds["error"] = ([
        tone(150, 0, 0.4, 0.3),
        tone(158, 0, 0.4, 0.3),
        tone(220, 0.4, 0.35, 0.3, to=110),
    ], 0.82)
    sounds["muted"] = ([tone(130, 0, 0.12, 0.4, to=60)], 0.16)
    sounds["offline"] = ([
        *[
            tone(x, i * 0.11 + (i % 2) * 0.02, 0.07, 0.25)
            for i, x in enumerate([900, 740, 560, 380])
        ],
        tone(120, 0.55, 0.30, 0.3, to=70, vib=(18, 12)),
    ], 0.92)
    sounds["focus"] = ([
        tone(N["C4"], 0, 1.3, 0.2, atk=0.25),
        tone(N["E4"], 0, 1.3, 0.2, atk=0.25),
        tone(N["G4"], 0, 1.3, 0.2, atk=0.25),
        tone(N["C5"], 0.1, 1.2, 0.1, atk=0.3),
    ], 1.42)
    sounds["sleepy"] = ([
        tone(n, i * 0.55, 0.7, 0.14, atk=0.12, to=n * 0.97, vib=(4, 3))
        for i, n in enumerate([N["A4"], N["F4"], N["D4"]])
    ], 1.82)

    for name, (events, length) in sounds.items():
        save(name, events, length)

    # Legacy name used by the terminal bot for its music state.
    (OUT / "music.wav").write_bytes((OUT / "dance.wav").read_bytes())
    print(f"{(OUT / 'music.wav').relative_to(ROOT)}  {(OUT / 'music.wav').stat().st_size} bytes")


if __name__ == "__main__":
    main()
