#!/usr/bin/env python3
"""Regenerate the bundled chimes in assets/.

Two short, distinct marimba-ish arpeggios so YouTube and Twitch alerts are
tellable apart without looking at the screen. Pure stdlib, no assets to vendor.
"""
import math
import os
import struct
import wave

RATE = 44100
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")


def tone(freq, seconds, attack=0.006, decay=0.35, gain=0.5):
    """One plucked note: sine plus a quiet octave, exponential decay."""
    frames = int(RATE * seconds)
    out = []
    for i in range(frames):
        t = i / RATE
        envelope = min(1.0, t / attack) * math.exp(-t / decay)
        sample = math.sin(2 * math.pi * freq * t)
        sample += 0.25 * math.sin(4 * math.pi * freq * t)
        out.append(gain * envelope * sample / 1.25)
    return out


def mix(notes, total_seconds):
    """Overlap notes at their given offsets so the arpeggio rings together."""
    buffer = [0.0] * int(RATE * total_seconds)
    for offset, freq, seconds, gain in notes:
        start = int(RATE * offset)
        for index, sample in enumerate(tone(freq, seconds, gain=gain)):
            position = start + index
            if position < len(buffer):
                buffer[position] += sample
    peak = max((abs(sample) for sample in buffer), default=1.0) or 1.0
    return [sample / peak * 0.85 for sample in buffer]


def write(name, samples):
    path = os.path.join(ASSETS, name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    return path


# YouTube: rising major third + fifth, "something new arrived".
YOUTUBE = [(0.00, 587.33, 0.9, 0.55), (0.09, 739.99, 0.9, 0.5), (0.18, 880.00, 1.1, 0.6)]
# Twitch: a brighter four-note flourish that lands high, "someone is live now".
TWITCH = [(0.00, 659.25, 0.7, 0.5), (0.07, 830.61, 0.7, 0.45),
          (0.14, 987.77, 0.8, 0.5), (0.22, 1318.51, 1.0, 0.6)]

if __name__ == "__main__":
    print(write("youtube.wav", mix(YOUTUBE, 1.4)))
    print(write("twitch.wav", mix(TWITCH, 1.4)))
