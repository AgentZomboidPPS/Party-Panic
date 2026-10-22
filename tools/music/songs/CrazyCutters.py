"""Cookie Cutter Swing - the round track for CrazyCutters (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Part, Song, finish, plan, strum, walking_bass


def crazy_cutters():
    """Cookie Cutter Swing (144 bpm swing, F major): the bake-off on the giant cookie in the meadow.
    A jazz combo (clarinet with the tune, vibraphone, piano, walking upright bass, ride and brushes)
    with an oven timer's ding; a vibes bridge, a stop-time chorus where clarinet and vibes trade
    licks, then up to G with a little horn section for the last cookie."""
    tr = Track(bpm=144, bars=60, spb=12)
    parts = plan(tr, [
        ("intro", 8, "F6 | F6 | Bb7 | Bb7 | F6 | D7 | Gm7 C7 | Gm7 C7"),
        ("A1", 8, "F6 | Bb7 | F6 | D7 | Gm7 | C7 | Am7 D7 | Gm7 C7"),
        ("A2", 8, "F6 | Bb7 | F6 | D7 | Gm7 | C7 | Am7 D7 | Gm7 C7"),
        ("B", 8, "Bbmaj7 | Bbm6 | Am7 | D7 | Gm7 | C7 | Fmaj7 D7 | Gm7 C7"),
        ("A3", 8, "F6 | Bb7 | F6 | D7 | Gm7 | C7 | Am7 D7 | Gm7 C7"),
        ("trades", 8, "F6 | F6 | D7 | D7 | Gm7 | C7 | Bbm6 Eb7 | Am7 D7"),
        ("finale", 12, "G6 | C7 | G6 | E7 | Am7 | D7 | Bm7 E7 | Am7 D7 | G6 | Eb7 | G6 | C7"),
    ])
    hook = melody("""C5:2 D5:1 F5:3 A5:3 G5:2 F5:1 | Ab5:3 G5:2 F5:1 D5:6 | C5:2 D5:1 F5:3 A5:3 C6:2 A5:1 | F#5:3 A5:3 C6:6 |
                     Bb5:2 A5:1 G5:2 F5:1 D5:3 F5:3 | E5:2 G5:1 Bb5:3 A5:2 G5:1 E5:3 | C5:2 E5:1 G5:3 F#5:2 A5:1 C6:3 |
                     Bb5:3 G5:2 E5:1 F5:3 r:3""", 12)
    bridge = melody("""D6:6 C6:3 A5:3 | Db6:6 Bb5:3 G5:3 | C6:3 E6:3 G6:6 | F#6:3 E6:2 D6:1 C6:6 |
                       Bb5:6 A5:3 G5:3 | E5:3 G5:3 Bb5:3 D6:3 | C6:6 A5:2 F#5:1 A5:3 | G5:3 Bb5:3 E5:6""", 12)
    answers = melody("""r:9 F5:2 G5:1 | r:9 F5:2 Ab5:1 | r:12 | r:6 A5:2 G5:1 F#5:2 E5:1 |
                        r:9 Bb4:2 C5:1 | r:12 | r:12 | r:6 Db5:2 D5:1 E5:3""", 12)
    trade_clar = melody("""F5:1 G5:1 A5:1 C6:2 A5:1 Bb5:2 A5:1 G5:3 | F5:2 D5:1 F5:3 r:6 | r:12 | r:12 |
                           D5:1 F5:1 G5:1 Bb5:2 G5:1 D6:2 C6:1 Bb5:3 | G5:2 E5:1 C5:3 r:6 |
                           Db6:2 Bb5:1 F5:3 G5:2 Bb5:1 Db6:3 | C6:2 A5:1 E5:3 F#5:2 A5:1 D6:3""", 12)
    trade_vibes = melody("""r:12 | r:12 | A5:2 C6:1 F#6:3 E6:2 D6:1 C6:3 | F#5:2 A5:1 D6:3 r:6 | r:12 | r:12 |
                            Db6:2 Bb5:1 F5:3 G5:2 Bb5:1 Db6:3 | C6:2 A5:1 E5:3 F#5:2 A5:1 D6:3""", 12)
    tag = melody("D6:2 E6:1 G6:3 E6:2 D6:1 B5:3 | Db6:3 Bb5:2 G5:1 Eb5:6 | D6:2 E6:1 G6:3 r:3 G6:2 G6:1 | E6:3! r:9", 12)
    pickup = melody("r:6 Bb5:1 G5:1 E5:1 D5:1 C5:1 E5:1", 12)
    intro_lick = melody("r:6 A4:2 C5:1 D5:2 E5:1 | F5:2 E5:1 Eb5:2 D5:1 Db5:2 C5:1 Bb4:2 G4:1", 12)

    def clar(m, sec):
        return ins.clarinet(m, sec)

    def vib(m, sec):
        return ins.vibes(m, min(sec, 1.0), motor=4.5)

    def horns(m, sec):
        return ins.brass(m, sec, bright=0.55, section=3, vibrato=0.05)

    ride, hat, kick = ins.ride(1.0, 0.25), s.hat(False), s.kick(0.6, 0.3)
    snare, tap, swish = ins.snare2(220.0, 0.6, 0.22), ins.brush(0.2), ins.brush(0.45, swish=True)

    def ding(bar, step, gain=0.5):  # the oven timer
        tr.add("fx", bar, step, ins.glock(96, 0.8), gain, 0.35)
        tr.add("fx", bar, step, ins.glock(103, 0.6), gain * 0.4, 0.35)

    prev = None
    for part in parts:
        name = part.name
        if name not in ("intro", "trades"):
            walk = part if name != "finale" else Part(name, part.first, part.bars - 1, part.changes[:-1])
            walking_bass(tr, "bass", walk, lambda m, sec: ins.upright(m, sec), 1.0, low=33)
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 33)
            notes = voicing(c, 55, 68, prev, size=4)
            prev = notes
            seconds = length * tr.step
            if name == "intro":
                if local < 4:  # vibes chords, rolled gently
                    strum(tr, "vibes", bar, step, notes, lambda m, sec: ins.vibes(m, sec, motor=4.5), 1.6, 0.35 + 0.12 * local, spread=0.05)
                else:
                    tr.add("bass", bar, step, ins.upright(root, tr.step * 5), 0.7)
                    tr.add("bass", bar, step + 6, ins.upright(root + 7 if root + 7 <= 45 else root - 5, tr.step * 5), 0.6)
                if local >= 4:
                    strum(tr, "piano", bar, step, notes, ins.piano, tr.step * 2, 0.7, spread=0.008)
                    strum(tr, "piano", bar, step + 5, notes, ins.piano, tr.step * 1.5, 0.55, spread=0.008)
                continue
            if name == "trades":
                # stop-time: the band hits beat one, the soloist fills the rest
                strum(tr, "piano", bar, step, notes, ins.piano, tr.step * 2, 1.0, spread=0.006)
                tr.add("bass", bar, step, ins.upright(root, tr.step * 2.5), 1.0)
                continue
            # piano comp: the Charleston (one, and the and-of-two), busier in the finale
            if name == "finale" and local == part.bars - 1:
                strum(tr, "piano", bar, step, notes, ins.piano, tr.step * 3, 1.0, spread=0.006)
                tr.add("bass", bar, step, ins.upright(root, tr.step * 3), 1.0)
                continue
            hits = ((0, 2, 1.0), (5, 1.5, 0.8)) if name != "finale" else ((0, 2, 1.0), (5, 1.5, 0.8), (8, 1, 0.6), (11, 1, 0.7))
            for st, ln, g in hits:
                if st < length:
                    strum(tr, "piano", bar, step + st, notes, ins.piano, tr.step * ln, g, spread=0.006)
            if name in ("A2", "A3", "finale") and length == 12 and local % 2 == 1:
                strum(tr, "vibes", bar, 8, [n + 12 for n in notes], vib, tr.step * 3, 0.6, spread=0.02)
            if name == "finale" and local < 8:
                strum(tr, "horns", bar, step + 11 if length == 12 else step + 5, [n + 12 for n in notes[1:]], horns, tr.step * 1, 0.8, spread=0.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local in (1, 3):
                    tr.add("drums", bar, 0, swish, 0.5)
                    tr.add("drums", bar, 6, swish, 0.5)
                if local >= 2:
                    tr.drum("ride", bar, "x..x.xx..x.x", ride, 0.3 + 0.08 * (local - 2))
                if local >= 4:
                    tr.drum("hat", bar, "...x.....x..", hat, 0.6)
                if local == 7:
                    tr.drum("drums", bar, "......x.xx.x", snare, 0.7)
                    tr.kick("kick", bar, "......x.....", kick, 0.8)
                    ding(bar, 6, 0.4)
                continue
            if name == "trades":
                tr.kick("kick", bar, "x...........", kick, 1.0)
                tr.drum("drums", bar, "x...........", snare, 0.8)
                tr.drum("ride", bar, "x..x.xx..x.x", ride, 0.8)
                tr.drum("hat", bar, "...x.....x..", hat, 0.9)
                tr.drum("drums", bar, "...x.....x..", tap, 0.7)
                if local == part.bars - 1:
                    tr.drum("drums", bar, "......x.xxxx", snare, 0.8)
                    tr.add("cymbal", bar, 11, s.crash(), 0.5, 0.2)
                continue
            big = name == "finale"
            if big and local == part.bars - 1:  # the last hit, then the vibes run back to the top
                tr.kick("kick", bar, "x...........", kick, 1.0)
                tr.drum("drums", bar, "x...........", snare, 1.0)
                tr.add("cymbal", bar, 0, s.crash(), 1.0, 0.2)
                tr.drum("ride", bar, "......x..x..", ride, 0.5)
                continue
            tr.drum("ride", bar, "x..x.xx..x.x", ride, 0.9 if big else 0.8)
            tr.drum("hat", bar, "...x.....x..", hat, 0.8)
            tr.kick("kick", bar, "x..x..x..x.." if big else "o..o..o..o..", kick, 0.7 if big else 1.0)
            if name in ("A3", "finale"):
                tr.drum("drums", bar, "...x.....x..", snare, 0.9)
                tr.drum("drums", bar, "..o.....o..o", tap, 0.5)
            else:
                tr.drum("drums", bar, "...x.....x..", tap, 0.8)
                tr.drum("drums", bar, "..o.....o...", tap, 0.4)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(), 0.7 if not big else 1.0, 0.2)
            if big and local % 4 == 0 and local:
                tr.add("cymbal", bar, 0, s.crash(), 0.8, -0.2)
            if local == part.bars - 1 and name in ("A2", "B", "A3"):
                tr.drum("drums", bar, ".........xxx", snare, 0.6)

    ding(8, 0, 0.5)
    ding(48, 0, 0.6)
    tr.play("lead", 6, intro_lick, clar, 0.7)
    tr.play("lead", 8, hook, clar)
    tr.play("lead", 16, hook, clar)
    tr.play("lead2", 16, shift(hook, 12), vib, 0.8, pan=0.25)
    tr.play("lead", 24, bridge, vib, 0.7)
    tr.play("counter", 24, answers, clar, pan=-0.25)
    tr.play("lead", 32, hook, clar)
    tr.play("lead2", 32, shift(hook, -12), vib, pan=0.25)
    tr.play("lead", 40, trade_clar, clar)
    tr.play("lead2", 40, trade_vibes, vib, 1.2, pan=0.2)
    tr.play("lead", 48, shift(hook, 2), clar)
    tr.play("horns", 48, shift(hook, 2 - 12), horns, 0.9, pan=-0.15)
    tr.play("lead2", 48, shift(hook, 2 + 12), vib, 0.6, pan=0.25)
    tr.play("lead", 56, tag, clar)
    tr.play("horns", 56, shift(tag, -12), horns, 0.9, pan=-0.15)
    tr.play("lead2", 59, pickup, vib, 0.8, pan=0.2)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.18, delay=0.04),
        "lead2": Bus(-11, reverb=0.2),
        "counter": Bus(-12, reverb=0.2),
        "horns": Bus(-9, reverb=0.18),
        "vibes": Bus(-15, reverb=0.25),
        "piano": Bus(-12, reverb=0.15),
        "bass": Bus(-8),
        "kick": Bus(-15),
        "drums": Bus(-15, reverb=0.12),
        "hat": Bus(-20),
        "ride": Bus(-15, reverb=0.08),
        "cymbal": Bus(-20, reverb=0.1),
        "fx": Bus(-16, reverb=0.3),
    }, reverb_decay=1.5, reverb_tone=5500, delay_time=tr.beat * 2 / 3, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("CrazyCutters", "Cookie Cutter Swing", 144, 8, 60, crazy_cutters)
