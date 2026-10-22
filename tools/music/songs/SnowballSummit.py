"""Summit Polka - the round track for SnowballSummit (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum


def snowball_summit():
    """Summit Polka (133.3 bpm, F major): an alpine polka band on the frozen mountain top above the
    clouds. An alphorn calls across the peaks in the intro, then a flugelhorn's yodelling hook leaps
    over accordion oom-pahs, a helicon bass and cowbells; the accordion takes the tune, the trio sings
    in B flat, and the BLIZZARD (72% of the round: 43.2 s, on a bar line) blows it all up to G with
    swirling glockenspiel snow and gusts of wind."""
    tr = Track(bpm=400 / 3, bars=42)
    parts = plan(tr, [
        ("intro", 8, "F | F | Bb | F | F | Bb | C | C7"),
        ("A1", 8, "F | C7 | C7 | F | F | C7 | C7 | F"),
        ("A2", 8, "F | C7 | C7 | F | F | C7 | C7 | F"),
        ("trio", 8, "Bb | F7 | F7 | Bb | Bb | Eb | C7 | D7"),
        ("blizzard", 10, "G | D7 | D7 | G | G | D7 | D7 | G | G | C7"),
    ])
    hook = melody("""C5:2 F5:2 A5:2 C6:2 A5:4 F5:4 | G5:2 Bb5:2 G5:2 E5:2 C5:8 | E5:2 G5:2 Bb5:2 C6:2 D6:4 C6:4 | A5:4 C6:2 A5:2 F5:8 |
                     C5:2 F5:2 A5:2 C6:2 F6:4 E6:2 D6:2 | C6:4 Bb5:2 G5:2 E5:4 G5:4 | Bb5:2 A5:2 G5:2 F5:2 E5:2 F5:2 G5:2 E5:2 | F5:8 r:2 C5:2 F5:2 A5:2""")
    trio = melody("""D5:6 F5:2 Bb5:8 | A5:4 G5:2 F5:2 Eb5:8 | C5:6 Eb5:2 A5:8 | Bb5:4 F5:4 D5:8 |
                     D5:6 F5:2 Bb5:4 D6:4 | Eb6:6 D6:2 C6:4 Bb5:4 | Bb5:4 G5:4 E5:4 C5:4 | D5:4 F#5:4 A5:4 C6:4""")
    alphorn_call = melody("""r:16 | C4:8 F4:8 | A4:12 G4:4 | F4:16 | r:16 | C4:8 F4:8 | G4:8 A4:4 Bb4:4 | C5:16""")
    snowflakes = melody("""r:8 F6:1 A6:1 C7:1 A6:1 F6:4 | r:16 | r:8 E6:1 G6:1 C7:1 G6:1 E6:4 | r:16 |
                           r:8 F6:1 A6:1 C7:1 A6:1 F6:4 | r:16 | r:8 G6:1 Bb6:1 C7:1 Bb6:1 G6:4 | r:16""")
    ending = melody("D6:2 B5:2 G5:2 D5:2 G5:8 | E5:4 G5:4 Bb5:8")

    def flugel(m, sec):
        return ins.brass(m, sec, bright=0.55, section=1, vibrato=0.1)

    def alphorn(m, sec):
        return ins.brass(m, sec, bright=0.15, section=1, vibrato=0.04)

    def helicon(m, sec):
        return ins.brass(m, sec, bright=0.3, section=2, vibrato=0.0)

    kick, chat, ohat = s.kick(0.9, 0.3), s.hat(False), s.hat(True)
    snare = ins.snare2(240.0, 0.7, 0.18)
    bells = [ins.alpine_bell(m, 1.4, variant=v) for v, m in enumerate((74, 79, 71, 77))]

    for bar in (0, 2, 4):
        tr.add("fx", bar, 0, ins.whoosh(tr.bar * 1.6), 0.5, -0.4 + 0.4 * (bar // 2))
    for bar, step, v in ((1, 4, 0), (2, 10, 1), (3, 6, 2), (5, 2, 3), (6, 8, 1)):
        tr.add("bells", bar, step, bells[v], 0.35, (-0.6, 0.5, -0.2, 0.6, -0.4)[v % 5])

    for k, m in enumerate((77, 81, 84, 89, 84, 81)):  # the first snowflakes
        tr.add("snow", 4, 2 + k * 2, ins.glock(m, 0.4), 0.45, -0.4 + 0.15 * k)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            notes = voicing(c, 60, 72, prev)
            prev = notes
            root = bass_note(c, 38)
            fifth = root + 7 if root + 7 <= 50 else root - 5
            seconds = length * tr.step
            if name == "intro":
                tr.add("pad", bar, 0, ins.accordion(tuple(notes[:3]), seconds), 0.25 + 0.06 * local)
                if local >= 4:
                    for k, m in ((0, root), (8, fifth)):
                        tr.add("bass", bar, k, helicon(m, tr.step * 3), 0.5 + 0.1 * (local - 4))
                if local >= 6:
                    for k in (2, 6, 10, 14):
                        tr.add("accordion", bar, k, ins.accordion(tuple(notes), tr.step * 1.4), 0.6 + 0.15 * (local - 6), 0.2)
                continue
            # oom-pah: the helicon on every beat (root, fifth), the accordion's chord on every off-beat
            for k, m in ((0, root), (4, fifth), (8, root), (12, fifth)):
                tr.add("bass", bar, k, helicon(m, tr.step * 2.5), 1.0 if k % 8 == 0 else 0.85)
                tr.add("bass", bar, k, ins.bass_guitar(m, tr.step * 2.5, bright=0.2), 0.4)
            for k in (2, 6, 10, 14):
                tr.add("accordion", bar, k, ins.accordion(tuple(notes), tr.step * 1.4), 1.0 if name != "trio" else 0.8, 0.2)
            if name == "trio":
                tr.add("pad", bar, 0, ins.strings(tuple(n + 12 for n in notes[:3]), seconds, attack=0.3, bright=0.4), 1.0)
            if name == "blizzard":
                tr.add("pad", bar, 0, ins.strings(tuple(n + 12 for n in notes[:3]), seconds, attack=0.05, bright=0.6), 1.0)
                tr.add("choir", bar, 0, ins.choir(tuple(notes[:3]), seconds, "ah", attack=0.08), 1.0)
                # the blizzard swirling: a glockenspiel arpeggio of the chord, up and down
                ring = sorted(n + 24 for n in notes[:3]) + [notes[0] + 36]
                for k in range(16):
                    tr.add("snow", bar, k, ins.glock(ring[(0, 1, 2, 3, 2, 1, 2, 3)[k % 8]], 0.25), 0.7 if k % 2 else 0.9, -0.5 + k / 16)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.drum("hats", bar, "..x...x...x...x.", chat, 0.3 + 0.1 * (local - 4), 0.2)
                if local >= 6:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.5 + 0.2 * (local - 6))
                if local == 7:
                    for k in range(16):
                        tr.add("drums", bar, k, snare, 0.25 + 0.045 * k, 0.05)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.45)
                continue
            big = name == "blizzard"
            tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
            tr.drum("drums", bar, "..x...x...x...x." if name != "trio" else "....x.......x...", snare, 0.8, 0.05)
            tr.drum("hats", bar, "xxxxxxxxxxxxxxxx" if big else "x.x.x.x.x.x.x.x.", chat, 0.55, 0.2)
            tr.drum("bells", bar, "X...x...X...x..." if big else "X...............", bells[local % 4], 0.8, (-0.5, 0.5)[local % 2])
            if local == 0 or (big and local % 4 == 0):
                tr.add("hats", bar, 0, s.crash(), 1.8, -0.2)
            if big and local % 2 == 1:
                tr.add("fx", bar, 0, ins.whoosh(tr.bar, up=local % 4 == 1), 0.8, (-0.6, 0.6)[local % 4 // 2])
            if name in ("A1", "A2") and local == 7:
                for k, step in enumerate((12, 13, 14, 15)):
                    tr.add("drums", bar, step, snare, 0.6 + 0.1 * k, 0.05)
            if name == "trio" and local == 7:
                for k in range(16):
                    tr.add("drums", bar, k, snare, 0.35 + 0.04 * k, 0.05)
                tr.add("fx", bar, 0, s.riser(tr.bar), 0.5)
            if bar == tr.bars - 1:
                tr.add("fx", bar, 4, ins.whoosh(tr.bar * 1.2, up=False), 0.7)

    tr.play("lead", 0, alphorn_call, alphorn, 0.85)
    first = parts[1].first
    tr.play("lead", first, hook, flugel)
    first = parts[2].first
    tr.play("lead", first, hook, lambda m, sec: ins.accordion((m,), sec), 0.9)
    tr.play("lead2", first, shift(hook, -12), flugel, 0.5, pan=-0.2)
    tr.play("snow", first, snowflakes, ins.glock, 0.8)
    first = parts[3].first
    tr.play("lead", first, trio, flugel)
    tr.play("lead2", first, shift(trio, 12), ins.glock, 0.7, pan=0.3)
    tr.play("lead2", first, shift(trio, -12), lambda m, sec: ins.accordion((m,), sec), 0.5, pan=-0.3)
    first = parts[4].first
    tr.play("lead", first, shift(hook, 2), flugel, 1.15)
    tr.play("lead2", first, shift(hook, 2 - 12), lambda m, sec: ins.accordion((m, m + 12), sec), 0.9, pan=-0.2)
    tr.play("lead", first + 8, ending, flugel, 1.1)
    tr.play("lead2", first + 8, shift(ending, -12), alphorn, 0.8)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.22, delay=0.05),
        "lead2": Bus(-12, reverb=0.2),
        "accordion": Bus(-13, pump=0.1, reverb=0.12),
        "pad": Bus(-17, reverb=0.3),
        "choir": Bus(-17, reverb=0.35),
        "snow": Bus(-16, reverb=0.3, delay=0.15),
        "bass": Bus(-9),
        "kick": Bus(-12, drive=1.3, eq=(("hp", 55), ("hp", 55), ("peak", 120, 4, 1.2))),
        "drums": Bus(-14, reverb=0.12),
        "hats": Bus(-19),
        "bells": Bus(-15, reverb=0.25),
        "fx": Bus(-17, reverb=0.3),
    }, reverb_decay=2.0, reverb_tone=6500, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("SnowballSummit", "Summit Polka", 400 / 3, 8, 42, snowball_summit)
