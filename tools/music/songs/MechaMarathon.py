"""Wind-Up Wings (145 bpm, D major): Mecha-Marathon's sunny, bunting-hung flying field.

A toy-box band: a tin whistle and a toy piano wind the tune up over clicking ratchets and a
ukulele, then a brass band takes the flight theme as the toys lift off, with an oom-pah tuba
under it. The tempo is set so the lift-off lands on a bar line: GO, then 7 bars of winding
(10 s of WIND plus the 1.6 s launch beat = 11.6 s), then LAUNCH on the flight theme's downbeat.
"""

from __future__ import annotations

import instruments as ins
import synth as s
from modes import Song, finish, plan, strum
from score import Bus, Mix, Track, bass_note, melody, shift, voicing

BPM = 145
INTRO = 8


def wind_up_wings():
    tr = Track(bpm=BPM, bars=39)
    parts = plan(tr, [
        ("intro", 8, "D | D | G | D | Bm | G | Em | A"),
        ("wind", 7, "D | G | D | A | D | G | A7"),
        ("flight", 8, "D | Bm | G | A | D | Bm | Em7 A7 | D"),
        ("glide", 8, "Bm | G | D | A | Bm | G | Em | A7"),
        ("finale", 8, "D | Bm | G | A | D | Bm | Em7 A7 | D"),
    ])
    # The winding hook: a little crank that turns round and round, climbing at the end.
    crank = melody("""D5:2 F#5:2 A5:2 F#5:2 D5:2 F#5:2 A5:4 | B5:2 A5:2 G5:2 B5:2 D6:6 r:2 |
                      A5:2 F#5:2 D5:2 F#5:2 A5:2 D6:2 C#6:2 B5:2 | A5:6 E5:2 C#5:8 |
                      D5:2 F#5:2 A5:2 F#5:2 D5:2 F#5:2 A5:4 | B5:2 C#6:2 D6:2 E6:2 D6:2 B5:2 G5:4 |
                      A5:2 B5:2 C#6:2 D6:2 E6:2 F#6:2 G6:2 A6:2""")
    # The flight theme: long, soaring notes.
    soar = melody("""F#5:8 A5:4 D6:4 | D6:6 C#6:2 B5:8 | G5:4 B5:4 D6:4 E6:4 | C#6:8 A5:4 E5:4 |
                     F#5:8 A5:4 D6:4 | F#6:6 E6:2 D6:8 | E6:4 G6:4 C#6:4 E6:4 | D6:12 r:4""")
    # The glide: the springs run down, the tune flutters down in little loops.
    flutter = melody("""r:2 F#5:2 B5:2 D6:2 C#6:2 B5:2 F#5:4 | G5:2 B5:2 D6:2 B5:2 G5:4 D5:4 |
                        r:2 F#5:2 A5:2 D6:2 C#6:2 A5:2 F#5:4 | E5:4 A5:4 C#6:4 r:4 |
                        r:2 B5:2 D6:2 F#6:2 E6:2 D6:2 B5:4 | D6:2 B5:2 G5:2 B5:2 D6:4 G6:4 |
                        E6:4 B5:4 G5:4 E5:4 | A5:4 C#6:2 E6:2 G6:8""")
    horns = melody("""A4:8 D5:8 | F#4:8 B4:8 | B4:8 G4:8 | A4:8 C#5:8 | A4:8 D5:8 | B4:8 F#4:8 | G4:8 G4:8 | F#4:16""")
    intro_tune = melody("""r:16 | r:16 | B5:4 r:4 D6:4 r:4 | A5:4 r:4 F#5:8 | F#5:4 r:4 B5:4 r:4 | G5:4 B5:4 D6:8 |
                           E6:4 D6:4 B5:4 G5:4 | A5:8 r:8""")

    def tin_whistle(m, sec):
        return ins.whistle(m, sec)

    def trumpets(m, sec):
        return ins.brass(m, sec, bright=0.9, section=3, vibrato=0.1)

    def horn_section(m, sec):
        return ins.brass(m, sec, bright=0.35, section=2)

    kick = s.kick(1.0, 0.35)
    snare = ins.snare2(210.0, 0.9, 0.22)
    roll = ins.snare2(230.0, 0.7, 0.12)
    chat, ohat = s.hat(False), s.hat(True)
    tick, tock = ins.woodblock(1400.0), ins.woodblock(950.0)
    crank_click = ins.ratchet(0.18, 6)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 38)  # D2..C#3: a register phone speakers can carry
            notes = voicing(c, 60, 72, prev)
            prev = notes
            seconds = length * tr.step
            fifth = root + 7 if root + 7 <= 50 else root - 5
            uke = voicing(c, 60, 77, None, 4)
            if name == "intro":
                if local >= 4:
                    tr.add("pad", bar, step, ins.strings(tuple(notes[:3]), seconds, attack=0.9, bright=0.25), 0.8 + 0.1 * (local - 4))
                if local >= 5:
                    for k in (0, 8):
                        tr.add("bass", bar, step + k, ins.upright(root if k == 0 else fifth, tr.step * 6), 0.7)
                continue
            if name == "wind":
                # driving eighths on a picked bass, a ukulele chopping the off-beats
                for k in range(0, 16, 2):
                    m = root if k not in (6, 14) else fifth
                    tr.add("bass", bar, step + k, ins.bass_guitar(m, tr.step * 1.6, bright=0.6, variant=k), 0.7 if k % 4 == 0 else 0.55)
                for k in range(2, 16, 4):
                    strum(tr, "uke", bar, step + k, uke, ins.nylon, tr.step * 1.5, 0.9, spread=0.008, down=k % 8 == 2, pan=0.3)
                for k in (0, 8):
                    tr.add("keys", bar, step + k, ins.toy_piano(notes[0] + 12, 0.3), 0.6, -0.3)
            elif name in ("flight", "finale"):
                # oom-pah: tuba on the beat, a ukulele and toy-piano chord on the "pah"
                beats = int(length // 4)
                for k in range(beats):
                    st = step + k * 4
                    m = root if k % 2 == 0 else fifth
                    tr.add("bass", bar, st, ins.tuba(m, tr.step * 2.5), 1.0)
                    tr.add("bass", bar, st, ins.bass_guitar(m, tr.step * 3, bright=0.3, variant=k), 0.5)
                    strum(tr, "uke", bar, st + 2, uke, ins.nylon, tr.step * 1.5, 0.85, spread=0.006, pan=0.3)
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.15, bright=0.55), 1.0)
            elif name == "glide":
                for k in (0, 6, 10):
                    tr.add("bass", bar, step + k, ins.upright(root if k != 6 else fifth, tr.step * 3), 1.0)
                for k in range(0, 16, 2):
                    tr.add("keys", bar, step + k, ins.xylophone(uke[(0, 1, 2, 3, 2, 1, 2, 3)[k // 2]] + 12, 0.15), 0.8 if k % 4 else 1.0, -0.3)
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.4, bright=0.35), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                # a clockwork tick-tock from the start, a key being wound, then the band warming up
                tr.drum("clock", bar, "x...x...x...x...", tick, 0.35 + 0.05 * local)
                tr.drum("clock", bar, "..x...x...x...x.", tock, 0.25 + 0.04 * local)
                if local in (1, 3):
                    for k in range(0, 16, 2):
                        tr.add("fx", bar, k, crank_click, 0.3 + 0.03 * k, 0.4)
                if local >= 6:
                    tr.drum("hats", bar, "..x...x...x...x.", chat, 0.5)
                if local == 7:
                    for k in range(16):
                        tr.add("drums", bar, k, roll, 0.2 + 0.05 * k, 0.1)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.4)
                continue
            if name == "wind":
                # the winding: ratchet clicks every 8th, faster towards the launch
                pattern = "x.x.x.x.x.x.x.x." if local < 4 else "xxxxxxxxxxxxxxxx"
                tr.drum("fx", bar, pattern, crank_click, 0.35 + 0.04 * local, 0.4)
                tr.kick("kick", bar, "X.......X.......", kick, 1.0)
                tr.drum("drums", bar, "....X.......X...", snare, 1.0)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.6, -0.25)
                if local == 0:
                    tr.add("cymbal", bar, 0, s.crash(), 1.4, 0.2)
                if local == part.bars - 1:
                    for k in range(8, 16):
                        tr.add("drums", bar, k, roll, 0.4 + 0.07 * (k - 8), 0.1)
                    tr.add("fx", bar, 4, ins.slide_whistle(72, 96, tr.step * 12), 0.8, -0.2)
                continue
            if name == "glide":
                tr.kick("kick", bar, "X.....X...X.....", kick, 0.9)
                tr.drum("drums", bar, "....x.......x...", snare, 0.8)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.5, -0.25)
                tr.drum("clock", bar, "..x...x...x...x.", tock, 0.5)
                if local == 3:
                    tr.add("fx", bar, 8, ins.slide_whistle(91, 74, tr.step * 7), 0.5, 0.3)
                if local == 7:
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.4)
                continue
            # flight and finale: a marching band in full flight
            tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
            tr.drum("drums", bar, "....X.......X..x", snare, 1.0)
            tr.drum("drums", bar, "..o...o..o....o.", roll, 0.5, 0.1)
            tr.drum("hats", bar, "..X...X...X...X.", ohat, 0.6, 0.25)
            tr.drum("hats", bar, "xxxxxxxxxxxxxxxx" if name == "finale" else "x.x.x.x.x.x.x.x.", chat, 0.45, -0.25)
            if local % 4 == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.5, 0.2)
            if name == "finale" and local == part.bars - 1:
                tr.add("fx", bar, 0, ins.orchestra_hit((62, 66, 69, 74)), 0.8)

    tr.play("lead", 0, intro_tune, ins.toy_piano, 0.8)
    tr.play("lead", 8, crank, tin_whistle)
    tr.play("lead2", 8, shift(crank, -12), ins.toy_piano, pan=0.25)
    tr.play("lead", 15, soar, trumpets)
    tr.play("brass", 15, horns, horn_section, pan=-0.2)
    tr.play("lead2", 15, shift(soar, 12), ins.glock, pan=0.25)
    tr.play("lead", 23, flutter, ins.toy_piano)
    tr.play("lead2", 23, shift(flutter, -12), tin_whistle, 0.8, pan=-0.2)
    tr.play("lead", 31, soar, trumpets)
    tr.play("lead2", 31, shift(soar, 12), tin_whistle, pan=0.2)
    tr.play("brass", 31, horns, horn_section, pan=-0.2)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.18, delay=0.06),
        "lead2": Bus(-13, reverb=0.2),
        "brass": Bus(-13, reverb=0.18),
        "keys": Bus(-15, reverb=0.15),
        "uke": Bus(-13, reverb=0.12),
        "pad": Bus(-17, reverb=0.25),
        "bass": Bus(-9),
        "kick": Bus(-10, drive=1.4),
        "drums": Bus(-12, reverb=0.12),
        "hats": Bus(-19),
        "cymbal": Bus(-19, reverb=0.1),
        "clock": Bus(-17, reverb=0.12),
        "fx": Bus(-15, reverb=0.2),
    }, reverb_decay=1.4, reverb_tone=6500, delay_time=tr.beat * 0.75, delay_feedback=0.28)
    return finish(tr, mix), tr


SONG = Song("MechaMarathon", "Wind-Up Wings", BPM, INTRO, 39, wind_up_wings)
