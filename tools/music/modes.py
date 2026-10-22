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

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, chords, master, melody, mixdown, shift, voicing


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


# ====================================================================== FIRE ROPE

def fire_rope():
    """Dragon Temple Drums (126 bpm, D minor pentatonic): a fire festival on a stone bridge over lava.
    Taiko, a bamboo flute (dizi) with a heroic theme, koto, an erhu, gongs and a choir; up to E minor
    for the climax and G major for the final stretch, as the rope gets faster."""
    tr = Track(bpm=126, bars=52)
    parts = plan(tr, [
        ("intro", 8, "Dm | Dm | Dm | Dm | Bb | C | Dm | Dm"),
        ("A1", 8, "Dm | Dm | Bb | C | Dm | Dm | Gm | A"),
        ("A2", 8, "Dm | Dm | Bb | C | Dm | Dm | Gm | A"),
        ("B", 8, "F | C | Dm | Bb | F | C | Bb | C"),
        ("break", 4, "Dm | Dm | Bb | C"),
        ("climax", 8, "Em | Em | C | D | Em | Em | Am | B"),
        ("finale", 8, "G | D | Em | C | G | D | C | D"),
    ])
    theme = melody("""D5:4 F5:2 G5:2 A5:6 C6:2 | A5:4 G5:2 F5:2 G5:8 | F5:4 D5:2 F5:2 G5:4 F5:2 D5:2 | C5:6 D5:2 E5:8 |
                      D5:4 F5:2 G5:2 A5:6 C6:2 | D6:4 C6:2 A5:2 C6:8 | Bb5:4 A5:2 G5:2 D5:4 G5:4 | A5:12 r:4""")
    counter = melody("A3:8 D4:8 | C4:16 | D4:8 F4:8 | E4:16 | A3:8 D4:8 | F4:16 | D4:8 G4:8 | E4:8 C#4:8")
    lyric = melody("""C6:6 A5:2 G5:4 F5:4 | G5:8 E5:4 G5:4 | A5:6 F5:2 D5:4 F5:4 | F5:12 D5:4 |
                      C6:6 D6:2 C6:4 A5:4 | G5:6 A5:2 G5:4 E5:4 | F5:4 G5:4 A5:4 Bb5:4 | C6:16""")
    solo = melody("""r:4 A5:8 G5:4 | A5:6 C6:2 D6:8 | C6:4 A5:4 G5:4 F5:4 | G5:16 |
                     r:4 D6:4 C6:4 A5:4 | G5:8 r:8""")

    def dizi(m, sec):
        return ins.flute(m, sec, breath=0.09, vibrato=0.14, buzz=0.35, fall=0.6 if sec > 0.9 else 0.0)

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.55, section=3)

    odaiko = [ins.taiko(58.0, 1.4, 1.0, v) for v in range(3)]
    mid = [ins.taiko(105.0, 0.7, 0.8, v) for v in range(3)]
    shime = ins.tom(420.0, 0.15)
    ka = ins.rim_click(1500.0)
    chappa = s.hat(True)
    kick, clap = s.kick(1.0, 0.45), s.clap()

    tr.add("fx", 0, 0, ins.crackle(tr.bar * 2), 0.5)
    tr.add("fx", 2, 0, ins.gong(5.0, 98.0), 1.0)
    tr.play("lead", 2, solo, dizi, 0.8)

    prev = None
    for part in parts:
        for bar, step, length, c in part.changes:
            root = bass_note(c, 26)
            notes = voicing(c, 57, 72, prev)
            prev = notes
            local = bar - part.first
            seconds = length * tr.step
            name = part.name
            if name == "intro":
                tr.add("pad", bar, 0, ins.strings((root + 12, root + 19), seconds, attack=0.8, bright=0.25), 1.0)
            elif name in ("B", "finale"):
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.3, bright=0.45), 1.0)
            if name in ("break", "climax", "finale"):
                tr.add("choir", bar, step, ins.choir(tuple(n - 12 for n in notes[:3]), seconds, "ah"), 1.0)
            if name in ("A1", "A2", "climax"):
                for k, offset in enumerate((0, 0, 12, 0, 7, 0, 12, 0)):
                    tr.add("bass", bar, k * 2, ins.synth_bass(root + 12 + offset, tr.step * 1.6, cutoff=700, env_amt=1200, sub=0.4), 1.0)
                    tr.add("ostinato", bar, k * 2, ins.spiccato(root + 24 + offset, tr.step * 1.5), 1.0, -0.25)
            elif name in ("B", "finale"):
                tr.add("bass", bar, 0, ins.synth_bass(root + 12, tr.step * 7, cutoff=600, env_amt=600, sub=0.5), 1.0)
                tr.add("bass", bar, 8, ins.synth_bass(root + (19 if name == "B" else 12), tr.step * 7, cutoff=600, env_amt=600, sub=0.5), 0.85)
            elif name == "break":
                tr.add("bass", bar, 0, ins.synth_bass(root + 12, tr.step * 14, cutoff=500, env_amt=300, sub=0.6), 1.0)
            ring = notes + [notes[0] + 12, notes[1] + 12]
            if name in ("A1", "A2", "climax"):
                for k, idx in enumerate((0, 1, 2, 1, 3, 1, 2, 1)):
                    tr.add("koto", bar, k * 2, ins.koto(ring[idx], tr.step * 2, variant=k), 1.0, 0.3)
            elif name in ("B", "finale"):
                for k in range(16):
                    tr.add("koto", bar, k, ins.koto(ring[(0, 1, 2, 3, 4, 3, 2, 1)[k % 8]], tr.step * 1.5, variant=k), 0.85 if k % 2 else 1.0, 0.35 if k % 2 else -0.1)
            elif name == "intro" and local >= 4:
                for k in (0, 6, 10):
                    tr.add("koto", bar, k, ins.koto(ring[k % 3], tr.step * 4, press=1.0 if k == 6 else 0.0), 1.0, 0.3)

        for bar in part.bars_range():
            local = bar - part.first
            name = part.name
            if name == "intro":
                if local >= 3:
                    tr.drum("taiko", bar, "X.......X.......", odaiko[local % 3], 0.6 + 0.08 * (local - 3))
                if local >= 5:
                    tr.drum("taiko", bar, "....x......x.x..", mid[local % 3], 0.6)
                if local >= 6:
                    tr.drum("perc", bar, "x.x.x.x.x.x.x.x.", shime, 0.6 + 0.2 * (local - 6), 0.3)
                if local == 7:
                    for k in range(16):
                        tr.add("taiko", bar, k, mid[k % 3], 0.25 + 0.05 * k)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.5)
                continue
            if name == "break":
                tr.drum("taiko", bar, "X.....X.....X...", odaiko[local % 3], 1.0)
                tr.drum("taiko", bar, "....x.....x...x." if local % 2 == 0 else "..x.x..x..x.x.xx", mid[local % 3], 0.6)
                tr.drum("perc", bar, "..X...X...X...X.", ka, 0.8, 0.2)
                if local == 3:
                    for k in range(8, 16):
                        tr.add("taiko", bar, k, mid[k % 3], 0.35 + 0.08 * (k - 8))
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.5)
                continue
            big = name in ("climax", "finale")
            tr.kick("kick", bar, "X.......X.......", kick, 1.0)
            tr.drum("taiko", bar, "X.....x.X.......", odaiko[local % 3], 0.8)
            tr.drum("taiko", bar, "....X..x....X..x" if local % 2 == 0 else "....X..x..x.X.xx", mid[local % 3], 0.55)
            tr.drum("snare", bar, "....X.......X...", clap, 1.0, 0.05)
            tr.drum("perc", bar, "x.x.x.x.x.x.x.x." if name in ("A1", "B") else "xoxoxoxoxoxoxoxo", shime, 0.8, 0.3)
            tr.drum("perc", bar, "..x...x...x...x.", ka, 0.7, -0.3)
            tr.drum("cymbal", bar, "..x...x...x...x." if not big else "..x.x.x...x.x.x.", chappa, 1.0, -0.2)
            if local % 8 == 0:
                tr.add("fx", bar, 0, ins.gong(3.0, 110.0), 0.8)
                tr.add("cymbal", bar, 0, s.crash(), 1.6, 0.2)

    tr.play("lead", 8, theme, dizi)
    tr.play("lead", 16, theme, dizi)
    tr.play("harmony", 16, shift(theme, -5), ins.koto)
    tr.play("brass", 16, counter, horn, pan=-0.2)
    tr.play("lead", 24, lyric, ins.erhu)
    tr.play("lead", 36, shift(theme, 2), dizi)
    tr.play("brass", 36, shift(theme, 2 - 12), horn, pan=-0.15)
    tr.play("lead", 44, shift(lyric, 7 - 12), dizi)
    tr.play("brass", 44, shift(lyric, 7 - 24), horn, pan=-0.15)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.2, delay=0.08),
        "harmony": Bus(-15, reverb=0.2),
        "brass": Bus(-11, reverb=0.18),
        "koto": Bus(-13, reverb=0.18, delay=0.1),
        "ostinato": Bus(-14, pump=0.2, reverb=0.1),
        "pad": Bus(-14, pump=0.15, reverb=0.25),
        "choir": Bus(-14, reverb=0.35),
        "bass": Bus(-9, pump=0.2),
        "taiko": Bus(-6, drive=1.6, reverb=0.1),
        "kick": Bus(-10, drive=1.4),
        "snare": Bus(-14, reverb=0.15),
        "perc": Bus(-15, reverb=0.08),
        "cymbal": Bus(-19, reverb=0.1),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=2.2, reverb_tone=5000, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


# ====================================================================== HEX MELTDOWN

def hex_meltdown():
    """Molten Showdown (124 bpm, E minor): the volcano crater's game show. A disco-funk band (slap bass,
    clavinet, brass, strings) with the referee robot's bleeps and lava bubbles; a big G major chorus,
    a lava-drama break, then up to F sharp minor as the calls come faster."""
    tr = Track(bpm=124, bars=56)
    parts = plan(tr, [
        ("intro", 8, "Em | Em | Em | Em | Em | Em | C | B7"),
        ("A1", 8, "Em7 | A7 | Em7 | A7 | Em7 | A7 | Cmaj7 | B7"),
        ("A2", 8, "Em7 | A7 | Em7 | A7 | Em7 | A7 | Cmaj7 | B7"),
        ("chorus", 8, "Cmaj7 | D | Bm7 | Em7 | Cmaj7 | D | B7sus4 | B7"),
        ("break", 4, "Em | C | Am | B7"),
        ("A3", 8, "Em7 | A7 | Em7 | A7 | Em7 | A7 | Cmaj7 | B7"),
        ("climax", 8, "Dmaj7 | E | C#m7 | F#m7 | Dmaj7 | E | C#7sus4 | C#7"),
        ("final", 4, "F#m7 | B7 | F#m7 | B7"),
    ])
    hook = melody("""r:2 B4:2 D5:2 E5:4 D5:2 B4:2 G4:2 | A4:4 r:2 C#5:2 E5:2 G5:4 r:2 | r:2 B4:2 D5:2 E5:4 G5:2 F#5:2 E5:2 | E5:6 C#5:2 A4:8 |
                     r:2 B4:2 D5:2 E5:4 D5:2 B4:2 G4:2 | A4:4 r:2 C#5:2 E5:2 A5:4 G5:2 | G5:4 E5:4 B4:4 G4:4 | F#5:4 D#5:4 B4:4 A4:4""")
    chorus = melody("""E5:6 G5:2 B5:8 | A5:6 F#5:2 D5:8 | F#5:4 A5:4 B5:4 D6:4 | B5:12 G5:4 |
                       E5:6 G5:2 B5:4 C6:4 | D6:6 C6:2 A5:4 F#5:4 | E5:8 F#5:8 | D#5:16""")
    fanfare = melody("B4:2 E5:2 G5:2 B5:10 | A5:2 G5:2 F#5:2 G5:2 E5:8 | G5:2 C6:2 E6:2 G6:6 F#6:2 E6:2 | D#6:4 F#6:4 A5:2 B5:6")
    strings_line = melody("B5:16 | C#6:16 | B5:16 | C#6:8 E6:8 | G6:16 | E6:16 | E6:8 G6:8 | F#6:16")

    def lead_brass(m, sec):
        return ins.brass(m, sec, bright=1.0, section=3)

    kick, clap, ohat, chat, shake = s.kick(1.1, 0.4), s.clap(), s.hat(True), s.hat(False), s.shaker()
    toms = [ins.tom(p, 0.4) for p in (110.0, 150.0, 200.0)]

    for bar in (0, 1):
        for k, step in enumerate((3, 9, 14)):
            tr.add("fx", bar, step, ins.bloop(90.0 + 30 * k, 2.2), 0.6, -0.3 + 0.3 * k)
    tr.add("fx", 2, 0, ins.orchestra_hit((52, 59, 64, 67)), 1.0)
    for k in range(32):
        tr.add("fx", 2, k / 2, ins.timpani(40, 0.6, 0.4), 0.15 + 0.01 * k)
    tr.play("brass", 4, fanfare, lead_brass)

    pent = [64, 67, 69, 71, 74, 76, 79, 81]
    rng = np.random.default_rng(5)
    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 28)
            notes = voicing(c, 60, 74, prev)
            prev = notes
            seconds = length * tr.step
            # bass
            if name == "intro":
                if local >= 2:
                    for k in range(8):
                        tr.add("bass", bar, k * 2, ins.synth_bass(root + 12, tr.step * 1.4, cutoff=500, env_amt=800 + 120 * local), 0.9)
            elif name == "break":
                tr.add("bass", bar, 0, ins.synth_bass(root + 12, tr.step * 12, cutoff=400, env_amt=400), 1.0)
            else:
                seventh = 10 if "7" in c.name and "maj" not in c.name else 7
                # disco octaves: a thumbed root, a popped octave (slap_bass adds it), the seventh near the end
                for st, off, pop in ((0, 0, False), (2, 0, True), (4, 0, False), (6, 0, True),
                                     (8, 0, False), (10, 0, True), (12, seventh, False), (14, 0, True)):
                    tr.add("bass", bar, step + st, ins.slap_bass(root + 12 + off, tr.step * 1.6, pop), 0.8 if pop else 1.0)
            # clav funk
            if name in ("A1", "A2", "A3", "final"):
                for k, ch in enumerate("x.xx.x.x..x.xx.x"):
                    if ch == "x":
                        if k % 4 == 0:
                            strum(tr, "clav", bar, k, notes, ins.clav, tr.step * 0.9, 1.0, spread=0.004)
                        else:
                            tr.add("clav", bar, k, ins.clav(notes[k % len(notes)], tr.step * 0.8), 0.75, 0.25)
            # pads
            if name in ("chorus", "climax"):
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.08, bright=0.6), 1.0)
                tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "ah", attack=0.15), 1.0)
            elif name == "break" or (name == "intro" and local >= 4):
                tr.add("pad", bar, step, ins.strings(tuple(n - 12 for n in notes[:3]), seconds, attack=0.6, bright=0.3), 1.0)
                if name == "break":
                    tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "oo", attack=0.4), 1.0)
            # brass stabs on the and-of-4, and the robot's call-board bleeps
            if name in ("A1", "A2", "A3", "final") and local % 2 == 1:
                strum(tr, "stabs", bar, 14, [n + 12 for n in notes[:3]], lambda m, sec: ins.brass(m, sec, bright=1.0, section=2), tr.step * 1.5, 1.0, spread=0.0)
            if name in ("intro", "break", "A3", "final") or (name == "A2" and local >= 4):
                density = 8 if name in ("intro", "A2") else 16
                for k in range(0, 16, 16 // density):
                    if rng.random() < 0.8:
                        tr.add("bleeps", bar, k, ins.blip(pent[rng.integers(len(pent))] + 12, tr.step * 0.6), 0.7 + 0.3 * rng.random(), 0.4 if k % 2 else -0.4)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.4 + 0.1 * (local - 4))
                if local >= 5:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.5 + 0.1 * (local - 5))
                if local == 7:
                    for k, step in enumerate(range(8, 16)):
                        tr.add("drums", bar, step, toms[2 - k // 3], 0.7 + 0.04 * k)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.6)
                continue
            if name == "break":
                tr.kick("kick", bar, "X.......X.......", kick, 0.8)
                for k in range(16):
                    tr.add("fx", bar, k, ins.timpani(40, 0.4, 0.3), 0.1 + (0.012 * k if local == 3 else 0))
                tr.add("fx", bar, 4, ins.bloop(80.0, 2.5, 0.25), 0.7, -0.4)
                tr.add("fx", bar, 11, ins.bloop(120.0, 2.0, 0.2), 0.6, 0.4)
                if local == 3:
                    for k in range(16):
                        tr.add("drums", bar, k, s.snare(0.15), 0.25 + 0.04 * k, 0.1)
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.6)
                continue
            tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
            tr.drum("drums", bar, "....X.......X...", clap, 1.0, 0.05)
            tr.drum("hats", bar, "..X...X...X...X.", ohat, 0.9, 0.25)
            tr.drum("hats", bar, "x.x.x.x.x.x.x.x." if name in ("A1", "chorus") else "xxxxxxxxxxxxxxxx", chat, 0.5, -0.25)
            tr.drum("perc", bar, "xoxoxoxoxoxoxoxo", shake, 1.0, 0.35)
            if local == 0:
                tr.add("hats", bar, 0, s.crash(), 2.0, 0.2)
                if name in ("A1", "chorus", "climax"):
                    tr.add("fx", bar, 0, ins.orchestra_hit(tuple(voicing(part.changes[0][3], 60, 76))), 0.8)
            if local == part.bars - 1 and name in ("A2", "A3", "climax"):
                for k, step in enumerate((12, 13, 14, 15)):
                    tr.add("drums", bar, step, toms[2 - k // 2], 0.8)

    tr.play("lead", 8, hook, lead_brass)
    tr.play("lead", 16, hook, lead_brass)
    tr.play("lead2", 16, shift(hook, 12), lambda m, sec: ins.synth_pluck(m, sec, bright=2500), pan=0.2)
    tr.play("strings", 16, strings_line, lambda m, sec: ins.strings((m,), sec, attack=0.2, bright=0.6))
    tr.play("lead", 24, chorus, lead_brass)
    tr.play("lead2", 24, shift(chorus, 12), ins.glock, pan=0.25)
    tr.play("lead", 36, hook, lead_brass)
    tr.play("lead2", 36, shift(hook, -3), lead_brass, pan=-0.2)
    tr.play("lead", 44, shift(chorus, 2), lead_brass)
    tr.play("lead2", 44, shift(chorus, 14), ins.glock, pan=0.25)
    tr.play("strings", 44, shift(chorus, -10), lambda m, sec: ins.strings((m,), sec, attack=0.1, bright=0.6))
    tr.play("lead", 52, [n for n in shift(hook, 2) if n.step < 4 * 16], lead_brass)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.15, delay=0.08),
        "lead2": Bus(-15, reverb=0.2),
        "strings": Bus(-14, reverb=0.25),
        "stabs": Bus(-13, reverb=0.15),
        "clav": Bus(-14, pump=0.15, delay=0.06),
        "bass": Bus(-8, pump=0.3),
        "pad": Bus(-15, pump=0.3, reverb=0.25),
        "choir": Bus(-16, pump=0.2, reverb=0.3),
        "bleeps": Bus(-19, delay=0.25),
        "kick": Bus(-8, drive=1.4),
        "drums": Bus(-12, reverb=0.12),
        "hats": Bus(-17),
        "perc": Bus(-20),
        "fx": Bus(-14, reverb=0.3),
    }, reverb_decay=1.6, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.32, pump_release=0.16)
    return finish(tr, mix), tr


# ====================================================================== HONEY TRAP

def honey_trap():
    """Honeycomb Hush (104 bpm shuffle, F major): the storybook meadow under the honey oak. A tiptoeing
    bassoon over pizzicato, a clarinet that takes the tune, a glockenspiel melody as sweet as honey, and
    a buzzing bee chase in D minor. Light enough to think over for a 150-second game of turns."""
    tr = Track(bpm=104, bars=44, spb=12)
    parts = plan(tr, [
        ("intro", 8, "F | Dm | Bb | C | F | Dm | Gm7 | C7"),
        ("A1", 8, "F | F | Bb | F | Gm7 | C7 | F | C7"),
        ("A2", 8, "F | F | Bb | F | Gm7 | C7 | F | C7"),
        ("B", 8, "Bb | C | Am7 | Dm7 | Gm7 | C7 | F | F"),
        ("C", 8, "Dm | A7 | Dm | A7 | Gm | C7 | F | C7"),
        ("tag", 4, "F | Bb | F C7 | F"),
    ])
    tiptoe = melody("""F3:2 A3:1 C4:3 A3:2 F3:1 C3:3 | F3:2 G3:1 A3:2 Bb3:1 C4:6 | D4:2 C4:1 Bb3:3 F3:2 D3:1 Bb2:3 | A3:2 Ab3:1 G3:2 Gb3:1 F3:6 |
                       G3:2 Bb3:1 D4:3 F4:2 D4:1 Bb3:3 | C4:2 E4:1 G4:3 Bb3:2 G3:1 E3:3 | F3:2 A3:1 C4:2 Db4:1 C4:3 A3:3 | G3:3 r:3 C3:3 r:3""", 12)
    sweet = melody("""D6:3 C6:2 Bb5:1 F5:6 | E5:2 F5:1 G5:2 A5:1 C6:6 | C6:2 A5:1 E5:3 G5:6 | F5:6 A5:3 C6:3 |
                      Bb5:3 A5:2 G5:1 D5:6 | E5:2 G5:1 Bb5:2 C6:1 E6:6 | F6:9 C6:3 | A5:12""", 12)
    chase = melody("""D5:1 C#5:1 D5:1 F5:1 E5:1 D5:1 A5:6 | A5:1 G#5:1 A5:1 C#6:1 B5:1 A5:1 E5:6 | D5:1 C#5:1 D5:1 F5:1 E5:1 D5:1 A5:3 Bb5:3 | A5:3 G5:3 E5:3 C#5:3 |
                      Bb4:1 A4:1 Bb4:1 D5:1 C5:1 Bb4:1 G5:6 | G5:1 F#5:1 G5:1 Bb5:1 A5:1 G5:1 E5:6 | F5:3 A5:3 C6:3 A5:3 | G5:6 r:6""", 12)
    box = melody("E6:6 G6:6 | A6:6 F6:6 | D6:3 F6:3 A6:6 | G6:6 F6:3 D6:3", 12)
    counter = melody("""F2:6 C3:6 | A2:6 F2:6 | Bb2:6 D3:6 | C3:6 A2:6 | G2:6 Bb2:6 | C3:6 E3:6 | F3:6 C3:6 | C3:3 D3:3 E3:3 G3:3""", 12)
    tag_tune = melody("F3:2 A3:1 C4:3 A3:2 F3:1 C3:3 | D4:2 C4:1 Bb3:3 F3:2 D3:1 Bb2:3 | A3:2 Ab3:1 G3:2 Gb3:1 F3:3 E3:3 | F3:12", 12)

    tick, tock = ins.woodblock(1250.0), ins.woodblock(880.0)
    snap = ins.finger_snap()
    shake = s.shaker()

    for k, m in enumerate((65, 69, 72, 77, 81, 84, 89)):
        tr.add("sparkle", 1, 6 + k * 0.5, ins.harp(m, 1.2, variant=k), 0.8, -0.3 + 0.1 * k)
    tr.play("sparkle", 3, box, ins.music_box, 1.0)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 36)
            notes = voicing(c, 58, 70, prev)
            prev = notes
            seconds = length * tr.step
            fifth = root + 7 if root + 7 <= 47 else root - 5
            if name == "intro":
                if local >= 5:
                    tr.add("pizz", bar, 0, ins.pizz(root, 0.3), 1.0)
                    tr.add("pizz", bar, 6, ins.pizz(fifth, 0.3), 0.85)
                if local == 7:  # a creeping chromatic walk up into the drop
                    for k, m in enumerate((43, 44, 45, 46)):
                        tr.add("pizz", bar, 6 + k * 1.5, ins.pizz(m, 0.2), 0.8 + 0.05 * k)
                continue
            if name in ("A1", "A2", "tag"):
                halves = [(step, root), (step + length / 2, fifth)] if length >= 12 else [(step, root)]
                for st, bass in halves:
                    tr.add("pizz", bar, st, ins.pizz(bass, 0.3), 1.0)
                    strum(tr, "pizz", bar, st + 3, notes[:3], ins.pizz, 0.2, 0.75, spread=0.008)
            elif name == "B":
                tr.add("pizz", bar, 0, ins.pizz(root, 0.6), 1.0)
                tr.add("pad", bar, 0, ins.strings(tuple(notes), seconds, attack=0.5, bright=0.35), 1.0)
                for k in range(0, 12, 2):
                    tr.add("kalimba", bar, k, ins.kalimba(notes[(k // 2) % len(notes)] + 12, 0.3), 1.0 if k % 6 == 0 else 0.7, 0.3)
            elif name == "C":
                for k in range(0, 12, 3):
                    line = [root, root + 7, root + 12, root + 7]
                    tr.add("pizz", bar, k, ins.pizz(line[k // 3], 0.2), 1.0)
                    tr.add("pizz", bar, k + 2, ins.pizz(line[k // 3] + (3 if "m" in c.name else 4), 0.15), 0.6)
                strum(tr, "pad", bar, 0, notes, lambda m, sec: ins.xylophone(m + 12, sec), 0.2, 0.9, spread=0.02)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 5:
                    tr.drum("clock", bar, "...x.....x..", tick, 0.8)
                    tr.drum("clock", bar, "x.....x.....", tock, 0.6)
                if local == 6:
                    tr.play("buzz", bar, melody("r:6 A5:1 Bb5:1 B5:1 C6:3", 12), ins.bee, 0.9)
                continue
            if name == "C":
                tr.drum("clock", bar, "x.xx.xx.xx.x", tick, 0.75)
                tr.drum("brush", bar, "..x..x..x..x", ins.brush(0.15), 0.7)
            else:
                tr.drum("clock", bar, "...x.....x..", tick, 0.8)
                tr.drum("clock", bar, "x.....x.....", tock, 0.5)
                tr.drum("brush", bar, "x.xx.xx.xx.x", shake, 0.6)
                tr.drum("snap", bar, "...x.....x..", snap, 0.8, 0.25)
            if name == "B" and local % 4 == 3:
                for k, m in enumerate((77, 81, 84, 89, 93)):
                    tr.add("sparkle", bar, 7 + k * 0.6, ins.glock(m, 0.3), 0.6, 0.4)

    tr.play("lead", 8, tiptoe, ins.bassoon)
    tr.play("lead", 16, shift(tiptoe, 12), ins.clarinet)
    tr.play("counter", 16, counter, ins.bassoon)
    tr.play("sparkle", 16, melody("F6:3 r:9 | r:12 | D6:3 r:9 | r:12 | Bb5:3 r:9 | r:12 | A5:3 C6:3 F6:6 | r:12", 12), ins.glock)
    tr.play("lead", 24, sweet, ins.glock)
    tr.play("lead2", 24, shift(sweet, -12), ins.celesta)
    tr.play("lead", 32, chase, ins.bee)
    tr.play("lead2", 32, shift(chase, -12), ins.clarinet)
    tr.play("lead", 40, tag_tune, ins.bassoon)
    tr.play("lead2", 40, shift(tag_tune, 12), ins.clarinet)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.2),
        "lead2": Bus(-12, reverb=0.2),
        "counter": Bus(-13, reverb=0.15),
        "pizz": Bus(-10, reverb=0.15),
        "pad": Bus(-15, reverb=0.25),
        "kalimba": Bus(-16, reverb=0.2, delay=0.15),
        "sparkle": Bus(-14, reverb=0.3, delay=0.15),
        "clock": Bus(-16, reverb=0.12),
        "brush": Bus(-20),
        "snap": Bus(-20, reverb=0.15),
        "buzz": Bus(-14, reverb=0.15),
    }, reverb_decay=1.5, reverb_tone=6000, delay_time=tr.beat * 2 / 3, delay_feedback=0.3)
    return finish(tr, mix), tr


SONGS = [
    Song("FireRope", "Dragon Temple Drums", 126, 8, 52, fire_rope),
    Song("HexMeltdown", "Molten Showdown", 124, 8, 56, hex_meltdown),
    Song("HoneyTrap", "Honeycomb Hush", 104, 8, 44, honey_trap),
]
