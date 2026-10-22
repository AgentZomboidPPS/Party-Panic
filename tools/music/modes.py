"""Party Panic's mini-game round tracks: one original song per mini-game.

Owner: "put in the backlog custom music for each mini game". Until now every round played "Panic
Mode"; now each arena has its own band, tempo and tune, written here as lead sheets (score.py's
notation) and played by tools/music/instruments.py:

    FireRope      "Dragon Temple Drums"   taiko, a bamboo flute and koto over a lava temple
    HexMeltdown   "Molten Showdown"       a game-show disco-funk band in a volcano crater
    HoneyTrap     "Honeycomb Hush"        tiptoeing bassoon and pizzicato in a storybook meadow
    BumperBallers "Tiki Bumper Bash"      steel pans and soca drums on a tiki island
    SkateEscape   "Canyon Grind"          skate punk over a lava canyon
    SinkingSands  "Quicksand Caravan"     oud, ney and darbuka on a desert mesa
    ArrowAmbush   "Archer's Jig"          fife, lute and fanfare at a castle tournament
    PumpAndPop    "Balloon Bandstand"     a carnival calliope march, slide whistles inflating
    RakeItIn      "Harvest Hoedown"       banjo and fiddle on the farm
    CrazyCutters  "Cookie Cutter Swing"   a bake-off jazz combo with vibes and clarinet
    CakeFactory   "Conveyor Belt Boogie"  a toy factory's clanks, hisses and music box
    BobsledRun    "Ice Chute Rush"        sleigh bells and heroic brass down the ice
    SharkBait     "Shark Surf Panic"      surf guitar, spring reverb and a lurking shark riff
    StampOut      "Ink Pad Ska"           a two-tone ska band on a giant desk, BIG STAMPS up a step at 30 s
    RockinRaceway "Hobby Horse Hop"       rock'n'roll sax, boogie piano and galloping hooves round the fair

Every track opens with an intro of at least 13 seconds (the rules card and the 3-2-1, while the
game loads its own track), then the band kicks in on GO: AudioController starts the track so its
drop (the end of the intro) lands exactly when the round starts. Intros start softly, because how
much of their opening a player hears depends on how fast the track loads. After the intro comes at
least the round's full length of music, with the big finish where the round's own finale is
(Bumper Ballers' BIG BUMPS at 45 s, Rake It In's GOLDEN RUSH at 38.5 s, Shark Bait's COIN RUSH at
45 s), and the whole track loops seamlessly for a round that runs longer.

Mixing: every bus has a loudness target relative to the whole mix (score.Bus.level), so the tune
always sits on top, the drums and bass carry it, and nothing important hides; the master aims at
-11 LUFS with true peaks under -1 dBTP (the old round track measures -10.7, the lobby tracks
-11.5 and -12.3), with the bass written in a register phone speakers can play.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from score import Mix, Track, bass_note, chords, master, mixdown


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
    # -2 dBTP before encoding: Vorbis adds up to about half a dB of overshoot, and the game's files
    # must stay under -1 dBTP as decoded.
    return master(mixdown(track, mix), target_lufs=mix.target_lufs, ceiling_dbtp=-2.0)


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


def songs() -> list[Song]:
    """Every round track: one module per mini-game in tools/music/songs/<Id>.py, each defining SONG."""
    import importlib
    from pathlib import Path

    found = []
    for path in sorted((Path(__file__).parent / "songs").glob("[A-Z]*.py")):
        song = importlib.import_module(f"songs.{path.stem}").SONG
        if song.id != path.stem:
            raise ValueError(f"songs/{path.name} defines {song.id}")
        found.append(song)
    return found
