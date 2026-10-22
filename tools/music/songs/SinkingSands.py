"""Quicksand Caravan - the round track for SinkingSands (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum, tremolo


def sinking_sands():
    """Quicksand Caravan (120 bpm maqsum, D hijaz): the desert mesa round the sinkhole. An oud with the
    hook, a breathy ney, a darbuka (doum and tek), a riq, an upright bass and a zither's tremolo; a
    camel-ride B tune in G minor where the GOLDEN IDOL drops (about 23 s in), a darbuka break with
    the sand swirling, then the whole caravan up a tone (E hijaz) for the last 15 seconds."""
    tr = Track(bpm=120, bars=36)  # 2 s a bar: GO at bar 8 (16 s), the finale at bar 28 (40 s in)
    parts = plan(tr, [
        ("intro", 8, "D | D | D | D | Cm | D | Cm | D"),
        ("A", 8, "D | D | Cm | D | Gm | Eb | Cm | D"),
        ("B", 8, "Gm | Cm | F | Bb | Gm | Cm | Eb | D"),
        ("break", 4, "D | Eb | D | Eb"),
        ("finale", 8, "E | E | Dm | E | Am | F | Dm | E"),
    ])
    hook = melody("""D5:2 Eb5:2 F#5:4 G5:2 F#5:2 Eb5:2 D5:2 | A5:6 G5:2 F#5:4 r:4 | G5:2 A5:2 Bb5:4 A5:2 G5:2 F#5:2 G5:2 | A5:8 F#5:4 Eb5:4 |
                     Bb5:2 A5:2 G5:4 Bb5:2 C6:2 D6:4 | Eb6:4 D6:2 C6:2 Bb5:4 G5:4 | C6:2 Bb5:2 A5:2 G5:2 F#5:2 G5:2 A5:4 | Eb5:2 D5:10 r:4""")
    camel = melody("""D5:4 G5:4 Bb5:6 A5:2 | G5:4 Eb5:4 C5:8 | C5:2 D5:2 F5:4 A5:4 C6:4 | Bb5:12 r:4 |
                      D6:4 C6:2 Bb5:2 A5:4 G5:4 | Eb6:6 D6:2 C6:8 | Bb5:4 G5:4 Eb5:4 G5:4 | F#5:4 Eb5:4 D5:8""")
    taqsim = melody("r:16 | r:8 A4:4 Bb4:2 A4:2 | F#4:4 G4:2 F#4:2 Eb4:2 D4:6 | r:16")
    call = melody("A5:6 Bb5:2 A5:8 | F#5:4 Eb5:4 D5:8")
    swirl = melody("D5:1 Eb5:1 F#5:1 G5:1 A5:1 Bb5:1 C6:1 D6:1 C6:1 Bb5:1 A5:1 G5:1 F#5:1 Eb5:1 D5:2 | "
                   "Eb5:1 F#5:1 G5:1 A5:1 Bb5:1 C6:1 D6:1 Eb6:1 D6:1 C6:1 Bb5:1 A5:1 G5:1 F#5:1 Eb5:2")

    def ney(m, sec):
        return ins.flute(m, sec, breath=0.22, vibrato=0.1, fall=0.4 if sec > 1.2 else 0.0)

    def oud(m, sec, slide=0.0):
        return ins.oud(m, sec, slide=slide)

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.7, section=3)

    doum, doum_lo = ins.doum(92.0), ins.doum(78.0)
    teks = [ins.tek(1.0, v) for v in range(3)]
    ka = ins.tek(0.5)
    riq = [ins.jingles(0.18, 1.0, v) for v in range(3)]
    clap = s.clap()

    # The intro: wind over the mesa, a drone, the ney calling, the oud's taqsim, then the drums.
    tr.add("fx", 0, 0, ins.whoosh(tr.bar * 3, up=True), 0.7)
    tr.add("fx", 3, 0, ins.whoosh(tr.bar * 3, up=False), 0.5)
    tr.add("fx", 6, 0, s.riser(tr.bar * 2), 0.5)
    tr.play("lead", 1, call, ney, 0.3)
    tr.play("oud", 2, taqsim, lambda m, sec: oud(m, sec, slide=1.0 if sec > 0.5 else 0.0), 0.6)
    tr.play("lead", 5, call, ney, 0.45)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 38)  # D2..C#3 (73-139 Hz) on a round upright with strong 2nd harmonics
            notes = voicing(c, 57, 69, prev)
            prev = notes
            seconds = length * tr.step
            fifth = root + 7 if root + 7 <= 50 else root - 5
            # the drone / string pad
            if name == "intro" or name == "break":
                tr.add("pad", bar, step, ins.strings((root + 12, root + 19), seconds, attack=0.8, bright=0.25), 0.9 if name == "intro" else 1.0)
            elif name in ("B", "finale"):
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.3, bright=0.4), 1.0)
            elif name == "A":
                tr.add("pad", bar, step, ins.strings((root + 12, root + 19), seconds, attack=0.3, bright=0.3), 0.8)
            if name == "finale":
                tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "ah", attack=0.2), 1.0)
            # bass: the maqsum's doum notes (1, the and-of-2, 3)
            if name == "intro":
                if local >= 6:
                    for st in (0, 8):
                        tr.add("bass", bar, st, ins.upright(root, tr.step * 3), 0.8)
            elif name == "break":
                for st in (0, 6, 8):
                    tr.add("bass", bar, st, ins.upright(root, tr.step * 2), 1.0)
            else:
                for st, m in ((0, root), (6, root), (8, fifth), (12, root + 12 if root + 12 <= 52 else root), (14, fifth)):
                    tr.add("bass", bar, st, ins.upright(m, tr.step * 2), 1.0 if st in (0, 8) else 0.8)
            # the oud: a running ostinato under the A tune, strummed chords under B, tremolo in the finale
            ring = [notes[0] - 12, notes[0], notes[1], notes[2], notes[0] + 12]
            if name == "A" or (name == "intro" and local >= 4):
                for k, idx in enumerate((0, 2, 1, 3, 4, 3, 1, 2)):
                    tr.add("oud", bar, k * 2, oud(ring[idx], tr.step * 2), (1.0 if k % 4 == 0 else 0.75) * (0.7 if name == "intro" else 1.0), -0.3)
            elif name == "B":
                for st in (0, 3, 6, 10, 12):
                    strum(tr, "oud", bar, st, notes, oud, tr.step * 2.5, 1.0 if st in (0, 6) else 0.75, spread=0.015, down=st != 10, pan=-0.3)
            elif name == "break":
                for k in range(16):
                    tr.add("oud", bar, k, oud(ring[(0, 1, 0, 2, 0, 3, 0, 2)[k % 8]], tr.step * 1.2), 0.8 if k % 2 else 1.0, -0.3)
            elif name == "finale":
                for k, idx in enumerate((0, 2, 1, 3, 4, 3, 1, 2)):
                    tr.add("oud", bar, k * 2, oud(ring[idx], tr.step * 2), 1.0 if k % 4 == 0 else 0.8, -0.3)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.drum("darbuka", bar, "X.......X.......", doum, 0.5 + 0.1 * (local - 4))
                if local >= 5:
                    tr.drum("darbuka", bar, "..x...x.....x...", teks[local % 3], 0.4 + 0.1 * (local - 5), 0.15)
                if local >= 6:
                    tr.drum("riq", bar, "x.o.x.o.x.o.x.o.", riq[local % 3], 0.5 + 0.2 * (local - 6), 0.35)
                if local == 7:
                    for k in range(8, 16):
                        tr.add("darbuka", bar, k, teks[k % 3], 0.4 + 0.07 * (k - 8), 0.15)
                continue
            if name == "break":  # the darbuka takes a solo while the sand swirls
                tr.drum("darbuka", bar, "X.....X.X.......", doum, 1.0)
                tr.drum("darbuka", bar, ("..x.xx...x.x.xx." if local % 2 == 0 else "..x.x.xx..xxx.xx"), teks[local % 3], 0.85, 0.15)
                tr.drum("darbuka", bar, ".o.o...o.o.o.o..", ka, 0.6, -0.15)
                tr.drum("riq", bar, "x...x...x...x...", riq[local % 3], 0.8, 0.35)
                tr.add("fx", bar, 0, ins.whoosh(tr.bar, up=local % 2 == 0), 0.6, -0.5 + local * 0.33)
                if local == 3:
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.6)
                    for k in range(8, 16):
                        tr.add("darbuka", bar, k, doum_lo, 0.5 + 0.06 * (k - 8))
                continue
            big = name == "finale"
            tr.drum("darbuka", bar, "X.....X.X.......", doum, 1.0)
            tr.drum("darbuka", bar, "X.....x.........", doum_lo, 0.6)
            tr.drum("darbuka", bar, "..X...X.....X..." if not big else "..X.x.X...x.X.x.", teks[local % 3], 0.9, 0.15)
            tr.drum("darbuka", bar, ".o.o.o.o.o.o.o.o" if big else "....o......o..o.", ka, 0.6, -0.15)
            tr.drum("riq", bar, "x.o.x.o.x.o.x.o." if name == "A" else "x.xox.xox.xox.xo", riq[local % 3], 0.9, 0.35)
            tr.drum("clap", bar, "....x.......x..x" if big else "....x.......x...", clap, 0.9 if name != "A" else 0.7, -0.1)
            if local == 0:
                tr.add("fx", bar, 0, ins.gong(2.5, 147.0), 0.6)
            if local == part.bars - 1 and name in ("A", "B"):
                for k in range(12, 16):
                    tr.add("darbuka", bar, k, teks[k % 3], 0.7 + 0.05 * (k - 12), 0.15)

    # The GOLDEN IDOL (about 23 s into the round): a gong and a glittering zither run.
    tr.add("fx", 11, 8, ins.gong(3.0, 196.0), 0.8)
    for k, m in enumerate((70, 74, 77, 82, 86, 89, 94)):
        tr.add("kanun", 11, 8 + k * 0.5, ins.harp(m, 0.6, variant=k), 0.8, -0.3 + 0.1 * k)

    tr.play("hook", 8, hook, lambda m, sec: oud(m, sec, slide=0.6 if sec > 0.7 else 0.0))
    tr.play("lead2", 8, [n for n in hook if n.step >= 64], ney, 0.6, pan=0.25)
    tr.play("lead", 16, camel, ney)
    tr.play("lead2", 16, shift(camel, -12), oud, 0.7, pan=-0.2)
    tr.play("lead", 24, swirl, ney, 0.9)
    tr.play("lead", 26, swirl, ney, 1.0)
    tr.play("lead", 28, shift(hook, 2), ney, 1.05)
    tr.play("lead2", 28, shift(hook, 2 - 12), oud, 0.8, pan=-0.2)
    tr.play("horns", 28, [n for n in shift(hook, 2 - 12) if n.length >= 4], horn, 0.9, pan=0.2)
    tremolo(tr, "kanun", 28, shift(hook, 2 + 12), ins.koto, 1, 0.45, pan=0.35)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.22, delay=0.08),
        "hook": Bus(-5, reverb=0.18, delay=0.1),
        "lead2": Bus(-14, reverb=0.2),
        "horns": Bus(-14, reverb=0.25),
        "oud": Bus(-11, reverb=0.15),
        "kanun": Bus(-17, reverb=0.25, delay=0.1),
        "pad": Bus(-16, reverb=0.3),
        "choir": Bus(-17, reverb=0.35),
        "bass": Bus(-9),
        "darbuka": Bus(-10, drive=1.3, reverb=0.12),
        "riq": Bus(-19, reverb=0.08),
        "clap": Bus(-17, reverb=0.15),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=1.8, reverb_tone=5500, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("SinkingSands", "Quicksand Caravan", 120, 8, 36, sinking_sands)
