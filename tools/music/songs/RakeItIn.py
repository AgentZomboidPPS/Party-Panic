"""Harvest Hoedown - the round track for RakeItIn (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import numpy as np

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum

# 22 bars after GO land exactly on the GOLDEN RUSH (70% of the 55 s round = 38.5 s).
BPM = 240 * 22 / 38.5


def rake_it_in():
    """Harvest Hoedown (137 bpm, G major): the farm field round the red silo. A bluegrass barn band
    (banjo rolls over the banjo's high G drone, a fiddle with the hook, harmonica, upright bass,
    guitar chop, washboard and stomps) wakes up with a fiddle rooster; the harmonica takes the
    bridge, and the GOLDEN RUSH kicks it up to A major with pumpkins raining down on a glockenspiel."""
    tr = Track(bpm=BPM, bars=40)
    parts = plan(tr, [
        ("intro", 8, "G | G | G | G | C | G | D | D7"),
        ("A1", 8, "G | G | C | C | G | Em | A7 D7 | G"),
        ("A2", 8, "G | G | C | C | G | Em | A7 D7 | G"),
        ("B", 6, "C | G | Em | D | C | E7"),
        ("rush", 10, "A | A | D | D | A | F#m | B7 E7 | A | A D | D7"),
    ])
    hook = melody("""r:2 D5:2 G5:3 A5:1 B5:4 G5:2 D5:2 | E5:2 G5:2 D5:4 B4:2 A4:2 G4:4 |
                     C5:2 E5:2 G5:3 A5:1 G5:2 E5:2 C5:2 E5:2 | D5:4 E5:2 C5:2 A4:4 B4:2 C5:2 |
                     r:2 D5:2 G5:3 A5:1 B5:4 D6:4 | E6:3 D6:1 B5:2 G5:2 E5:4 G5:4 |
                     E5:2 A5:2 C#6:2 A5:2 C6:2 A5:2 F#5:2 D5:2 | G5:3 D5:1 B4:2 G4:2 G5:4! r:4""")
    counter = melody("""B4:16 | D5:8 B4:8 | E5:16 | C5:8 E5:8 | D5:16 | G5:8 E5:8 | C#5:8 C5:8 | B4:12 r:4""")
    bridge = melody("""E5:6 G5:2 C6:8 | B5:4 A5:2 G5:2 D5:8 | E5:4 G5:4 B5:6 A5:2 |
                       A5:4 F#5:2 E5:2 D5:8 | E5:4 G5:4 C6:4 E6:4 | D6:4 B5:4 G#5:4 E5:4""")
    fills = melody("""r:10 G5:1 A5:1 G5:1 E5:1 C5:2 | r:10 B5:1 A5:1 G5:1 F#5:1 D5:2 | r:16 |
                      r:10 D5:1 E5:1 F#5:1 A5:1 D6:2 | r:16 | r:16""")
    tag = melody("A5:4 C#6:2 A5:2 F#5:4 A5:4 | C6:4 A5:2 F#5:2 D6:4! B4:1 C5:1 C#5:1 D5:1")
    kickoff = melody("r:8 D4:1 E4:1 F#4:1 G4:1 A4:1 B4:1 C5:1 C#5:1")

    def fid(m, sec):
        return ins.fiddle(m, sec)

    def harp(m, sec):
        return ins.harmonica(m, sec, bend_from=0.5 if sec > 0.3 else 0.0, wah=0.6 if sec > 0.5 else 0.0)

    stomp, clap, tam = s.kick(0.7, 0.3), s.clap(0.25), ins.jingles(0.16)
    snare = ins.snare2(210.0, 0.5, 0.2)
    rub = ins.washboard(0.06)

    # the rooster, played on the fiddle, and a sleepy first banjo roll
    for step, m, sec, glide in ((0, 74, 0.14, None), (2, 79, 0.14, 74.0), (4, 83, 0.55, 79.0), (10, 79, 0.7, 84.0)):
        tr.add("lead", 1, step, ins.fiddle(m, sec, glide_from=glide), 0.4)
    tr.play("lead", 7, kickoff, fid, 0.8)
    tr.add("fx", 7, 8, ins.slide_whistle(62.0, 86.0, tr.step * 8), 0.45, 0.3)

    rng = np.random.default_rng(38)
    prev = None
    for part in parts:
        name = part.name
        drone = 69 if name == "rush" else 67  # the banjo's short fifth string (capoed up for the rush)
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 33)
            fifth = root + 7 if root + 7 <= 45 else root - 5
            notes = voicing(c, 55, 67, prev, size=3)
            prev = notes
            # banjo forward rolls: two fingers and the thumb on the drone, 16ths
            ring = notes + [drone]
            order = (1, 2, 3, 0, 1, 3, 0, 2)
            k0 = int(step)
            soft = name == "intro"
            last = name == "rush" and local == part.bars - 1
            for k in range(k0, k0 + int(length)):
                if last and k >= 9:
                    break  # the band stops on the final hit; the fiddle alone leads back to the top
                g = (1.0 if k % 4 == 0 else 0.75) * ((0.3 + 0.1 * local) if soft else (0.8 if name == "B" else 1.0))
                tr.add("banjo", bar, k, ins.banjo(ring[order[k % 8]], tr.step * 2.5, variant=k % 3), g, 0.25)
            # upright bass, boom on 1 and 3 (a walk up into the next chord in the rush)
            if name != "intro" or local >= 2:
                g = 1.0 if name != "intro" else 0.5 + 0.08 * local
                for st in range(0, int(length), 8):
                    tr.add("bass", bar, step + st, ins.upright(root if st == 0 else fifth, tr.step * 6), g)
                if name == "rush" and length == 16:
                    tr.add("bass", bar, 6, ins.upright(root + 4 if "m" not in c.name else root + 3, tr.step * 2), 0.7)
                    tr.add("bass", bar, 14, ins.upright(fifth + 2 if fifth + 2 <= 46 else fifth - 1, tr.step * 2), 0.7)
            # guitar chop on the off-beats (2 and 4)
            if name != "intro" or local >= 4:
                chord = voicing(c, 60, 72, None, size=3)
                for st in range(4, 8 if last else int(length), 8):
                    strum(tr, "chop", bar, step + st, chord, ins.acoustic_guitar, tr.step * 1.2,
                          1.0 if name != "intro" else 0.6, spread=0.006, down=st % 16 == 4, pan=-0.3)
            if name == "B":
                tr.add("pad", bar, step, ins.accordion(tuple(voicing(c, 57, 69, None)), length * tr.step), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.drum("wash", bar, "x.x.x.x.x.x.x.x.", rub, 0.4 + 0.1 * (local - 4), 0.2)
                if local >= 6:
                    tr.kick("kick", bar, "X.......X.......", stomp, 0.6 + 0.2 * (local - 6))
                    tr.drum("snare", bar, "....x.......x...", snare, 0.7)
                if local == 7:
                    tr.drum("snare", bar, "........x.x.xxxx", snare, 0.8)
                continue
            rush = name == "rush"
            if rush and local == part.bars - 1:  # the stop: two hits, then the fiddle's pickup
                tr.kick("kick", bar, "X.......X.......", stomp, 1.0)
                tr.drum("snare", bar, "....X...X.......", snare, 0.9)
                tr.drum("clap", bar, "....X...X.......", clap, 1.0, 0.1)
                tr.drum("wash", bar, "XxxxXxxxX.......", rub, 0.9, 0.2)
                tr.add("cymbal", bar, 8, s.crash(1.4), 0.7, 0.25)
                continue
            tr.kick("kick", bar, "X.......X.......", stomp, 1.0)
            tr.drum("snare", bar, "....X.......X...", snare, 0.9)
            tr.drum("wash", bar, "xoxoxoxoxoxoxoxo" if not rush else "XxxxXxxxXxxxXxxx", rub, 0.9, 0.2)
            if name in ("A2", "rush"):
                tr.drum("perc", bar, "..x...x...x...x." if name == "A2" else "x.x.x.x.x.x.x.x.", tam, 0.8, -0.3)
            if rush:
                tr.drum("clap", bar, "....X.......X...", clap, 1.0, 0.1)
                if local % 4 == 0:
                    tr.add("cymbal", bar, 0, s.crash(), 1.0, 0.25)
                # pumpkins raining down: a falling glockenspiel scatter in A major pentatonic
                pent = [69, 71, 73, 76, 78, 81, 83, 85, 88]
                top = int(rng.integers(5, 9))
                for j, st in enumerate((8, 9, 10, 11, 12, 13)):
                    tr.add("sparkle", bar, st, ins.glock(pent[max(0, top - j)] + 12, 0.3), 0.5 + 0.08 * j, 0.4 - 0.15 * j)
            if name == "A2" and local % 2 == 1:
                tr.add("fx", bar, 14, ins.jaw_harp(55 if local % 4 == 1 else 50, 0.35), 0.6, -0.4)
            if local == 0 and name in ("A1", "B"):
                tr.add("cymbal", bar, 0, s.crash(), 0.8, 0.25)
            if local == part.bars - 1 and name in ("A2", "B"):
                tr.drum("snare", bar, "........x.x.xxxx", snare, 0.8)
            if name == "B" and local == part.bars - 1:
                tr.add("fx", bar, 4, ins.slide_whistle(64.0, 90.0, tr.step * 12), 0.4, 0.3)

    tr.play("lead", 8, hook, fid)
    tr.play("lead", 16, hook, harp)
    tr.play("counter", 16, counter, fid, pan=-0.2)
    tr.play("lead", 24, bridge, harp)
    tr.play("counter", 24, fills, fid, pan=0.2)
    tr.play("lead", 30, shift(hook, 2), fid)
    tr.play("lead2", 30, shift(hook, 2 - 12), harp, pan=-0.15)
    tr.play("lead2", 30, shift(hook, 2 + 12), lambda m, sec: ins.banjo(m, min(sec, 0.4)), 0.7, pan=0.3)
    tr.play("lead", 38, tag, fid)
    tr.play("lead2", 38, shift(tag, -12), harp, pan=-0.15)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.15, delay=0.05),
        "lead2": Bus(-12, reverb=0.15),
        "counter": Bus(-12, reverb=0.18),
        "banjo": Bus(-10, reverb=0.1),
        "chop": Bus(-15, reverb=0.08),
        "pad": Bus(-16, reverb=0.2),
        "bass": Bus(-8),
        "kick": Bus(-11, drive=1.3),
        "snare": Bus(-15, reverb=0.12),
        "clap": Bus(-15, reverb=0.12),
        "wash": Bus(-17),
        "perc": Bus(-19),
        "cymbal": Bus(-20, reverb=0.1),
        "sparkle": Bus(-15, reverb=0.25, delay=0.15),
        "fx": Bus(-15, reverb=0.2),
    }, reverb_decay=1.3, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("RakeItIn", "Harvest Hoedown", round(BPM, 2), 8, 40, rake_it_in)
