"""Boom Boom Capybara: the round song for CapyGoBoom (see songkit.py for the rules every song keeps)."""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def capy_go_boom():
    """Boom Boom Capybara (118 bpm, G major): a tropical calypso for a lawn of snacks and snack cannons.
    A teasing marimba-and-conga intro builds to the drop on GO; steel-pan hooks over a rolling bass and
    nylon-string skank carry the verses; a whistle-and-marimba bridge lets the capybaras chill for a
    moment; the big section brings the brass and the cannon booms (timpani and crash on the downbeats);
    and the finale, which starts as the FEAST does, is a brass fanfare over sixteenth-note pans that ends
    on the dominant, so the loop falls straight back into the drop."""
    tr = Track(bpm=118, bars=48, spb=16)
    parts = plan(tr, [
        ("intro", 8, "G | G | C | C | Em | Am | D | D7"),
        ("A1", 8, "G | Em | C | D | G | Em | Am | D"),
        ("A2", 8, "G | Em | C | D | G | Em | Am | D"),
        ("B", 8, "Em | Bm | C | G | Am | Em | C | D"),
        ("C", 7, "G | Em | C | D | G | B7 | Em D"),
        ("finale", 9, "C | D | Em | D | C | D | G | G | D"),
    ])

    # The tunes. Every bar is 16 steps (a step is a sixteenth); the hook leans on the calypso 3+3+2 rhythm.
    tune_a = melody("""G4:3 B4:3 D5:2 G5:3 F#5:3 D5:2 | E5:3 G5:3 B5:2 A5:3 G5:3 E5:2 |
                       C5:3 E5:3 G5:2 E5:3 D5:3 C5:2 | D5:3 F#5:3 A5:2 G5:3 F#5:3 D5:2 |
                       B5:3 A5:3 G5:2 B5:3 A5:3 G5:2 | G5:3 E5:3 G5:2 B5:3 G5:3 E5:2 |
                       A5:3 C6:3 B5:2 A5:3 G5:3 E5:2 | D5:4 F#5:4 A5:4 G5:2 F#5:2""", 16)
    tune_b = melody("""E5:6 G5:2 B5:8 | D5:6 F#5:2 B5:8 | E5:4 G5:4 C6:8 | B5:6 A5:2 G5:8 |
                       A5:6 C6:2 E6:8 | G5:4 B5:4 E6:8 | E6:4 D6:4 C6:4 G5:4 | A5:4 F#5:4 D5:4 r:4""", 16)
    tune_c = melody("""G5:4 G5:2 D5:2 G5:4 B5:4 | E5:4 E5:2 B4:2 E5:4 G5:4 | C5:4 C5:2 G4:2 C5:4 E5:4 |
                       D5:4 D5:2 A4:2 D5:4 F#5:4 | B5:3 B5:3 A5:2 G5:3 A5:3 B5:2 |
                       D#5:3 F#5:3 B5:2 A5:3 F#5:3 D#5:2 | E5:8 F#5:4 A5:4""", 16)
    tune_f = melody("""G5:2 G5:2 E5:2 G5:2 C6:4 B5:2 A5:2 | A5:2 A5:2 F#5:2 A5:2 D6:4 C#6:2 B5:2 |
                       B5:2 B5:2 G5:2 B5:2 E6:4 D6:2 B5:2 | A5:2 F#5:2 A5:2 D6:2 F#6:4 E6:2 D6:2 |
                       G5:2 G5:2 E5:2 G5:2 C6:4 B5:2 A5:2 | A5:2 A5:2 F#5:2 A5:2 D6:4 C#6:2 B5:2 |
                       G5:4 B5:4 D6:4 G6:4 | G6:8 D6:4 B5:4 | A5:2 A5:2 A5:2 A5:2 D6:8""", 16)
    fuse = melody("r:16 | r:16 | r:16 | r:16 | r:16 | r:16 | r:8 D5:2 E5:2 F#5:2 A5:2 | r:16", 16)

    shake = s.shaker()
    conga_lo, conga_hi = ins.conga(220.0), ins.conga(330.0, slap=True)
    bongo_hi, bongo_lo = ins.bongo(520.0), ins.bongo(420.0, slap=True)
    cow = ins.cowbell(0.25)
    rim = ins.rim_click(1900.0)
    thump = s.kick(0.9)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 36)
            notes = voicing(c, 55, 67, prev)
            prev = notes
            seconds = length * tr.step
            fifth = root + 7 if root + 7 <= 47 else root - 5
            half = length < 16
            # The bass: a rolling calypso line (every other pulse a fifth), drive in the big sections.
            if name == "intro":
                if local >= 4:
                    tr.add("bass", bar, step, ins.bass_guitar(root, 0.4), 0.9)
                    tr.add("bass", bar, step + 3, ins.bass_guitar(fifth, 0.3), 0.7)
            elif name in ("C", "finale"):
                for k in range(0, int(length), 2):
                    m = root if (k // 2) % 4 != 2 else fifth
                    tr.add("bass", bar, step + k, ins.bass_guitar(m, 0.18, bright=0.7), 1.0 if k % 4 == 0 else 0.8)
                tr.add("bass", bar, step, ins.tuba(root, 0.5), 0.8)
            else:
                line = [(0, root, 3), (3, fifth, 3)] + ([] if half else [(8, root, 3), (11, fifth, 3)])
                for k, m, ln in line:
                    tr.add("bass", bar, step + k, ins.bass_guitar(m, ln * tr.step), 1.0 if k in (0, 8) else 0.8)
            # The skank: nylon strings on the offbeats; the marimba carries the intro and the bridge.
            if name in ("A1", "A2", "C", "finale"):
                for k in (2, 6, 10, 14):
                    if k < length:
                        strum(tr, "gtr", bar, step + k, notes[:4], ins.nylon, 0.16, 0.7 if name in ("C", "finale") else 0.55,
                              pan=-0.3)
            if name in ("intro", "B"):
                gain = 0.55 if name == "intro" and local < 4 else 0.85
                for k in range(0, int(length), 2):
                    tr.add("marimba", bar, step + k, ins.marimba(notes[(k // 2) % len(notes)] + 12, 0.25), gain, 0.3)
            if name == "B":
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.5, bright=0.35), 1.0)
            # The big sections' brass stabs.
            if name in ("C", "finale"):
                stabs = (0, 6, 10) if not half else (0,)
                for k in stabs:
                    for m in notes:
                        tr.add("brass", bar, step + k, ins.brass(m + 12, 0.22, bright=1.0), 0.5)
            if name == "A2" and local in (3, 7):
                for k, m in enumerate(notes):
                    tr.add("brass", bar, 12 + k * 0.4, ins.brass(m + 12, 0.35, bright=0.9), 0.45)

        for bar in part.bars_range():
            local = bar - part.first
            # The percussion, section by section.
            if name == "intro":
                tr.drum("shake", bar, "o.o.o.o.o.o.o.o." if local < 2 else "xoxoxoxoxoxoxoxo", shake, 0.5 if local < 2 else 0.75)
                if local >= 2:
                    tr.drum("conga", bar, "x..x..x.x..x..x.", conga_lo, 0.8)
                    tr.drum("conga", bar, "..x...x...x...x.", conga_hi, 0.6)
                if local >= 4:
                    tr.drum("cow", bar, "x...x...x...x...", cow, 0.5)
                    tr.kick("kick", bar, "X.......X.......", thump, 0.8)
                if local == 7:  # the fuse: toms rolling down into the drop
                    for k, step in enumerate((8, 10, 12, 13, 14, 15)):
                        tr.add("tom", bar, step, ins.tom(260.0 - k * 20, 0.35), 0.8 + 0.04 * k)
            elif name in ("A1", "A2"):
                tr.drum("shake", bar, "XoxoXoxoXoxoXoxo", shake, 0.75)
                tr.drum("conga", bar, "x..x..x.x..x..x.", conga_lo, 0.85)
                tr.drum("conga", bar, "..x...x...x...x.", conga_hi, 0.65)
                tr.drum("cow", bar, "x...x...x...x...", cow, 0.55)
                tr.drum("rim", bar, "....X.......X...", rim, 0.7)
                tr.kick("kick", bar, "X.......X.......", thump, 0.9)
                if name == "A2" and local % 4 == 3:
                    tr.drum("bongo", bar, "............xxXx", bongo_hi, 0.7)
            elif name == "B":
                tr.drum("shake", bar, "o.o.o.o.o.o.o.o.", shake, 0.6)
                tr.drum("conga", bar, "x......x..x.....", conga_lo, 0.6)
                tr.drum("bongo", bar, "..x...x...x...x.", bongo_lo, 0.45)
                if local >= 4:
                    tr.drum("cow", bar, "x...x...x...x...", cow, 0.4)
                    tr.kick("kick", bar, "X.......X.......", thump, 0.7)
                if local == 7:
                    for k, step in enumerate((10, 12, 13, 14, 15)):
                        tr.add("tom", bar, step, ins.tom(300.0 - k * 25, 0.3), 0.8 + 0.05 * k)
            else:  # C and the finale: everything on
                tr.drum("shake", bar, "XxXxXxXxXxXxXxXx", shake, 0.8)
                tr.drum("conga", bar, "x..x..x.x..x..x.", conga_lo, 0.9)
                tr.drum("conga", bar, "..x...x...x...x.", conga_hi, 0.7)
                tr.drum("cow", bar, "x.x.x.x.x.x.x.x.", cow, 0.6)
                tr.drum("rim", bar, "....X.......X...", rim, 0.8)
                tr.kick("kick", bar, "X.....x.X..x..x.", thump, 1.0)
                if name == "finale" and local == 8:  # the last bar: a roll back into the drop
                    for k, step in enumerate((8, 10, 12, 13, 14, 15)):
                        tr.add("tom", bar, step, ins.tom(280.0 - k * 22, 0.35), 0.9 + 0.03 * k)
            # The cannon: a boom on the big downbeats (the drop, the big section, the finale).
            if (name == "A1" and local == 0) or (name == "C" and local in (0, 4)) or (name == "finale" and local in (0, 4, 6)):
                tr.add("boom", bar, 0, ins.timpani(31, 1.6, hard=1.0), 1.0)
                tr.add("boom", bar, 0, s.crash(2.2), 0.5)
            if name == "B" and local == 0:
                tr.add("boom", bar, 0, ins.timpani(36, 1.2, hard=0.6), 0.6)

    # The melodies.
    tr.play("lead", 6, fuse, ins.steel_pan, 0.8)
    tr.play("lead", 8, tune_a, ins.steel_pan, 1.0, legato=0.95)
    tr.play("lead", 16, tune_a, ins.steel_pan, 1.0, legato=0.95)
    tr.play("lead2", 16, shift(tune_a, -12), ins.marimba, 0.9)
    tr.play("lead", 24, tune_b, ins.whistle, 1.0)
    tr.play("lead2", 24, shift(tune_b, -12), ins.marimba, 0.8)
    tr.play("lead", 32, tune_c, lambda m, sec: ins.brass(m, sec, bright=1.0), 0.9)
    tr.play("lead2", 32, shift(tune_c, 12), ins.steel_pan, 0.9)
    tr.play("lead", 39, tune_f, ins.steel_pan, 1.0, legato=0.9)
    tr.play("lead2", 39, shift(tune_f, -12), lambda m, sec: ins.brass(m, sec, bright=1.0), 0.8)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.18, delay=0.1),
        "lead2": Bus(-12, reverb=0.15, delay=0.08),
        "bass": Bus(-9, pump=0.25),
        "gtr": Bus(-14, reverb=0.1),
        "marimba": Bus(-13, reverb=0.15, delay=0.12),
        "brass": Bus(-11, reverb=0.15),
        "pad": Bus(-17, reverb=0.25),
        "conga": Bus(-14, reverb=0.08),
        "bongo": Bus(-16, reverb=0.1),
        "cow": Bus(-19),
        "shake": Bus(-21),
        "rim": Bus(-18, reverb=0.12),
        "kick": Bus(-10, drive=0.2),
        "tom": Bus(-13, reverb=0.15),
        "boom": Bus(-10, reverb=0.3),
    }, reverb_decay=1.5, reverb_tone=6000, delay_time=tr.beat * 3 / 4, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("CapyGoBoom", "Boom Boom Capybara", 118, 8, 48, capy_go_boom)
