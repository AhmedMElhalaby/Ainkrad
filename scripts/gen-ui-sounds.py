#!/usr/bin/env python3
"""Synthesizes Ainkrad's UI sound effects (AIN-108) — original audio, no
samples or copyrighted material. Clean, glassy sci-fi tones in the spirit of
menu chimes from anime-style HUDs, built from a few detuned sine partials
(bell-like, slightly inharmonic) shaped by a soft linear attack and a fast
exponential decay. No numpy — just `wave`, `math`, and `struct` from the
stdlib, so this has zero dependencies beyond Python 3.

Run: python3 scripts/gen-ui-sounds.py
Writes 16-bit PCM mono WAVs into Sources/Ainkrad/Resources/Sounds/.
"""
import math
import os
import struct
import wave

SAMPLE_RATE = 44_100
OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Sources", "Ainkrad", "Resources", "Sounds",
)

# Peak target of ~-6 dBFS (0.5 linear) keeps every sound quiet and consistent
# in level so none of them jump out relative to the others.
PEAK_TARGET = 0.5


def _envelope(n: int, sr: int, attack_ms: float, decay_tau: float) -> list[float]:
    """Soft linear attack (avoids a click at t=0) then a fast exponential
    decay (avoids a click at the tail, and gives the "plink" character)."""
    attack_samples = max(1, int(sr * attack_ms / 1000))
    env = []
    for i in range(n):
        a = min(1.0, i / attack_samples)
        t = i / sr
        d = math.exp(-t / decay_tau)
        env.append(a * d)
    return env


def _tone(
    duration: float,
    freq_start: float,
    freq_end: float,
    partials: list[tuple[float, float]],
    decay_tau: float,
    attack_ms: float = 4.0,
    sr: int = SAMPLE_RATE,
) -> list[float]:
    """A short tone with an exponential pitch glide from `freq_start` to
    `freq_end` (exponential glide sounds like a natural pitch bend, unlike a
    linear Hz sweep). `partials` is a list of (frequency ratio, amplitude)
    pairs layered on the fundamental — a few slightly-detuned ratios (not
    exact harmonics) give the glassy/bell-like timbre instead of a flat buzz.
    """
    n = max(1, int(sr * duration))
    out = [0.0] * n
    ratio_total = sum(amp for _, amp in partials)
    for freq_ratio, amp in partials:
        phase = 0.0
        for i in range(n):
            frac = i / max(1, n - 1)
            f = freq_start * (freq_end / freq_start) ** frac
            phase += 2 * math.pi * f * freq_ratio / sr
            out[i] += (amp / ratio_total) * math.sin(phase)
    env = _envelope(n, sr, attack_ms=attack_ms, decay_tau=decay_tau)
    return [s * e for s, e in zip(out, env)]


def _concat(*chunks: list[float], gap: float = 0.0, sr: int = SAMPLE_RATE) -> list[float]:
    """Sequences tones back to back with an optional silent gap (seconds)."""
    gap_samples = int(sr * gap)
    out: list[float] = []
    for i, chunk in enumerate(chunks):
        out.extend(chunk)
        if i < len(chunks) - 1:
            out.extend([0.0] * gap_samples)
    return out


def _normalize(samples: list[float], target_peak: float = PEAK_TARGET) -> list[float]:
    peak = max((abs(s) for s in samples), default=0.0) or 1.0
    return [s / peak * target_peak for s in samples]


def _write_wav(name: str, samples: list[float], sr: int = SAMPLE_RATE) -> None:
    path = os.path.join(OUT_DIR, name)
    frames = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, s)) * 32767)
        frames += struct.pack("<h", v)
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes(bytes(frames))
    print(f"wrote {path} ({len(samples) / sr * 1000:.0f}ms)")


# A shared "glassy" partial stack: a slightly sharp octave and a detuned
# twelfth (not an exact 3rd harmonic) so tones ring rather than buzz.
GLASSY = [(1.0, 1.0), (2.02, 0.45), (3.01, 0.22)]
# A plainer, rounder stack (fewer/quieter upper partials) for "error" —
# gentler and less bright than the rest of the family.
SOFT = [(1.0, 1.0), (2.0, 0.18)]


def build() -> dict[str, list[float]]:
    sounds: dict[str, list[float]] = {}

    # open: upward glide, bright — summoning an overlay.
    sounds["open"] = _tone(
        duration=0.20, freq_start=523.25, freq_end=1046.50,
        partials=GLASSY, decay_tau=0.09, attack_ms=5,
    )

    # close: the mirror of open — downward glide, slightly shorter/softer
    # decay since dismissing should feel quicker/lighter than summoning.
    sounds["close"] = _tone(
        duration=0.18, freq_start=1046.50, freq_end=523.25,
        partials=GLASSY, decay_tau=0.07, attack_ms=4,
    )

    # confirm: a crisp upward fifth (E5 -> B5), shorter and brighter than
    # open — a distinct affirmative "ping" rather than a summon.
    sounds["confirm"] = _tone(
        duration=0.15, freq_start=659.25, freq_end=987.77,
        partials=GLASSY, decay_tau=0.06, attack_ms=3,
    )

    # install: a bright two-tone rising fifth (D5 -> A5) — two distinct
    # notes read as "added" more clearly than one continuous glide.
    sounds["install"] = _concat(
        _tone(duration=0.09, freq_start=587.33, freq_end=587.33,
              partials=GLASSY, decay_tau=0.05, attack_ms=3),
        _tone(duration=0.15, freq_start=880.00, freq_end=880.00,
              partials=GLASSY, decay_tau=0.08, attack_ms=3),
        gap=0.01,
    )

    # uninstall: the same two-tone shape, inverted (A5 -> D5, falling) —
    # cohesive with install but unmistakably "removed" rather than "added".
    sounds["uninstall"] = _concat(
        _tone(duration=0.09, freq_start=880.00, freq_end=880.00,
              partials=GLASSY, decay_tau=0.05, attack_ms=3),
        _tone(duration=0.16, freq_start=587.33, freq_end=587.33,
              partials=GLASSY, decay_tau=0.08, attack_ms=3),
        gap=0.01,
    )

    # toggle: a very short, quiet, low blip — a tiny downward nudge, not a
    # melodic event, so flipping a switch stays understated.
    sounds["toggle"] = _tone(
        duration=0.08, freq_start=360.0, freq_end=330.0,
        partials=SOFT, decay_tau=0.035, attack_ms=2,
    )

    # error: a gentle descending minor second (Bb4 -> Ab4) with the softer
    # partial stack and a slower decay — reads as "no"/"can't" without being
    # harsh or alarming.
    sounds["error"] = _tone(
        duration=0.26, freq_start=466.16, freq_end=415.30,
        partials=SOFT, decay_tau=0.14, attack_ms=6,
    )

    return sounds


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, samples in build().items():
        _write_wav(f"{name}.wav", _normalize(samples))


if __name__ == "__main__":
    main()
