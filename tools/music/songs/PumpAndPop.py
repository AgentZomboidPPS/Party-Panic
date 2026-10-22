"""Balloon Bandstand - the round track for PumpAndPop (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum


def pump_and_pop():
    """Balloon Bandstand (140 bpm circus march, C major): the striped bandshell at the fair, teams
    pumping their balloons. A steam calliope with a chromatic, bouncy tune over a tuba's oom-pah, a
    snare and a bass drum; slide whistles inflate between the phrases; the trio (F major) gives the
    tune to a clarinet and a glockenspiel; for the last 14 seconds the whole bandstand goes up to D
    with trumpets and a piccolo, and the loop ends with a pop and a balloon flying off deflating."""
    tr = Track(bpm=140, bars=32)  # 1.714 s a bar: GO at bar 8 (13.7 s), the finale at bar 24 (27.4 s in)
    parts = plan(tr, [
        ("intro", 8, "C | C | G7 | C | G7 | C | C | G7"),
        ("A", 8, "C | C | G7 | C | F | C | G7 | C"),
        ("B", 8, "F | Bb | C7 | F | Dm | Bb | G7 | A7"),
        ("finale", 8, "D | D | A7 | D | G | D | A7 | D"),
    ])
    march = melody("""E5:2 F5:2 G5:4 E5:2 C5:2 E5:4 | G5:2 Ab5:2 A5:2 C6:2 E6:4 C6:4 | D6:2 C6:2 B5:2 A5:2 G5:4 F5:4 | E5:2 D#5:2 E5:2 G5:2 C6:8 |
                      A5:2 G#5:2 A5:2 C6:2 F6:4 C6:4 | G5:2 F#5:2 G5:2 C6:2 E6:4 G5:4 | F5:2 E5:2 D5:2 G5:2 B5:2 D6:2 F6:4 | E6:4 C6:4 C5:4 r:4""")
    trio = melody("""C5:4 F5:4 A5:6 G5:2 | F5:4 D5:4 Bb4:8 | G5:4 Bb5:4 E5:6 F5:2 | A5:12 r:4 |
                     D6:4 C6:2 A5:2 F5:4 D5:4 | D6:4 Bb5:4 F5:8 | B5:4 D6:4 F6:4 D6:4 | C#6:4 E6:4 G6:4 A6:4""")
    piccolo = melody("""r:8 F#6:2 G6:2 A6:4 | r:8 A6:2 B6:2 D7:4 | r:8 E6:2 F#6:2 G6:4 | F#6:2 G6:2 F#6:2 E6:2 D6:8 |
                        r:8 B6:2 C#7:2 D7:4 | r:8 F#6:2 G6:2 A6:4 | r:8 G6:2 F#6:2 E6:4 | r:16""")
    vamp = melody("E5:4 G5:4 C6:8 | D5:4 F5:4 B5:8")

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.9, section=3)

    def piccolo_voice(m, sec):
        return ins.flute(m, sec, breath=0.04, vibrato=0.08)

    snare = ins.snare2(240.0, 0.9, 0.2)
    bass_drum = ins.tom(70.0, 0.45)
    cym = ins.splash(0.6)
    block = ins.woodblock(900.0)

    def inflate(bar, step, steps, low, high, gain=0.8, pan=0.0):
        tr.add("whistle", bar, step, ins.slide_whistle(low, high, steps * tr.step), gain, pan)

    # The intro: a balloon slowly blown up, the calliope warming up, then the band; pop on GO.
    tr.add("calliope", 0, 0, ins.calliope(60, tr.bar * 1.5), 0.25)
    tr.add("calliope", 0, 0, ins.calliope(67, tr.bar * 1.5), 0.2)
    inflate(0, 4, 24, 62, 79, 0.45, -0.2)
    tr.play("calliope", 1, vamp, ins.calliope, 0.45)
    tr.play("calliope", 3, vamp, ins.calliope, 0.55)
    tr.play("calliope", 6, melody("E5:2 F5:2 G5:4 E5:2 C5:2 E5:4 | G5:2 Ab5:2 A5:2 B5:2 D6:2 F6:2 G6:4", 16), ins.calliope, 0.75)
    inflate(4, 8, 8, 64, 76, 0.55, 0.3)
    inflate(6, 8, 24, 60, 84, 0.7, 0.0)
    tr.add("pop", 8, 0, ins.balloon_pop(), 1.0, 0.1)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 36)  # C2..B2 on a tuba with plenty of upper harmonics
            notes = voicing(c, 60, 72, prev)
            prev = notes
            seconds = length * tr.step
            fifth = root + 7 if root + 7 <= 47 else root - 5
            # oom-pah: tuba on the beat (root, fifth), chords on the off-beats
            if name == "intro" and local < 4:
                continue
            for k, st in enumerate((0, 4, 8, 12)):
                m = root if k % 2 == 0 else fifth
                tr.add("tuba", bar, st, ins.tuba(m, tr.step * 2.5), (1.0 if k % 2 == 0 else 0.85) * (0.7 if name == "intro" else 1.0))
            if name == "finale" and local == 7:
                strum(tr, "pah", bar, 2, notes, lambda m, sec: ins.brass(m, sec, bright=0.7, section=2), tr.step * 1.5, 1.0, spread=0.0)
                continue
            for st in (2, 6, 10, 14):
                if name in ("A", "finale") or (name == "intro" and local >= 4):
                    strum(tr, "pah", bar, st, notes, lambda m, sec: ins.brass(m, sec, bright=0.6, section=2), tr.step * 1.5, 0.85 if name != "intro" else 0.6, spread=0.0)
                elif name == "B":
                    strum(tr, "pah", bar, st, notes, ins.clarinet, tr.step * 1.5, 0.6, spread=0.0)
            if name == "B":
                tr.add("pad", bar, step, ins.accordion(tuple(notes), seconds * 0.95), 0.8, 0.3)
            if name == "finale":
                tr.add("pad", bar, step, ins.strings(tuple(notes + [notes[0] + 12]), seconds, attack=0.1, bright=0.6), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.drum("drums", bar, "X.......X.......", bass_drum, 0.6 + 0.08 * (local - 4))
                if local >= 5:
                    tr.drum("snare", bar, "....x.......x...", snare, 0.4 + 0.1 * (local - 5), 0.1)
                if local == 7:
                    for k in range(16):
                        tr.add("snare", bar, k, snare, 0.2 + 0.045 * k, 0.1)
                continue
            last = name == "finale" and local == 7
            tr.drum("drums", bar, "X.......X......." if not last else "X...............", bass_drum, 1.15 if name == "finale" else 0.9)
            if last:  # the last balloon pops, flies off deflating, and the band falls back to the intro
                tr.add("pop", bar, 4, ins.balloon_pop(), 1.0, -0.1)
                tr.add("cymbal", bar, 4, s.crash(), 1.4, 0.2)
                inflate(bar, 6, 14, 86, 58, 0.85, 0.0)  # rolls on round the loop
                continue
            tr.drum("cymbal", bar, "....x.......x...", cym, 0.8 if name != "finale" else 1.0, 0.2)
            tr.drum("snare", bar, "....X.......X..." if name != "B" else "....x.......x...", snare, 1.0, 0.1)
            tr.drum("snare", bar, "..o...o.o.o...oo" if name != "B" else "..o.......o.....", snare, 0.5, 0.1)
            if name in ("B", "finale"):
                tr.drum("perc", bar, "x.x.x.x.x.x.x.x." if name == "finale" else "x...x...x...x...", block, 0.5, -0.3)
            if local == 0 or (name == "finale" and local % 2 == 0):
                tr.add("cymbal", bar, 0, s.crash(), 1.3, 0.2)
            # pumping between phrases: a slide whistle inflating every other bar
            if name in ("A", "finale") and local % 2 == 1 and local < 7:
                inflate(bar, 12, 4, 67 + local + (2 if name == "finale" else 0), 79 + local + (2 if name == "finale" else 0), 0.55, 0.35 if local % 4 == 1 else -0.35)
            if name == "B" and local in (3, 7):
                inflate(bar, 10 if local == 3 else 8, 6 if local == 3 else 8, 65, 81 if local == 3 else 88, 0.6, 0.0)
            if local == part.bars - 1 and name in ("A", "B"):
                for k in range(8, 16):
                    tr.add("snare", bar, k, snare, 0.5 + 0.06 * (k - 8), 0.1)

    tr.play("calliope", 8, march, ins.calliope, 0.9)
    tr.play("lead2", 8, shift(march, 12), ins.glock, 0.5, pan=0.3)
    tr.play("lead", 16, trio, ins.clarinet)
    tr.play("lead2", 16, shift(trio, 12), ins.glock, 0.75, pan=0.3)
    tr.play("calliope", 24, [n for n in shift(march, 2) if n.step < 7 * 16 + 4], ins.calliope, 1.15)
    tr.play("horns", 24, [n for n in shift(march, 2 - 12) if n.step < 7 * 16 + 4], horn, 1.05, pan=-0.2)
    tr.play("lead2", 24, piccolo, piccolo_voice, 0.8, pan=0.3)

    mix = Mix(buses={
        "calliope": Bus(-5, reverb=0.2),
        "lead": Bus(-5, reverb=0.2),
        "lead2": Bus(-15, reverb=0.25),
        "horns": Bus(-11, reverb=0.2),
        "pah": Bus(-13, reverb=0.15),
        "pad": Bus(-17, reverb=0.25),
        "tuba": Bus(-8),
        "drums": Bus(-11, drive=1.3, reverb=0.1),
        "snare": Bus(-13, reverb=0.15),
        "cymbal": Bus(-20, reverb=0.1),
        "perc": Bus(-19, reverb=0.1),
        "whistle": Bus(-12, reverb=0.25),
        "pop": Bus(-13, reverb=0.2),
    }, reverb_decay=1.6, reverb_tone=6000)
    return finish(tr, mix), tr


SONG = Song("PumpAndPop", "Balloon Bandstand", 140, 8, 32, pump_and_pop)
