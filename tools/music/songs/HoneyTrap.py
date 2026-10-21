"""Honeycomb Hush: the round song for HoneyTrap (see songkit.py for the rules every song keeps)."""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


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


SONG = Song("HoneyTrap", "Honeycomb Hush", 104, 8, 44, honey_trap)
