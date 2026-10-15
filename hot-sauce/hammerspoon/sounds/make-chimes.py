"""Generate the Muesli dictation chimes: a rising fifth for start, falling for stop.

Each chime is two soft sine notes; the second enters while the first decays,
so the pair reads as one gesture moving up or down. Rerun after tweaking:
    python3 make-chimes.py
"""

import wave
from pathlib import Path

import numpy as np

RATE = 48_000
LOW, HIGH = 659.25, 987.77  # E5 → B5, a perfect fifth
NOTE_GAP = 0.09  # seconds between the two note onsets
LENGTH = 0.55
PEAK = 0.3  # well under full scale; volume is also set in Hammerspoon


def note(freq: float, start: float) -> np.ndarray:
    t = np.arange(int(RATE * LENGTH)) / RATE - start
    t = np.where(t < 0, 0, t)
    attack = np.clip(t / 0.012, 0, 1)  # 12 ms fade-in, no click
    decay = np.exp(-t / 0.14)
    tone = np.sin(2 * np.pi * freq * t) + 0.12 * np.sin(4 * np.pi * freq * t)
    return np.where(np.arange(len(t)) / RATE < start, 0, tone * attack * decay)


def write(path: Path, first: float, second: float) -> None:
    samples = note(first, 0) + 0.85 * note(second, NOTE_GAP)
    samples *= PEAK / np.abs(samples).max()
    fade = int(RATE * 0.02)  # make sure the tail ends at exact silence
    samples[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((samples * 32767).astype(np.int16).tobytes())


here = Path(__file__).parent
write(here / "dictation-start.wav", LOW, HIGH)
write(here / "dictation-stop.wav", HIGH, LOW)
