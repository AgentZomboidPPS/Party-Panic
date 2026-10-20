"""Composes and renders Party Panic's original music and sound effects.

    python3 tools/music/compose.py            # renders everything into assets/audio
    python3 tools/music/compose.py --preview  # also writes MP3 previews

Tracks loop seamlessly: reverb and delay tails from the end of each loop wrap around to its start.
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import synth as s  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio"


# ====================================================================== helpers

class Song:
    def __init__(self, bpm: float, bars: int):
        self.bpm = bpm
        self.beat = 60 / bpm
        self.bar = self.beat * 4
        self.step = self.beat / 4  # 16th note
        self.bars = bars
        self.length = self.bar * bars
        self.kicks: list[float] = []

    def t(self, bar: int, step: float = 0) -> float:
        """Time of 16th-note `step` in (0-based) `bar`."""
        return bar * self.bar + step * self.step

    def stem(self) -> s.Timeline:
        # Every stem wraps, so notes ringing past the loop point continue at the start.
        return s.Timeline(self.length, wrap=True)


def melody_events(phrase, bar_offset: int, transpose: int = 0):
    for bar, notes in enumerate(phrase):
        for step, midi, length in notes:
            yield bar + bar_offset, step, midi + transpose, length


# ====================================================================== lobby: "Party Plaza"

PLAZA_PROG_A = [  # Fmaj7, C/E, Dm7, Bb(add9), Fmaj7, C, Bb, C
    (["F4", "A4", "C5", "E5"], "F2"), (["E4", "G4", "C5", "D5"], "E2"), (["D4", "F4", "A4", "C5"], "D2"),
    (["D4", "F4", "Bb4", "C5"], "Bb1"), (["F4", "A4", "C5", "E5"], "F2"), (["E4", "G4", "C5", "D5"], "C2"),
    (["D4", "F4", "Bb4", "C5"], "Bb1"), (["E4", "G4", "C5", "D5"], "C2"),
]
PLAZA_PROG_B = [  # Bridge: Bb, C, Am, Dm, Gm, C, F, C
    (["D4", "F4", "Bb4", "D5"], "Bb1"), (["E4", "G4", "C5", "E5"], "C2"), (["E4", "A4", "C5", "E5"], "A1"),
    (["D4", "F4", "A4", "D5"], "D2"), (["D4", "G4", "Bb4", "D5"], "G1"), (["E4", "G4", "C5", "E5"], "C2"),
    (["F4", "A4", "C5", "F5"], "F2"), (["E4", "G4", "C5", "E5"], "C2"),
]
PLAZA_HOOK = [
    [(0, 84, 2), (3, 81, 1), (4, 84, 2), (7, 86, 1), (8, 84, 2), (10, 81, 2), (12, 77, 4)],
    [(0, 79, 2), (3, 76, 1), (4, 79, 2), (7, 81, 1), (8, 79, 3), (12, 76, 2), (14, 74, 2)],
    [(0, 77, 2), (3, 74, 1), (4, 77, 2), (7, 81, 1), (8, 84, 2), (10, 81, 2), (12, 77, 2), (14, 81, 2)],
    [(0, 79, 3), (4, 77, 2), (6, 74, 2), (8, 77, 4), (12, 79, 2), (14, 81, 2)],
    [(0, 84, 2), (3, 81, 1), (4, 84, 2), (7, 86, 1), (8, 84, 2), (10, 81, 2), (12, 77, 4)],
    [(0, 79, 2), (3, 76, 1), (4, 79, 2), (7, 81, 1), (8, 84, 4), (12, 86, 2), (14, 88, 2)],
    [(0, 89, 3), (4, 86, 2), (6, 84, 2), (8, 81, 2), (10, 79, 2), (12, 77, 2), (14, 79, 2)],
    [(0, 81, 2), (2, 79, 2), (4, 76, 2), (6, 79, 2), (8, 84, 6)],
]
PLAZA_BRIDGE = [
    [(0, 74, 4), (4, 77, 2), (6, 82, 2), (8, 81, 4), (12, 77, 4)],
    [(0, 76, 4), (4, 79, 2), (6, 84, 2), (8, 82, 4), (12, 79, 4)],
    [(0, 76, 2), (2, 81, 2), (4, 84, 4), (8, 81, 4), (12, 76, 4)],
    [(0, 77, 2), (2, 81, 2), (4, 86, 4), (8, 84, 2), (10, 81, 2), (12, 77, 4)],
    [(0, 79, 4), (4, 82, 2), (6, 86, 2), (8, 84, 4), (12, 82, 4)],
    [(0, 84, 4), (4, 88, 2), (6, 86, 2), (8, 84, 2), (10, 82, 2), (12, 79, 4)],
    [(0, 81, 4), (4, 84, 2), (6, 89, 2), (8, 88, 4), (12, 84, 4)],
    [(0, 86, 2), (2, 84, 2), (4, 82, 2), (6, 79, 2), (8, 76, 4), (12, 79, 4)],
]

# Section plan: (name, progression, transpose, features). 8 bars each, 64 bars (~2:08) in total.
PLAZA_SECTIONS = [
    ("groove", "A", 0, {"kick", "stabs", "bass"}),
    ("hook", "A", 0, {"kick", "stabs", "bass", "shaker", "pad", "marimba"}),
    ("sparkle", "A", 0, {"kick", "stabs", "bass", "shaker", "pad", "bells", "arp"}),
    ("bridge", "B", 0, {"kick", "bass", "shaker", "pad", "skank", "counter"}),
    ("breakdown", "A", 0, {"pad", "fragment", "build"}),
    ("lift", "A", 2, {"kick", "stabs", "bass", "shaker", "pad", "lead", "marimba"}),
    ("chorus", "A", 2, {"kick", "stabs", "bass", "shaker", "pad", "lead", "bells", "arp", "harmony"}),
    ("return", "A", 0, {"kick", "stabs", "bass", "shaker", "fill"}),
]


def party_plaza() -> np.ndarray:
    song = Song(bpm=120, bars=8 * len(PLAZA_SECTIONS))
    progs = {"A": PLAZA_PROG_A, "B": PLAZA_PROG_B}
    drums, bass_stem, stabs, pad, melody, sparkle, fx = (song.stem() for _ in range(7))
    kick_snd, clap_snd, hat_open, shake = s.kick(), s.clap(), s.hat(True), s.shaker()

    for index, (name, prog_key, transpose, feats) in enumerate(PLAZA_SECTIONS):
        first = index * 8
        if index == 0 or name in ("lift", "chorus", "bridge"):
            drums.add(song.t(first), s.crash(), 0.35, -0.2)
        for local in range(8):
            bar = first + local
            notes, root_name = progs[prog_key][local]
            chord = [s.note(x) + transpose for x in notes]
            root = s.note(root_name) + transpose
            for beat in range(4):
                kicking = "kick" in feats or ("build" in feats and local >= 6)
                half_time = "build" in feats and local in (4, 5) and beat in (0, 2)
                if kicking or half_time:
                    song.kicks.append(song.t(bar, beat * 4))
                    drums.add(song.t(bar, beat * 4), kick_snd, 0.95)
                if beat in (1, 3):
                    drums.add(song.t(bar, beat * 4), clap_snd, 0.55 if kicking else 0.38, 0.05)
                if kicking:
                    drums.add(song.t(bar, beat * 4 + 2), hat_open, 0.22, 0.25)
            if "shaker" in feats:
                for step in range(16):
                    swing = 0.12 if step % 2 else 0.0
                    drums.add(song.t(bar, step + swing), shake, 0.12 + (0.06 if step % 4 == 2 else 0), -0.3)
            if "build" in feats and local >= 4:
                rate = 2 if local < 6 else (1 if local == 6 else 0.5)
                step = 0.0
                while step < 16:
                    drums.add(song.t(bar, step), s.snare(0.15), 0.15 + 0.35 * ((local - 4) * 16 + step) / 64, 0.1)
                    step += rate
            if "fill" in feats and local == 7:
                for step in range(8, 16):
                    drums.add(song.t(bar, step), s.snare(0.15), 0.18 + 0.03 * (step - 8), 0.1)

            if "bass" in feats:
                for step, offset, length in ((0, 0, 2), (3, 12, 1), (6, 0, 2), (8, 0, 2), (11, 12, 1), (12, 7, 2), (14, 12, 1)):
                    bass_stem.add(song.t(bar, step), s.bass(root + offset, length * song.step * 0.9, cutoff=750), 0.55)
            if "stabs" in feats:
                cutoff = 2400 + min(index, 6) * 500
                if name == "return":
                    cutoff = 4200 - local * 300  # closes before the loop restarts
                for step in (2, 6, 10, 14):
                    stab = s.supersaw(chord, 0.16, cutoff=cutoff, voices=5, detune=0.12, attack=0.003, release=0.12, sustain=0.6, decay=0.08)
                    stabs.add(song.t(bar, step), stab, 0.42)
            if "skank" in feats:
                for step in (2, 6, 10, 14):
                    stabs.add(song.t(bar, step), s.supersaw(chord, 0.1, cutoff=1800, voices=3, detune=0.08, attack=0.002, release=0.08, sustain=0.5, decay=0.05), 0.4)
            if "pad" in feats:
                pad_gain = 0.3 if "build" in feats else 0.18  # the pad carries the breakdown
                pad.add(song.t(bar), s.supersaw([m - 12 for m in chord], song.bar, cutoff=1400, voices=5, detune=0.2, attack=0.3, release=0.6, sustain=0.9), pad_gain)
            if "arp" in feats:
                for step in range(16):
                    midi = chord[step % 4] + 12 + (12 if step % 8 >= 4 else 0)
                    sparkle.add(song.t(bar, step), s.fm_bell(midi, 0.12, ratio=4, index=1.2, decay=0.35), 0.1, 0.4 if step % 2 else -0.4)

        hook_events = list(melody_events(PLAZA_HOOK, first, transpose))
        if "marimba" in feats:
            for bar, step, midi, length in hook_events:
                melody.add(song.t(bar, step), s.fm_bell(midi, length * song.step, ratio=4.0, index=2.6, decay=0.5), 0.5)
        if "bells" in feats:
            for bar, step, midi, length in hook_events:
                melody.add(song.t(bar, step), s.fm_bell(midi, length * song.step, ratio=3.5, index=1.8, decay=1.1), 0.36)
        if "lead" in feats:
            for bar, step, midi, length in hook_events:
                melody.add(song.t(bar, step), s.lead(midi - 12, length * song.step * 0.95, cutoff=3800, vibrato=0.1), 0.2)
        if "harmony" in feats:
            for bar, step, midi, length in hook_events:
                melody.add(song.t(bar, step), s.lead(midi - 16, length * song.step * 0.95, cutoff=3000, vibrato=0.08), 0.12)
        if "counter" in feats:
            for bar, step, midi, length in melody_events(PLAZA_BRIDGE, first):
                melody.add(song.t(bar, step), s.fm_bell(midi - 12, length * song.step, ratio=4.0, index=2.2, decay=0.6), 0.5)
        if "fragment" in feats:
            for bar, step, midi, length in melody_events(PLAZA_HOOK[:6], first):
                melody.add(song.t(bar, step), s.fm_bell(midi - 12, length * song.step, ratio=4.0, index=2.0, decay=0.8), 0.45)
        if "build" in feats:
            fx.add(song.t(first + 4), s.riser(song.bar * 4), 0.3)
        if name == "return":
            fx.add(song.t(first + 6), s.riser(song.bar * 2), 0.22)
        if name in ("groove", "lift"):
            fx.add(song.t(first), s.impact(), 0.35)

    gain = s.sidechain(drums.length, song.kicks, depth=0.55, release=0.2)
    mix = s.Timeline(song.length)
    mix.mix(drums)
    mix.buffer += bass_stem.buffer * gain
    mix.buffer += s.ping_pong(stabs.buffer, song.beat * 0.75, 0.35, 0.18, wrap=True) * gain
    mix.buffer += pad.buffer * gain
    mix.buffer += s.ping_pong(melody.buffer, song.beat * 0.75, 0.4, 0.22, wrap=True)
    mix.buffer += sparkle.buffer
    mix.mix(fx)
    wet = s.reverb(mix.buffer, decay=1.8, mix=0.18, wrap=True)
    return s.master(wet, target_rms_db=-14.5)


# ====================================================================== lobby 2: "Sunset Social"

def conga(pitch: float = 220.0) -> np.ndarray:
    n = s.samples(0.25)
    t = np.arange(n) / s.SR
    tone = s.sine(pitch * (1 + 0.5 * np.exp(-t / 0.01)), n) * s.exp_decay(n, 0.07)
    slap = s.bandpass(s.noise(n), 1500, 5000) * s.exp_decay(n, 0.006) * 0.4
    return tone + slap


def rim() -> np.ndarray:
    n = s.samples(0.1)
    return s.bandpass(s.noise(n) * 0.4 + s.square(np.full(n, 1700.0), n, 0.5) * 0.6, 1200, 6000) * s.exp_decay(n, 0.015)


def steel_pan(midi: float, duration: float) -> np.ndarray:
    """Bright, rounded FM tone with a short bloom - a steel-drum flavor."""
    body = s.fm_bell(midi, duration, ratio=2.0, index=1.6, decay=0.75)
    shimmer = s.fm_bell(midi + 12.03, duration, ratio=3.0, index=0.6, decay=0.4) * 0.25
    body[: len(shimmer)] += shimmer
    return body


def whistle(midi: float, duration: float) -> np.ndarray:
    n = s.samples(duration + 0.12)
    t = np.arange(n) / s.SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.15) / 0.2, 0, 1)
    tone = s.sine(s.midi_hz(midi) * vib, n) + 0.12 * s.sine(s.midi_hz(midi + 12) * vib, n)
    breath = s.bandpass(s.noise(n), 2000, 6000) * 0.05
    return (tone + breath) * s.adsr(n, 0.05, 0.1, 0.85, 0.12, gate=duration)


SUNSET_PROG = [  # Am, F, C, G (twice)
    (["A3", "C4", "E4", "A4"], "A1"), (["F3", "A3", "C4", "F4"], "F1"), (["G3", "C4", "E4", "G4"], "C2"), (["G3", "B3", "D4", "G4"], "G1"),
] * 2
SUNSET_MELODY = [
    [(0, 76, 3), (3, 79, 1), (4, 81, 2), (6, 79, 2), (8, 76, 4), (12, 72, 2), (14, 74, 2)],
    [(0, 77, 3), (3, 76, 1), (4, 72, 2), (6, 69, 2), (8, 72, 6), (14, 74, 2)],
    [(0, 76, 3), (3, 79, 1), (4, 84, 2), (6, 81, 2), (8, 79, 4), (12, 76, 2), (14, 79, 2)],
    [(0, 79, 4), (4, 74, 2), (6, 71, 2), (8, 74, 6), (14, 71, 2)],
    [(0, 76, 3), (3, 79, 1), (4, 81, 2), (6, 79, 2), (8, 76, 4), (12, 72, 2), (14, 74, 2)],
    [(0, 77, 2), (2, 81, 2), (4, 84, 2), (6, 81, 2), (8, 77, 4), (12, 76, 2), (14, 74, 2)],
    [(0, 76, 3), (3, 72, 1), (4, 76, 2), (6, 79, 2), (8, 84, 4), (12, 83, 2), (14, 81, 2)],
    [(0, 79, 6), (6, 74, 2), (8, 71, 4), (12, 74, 4)],
]
SUNSET_SECTIONS = [
    ("intro", {"kick", "rim", "shaker", "bass", "plucks"}),
    ("theme", {"kick", "rim", "shaker", "bass", "plucks", "pan", "pad"}),
    ("lift", {"kick", "rim", "shaker", "bass", "plucks", "pan", "whistle", "congas", "pad"}),
    ("chill", {"pad", "pan_sparse", "rim", "plucks"}),
    ("chorus", {"kick", "rim", "shaker", "bass", "plucks", "pan", "whistle", "congas", "pad", "harmony"}),
    ("outro", {"kick", "rim", "shaker", "bass", "plucks", "congas", "riser"}),
]


def sunset_social() -> np.ndarray:
    song = Song(bpm=104, bars=8 * len(SUNSET_SECTIONS))
    drums, bass_stem, plucks, pad, melody, fx = (song.stem() for _ in range(6))
    soft_kick, rim_snd, shake = s.kick(0.8, 0.4), rim(), s.shaker()

    for index, (name, feats) in enumerate(SUNSET_SECTIONS):
        first = index * 8
        for local in range(8):
            bar = first + local
            notes, root_name = SUNSET_PROG[local]
            chord = [s.note(x) for x in notes]
            root = s.note(root_name)
            for beat in range(4):
                if "kick" in feats:
                    song.kicks.append(song.t(bar, beat * 4))
                    drums.add(song.t(bar, beat * 4), soft_kick, 0.8)
                if "rim" in feats and beat in (1, 3):
                    drums.add(song.t(bar, beat * 4), rim_snd, 0.35, 0.2)
            if "shaker" in feats:
                for step in range(16):
                    drums.add(song.t(bar, step + (0.15 if step % 2 else 0)), shake, 0.1 + (0.05 if step % 4 == 2 else 0), 0.35)
            if "congas" in feats:
                for step, pitch, gain in ((3, 260.0, 0.3), (6, 200.0, 0.35), (10, 260.0, 0.25), (11, 200.0, 0.3), (14, 330.0, 0.25)):
                    drums.add(song.t(bar, step), conga(pitch), gain, -0.4)
            if "bass" in feats:
                for step, offset, length in ((0, 0, 3), (3, 0, 1), (6, 12, 2), (10, 0, 2), (12, 7, 2), (14, 10 if local % 4 == 0 else 12, 2)):
                    bass_stem.add(song.t(bar, step), s.bass(root + offset, length * song.step * 0.85, cutoff=520, sub=0.9), 0.55)
            if "plucks" in feats:
                for step in (2, 5, 8, 10, 13):
                    for i, midi in enumerate(chord[1:]):
                        plucks.add(song.t(bar, step + i * 0.08), s.fm_bell(midi + 12, 0.18, ratio=4.0, index=1.4, decay=0.35), 0.13, -0.3 + i * 0.3)
            if "pad" in feats:
                pad.add(song.t(bar), s.supersaw(chord, song.bar, cutoff=1100, voices=5, detune=0.15, attack=0.5, release=0.8, sustain=0.9), 0.16)

        events = list(melody_events(SUNSET_MELODY, first))
        if "pan" in feats:
            for bar, step, midi, length in events:
                melody.add(song.t(bar, step), steel_pan(midi, length * song.step), 0.5)
        if "pan_sparse" in feats:
            for bar, step, midi, length in events:
                if step % 4 == 0:
                    melody.add(song.t(bar, step), steel_pan(midi, length * song.step), 0.4)
        if "whistle" in feats:
            for bar, step, midi, length in events:
                melody.add(song.t(bar, step), whistle(midi + 12, length * song.step * 0.9), 0.16, 0.25)
        if "harmony" in feats:
            for bar, step, midi, length in events:
                melody.add(song.t(bar, step), steel_pan(midi - 3, length * song.step), 0.25, -0.35)
        if "riser" in feats:
            fx.add(song.t(first + 6), s.riser(song.bar * 2), 0.18)

    gain = s.sidechain(drums.length, song.kicks, depth=0.35, release=0.25)
    mix = s.Timeline(song.length)
    mix.mix(drums)
    mix.buffer += bass_stem.buffer * gain
    mix.buffer += s.ping_pong(plucks.buffer, song.beat * 0.75, 0.4, 0.2, wrap=True) * gain
    mix.buffer += pad.buffer * gain
    mix.buffer += s.ping_pong(melody.buffer, song.beat * 0.75, 0.38, 0.2, wrap=True)
    mix.mix(fx)
    wet = s.reverb(mix.buffer, decay=2.2, mix=0.22, wrap=True)
    return s.master(wet, target_rms_db=-15.5)


# ====================================================================== rounds: "Panic Mode"

def panic_mode() -> np.ndarray:
    song = Song(bpm=140, bars=32)
    n = s.note
    chords = [
        [n("D4"), n("F4"), n("A4")],  # Dm
        [n("D4"), n("F4"), n("Bb4")],  # Bb
        [n("C4"), n("F4"), n("A4")],  # F
        [n("C4"), n("E4"), n("G4")],  # C
        [n("D4"), n("F4"), n("A4")],
        [n("D4"), n("F4"), n("Bb4")],
        [n("D4"), n("G4"), n("Bb4")],  # Gm
        [n("C#4"), n("E4"), n("A4")],  # A
    ]
    roots = [n("D2"), n("Bb1"), n("F2"), n("C2"), n("D2"), n("Bb1"), n("G1"), n("A1")]
    hook = [
        [(0, 81, 2), (2, 81, 2), (4, 86, 2), (6, 84, 2), (8, 81, 3), (11, 79, 1), (12, 77, 2), (14, 79, 2)],
        [(0, 77, 2), (2, 77, 2), (4, 82, 2), (6, 81, 2), (8, 77, 3), (11, 74, 1), (12, 77, 2), (14, 79, 2)],
        [(0, 81, 2), (2, 81, 2), (4, 84, 2), (6, 81, 2), (8, 77, 3), (11, 81, 1), (12, 84, 2), (14, 86, 2)],
        [(0, 88, 4), (4, 86, 2), (6, 84, 2), (8, 79, 4), (12, 76, 2), (14, 79, 2)],
        [(0, 81, 2), (2, 81, 2), (4, 86, 2), (6, 84, 2), (8, 81, 3), (11, 79, 1), (12, 77, 2), (14, 79, 2)],
        [(0, 77, 2), (2, 79, 2), (4, 82, 2), (6, 84, 2), (8, 86, 4), (12, 84, 2), (14, 82, 2)],
        [(0, 82, 2), (2, 81, 2), (4, 79, 2), (6, 82, 2), (8, 86, 4), (12, 91, 2), (14, 89, 2)],
        [(0, 88, 4), (4, 85, 4), (8, 81, 4), (12, 76, 2), (14, 73, 2)],
    ]

    drums, bass_stem, chords_stem, arp, lead_stem, fx = (song.stem() for _ in range(6))
    kick_snd, clap_snd, hat_closed, hat_open = s.kick(1.2, 0.4), s.clap(), s.hat(False), s.hat(True)
    snare_snd = s.snare()

    for bar in range(song.bars):
        section = bar // 8
        breakdown = section == 2 and bar < 20
        build = section == 2 and bar >= 20
        chord = chords[bar % 8]
        root = roots[bar % 8]

        for beat in range(4):
            if not breakdown:
                song.kicks.append(song.t(bar, beat * 4))
                drums.add(song.t(bar, beat * 4), kick_snd, 1.0)
            elif beat in (0, 2):
                # Half-time kick keeps the breakdown moving under the players' feet.
                song.kicks.append(song.t(bar, beat * 4))
                drums.add(song.t(bar, beat * 4), kick_snd, 0.75)
            if beat in (1, 3) and not build:
                drums.add(song.t(bar, beat * 4), clap_snd, 0.5, 0.05)
                drums.add(song.t(bar, beat * 4), snare_snd, 0.35 if not breakdown else 0.2, -0.05)
            drums.add(song.t(bar, beat * 4 + 2), hat_open, 0.2 if not breakdown else 0.12, 0.3)
        for step in range(16):
            accent = 0.16 if step % 4 == 2 else 0.08
            drums.add(song.t(bar, step), hat_closed, accent, -0.35 if step % 2 else 0.35)
        if build:
            rate = 2 if bar < 22 else (1 if bar == 22 else 0.5)
            step = 0.0
            while step < 16:
                level = 0.2 + 0.4 * ((bar - 20) * 16 + step) / 64
                drums.add(song.t(bar, step), snare_snd, level)
                step += rate
        if bar % 8 == 0:
            drums.add(song.t(bar), s.crash(), 0.4, 0.2)

        # Rolling offbeat bass with a sub underneath.
        for step in range(2, 16, 4):
            bass_stem.add(song.t(bar, step), s.bass(root + 12, song.step * 1.8, cutoff=1100 if not breakdown else 700, sub=0.7), 0.5 if not breakdown else 0.3)
            if section == 3:
                for step in (3, 7, 11, 15):
                    bass_stem.add(song.t(bar, step), s.bass(root + 12, song.step * 0.8, cutoff=1600, sub=0.4), 0.3)

        # Big pumping supersaw chords.
        cutoff = 3000 if section < 2 else (2200 + (bar - 16) * 500 if section == 2 else 7000)
        chords_stem.add(song.t(bar), s.supersaw(chord + [chord[0] + 12], song.bar, cutoff=cutoff, voices=7, detune=0.22, attack=0.01, release=0.3), 0.32, wrap=True)

        # Urgent 16th arp riff following the chord.
        arp_notes = [chord[0], chord[1], chord[2], chord[0] + 12]
        for step in range(16):
            pattern = (0, 2, 1, 3, 2, 1, 3, 2)
            midi = arp_notes[pattern[step % 8]] + 12
            arp.add(song.t(bar, step), s.pluck(midi, song.step * 0.9, brightness=3800 if section != 2 else 2200), 0.22, -0.25 if step % 2 else 0.25)

    for offset in (8, 24):
        for bar, step, midi, length in melody_events(hook, offset):
            lead_stem.add(song.t(bar, step), s.lead(midi, length * song.step * 0.95), 0.34)
    fx.add(song.t(20), s.riser(song.bar * 4), 0.3)
    fx.add(song.t(16), s.downlifter(song.bar * 2), 0.25)
    for bar in (0, 24):
        fx.add(song.t(bar), s.impact(), 0.4)

    gain = s.sidechain(drums.length, song.kicks, depth=0.75, release=0.18)
    mix = s.Timeline(song.length)
    mix.mix(drums)
    mix.buffer += bass_stem.buffer * gain
    mix.buffer += chords_stem.buffer * gain
    mix.buffer += s.ping_pong(arp.buffer, song.beat * 0.75, 0.35, 0.2, wrap=True) * (0.5 + 0.5 * gain)
    mix.buffer += s.ping_pong(lead_stem.buffer, song.beat * 0.75, 0.38, 0.22, wrap=True)
    mix.mix(fx)
    wet = s.reverb(mix.buffer, decay=1.4, mix=0.16, wrap=True)
    return s.master(wet, target_rms_db=-13.5)


# ====================================================================== stings & sound effects

def render_sfx(build) -> np.ndarray:
    # A short fade-out guarantees no click if a tail is still ringing at the end of the file.
    return s.fade(s.master(build(), target_rms_db=-16, ceiling_db=-1.5), 0, 0.05)


def sfx_vote_open():
    tl = s.Timeline(1.8)
    tl.add(0, s.riser(0.5), 0.5)
    chord = [s.note(x) for x in ("F4", "A4", "C5", "G5")]
    tl.add(0.45, s.supersaw(chord, 0.5, cutoff=7000, attack=0.005, release=0.6), 0.6)
    for i, midi in enumerate((77, 81, 84, 89)):
        tl.add(0.45 + i * 0.07, s.fm_bell(midi + 12, 0.2, ratio=3.5, index=1.5, decay=0.8), 0.35, -0.5 + i * 0.33)
    return s.reverb(tl.buffer, 1.4, 0.3)


def sfx_countdown():
    n = s.samples(0.22)
    tone = s.sine(np.full(n, 880.0), n) + 0.3 * s.square(np.full(n, 880.0), n)
    return s.pan(tone * s.adsr(n, 0.003, 0.05, 0.6, 0.12))


def sfx_round_start():
    tl = s.Timeline(2.2)
    tl.add(0, s.kick(1.4), 0.8)
    tl.add(0, s.crash(1.2), 0.5)
    for i, midi in enumerate((81, 88)):
        tl.add(i * 0.09, s.supersaw([midi, midi - 12, midi + 7 - 12], 0.35, cutoff=8000, attack=0.003, release=0.4), 0.5)
    return s.reverb(tl.buffer, 1.2, 0.25)


def sfx_hazard():
    tl = s.Timeline(0.5)
    for i, freq in enumerate((1250.0, 950.0)):
        n = s.samples(0.11)
        tone = s.square(np.full(n, freq), n, 0.3) * s.adsr(n, 0.002, 0.03, 0.7, 0.04)
        tl.add(i * 0.14, s.lowpass(tone, 4000), 0.5)
    return tl.buffer


def sfx_hit():
    n = s.samples(0.35)
    t = np.arange(n) / s.SR
    bonk = s.sine(620 * np.exp(-t / 0.05) + 140, n) * s.exp_decay(n, 0.09)
    smack = s.bandpass(s.noise(n), 600, 4000) * s.exp_decay(n, 0.02)
    return s.pan(s.soft_clip(bonk + smack * 0.8, 1.5))


def sfx_pickup():
    tl = s.Timeline(0.45)
    for i, midi in enumerate((83, 88)):
        n = s.samples(0.12 if i == 0 else 0.3)
        f = np.full(n, s.midi_hz(midi))
        tone = s.square(f, n, 0.25) * 0.5 + s.sine(f, n) * 0.5
        tl.add(i * 0.07, s.lowpass(tone * s.adsr(n, 0.002, 0.05, 0.5, 0.08), 6000), 0.6)
    return tl.buffer


def sfx_eliminated():
    tl = s.Timeline(1.6)
    for i, (start, end) in enumerate(((62, 60), (60, 58), (58, 51))):
        length = 0.32 if i < 2 else 0.8
        n = s.samples(length)
        glide = np.linspace(s.midi_hz(start), s.midi_hz(end), n)
        wobble = 1 + 0.02 * np.sin(2 * np.pi * 6 * np.arange(n) / s.SR) * (i == 2)
        voice = s.saw(glide * wobble, n) * 0.6 + s.square(glide * wobble, n, 0.4) * 0.3
        voice = s.lowpass(voice, 1400) * s.adsr(n, 0.02, 0.1, 0.8, 0.12)
        tl.add(i * 0.34, voice, 0.6)
    return s.reverb(tl.buffer, 0.9, 0.2)


def sfx_victory():
    tl = s.Timeline(3.6)
    n = s.note
    progression = [([n("F4"), n("A4"), n("C5")], 0.0, 0.22), ([n("Bb4"), n("D5"), n("F5")], 0.24, 0.22),
                   ([n("C5"), n("E5"), n("G5")], 0.48, 0.22), ([n("F4"), n("A4"), n("C5"), n("F5")], 0.72, 1.6)]
    for chord, start, length in progression:
        tl.add(start, s.supersaw(chord, length, cutoff=7500, attack=0.01, release=0.6), 0.45)
        tl.add(start, s.bass(chord[0] - 24, length, cutoff=900), 0.4)
    for i, midi in enumerate((77, 81, 84, 89, 93, 96)):
        tl.add(0.72 + i * 0.08, s.fm_bell(midi, 0.3, ratio=3.5, index=1.6, decay=1.2), 0.3, -0.6 + i * 0.24)
    tl.add(0.72, s.kick(1.2), 0.7)
    tl.add(0.72, s.crash(2.4), 0.5)
    return s.fade(s.reverb(tl.buffer, 2.0, 0.28), 0, 0.4)


def sfx_results():
    tl = s.Timeline(2.0)
    for i, midi in enumerate((72, 76, 79, 84)):
        tl.add(i * 0.1, s.fm_bell(midi, 0.25, ratio=3.5, index=1.4, decay=1.0), 0.4, -0.4 + i * 0.27)
    tl.add(0.4, s.supersaw([72, 76, 79], 0.6, cutoff=4000, attack=0.05, release=0.6), 0.25)
    return s.fade(s.reverb(tl.buffer, 1.6, 0.3), 0, 0.3)


def sfx_return():
    tl = s.Timeline(1.0)
    tl.add(0, s.downlifter(0.7), 0.6)
    tl.add(0.25, s.supersaw([65, 69, 72], 0.4, cutoff=2500, attack=0.08, release=0.4), 0.3)
    return s.reverb(tl.buffer, 1.0, 0.25)


def sfx_boing():
    n = s.samples(0.55)
    t = np.arange(n) / s.SR
    freq = 220 + 380 * (1 - np.exp(-t / 0.08)) + 60 * np.sin(2 * np.pi * 18 * t) * np.exp(-t / 0.2)
    return s.pan(s.sine(freq, n) * s.exp_decay(n, 0.12))


def sfx_purchase():
    tl = s.Timeline(1.2)
    for i, midi in enumerate((84, 88, 91, 96)):
        tl.add(i * 0.05, s.fm_bell(midi, 0.15, ratio=3.5, index=1.8, decay=0.7), 0.35, -0.3 + i * 0.2)
    tl.add(0.18, sfx_pickup()[0], 0.5)
    return s.reverb(tl.buffer, 1.0, 0.25)


def sfx_splash():
    n = s.samples(0.8)
    body = s.sweep_lowpass(s.noise(n), 6000, 300, blocks=24) * s.adsr(n, 0.005, 0.2, 0.3, 0.4)
    return s.pan(body)


def sfx_click():
    n = s.samples(0.06)
    return s.pan(s.sine(np.full(n, 1400.0), n) * s.exp_decay(n, 0.012))


def sfx_vote_click():
    n = s.samples(0.16)
    t = np.arange(n) / s.SR
    return s.pan(s.sine(520 + 500 * (1 - np.exp(-t / 0.02)), n) * s.exp_decay(n, 0.05))


SFX = {
    "VoteOpen": sfx_vote_open,
    "Countdown": sfx_countdown,
    "RoundStart": sfx_round_start,
    "HazardWarning": sfx_hazard,
    "Hit": sfx_hit,
    "Pickup": sfx_pickup,
    "Eliminated": sfx_eliminated,
    "Victory": sfx_victory,
    "Results": sfx_results,
    "ReturnToLobby": sfx_return,
    "Boing": sfx_boing,
    "Purchase": sfx_purchase,
    "Splash": sfx_splash,
    "Click": sfx_click,
    "VoteClick": sfx_vote_click,
}

MUSIC = {
    "Lobby": party_plaza,
    "Lobby2": sunset_social,
    "Round": panic_mode,
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, help="also write MP3 previews into this folder")
    parser.add_argument("--only", help="render just one name (e.g. Lobby, Victory)")
    args = parser.parse_args()

    (OUT / "music").mkdir(parents=True, exist_ok=True)
    (OUT / "sfx").mkdir(parents=True, exist_ok=True)
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)

    jobs = [("music", name, fn) for name, fn in MUSIC.items()] + [("sfx", name, lambda fn=fn: render_sfx(fn)) for name, fn in SFX.items()]
    rendered_sfx: dict[str, np.ndarray] = {}
    with tempfile.TemporaryDirectory() as tmp:
        for group, name, fn in jobs:
            if args.only and args.only != name:
                continue
            audio = fn()
            if group == "sfx":
                rendered_sfx[name] = audio
            wav = Path(tmp) / f"{name}.wav"
            s.write_wav(wav, audio)
            target = OUT / group / f"{name}.ogg"
            s.encode(wav, target, "ogg")
            if args.preview:
                s.encode(wav, args.preview / f"{group}-{name}.mp3", "mp3")
            print(f"{group}/{name}: {audio.shape[1] / s.SR:.1f}s -> {target.relative_to(ROOT)}")
        if len(rendered_sfx) == len(SFX):
            write_sprite(rendered_sfx, Path(tmp))


SPRITE_GAP = 0.3


def write_sprite(effects: dict[str, np.ndarray], tmp: Path):
    """Packs every effect into one file (one upload instead of fifteen) plus an offsets table.

    Roblox limits audio uploads per month, so the game plays each effect as a PlaybackRegion of
    this single sprite.
    """
    gap = np.zeros((2, s.samples(SPRITE_GAP)))
    pieces, regions, cursor = [], [], 0.0
    for name, audio in effects.items():
        length = audio.shape[1] / s.SR
        regions.append((name, cursor, length))
        pieces += [audio, gap]
        cursor += length + SPRITE_GAP
    sprite = np.hstack(pieces)
    wav = tmp / "SfxSprite.wav"
    s.write_wav(wav, sprite)
    s.encode(wav, OUT / "sfx" / "SfxSprite.ogg", "ogg")
    lines = [
        "-- GENERATED by tools/music/compose.py - do not edit by hand.",
        "-- Where each sound effect sits inside assets/audio/sfx/SfxSprite.ogg (seconds).",
        "",
        "return {",
    ]
    for name, start, length in regions:
        lines.append(f"\t{name} = {{ Start = {start:.3f}, Length = {length:.3f} }},")
    lines.append("}")
    (ROOT / "src" / "shared" / "SfxSprite.luau").write_text("\n".join(lines) + "\n")
    print(f"sfx/SfxSprite: {sprite.shape[1] / s.SR:.1f}s ({len(regions)} effects) -> assets/audio/sfx/SfxSprite.ogg")


if __name__ == "__main__":
    main()
