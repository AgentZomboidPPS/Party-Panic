"""The shared kit for the mini-games' own round songs (tools/music/songs/<ModeId>.py).

Owner: "put in the backlog custom music for each mini game".

A song file writes one song with score.py's lead-sheet notation, played by instruments.py, and ends
with `SONG = Song(<mode id>, <title>, <bpm>, <intro bars>, <bars>, render)`. `render()` returns
(stereo audio, Track). Rules every song keeps (tools/music/modes.py checks them):

  - The intro (the first `intro` bars) lasts at least 13 seconds: the rules card and the 3-2-1. The
    game starts the song so the end of the intro, the drop, lands exactly on GO. Intros start softly,
    because how much of their opening a player hears depends on how fast the track loads.
  - After the intro comes at least the round's full length of music (GameDefinitions Duration), with
    the big finish where the round's own finale is. In a longer round the game loops the part after
    the intro, so the last bars lead back into the drop.
  - The master aims at -11 LUFS with true peaks under -1 dBTP; the bass sits where phone speakers can
    play it (mostly above 60 Hz).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, chords, master, melody, mixdown, shift, voicing

__all__ = [
    "Bus", "Mix", "Track", "bass_note", "chords", "master", "melody", "mixdown", "shift", "voicing",
    "ins", "s", "np", "Song", "Part", "plan", "finish", "strum", "tremolo", "walking_bass",
]


@dataclass
class Song:
    id: str
    title: str
    bpm: float
    intro: int  # bars before the drop (the round's GO)
    bars: int
    render: object  # () -> (stereo audio, Track)


@dataclass
class Part:
    name: str
    first: int
    bars: int
    changes: list  # (bar, step, length in steps, Chord)

    def bars_range(self):
        return range(self.first, self.first + self.bars)

    def at(self, bar: int):
        return [(step, length, c) for b, step, length, c in self.changes if b == bar]


def plan(track: Track, spec) -> list[Part]:
    """Sections [(name, bars, progression)] laid end to end; they must fill the track exactly."""
    parts, first = [], 0
    for name, bars, progression in spec:
        changes = []
        for step, length, c in chords(progression, track.spb):
            changes.append((first + int(step // track.spb), step % track.spb, length, c))
        if len({b for b, *_ in changes}) != bars:
            raise ValueError(f"{name}: the progression has {len({b for b, *_ in changes})} bars, not {bars}")
        parts.append(Part(name, first, bars, changes))
        first += bars
    if first != track.bars:
        raise ValueError(f"sections add up to {first} bars, the track has {track.bars}")
    return parts


def finish(track: Track, mix: Mix) -> np.ndarray:
    return master(mixdown(track, mix), target_lufs=mix.target_lufs)


def strum(track: Track, stem: str, bar: float, step: float, notes, voice, seconds: float, gain: float,
          spread: float = 0.012, down: bool = True, pan: float = 0.0):
    order = list(notes) if down else list(reversed(notes))
    for i, m in enumerate(order):
        track.add(stem, bar, step + i * spread / track.step, voice(m, seconds), gain / len(order) ** 0.5, pan)


def tremolo(track: Track, stem: str, bar: float, notes, voice, rate: float, gain: float, pan: float = 0.0):
    """Tremolo picking: every long note re-picked every `rate` steps, alternating strokes."""
    for n in notes:
        k = 0.0
        while k < n.length - 1e-6:
            sec = min(rate, n.length - k) * track.step * 1.3
            track.add(stem, bar, n.step + k, voice(n.midi, sec), gain * n.vel * (1.0 if int(k / rate) % 2 == 0 else 0.78), pan)
            k += rate


def walking_bass(track: Track, stem: str, part: Part, voice, gain: float, low: int = 29):
    """A walking bass line, four to the bar: the root, chord tones, then a half step into the next root."""
    beat = track.spb // 4
    changes = part.changes
    for index, (bar, step, length, c) in enumerate(changes):
        nxt = changes[(index + 1) % len(changes)][3]
        beats = max(1, int(round(length / beat)))
        root = bass_note(c, low)
        third = root + c.intervals[1] % 12
        fifth = root + (c.intervals[2] % 12 if len(c.intervals) > 2 else 7)
        target = bass_note(nxt, low)
        line = [root, third, fifth, target - 1 if target - 1 != fifth else target + 1][: beats]
        if beats == 2:
            line = [root, target - 1 if target - 1 != root else target + 1]
        for k, m in enumerate(line):
            track.add(stem, bar, step + k * beat, voice(m, track.step * beat * 0.95), gain * (1.0 if k == 0 else 0.85))
