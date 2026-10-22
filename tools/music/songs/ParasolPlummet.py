"""Coins From the Clouds - the round track for ParasolPlummet (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import numpy as np

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum


def parasol_plummet():
    """Coins From the Clouds (120 bpm, A major): sunshine pop for drifting down a blue sky under an
    umbrella. A whistled tune over ukulele, upright bass, vibes and handclaps; coins glint on the
    glockenspiel and slide whistles drop and float. A dreamier B section floats on vibes, then the
    COIN RUSH (the last 7 s; it starts 28 s in, bar 14 of the round) jumps up to B major with a
    trumpet section, double-time drums and a shower of coins, and lands on one big chord that rings
    back into the intro."""
    tr = Track(bpm=120, bars=25)
    parts = plan(tr, [
        ("intro", 7, "Amaj7 | Amaj7 | Dmaj7 | Dmaj7 | C#m7 | Bm7 | E7sus4 E7"),
        ("A", 8, "Amaj7 | Dmaj7 | C#m7 F#m7 | Bm7 E7 | Amaj7 | Dmaj7 | Bm7 E7 | A"),
        ("B", 6, "Dmaj7 | E | C#m7 | F#m7 | Bm7 | E7sus4 E7"),
        ("rush", 4, "B | E | C#m7 F#7 | B"),
    ])
    hook = melody("""E5:3 C#5:1 E5:4 A5:6 G#5:2 | F#5:4 A5:4 E5:8 | r:2 E5:2 G#5:2 B5:2 A5:4 F#5:4 | D5:3 C#5:1 B4:4 G#4:8 |
                     E5:3 C#5:1 E5:4 A5:6 B5:2 | C#6:4 A5:4 F#5:8 | D6:3 C#6:1 B5:4 G#5:2 A5:2 B5:4 | A5:12 r:4""")
    float_tune = melody("""F#5:8 A5:4 C#6:4 | B5:12 G#5:4 | E5:4 G#5:4 B5:4 E6:4 | C#6:12 A5:4 |
                           D6:4 C#6:4 B5:4 A5:4 | B5:8 G#5:4 E5:2 D#5:2""")
    rush = melody("""F#5:2 B5:2 D#6:2 F#6:2 E6:2 D#6:2 C#6:2 B5:2 | G#5:2 B5:2 E6:2 G#6:2 F#6:2 E6:2 D#6:2 C#6:2 |
                     E6:2 C#6:2 G#5:2 E5:2 F#5:2 A#5:2 C#6:2 E6:2 | D#6:4 B5:12""")
    intro_tune = melody("r:16 | r:16 | r:4 E5:3 C#5:1 E5:4 A5:4 | F#5:16 | E5:3 C#5:1 E5:4 G#5:4 B5:4 | A5:8 F#5:8 | E5:16")
    vibe_line = melody("C#6:8 E6:8 | D6:8 F#6:8 | B5:16 | A5:8 G#5:8 | C#6:8 E6:8 | F#6:16 | D6:8 G#5:8 | A5:16")

    def trumpets(m, sec):
        return ins.brass(m, sec, bright=1.0, section=3)

    def coin(bar, step, gain, pan, high=0):
        tr.add("coins", bar, step, ins.glock(83 + high, 0.08), gain, pan)
        tr.add("coins", bar, step + 0.75, ins.glock(88 + high, 0.3), gain, pan)

    kick, clap, shake = s.kick(0.7, 0.35), s.clap(), s.shaker()
    tamb = [ins.jingles(0.16, 0.8, v) for v in range(3)]
    bonk = ins.log_drum(260.0, 0.25)
    rng = np.random.default_rng(31)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 40)
            notes = voicing(c, 59, 74, prev, size=4)
            prev = notes
            seconds = length * tr.step
            fifth = root + 7 if root + 7 <= 52 else root - 5
            # vibes: soft sustained chords (intro and B), stabs elsewhere
            if name == "intro" or name == "B":
                tr.add("vibes", bar, step, ins.vibes(notes[0] + 12, seconds), 0.6, -0.2)
                for i, m in enumerate(notes[1:]):
                    tr.add("vibes", bar, step + 0.4 * (i + 1), ins.vibes(m + 12 if name == "B" else m, seconds), 0.4 if name == "B" else 0.55, 0.2 * i)
            # ukulele: a bright down-down-up strum (from bar 2 of the intro)
            if name != "intro" or local >= 2:
                pattern = ((0, True), (4, True), (6, False), (10, False), (12, True), (14, False))
                if name == "rush":
                    pattern = tuple((k, k % 4 == 0) for k in range(0, 16, 2))
                for st, down in pattern:
                    if st < length:
                        g = 0.55 if name == "intro" else 1.0
                        strum(tr, "uke", bar, step + st, notes, lambda m, sec: ins.nylon(m, sec, variant=st), tr.step * 1.8, g * (1.0 if down else 0.75), spread=0.008, down=down, pan=0.25)
            # upright bass: root, fifth, a pickup into the next chord
            if name == "intro" and local >= 4:
                tr.add("bass", bar, step, ins.upright(root, seconds * 0.5), 0.7)
            elif name in ("A", "B"):
                tr.add("bass", bar, step, ins.upright(root, tr.step * 5), 1.0)
                if length >= 16:
                    tr.add("bass", bar, step + 6, ins.upright(fifth, tr.step * 2), 0.75)
                    tr.add("bass", bar, step + 8, ins.upright(fifth, tr.step * 5), 0.9)
                    tr.add("bass", bar, step + 14, ins.upright(root + 2 if name == "A" else root - 1, tr.step * 2), 0.7)
                else:
                    tr.add("bass", bar, step + 6, ins.upright(fifth, tr.step * 2), 0.8)
            elif name == "rush":
                if local < 3:
                    for k in range(0, int(length), 2):
                        tr.add("bass", bar, step + k, ins.upright(root if k % 4 == 0 else (fifth if k % 8 == 2 else root + 12), tr.step * 1.8), 1.0 if k % 4 == 0 else 0.8)
                else:
                    tr.add("bass", bar, 0, ins.upright(root, tr.step * 14), 1.1)
            if name == "rush":
                tr.add("pad", bar, step, ins.strings(tuple(n + 12 for n in notes), seconds if local < 3 else tr.bar * 1.0, attack=0.05, bright=0.7, release=1.0 if local < 3 else 2.0), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local == 0:
                    tr.add("fx", bar, 0, ins.whoosh(tr.bar * 2, True), 0.35)
                if local >= 3:
                    tr.drum("perc", bar, "x.x.x.x.x.x.x.x.", shake, 0.4 + 0.08 * (local - 3), 0.35)
                if local >= 5:
                    tr.drum("claps", bar, "....x.......x...", clap, 0.4 + 0.15 * (local - 5), 0.05)
                    tr.kick("kick", bar, "X.......X.......", kick, 0.5)
                if local == 6:
                    tr.add("fx", bar, 0, ins.slide_whistle(67, 91, tr.bar * 0.9), 0.8, -0.2)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.4)
                    for k in range(8, 16, 2):
                        tr.add("claps", bar, k, clap, 0.5 + 0.06 * k)
                if local in (1, 3):
                    coin(bar, 10, 0.6, 0.4)
                continue
            if name == "rush":
                if local < 3:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
                    tr.drum("claps", bar, "....X.......X...", clap, 1.0, 0.05)
                    tr.drum("perc", bar, "xxxxxxxxxxxxxxxx", shake, 0.8, 0.35)
                    tr.drum("perc", bar, "..x...x...x...x.", tamb[local % 3], 0.9, -0.35)
                    tr.drum("perc", bar, "x..x..x...x..x..", ins.cowbell(0.2), 0.45, 0.2)
                    tr.drum("toms", bar, "............xxxx" if local == 2 else "..............xx", ins.tom(180.0, 0.3), 0.8, -0.2)
                    for k in range(0, 16, 2):  # a shower of coins
                        if rng.random() < 0.75:
                            coin(bar, k + rng.choice((0, 1)), 0.55 + 0.3 * rng.random(), rng.uniform(-0.7, 0.7), rng.choice((0, 2, 4, 7)))
                    if local == 0:
                        tr.add("cymbal", bar, 0, s.crash(2.5), 1.6, 0.2)
                        tr.add("fx", bar, 0, ins.orchestra_hit((71, 75, 78, 83)), 0.8)
                else:  # the final chord
                    tr.kick("kick", bar, "X...............", kick, 1.0)
                    tr.add("cymbal", bar, 0, s.crash(3.0), 1.8, 0.0)
                    tr.add("fx", bar, 0, ins.orchestra_hit((71, 75, 78, 83), 0.9), 1.0)
                    for k, m in enumerate((95, 91, 88, 83, 79, 76, 71)):
                        tr.add("coins", bar, 4 + k, ins.glock(m, 0.4), 0.5, 0.6 - 0.2 * k)
                    tr.add("fx", bar, 8, ins.slide_whistle(84, 64, tr.bar * 0.45), 0.6, 0.3)
                continue
            tr.kick("kick", bar, "X.....x...X....." if name == "A" else "X.........X.....", kick, 0.9)
            tr.drum("claps", bar, "....X.......X...", clap, 0.9 if name == "A" else 0.5, 0.05)
            tr.drum("perc", bar, "x.xxx.xxx.xxx.xx", shake, 0.7, 0.35)
            if name == "A":
                tr.drum("perc", bar, "..x...x...x...x.", tamb[local % 3], 0.6, -0.35)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(2.0), 1.0, 0.2)
            # coins tossed across, now and then; a hammer's bonk at the end of a phrase
            for k in (6, 13) if name == "A" else (10,):
                if rng.random() < 0.6:
                    coin(bar, k, 0.6, rng.uniform(-0.6, 0.6), rng.choice((0, 2, 4)))
            if name == "A" and local in (3, 7):
                tr.add("perc", bar, 14, bonk, 0.8, -0.2)
                tr.add("perc", bar, 15, ins.log_drum(200.0, 0.3), 0.8, -0.2)
            if name == "B" and local % 2 == 1:
                tr.add("fx", bar, 8, ins.slide_whistle(86, 72, tr.bar * 0.4), 0.45, 0.4)
            if name == "B" and local == 5:
                tr.add("fx", bar, 0, s.riser(tr.bar), 0.55)
                for k in range(8, 16):
                    tr.add("claps", bar, k, clap, 0.4 + 0.07 * (k - 8))

    tr.play("lead", 0, intro_tune, ins.whistle, 0.6)
    tr.play("lead", 7, hook, ins.whistle)
    tr.play("lead2", 7, [n for n in shift(hook, -12) if n.step >= 64], ins.vibes, 0.7)
    tr.play("vibes", 7, vibe_line, ins.vibes, 0.45)
    tr.play("lead", 15, float_tune, ins.whistle, 0.75)
    tr.play("lead2", 15, shift(float_tune, -12), lambda m, sec: ins.flute(m, sec, breath=0.05), 0.5)
    tr.play("lead", 21, rush, trumpets, 1.7)
    tr.play("lead2", 21, shift(rush, -12), trumpets, 1.3, pan=-0.2)
    tr.play("whistle", 21, shift(rush, 12)[:-1], ins.whistle, 0.8, pan=0.2)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.18, delay=0.08),
        "lead2": Bus(-13, reverb=0.2),
        "whistle": Bus(-15, reverb=0.2),
        "vibes": Bus(-14, reverb=0.25),
        "uke": Bus(-11, reverb=0.12),
        "bass": Bus(-9),
        "pad": Bus(-15, reverb=0.25),
        "coins": Bus(-17, reverb=0.25, delay=0.15),
        "kick": Bus(-12, drive=1.3),
        "claps": Bus(-14, reverb=0.15),
        "toms": Bus(-16, reverb=0.15),
        "perc": Bus(-18),
        "cymbal": Bus(-20, reverb=0.1),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=1.5, reverb_tone=6500, delay_time=tr.beat * 0.75, delay_feedback=0.3, pump_release=0.15)
    return finish(tr, mix), tr


SONG = Song("ParasolPlummet", "Coins From the Clouds", 120, 7, 25, parasol_plummet)
