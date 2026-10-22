"""Conveyor Belt Boogie - the round track for CakeFactory (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum


def cake_factory():
    """Conveyor Belt Boogie (132 bpm, C major): the toy cake factory. A music box winds up over the
    ticking gears, the shift whistle blows on GO, and a boogie band (toy piano with the tune, rolling
    boogie bass, clarinet) plays over the machines' own rhythm section: clanks, steam hisses, ratchets
    and the cream nozzle's bloops. It adds a layer every time the belts speed up, has a minor 'steam
    break', and goes up to D, double time, for the last fifteen seconds."""
    tr = Track(bpm=132, bars=40)
    parts = plan(tr, [
        ("intro", 8, "C | C | C | C | F | F | G | G7"),
        ("A1", 8, "C | C | F | C | G | F | C | G7"),
        ("A2", 8, "C | C | F | C | G | F | C | G7"),
        ("B", 6, "Am | F | Dm | G | F | G7"),
        ("finale", 10, "D | D | G | D | A | G | D | A7 | D G | G7"),
    ])
    hook = melody("""G5:3 G5:1 E5:2 C5:2 D5:2 E5:2 G5:4 | A5:2 G5:2 E5:2 G5:2 r:2 C6:2 r:4 |
                     A5:3 A5:1 F5:2 C5:2 D5:2 F5:2 A5:4 | G5:2 E5:2 C5:2 E5:2 G5:8 |
                     B5:3 B5:1 G5:2 D5:2 E5:2 F5:2 G5:4 | A5:2 C6:2 A5:2 F5:2 D5:4 F5:4 |
                     E5:2 G5:2 C6:4 B5:2 A5:2 G5:4 | F5:2 E5:2 D5:2 B4:2 G4:4 r:4""")
    steam_tune = melody("""E5:4 A5:4 C6:6 B5:2 | A5:4 F5:4 C5:8 | D5:4 F5:4 A5:6 G5:2 | G5:4 D5:4 B4:8 |
                           C5:2 D5:2 F5:2 A5:2 C6:4 A5:4 | B5:4 D6:4 F6:4 G6:4""")
    box_arps = melody("""C6:2 E6:2 G6:2 E6:2 C6:2 E6:2 G6:2 C7:2 | C6:2 E6:2 G6:2 E6:2 C6:2 E6:2 G6:2 C7:2 |
                         C6:2 F6:2 A6:2 F6:2 C6:2 F6:2 A6:2 C7:2 | C6:2 E6:2 G6:2 E6:2 C6:2 E6:2 G6:2 C7:2 |
                         B5:2 D6:2 G6:2 D6:2 B5:2 D6:2 G6:2 B6:2 | A5:2 C6:2 F6:2 C6:2 A5:2 C6:2 F6:2 A6:2 |
                         C6:2 E6:2 G6:2 E6:2 C6:2 E6:2 G6:2 C7:2 | B5:2 D6:2 F6:2 D6:2 B5:2 D6:2 G6:2 F6:2""")
    tag = melody("F#6:2 A6:2 F#6:2 D6:2 B5:2 D6:2 G6:4 | G6:4! r:4 r:2 B5:1 C6:1 D6:1 F6:1 E6:2")
    break_arps = melody("""A5:2 C6:2 E6:2 C6:2 A5:2 C6:2 E6:2 A6:2 | A5:2 C6:2 F6:2 C6:2 A5:2 C6:2 F6:2 A6:2 |
                           A5:2 D6:2 F6:2 D6:2 A5:2 D6:2 F6:2 A6:2 | B5:2 D6:2 G6:2 D6:2 B5:2 D6:2 G6:2 B6:2 |
                           A5:2 C6:2 F6:2 C6:2 A5:2 C6:2 F6:2 A6:2 | B5:2 D6:2 F6:2 D6:2 B5:2 D6:2 G6:2 F6:2""")

    def toy(m, sec):
        return ins.toy_piano(m, sec)

    def clar(m, sec):
        return ins.clarinet(m, sec)

    def horns(m, sec):
        return ins.brass(m, sec, bright=0.8, section=3)

    kick, clap = s.kick(0.9, 0.35), s.clap(0.25)
    snare = ins.snare2(240.0, 0.8, 0.2)
    chat, ohat = s.hat(False), s.hat(True)
    tick, tock = ins.woodblock(1400.0), ins.woodblock(950.0)
    clank_hi, clank_lo = ins.clank(620.0, 0.3), ins.clank(330.0, 0.45)
    hiss, ratch = ins.steam(0.22), ins.ratchet(0.12, 4)

    # the music box winds up over the ticking gears
    tr.add("fx", 0, 0, ins.ratchet(0.6, 14), 0.5, -0.3)
    tr.play("box", 1, [n for n in hook if n.step < 32], ins.music_box, 0.8)
    tr.play("box", 3, [n for n in shift(hook, 0, -64) if 0 <= n.step < 32], ins.music_box, 0.9)
    tr.add("fx", 7, 8, ins.factory_whistle((79, 83, 86), tr.step * 7), 0.8, 0.0)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 33)
            third = 3 if "m" in c.name else 4
            notes = voicing(c, 60, 72, prev, size=3)
            prev = notes
            # the boogie bass: root, third, fifth, sixth, seventh, sixth, fifth, third (8ths; 16ths in the finale)
            line = [0, third, 7, 9, 10, 9, 7, third]
            if name == "intro" and local < 4:
                continue
            if name == "B":
                for k, off in enumerate((0, 0, 7, 0)):
                    tr.add("bass", bar, step + k * 4, ins.bass_guitar(root + off, tr.step * 2.5, bright=0.7), 1.0 if k % 2 == 0 else 0.8)
            else:
                rate = 2
                for k in range(int(length) // rate):
                    g = (1.0 if k % 2 == 0 else 0.8) * (0.7 if name == "intro" else 1.0)
                    tr.add("bass", bar, step + k * rate, ins.bass_guitar(root + line[k % 8], tr.step * 1.8, bright=0.7), g)
            if name == "intro":
                continue
            # toy piano / clarinet "boogie" chord stabs on the off-beats
            for st in range(2, int(length), 4):
                strum(tr, "keys", bar, step + st, notes, lambda m, sec: ins.piano(m, sec, hard=0.9), tr.step * 1.2,
                      0.9 if st % 8 == 6 else 0.7, spread=0.004, pan=0.2)
            if name == "B":
                tr.add("pad", bar, step, ins.accordion(tuple(voicing(c, 57, 69, None)), length * tr.step), 1.0)
            if name == "finale" and local < 8:
                strum(tr, "horns", bar, 14, [n + 12 for n in notes], horns, tr.step * 1.5, 0.9, spread=0.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                tr.drum("gears", bar, "x...x...x...x...", tick, 0.35 + 0.05 * local, 0.3)
                if local >= 2:
                    tr.drum("gears", bar, "..x...x...x...x.", tock, 0.3 + 0.05 * local, -0.3)
                if local >= 4:
                    tr.drum("machines", bar, "X.......X.......", clank_lo, 0.4 + 0.08 * (local - 4))
                    tr.drum("machines", bar, "....x.......x...", hiss, 0.4 + 0.08 * (local - 4), 0.2)
                if local >= 6:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.6 + 0.15 * (local - 6))
                if local == 7:
                    tr.drum("snare", bar, "........x.x.xxxx", snare, 0.8)
                continue
            if name == "finale" and local == part.bars - 1:  # the last chord, then the little scale back up
                tr.kick("kick", bar, "X...............", kick, 1.0)
                tr.drum("machines", bar, "X.......x...x...", clank_lo, 0.8)
                tr.drum("gears", bar, "x...x...x.x.x.x.", tick, 0.6, 0.3)
                tr.add("cymbal", bar, 0, s.crash(), 1.0, 0.2)
                tr.add("fx", bar, 4, ins.steam(0.9), 0.5, -0.2)
                continue
            big = name == "finale"
            tr.kick("kick", bar, "X...X...X...X..." if name != "B" else "X.......X.....x.", kick, 1.0)
            tr.drum("snare", bar, "....X.......X...", snare, 0.9)
            tr.drum("machines", bar, "....x.......x...", hiss, 0.7, 0.25)
            tr.drum("machines", bar, "X......xX.......", clank_lo, 0.6)
            tr.drum("gears", bar, "x...x...x...x...", tick, 0.6, 0.3)
            tr.drum("hats", bar, "xxxxxxxxxxxxxxxx" if big else "x.x.x.x.x.x.x.x.", chat, 0.6, -0.2)
            tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.4 if name == "A1" else 0.6, -0.2)
            if name in ("A2", "finale"):
                tr.drum("machines", bar, "..x...x...x..x.x", clank_hi, 0.5, -0.35)
                tr.drum("clap", bar, "....X.......X...", clap, 1.0, 0.05)
            if name in ("A2", "B", "finale"):
                tr.drum("gears", bar, ".x.x.x.x.x.x.x.x" if big else "...x.......x....", ratch, 0.6, 0.4)
            if local % 2 == 1 and name != "B":  # the cream nozzle's splurt and a berry's plop
                tr.add("fx", bar, 14, ins.bloop(180.0, 2.5, 0.12), 0.5, -0.3)
                tr.add("fx", bar, 15, ins.bloop(420.0, 1.6, 0.08), 0.4, 0.3)
            if local == 0 or (big and local == 4):
                tr.add("cymbal", bar, 0, s.crash(), 0.9, 0.2)
            if local == part.bars - 1 and name in ("A1", "A2", "B"):
                tr.drum("snare", bar, "........x.x.xxxx", snare, 0.8)
                if name == "B":
                    tr.add("fx", bar, 8, ins.factory_whistle((81, 85, 88), tr.step * 7), 0.7)

    tr.play("lead", 8, hook, toy, 1.0)
    tr.play("lead2", 8, shift(hook, 12), ins.glock, 0.5, pan=0.25)
    tr.play("lead", 16, hook, clar)
    tr.play("lead2", 16, shift(hook, 12), toy, 0.8, pan=0.2)
    tr.play("box", 16, box_arps, ins.music_box, 0.7)
    tr.play("lead", 24, steam_tune, clar)
    tr.play("box", 24, break_arps, ins.music_box, 0.6)
    tr.play("lead", 30, shift(hook, 2), toy, 1.0)
    tr.play("horns", 30, shift(hook, 2 - 12), horns, 0.8, pan=-0.15)
    tr.play("lead2", 30, shift(hook, 14), ins.glock, 0.6, pan=0.25)
    tr.play("lead", 38, tag, toy)
    tr.play("lead2", 38, shift(tag, -12), clar, pan=-0.15)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.15, delay=0.06),
        "lead2": Bus(-12, reverb=0.18),
        "horns": Bus(-11, reverb=0.15),
        "box": Bus(-14, reverb=0.25, delay=0.12),
        "keys": Bus(-14, pump=0.15, reverb=0.1),
        "pad": Bus(-16, reverb=0.2),
        "bass": Bus(-8, pump=0.2),
        "kick": Bus(-9, drive=1.3),
        "snare": Bus(-14, reverb=0.12),
        "clap": Bus(-16, reverb=0.12),
        "hats": Bus(-19),
        "gears": Bus(-17, reverb=0.08),
        "machines": Bus(-14, reverb=0.15),
        "cymbal": Bus(-20, reverb=0.1),
        "fx": Bus(-15, reverb=0.25),
    }, reverb_decay=1.2, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.25, pump_release=0.15)
    return finish(tr, mix), tr


SONG = Song("CakeFactory", "Conveyor Belt Boogie", 132, 8, 40, cake_factory)
