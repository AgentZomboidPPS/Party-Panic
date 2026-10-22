"""Archer's Jig - the round track for ArrowAmbush (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum


def arrow_ambush():
    """Archer's Jig (126 bpm, 6/8 jig, D major): a castle tournament, archers on the tower, runners
    dodging between the target boards. The heralds' trumpets and a field drum open it; a fife takes
    the jig over a lute and a tambourine; the B tune is the lute's, in B minor; for the last 15
    seconds the trumpets play a fanfare against the jig, with timpani and arrows whizzing by."""
    tr = Track(bpm=126, bars=32, spb=12)  # 1.905 s a bar: GO at bar 8 (15.2 s), the finale at bar 24 (30.5 s in)
    parts = plan(tr, [
        ("intro", 8, "D | D | D | D | D | G | A | A7"),
        ("A", 8, "D | G | D | A | D | G | A | D"),
        ("B", 8, "Bm | G | D | A | Bm | Em | G | A7"),
        ("finale", 8, "D | G | D | A | D | G | A | D"),
    ])
    jig = melody("""A4:1 D5:1 F#5:1 A5:2 F#5:1 D5:1 F#5:1 A5:1 D6:2 A5:1 | B5:2 G5:1 D5:2 G5:1 B5:1 A5:1 G5:1 F#5:2 E5:1 |
                    F#5:1 A5:1 D6:1 C#6:2 B5:1 A5:2 F#5:1 D5:2 F#5:1 | E5:2 C#5:1 A4:2 C#5:1 E5:3 A5:3 |
                    A4:1 D5:1 F#5:1 A5:2 F#5:1 D5:1 F#5:1 A5:1 D6:2 E6:1 | F#6:2 E6:1 D6:2 B5:1 G5:2 B5:1 D6:2 B5:1 |
                    A5:2 F#5:1 E5:2 C#5:1 E5:1 F#5:1 G5:1 A5:2 C#6:1 | D6:3 A5:3 D5:3 r:3""", 12)
    lute_tune = melody("""F#5:3 B5:3 D6:2 C#6:1 B5:3 | G5:3 B5:3 D6:6 | A5:2 F#5:1 D5:3 F#5:2 A5:1 D6:3 | C#6:6 E6:6 |
                          D6:2 C#6:1 B5:3 F#5:2 B5:1 D6:3 | E6:2 D6:1 B5:3 G5:3 E5:3 | B5:3 D6:3 G6:3 F#6:3 | E6:3 C#6:3 A5:3 G5:3""", 12)
    fanfare = melody("D4:6 F#4:3 A4:3 | B4:6 D5:6 | A4:6 F#4:6 | E4:3 A4:3 C#5:6 | D5:6 A4:3 F#4:3 | G4:3 B4:3 D5:6 | C#5:6 E5:6 | D5:9 r:3", 12)
    herald = melody("A4:2 A4:1 D5:3 A4:2 D5:1 F#5:3 | A5:9 r:3", 12)
    herald2 = melody("A4:2 A4:1 E5:3 A4:2 C#5:1 E5:3 | A5:6 G5:3 r:3", 12)

    def fife(m, sec):
        return ins.flute(m, sec, breath=0.06, vibrato=0.05)

    def trumpets(m, sec):
        return ins.brass(m, sec, bright=1.0, section=3, vibrato=0.06)

    drum = ins.snare2(260.0, 0.7, 0.2)
    roll = ins.snare2(260.0, 0.5, 0.12, variant=1)
    boom = ins.tom(85.0, 0.5)
    tom_hi = ins.tom(150.0, 0.3)
    tamb = [ins.jingles(0.15, 0.9, v) for v in range(3)]
    kick = s.kick(0.8, 0.35)

    def arrow(bar, step, pan):
        """An arrow: a whizz past and a thunk into a target board."""
        tr.add("fx", bar, step, ins.whoosh(0.35, up=False), 0.6, pan)
        tr.add("fx", bar, step + 2, ins.woodblock(420.0, 0.1), 0.8, pan)

    # The intro: heralds far off on the battlements, a field drum, the lute, then the fife.
    tr.play("brass", 0, herald, trumpets, 0.45)
    tr.play("brass", 2, herald, trumpets, 0.6)
    tr.play("brass", 6, herald2, trumpets, 0.8)
    tr.add("fx", 6, 0, s.riser(tr.bar * 2), 0.45)
    tr.play("lead", 4, [n for n in jig if n.step < 24], fife, 0.55)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 38)  # D2..C#3 on a plucked bass, with a strong second harmonic
            notes = voicing(c, 59, 71, prev)
            prev = notes
            seconds = length * tr.step
            fifth = root + 7 if root + 7 <= 50 else root - 5
            if name == "intro":
                if local >= 4:
                    for st in (0, 6):
                        strum(tr, "lute", bar, st, notes, ins.lute, tr.step * 5, 0.6 + 0.08 * (local - 4), spread=0.02, pan=-0.3)
                if local >= 5:
                    tr.add("bass", bar, 0, ins.upright(root, tr.step * 5), 0.7)
                    tr.add("bass", bar, 6, ins.upright(fifth, tr.step * 5), 0.6)
                continue
            # bass: a jig's "oom - pa" on each dotted beat
            for st, m in ((0, root), (3, fifth), (6, root), (9, fifth)):
                tr.add("bass", bar, st, ins.upright(m, tr.step * 2.5), 1.0 if st % 6 == 0 else 0.8)
            # lute: the jig's strum (down-up-down on every dotted beat) or the B tune's broken chords
            if name in ("A", "finale"):
                for st in (0, 2, 3, 5, 6, 8, 9, 11):
                    strum(tr, "lute", bar, st, notes, ins.lute, tr.step * 1.4, 1.0 if st % 3 == 0 else 0.7, spread=0.012, down=st % 3 == 0, pan=-0.3)
            else:
                ring = notes + [notes[0] + 12]
                for k in range(12):
                    tr.add("lute", bar, k, ins.lute(ring[(0, 1, 2, 3, 2, 1)[k % 6]], tr.step * 1.5, variant=k), 0.85 if k % 3 == 0 else 0.6, -0.3)
                tr.add("pad", bar, step, ins.strings(tuple(n - 12 for n in notes), seconds, attack=0.4, bright=0.35), 1.0)
            if name == "finale":
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.15, bright=0.5), 1.2)
                tr.add("timp", bar, 0, ins.timpani(root, 1.2), 0.9)
                tr.add("timp", bar, 6, ins.timpani(fifth, 1.0), 0.7)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 2:  # the field drum: a roll that swells, then the march beat
                    if local < 4:
                        for k in range(12):
                            tr.add("drums", bar, k, roll, 0.15 + 0.03 * k + 0.2 * (local - 2), 0.1)
                    else:
                        tr.drum("drums", bar, "x.xx.xx.xx.x", drum, 0.5 + 0.08 * (local - 4), 0.1)
                if local >= 4:
                    tr.drum("toms", bar, "X.....X.....", boom, 0.6 + 0.08 * (local - 4))
                if local >= 6:
                    tr.drum("tamb", bar, "x..x..x..x..", tamb[local % 3], 0.5 + 0.2 * (local - 6), 0.4)
                if local == 7:
                    for k in range(6, 12):
                        tr.add("drums", bar, k, drum, 0.55 + 0.08 * (k - 6), 0.1)
                continue
            big = name == "finale"
            tr.kick("kick", bar, "X.....X.....", kick, 0.8 if not big else 1.0)
            tr.drum("toms", bar, "X.....X....." if name != "B" else "X...........", boom, 0.9)
            tr.drum("drums", bar, "x.xx.xx.xx.x" if name != "B" else "...x.....x..", drum, 0.85 if not big else 1.0, 0.1)
            if big:
                tr.drum("drums", bar, "...X.....X..", s.clap(), 0.8, -0.1)
                tr.drum("toms", bar, "..x..x..x..x", tom_hi, 0.45, 0.3)
            tr.drum("tamb", bar, "x.xx.xx.xx.x" if name != "B" else "x..x..x..x..", tamb[local % 3], 0.8, 0.4)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.3, 0.2)
            if local == part.bars - 1 and name in ("A", "B"):
                for k in range(6, 12):
                    tr.add("drums", bar, k, drum, 0.6 + 0.06 * (k - 6), 0.1)
            if name == "B" and local == 7:
                tr.add("fx", bar, 0, s.riser(tr.bar), 0.5)

    for bar, step, pan in ((9, 4, 0.5), (12, 10, -0.5), (15, 4, 0.4), (25, 4, -0.5), (27, 10, 0.5), (29, 4, -0.4), (30, 10, 0.4)):
        arrow(bar, step, pan)

    tr.play("lead", 8, jig, fife)
    tr.play("lead2", 8, [n for n in shift(jig, -12) if n.step >= 48], ins.lute, 0.6, pan=0.3)
    tr.play("lead", 16, lute_tune, lambda m, sec: ins.flute(m, sec, breath=0.1, vibrato=0.1), 0.85)
    tr.play("lead2", 16, shift(lute_tune, -12), ins.lute, 0.9, pan=0.3)
    tr.play("lead", 24, jig, fife, 1.1)
    tr.play("lead2", 24, shift(jig, -12), ins.lute, 0.8, pan=0.3)
    tr.play("brass", 24, fanfare, trumpets, 1.0, pan=-0.2)
    tr.play("brass", 24, shift(fanfare, 12), trumpets, 0.5, pan=0.2)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.22),
        "lead2": Bus(-15, reverb=0.2),
        "brass": Bus(-10, reverb=0.3),
        "lute": Bus(-12, reverb=0.18),
        "pad": Bus(-18, reverb=0.3),
        "bass": Bus(-10),
        "kick": Bus(-14, drive=1.3),
        "toms": Bus(-12, reverb=0.15),
        "timp": Bus(-14, reverb=0.25),
        "drums": Bus(-12, reverb=0.15),
        "tamb": Bus(-19, reverb=0.1),
        "cymbal": Bus(-20, reverb=0.15),
        "fx": Bus(-16, reverb=0.25),
    }, reverb_decay=2.0, reverb_tone=5500, delay_time=tr.beat * 0.5, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("ArrowAmbush", "Archer's Jig", 126, 8, 32, arrow_ambush)
