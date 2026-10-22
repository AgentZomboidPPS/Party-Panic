"""Clockwork Air Show - the round track for MechaMarathon (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan


def mecha_marathon():
    """Clockwork Air Show (144 bpm, B flat major): a village brass band at the sunny fete where the
    wind-up toys fly. Ticking clockwork and a toy piano wake it up; on GO a marching tune climbs bar
    by bar for the 10 seconds of winding, with ratchets clicking left-right like two thumbs mashing
    WIND (six bars of 144 bpm are exactly those 10 s). The band holds its breath on F7 for "Ready...
    LAUNCH!", and the soaring flight theme takes off with the toys 11.67 s in. As the toys come down
    it jumps up to C major for the big finish, then winds down tick by tock into the intro."""
    tr = Track(bpm=144, bars=28)
    parts = plan(tr, [
        ("intro", 8, "Bb | Bb | Eb | Bb | Gm | Eb | F | F7"),
        ("wind", 6, "Bb | Gm | Eb | F | Bb/D Eb | F7"),
        ("launch", 1, "F7"),
        ("flight", 5, "Bb | Eb | Bb/F | F7 | Bb G7"),
        ("finale", 6, "C | F | C/G | G7 | F G7 | C"),
        ("outro", 2, "C7 | F7"),
    ])
    wind = melody("""F4:2 Bb4:2 D5:2 F5:4 D5:2 Bb4:2 D5:2 | G5:4 F5:2 D5:2 Bb4:4 G4:4 |
                     G4:2 Bb4:2 Eb5:2 G5:4 Eb5:2 Bb4:2 Eb5:2 | A5:4 G5:2 F5:2 C5:4 A4:4 |
                     Bb4:2 D5:2 F5:2 Bb5:2 G5:2 Bb5:2 Eb6:4 | D6:2 C6:2 Bb5:2 A5:2 C6:8""")
    launch = melody("C6:12 F4:1 A4:1 C5:1 Eb5:1")
    hook = melody("""F5:6 Bb5:2 D6:8 | C6:2 Bb5:2 G5:4 Eb6:8 | D6:4 C6:2 Bb5:2 F5:4 D5:4 |
                     Eb5:2 F5:2 G5:2 A5:2 C6:8 | Bb5:8 G5:2 B5:2 D6:2 F6:2""")
    big_end = melody("F6:4 E6:4 D6:4 B5:4 | C6:16")
    counter = melody("""D4:8 F4:8 | G4:8 Bb4:8 | F4:8 D4:8 | C4:4 Eb4:4 A4:8 | D5:8 B4:8""")
    tick_tune = melody("""r:2 F5:4 Bb5:2 D6:8 | C6:2 Bb5:2 G5:4 Eb6:8 | D6:4 C6:2 Bb5:2 F5:8 |
                          r:16 | D5:6 G5:2 Bb5:8 | G5:4 Bb5:4 Eb6:8 | C6:4 A5:4 F5:4 C5:4 | Eb5:8 r:8""")
    outro_tune = melody("E5:4 G5:4 Bb5:4 C6:4 | A5:4 F5:4 Eb5:4 C5:4")

    def cornet(m, sec):
        return ins.brass(m, sec, bright=0.85, section=3)

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.35, section=2, vibrato=0.04)

    bass_drum = s.kick(0.7, 0.5)
    snare = [ins.snare2(230.0, 0.85, 0.25, v) for v in range(3)]
    tick, tock = ins.woodblock(1400.0), ins.woodblock(950.0)
    click = ins.ratchet(0.09, 3)
    crash = s.crash(2.5)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 36)
            notes = voicing(c, 55, 67, prev)
            prev = notes
            seconds = length * tr.step
            # tuba oom-pah: the root on 1 and 3 (the fifth on 3 when the chord lasts the bar), horns on 2 and 4
            if name == "intro" and local < 2:
                pass
            elif name in ("launch",):
                tr.add("tuba", bar, 0, ins.tuba(root, seconds * 0.95), 1.0)
                tr.add("horns", bar, 0, ins.strings(tuple(notes), seconds, attack=0.9, bright=0.5), 1.4)
            elif name == "outro":
                tr.add("tuba", bar, 0, ins.tuba(root, tr.beat * 0.8), 0.8)
                tr.add("tuba", bar, 8, ins.tuba(root + 7 if root + 7 < 48 else root - 5, tr.beat * 0.8), 0.6)
            else:
                beats = int(length // 4)
                soft = 0.55 if name == "intro" else 1.0
                for k in range(beats):
                    st = step + k * 4
                    if k % 2 == 0:
                        b = root if (k // 2) % 2 == 0 or beats < 4 else (root + 7 if root + 7 < 48 else root - 5)
                        tr.add("tuba", bar, st, ins.tuba(b, tr.beat * 0.85), soft)
                    elif name != "intro" or local >= 4:
                        for i, m in enumerate(notes):
                            tr.add("horns", bar, st, horn(m, tr.beat * 0.55), soft * 0.6, -0.3 + 0.3 * i)
            if name in ("flight", "finale"):
                tr.add("strings", bar, step, ins.strings(tuple(n + 12 for n in notes), seconds, attack=0.15, bright=0.55), 1.0)
            elif name == "intro" and local >= 4:
                tr.add("strings", bar, step, ins.strings(tuple(notes[:2]), seconds, attack=0.8, bright=0.3), 0.7)
            elif name == "outro":  # held into the loop point, so the intro picks up from it
                tr.add("strings", bar, step, ins.strings(tuple(notes[:3]), seconds, attack=0.3, bright=0.3, release=1.2), 0.8)
            if name == "finale":
                tr.add("choir", bar, step, ins.choir(tuple(notes), seconds, "ah", attack=0.1), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            # the clockwork: tick-tock on every beat, always
            if name != "finale":
                tr.drum("clock", bar, "x...x...x...x..." if bar else "....x...x...x...", tick, 0.8 if name in ("intro", "outro") else 0.6, 0.35)
                tr.drum("clock", bar, "..x...x...x...x.", tock, 0.6 if name in ("intro", "outro") else 0.45, -0.35)
            if name == "intro":
                if local >= 2:
                    tr.drum("ratchet", bar, "x.......x.......", click, 0.5 + 0.05 * local, 0.5)
                if local >= 4:
                    tr.kick("drum", bar, "X.......X.......", bass_drum, 0.4 + 0.1 * (local - 4))
                    tr.drum("snare", bar, "....x.......x.x.", snare[0], 0.35 + 0.1 * (local - 4), 0.1)
                if local == 7:
                    for k in range(16):  # a snare roll and the clockwork spinning up into GO
                        tr.add("snare", bar, k, snare[k % 3], 0.25 + 0.04 * k, 0.1)
                        tr.add("ratchet", bar, k, click, 0.4 + 0.03 * k, 0.5 if k % 2 else -0.5)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.5)
                continue
            if name == "outro":
                tr.drum("ratchet", bar, "x.......x.......", click, 0.5, 0.5)
                continue
            if name == "wind":
                # Q-E-Q-E: ratchets alternating sides, getting busier as the spring tightens
                pattern = "x.x.x.x.x.x.x.x." if local < 3 else "xxxxxxxxxxxxxxxx"
                for k, ch in enumerate(pattern):
                    if ch == "x":
                        tr.add("ratchet", bar, k, click, 0.55 + 0.06 * local, 0.55 if (k // (2 if local < 3 else 1)) % 2 else -0.55)
                tr.kick("drum", bar, "X.......X.......", bass_drum, 0.9)
                tr.drum("snare", bar, "....X.......X..x" if local % 2 == 0 else "....X...x.x.X.xx", snare[local % 3], 0.8, 0.1)
                if local == 0:
                    tr.add("cymbal", bar, 0, crash, 1.0, 0.3)
                if local == 5:
                    tr.add("fx", bar, 0, ins.whoosh(tr.bar * 2, True), 0.5)
                continue
            if name == "launch":
                for k in range(0, 16, 1):  # a snare roll swelling up to lift-off
                    tr.add("snare", bar, k, snare[k % 3], 0.3 + 0.045 * k, 0.1)
                tr.add("fx", bar, 0, s.riser(tr.bar), 0.6)
                continue
            big = name == "finale"
            tr.kick("drum", bar, "X...X...X...X...", bass_drum, 0.85 if not big else 1.0)
            tr.drum("snare", bar, "....X.......X..." if local % 2 == 0 else "....X.......X.xx", snare[local % 3], 1.0, 0.1)
            tr.drum("snare", bar, "..o...o...o...o." if not big else "o.o.o.o.o.o.o.o.", snare[(local + 1) % 3], 0.5, -0.15)
            tr.drum("cymbal", bar, "..x...x...x...x.", s.hat(True), 0.6, -0.25)
            if local == 0:
                tr.add("cymbal", bar, 0, crash, 1.4, 0.3)
                tr.add("fx", bar, 0, ins.orchestra_hit(tuple(voicing(part.changes[0][3], 60, 72))), 0.7)
            if big and local in (2, 4):
                tr.add("cymbal", bar, 0, crash, 1.0, -0.3)
            if big and local == 5:
                tr.add("cymbal", bar, 0, crash, 1.8, 0.0)
                tr.add("fx", bar, 0, ins.orchestra_hit((60, 64, 67, 72), 0.8), 1.0)
                for k in range(4, 16):
                    tr.add("snare", bar, k, snare[k % 3], 0.3 + 0.03 * k, 0.1)

    # the intro: the flight theme on a toy piano, as a music box would wind it
    tr.play("toy", 0, tick_tune, lambda m, sec: ins.toy_piano(m, min(sec, 0.6)), 0.8)
    tr.play("lead", 6, melody("r:16 | r:8 Bb3:2 C4:2 D4:2 Eb4:2"), cornet, 0.7)
    tr.play("glock", 4, melody("D6:8 F6:8 | Eb6:8 G6:8 | C6:8 A5:8 | C6:16"), ins.glock, 0.7)
    # winding
    tr.play("lead", 8, wind, cornet)
    tr.play("lead2", 8, [n for n in shift(wind, -12) if n.step >= 48], horn, pan=-0.2)
    tr.play("toy", 8, [n for n in shift(wind, 12) if n.step >= 48], ins.toy_piano, 0.6)
    tr.play("lead", 14, launch, cornet)
    tr.play("glock", 14, melody("C6:1 F6:1 C6:1 F6:1 C6:1 F6:1 C6:1 F6:1 C6:1 F6:1 C6:1 F6:1 A6:1 C7:1 A6:1 C7:1"), ins.glock, 0.5)
    # flight
    tr.play("lead", 15, hook, cornet)
    tr.play("lead2", 15, counter, horn, pan=-0.2)
    tr.play("glock", 15, shift(hook, 12), ins.glock, 0.55)
    # finale, a step up
    tr.play("lead", 20, [n for n in shift(hook, 2) if n.step < 64], cornet)
    tr.play("lead2", 20, [n for n in shift(hook, 2 - 12) if n.step < 64], horn, pan=-0.2)
    tr.play("glock", 20, [n for n in shift(hook, 14) if n.step < 64], ins.glock, 0.55)
    tr.play("lead", 24, big_end, cornet)
    tr.play("lead2", 24, shift(big_end, -12), horn, pan=-0.2)
    tr.play("strings2", 20, melody("E5:16 | F5:16 | G5:16 | G5:8 B5:8 | C6:8 D6:8 | E6:16"), lambda m, sec: ins.strings((m,), sec, attack=0.1, bright=0.6))
    # winding down
    tr.play("toy", 26, outro_tune, lambda m, sec: ins.toy_piano(m, min(sec, 0.6)), 0.8)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.16, delay=0.05),
        "lead2": Bus(-13, reverb=0.18),
        "toy": Bus(-12, reverb=0.2, delay=0.12),
        "glock": Bus(-16, reverb=0.25),
        "strings": Bus(-15, reverb=0.25),
        "strings2": Bus(-14, reverb=0.25),
        "horns": Bus(-14, reverb=0.12),
        "choir": Bus(-15, reverb=0.3),
        "tuba": Bus(-8, eq=(("hp", 45),)),
        "drum": Bus(-12, drive=1.3),
        "snare": Bus(-12, reverb=0.12),
        "cymbal": Bus(-19, reverb=0.1),
        "clock": Bus(-17, reverb=0.1),
        "ratchet": Bus(-17, eq=(("lp", 6000),)),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=1.5, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.3, pump_release=0.15)
    return finish(tr, mix), tr


SONG = Song("MechaMarathon", "Clockwork Air Show", 144, 8, 28, mecha_marathon)
