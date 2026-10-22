"""Ink Pad Ska - the round track for StampOut (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum, walking_bass


def stamp_out():
    """Ink Pad Ska (160 bpm, B flat major): a two-tone ska band on a giant school desk, bouncing like
    the rubber stamps. Upstroke guitar and organ bubble on every off-beat, a trumpet-and-sax hook that
    goes 'stamp, stamp', a rocksteady B section in G minor with the organ singing, a horn build, then
    BIG STAMPS (the round's last quarter, 30 s in) up a step in C with a stamp on every beat."""
    tr = Track(bpm=160, bars=37)
    parts = plan(tr, [
        ("intro", 9, "Bb | Bb | Eb | F | Bb | Bb | Eb | F | F"),
        ("A", 8, "Bb | Dm | Eb | F | Bb | Dm | Eb F | Bb"),
        ("B", 8, "Gm | Eb | Cm | F | Gm | Eb | Cm | D7"),
        ("build", 4, "Eb | F | Ab | G7"),
        ("finale", 8, "C | Em | F | G | C | Em | F G | C"),
    ])
    hook = melody("""D5:2 r:2 D5:2 F5:2 r:2 Bb5:4 A5:2 | A5:2 F5:2 r:2 D5:2 F5:6 r:2 | Eb5:2 r:2 Eb5:2 G5:2 r:2 C6:4 Bb5:2 | A5:4 G5:2 F5:2 C5:8 |
                     D5:2 r:2 D5:2 F5:2 r:2 Bb5:4 C6:2 | D6:4 C6:2 A5:2 F5:6 r:2 | G5:2 Bb5:2 G5:2 Eb5:2 F5:2 A5:2 C6:2 Eb6:2 | D6:6 Bb5:2 r:8""")
    bone = melody("Bb3:8 D4:8 | F4:8 A3:8 | G3:8 Bb3:8 | C4:8 A3:8 | Bb3:8 D4:8 | F4:8 A3:8 | G3:4 Bb3:4 A3:4 C4:4 | D4:8 r:8")
    song_b = melody("""G5:6 A5:2 Bb5:4 D6:4 | Eb6:8 D6:4 Bb5:4 | C6:6 Bb5:2 A5:4 G5:4 | A5:12 r:4 |
                       G5:6 A5:2 Bb5:4 D6:4 | G6:8 F6:4 Eb6:4 | Eb6:6 D6:2 C6:4 A5:4 | F#5:12 r:4""")
    climb = melody("Eb5:4 G5:4 Bb5:4 Eb6:4 | F5:4 A5:4 C6:4 F6:4 | Ab5:4 C6:4 Eb6:4 Ab6:4 | G6:2 F6:2 D6:2 B5:2 G5:8")
    tease = melody("D5:2 r:2 D5:2 F5:2 r:2 Bb5:4 A5:2 | A5:2 F5:2 r:2 D5:2 F5:6 r:2")

    def trumpet(m, sec):
        return ins.brass(m, sec, bright=1.0, section=2)

    def trombone(m, sec):
        return ins.brass(m, sec, bright=0.4, section=2, vibrato=0.05)

    def alto(m, sec):
        return ins.sax(m, sec, growl=0.15)

    def bubble(m, sec):
        return ins.organ(m, sec, drawbars=(0, 0, 8, 6, 0, 4, 0, 0, 0), leslie=0, click=0.8)

    def singing_organ(m, sec):
        return ins.organ(m, sec, drawbars=(6, 0, 8, 8, 4, 2, 0, 0, 3), leslie=6.0, click=0.4)

    def skank_guitar(m, sec):
        return ins.electric_guitar(m, sec, mute=True)

    kick, ohat, chat = s.kick(1.0, 0.4), s.hat(True), s.hat(False)
    snare = ins.snare2(230.0, 0.9, 0.25)
    rim = ins.rim_click(1700.0)
    stamp = ins.rubber_stamp(95.0)
    big_stamp = ins.rubber_stamp(78.0, 0.45)
    tick = ins.woodblock(1400.0, 0.08)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            notes = voicing(c, 62, 74, prev)
            prev = notes
            root = bass_note(c, 38)
            seconds = length * tr.step
            # the off-beat skank: guitar upstrokes and the organ's bubble
            offs = [k for k in (2, 6, 10, 14) if step <= k < step + length]
            if name == "intro":
                if local >= 1:
                    for k in offs:
                        tr.add("organ", bar, k, ins.organ(notes[0], tr.step * 1.5, drawbars=(0, 0, 8, 4, 0, 2, 0, 0, 0), leslie=0, click=0.3), 0.35 + 0.08 * local)
                        tr.add("organ", bar, k, ins.organ(notes[1], tr.step * 1.5, drawbars=(0, 0, 8, 4, 0, 2, 0, 0, 0), leslie=0, click=0.3), 0.35 + 0.08 * local)
                if local >= 4:
                    for k in offs:
                        strum(tr, "skank", bar, k, notes, skank_guitar, tr.step * 1.2, 0.5 + 0.08 * local, spread=0.006, down=False, pan=0.3)
                if local >= 2:
                    tr.add("bass", bar, 0, ins.bass_guitar(root, tr.step * 7), 0.6 + 0.05 * local)
                    tr.add("bass", bar, 8, ins.bass_guitar(root + 7 if root + 7 < 50 else root - 5, tr.step * 7), 0.5 + 0.05 * local)
                continue
            for k in offs:
                strum(tr, "skank", bar, k, notes, skank_guitar, tr.step * 1.2, 1.0, spread=0.006, down=False, pan=0.3)
                for m in notes:
                    tr.add("organ", bar, k, bubble(m, tr.step * 1.3), 0.8, -0.3)
                if name == "finale":
                    for m in notes:
                        tr.add("organ", bar, k + 1, bubble(m + 12, tr.step * 0.8), 0.45, -0.35)
            if name == "B":
                tr.add("pad", bar, step, ins.strings(tuple(notes[:3]), seconds, attack=0.3, bright=0.35), 1.0)
            if name == "finale":
                tr.add("pad", bar, step, ins.strings(tuple(n + 12 for n in notes[:3]), seconds, attack=0.05, bright=0.6), 1.0)
                tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "ah", attack=0.1), 1.0)
            if name == "build":
                for k, ch in enumerate("X..X..X...X.X..."):
                    if ch == "X":
                        strum(tr, "stabs", bar, k, [n + 12 for n in notes[:3]], trumpet, tr.step * 1.4, 0.8, spread=0.0)
                        tr.add("bass", bar, k, ins.bass_guitar(root, tr.step * 1.6), 1.0)
            elif name == "B":
                # rocksteady: the bass sits back, root and fifth with a skip
                for k, off, ln in ((0, 0, 5), (6, 0, 2), (8, 7, 4), (14, 12, 2)):
                    tr.add("bass", bar, step + k, ins.bass_guitar(root + off if root + off < 50 else root + off - 12, tr.step * ln), 1.0)
        if name in ("A", "finale"):
            walking_bass(tr, "bass", part, lambda m, sec: ins.bass_guitar(m, sec, bright=0.6), 1.0, low=38)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                tr.add("stamp", bar, 0, stamp, 0.35 + 0.06 * local)
                tr.drum("perc", bar, "x...x...x...x...", tick, 0.3 + 0.05 * local, 0.35)
                if local >= 5:
                    tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.4 + 0.1 * (local - 5), 0.25)
                if local >= 6:
                    tr.kick("kick", bar, "X.......X.......", kick, 0.5 + 0.15 * (local - 6))
                if local == 8:
                    for k in range(16):
                        tr.add("snare", bar, k, snare, 0.25 + 0.045 * k, 0.05)
                    for k in (0, 4, 8, 12):
                        tr.add("stamp", bar, k, big_stamp, 0.6 + 0.1 * k / 4)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.5)
                continue
            if name == "B":
                tr.kick("kick", bar, "........X.......", kick, 1.0)
                tr.drum("snare", bar, "........X.......", rim, 1.0, 0.1)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.6, -0.25)
                tr.drum("hats", bar, "..............x.", ohat, 0.7, 0.25)
                tr.drum("stamp", bar, "X...............", stamp, 0.6)
                if local == 7:
                    for k, step in enumerate((10, 11, 12, 13, 14, 15)):
                        tr.add("snare", bar, step, snare, 0.5 + 0.08 * k, 0.05)
                continue
            big = name == "finale"
            lift = {"A": 0.9, "build": 0.85, "finale": 1.1}[name]
            tr.kick("kick", bar, "X...X...X...X..." if big or name == "build" else "X.......X.....x.", kick, lift)
            tr.drum("snare", bar, "....X.......X...", snare, lift, 0.05)
            tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.8, 0.25)
            tr.drum("hats", bar, "xxxxxxxxxxxxxxxx" if big else "x.x.x.x.x.x.x.x.", chat, 0.55, -0.25)
            tr.drum("stamp", bar, "X...X...X...X..." if big else "X.......X.......", big_stamp if big else stamp, 1.0)
            if local == 0:
                tr.add("hats", bar, 0, s.crash(), 2.0, 0.2)
            if big and local % 2 == 0 and local:
                tr.add("hats", bar, 0, s.crash(), 1.4, -0.2 if local % 4 else 0.2)
            if big:
                tr.drum("perc", bar, "..x...x...x...x.", ins.jingles(0.15), 0.8, -0.35)
            if name == "build":
                if local == 2:
                    tr.add("fx", bar, 0, s.riser(tr.bar * 2), 0.6)
                if local == 3:
                    for k in range(8, 16):
                        tr.add("snare", bar, k, snare, 0.5 + 0.06 * (k - 8), 0.05)
            if name == "A" and local == 7:
                for k, step in enumerate((12, 13, 14, 15)):
                    tr.add("snare", bar, step, snare, 0.6 + 0.1 * k, 0.05)

    # intro: the organ teases the hook, the horns answer, then a long swell into GO
    tr.play("organ_lead", 4, tease, singing_organ, 0.7)
    tr.play("brass", 6, shift(tease, -12), trombone, 0.6)
    tr.play("lead", 8, melody("F5:16"), trumpet, 0.9)
    tr.play("lead2", 8, melody("A4:16"), alto, 0.8)
    # A: the hook
    first = parts[1].first
    tr.play("lead", first, hook, trumpet)
    tr.play("lead2", first, shift(hook, -12), alto, pan=-0.15)
    tr.play("brass", first, bone, trombone, pan=0.2)
    # B: rocksteady, the organ sings; the horns only answer at the phrase ends
    first = parts[2].first
    tr.play("organ_lead", first, song_b, singing_organ)
    tr.play("brass", first, melody("r:16 | r:12 Bb4:2 D5:2 | r:16 | r:8 F5:4 A5:4 | r:16 | r:12 G5:2 Bb5:2 | r:16 | D5:4 F#5:4 A5:4 C6:4"), trumpet, 0.8)
    for k, m in enumerate((79, 82, 86, 91)):
        tr.add("glock", first + 3, 8 + k, ins.glock(m, 0.4), 0.7, 0.3)
        tr.add("glock", first + 7, 8 + k, ins.glock(m - 2, 0.4), 0.7, 0.3)
    # build: the whole section climbs
    first = parts[3].first
    tr.play("lead", first, climb, trumpet, 0.85)
    tr.play("lead2", first, shift(climb, -12), alto, 0.8)
    tr.play("brass", first, shift(climb, -24), trombone, 0.8)
    # BIG STAMPS: the hook a step up, everyone in, the glockenspiel on top
    first = parts[4].first
    tr.play("lead", first, shift(hook, 2), trumpet, 1.15)
    tr.play("lead2", first, shift(hook, -10), alto, 1.15, pan=-0.15)
    tr.play("brass", first, [n for n in shift(bone, 2) if n.step < 7 * 16], trombone, 1.15, pan=0.2)
    tr.play("glock", first, [n for n in shift(hook, 14) if n.step < 7 * 16], ins.glock, 0.8, pan=0.3)
    # the ending: two hits and a trombone slide back down into the quiet intro
    last = tr.bars - 1
    for k in (0, 6):
        strum(tr, "stabs", last, k, [72, 76, 79, 84], trumpet, tr.step * 1.5, 1.0, spread=0.0)
    tr.add("brass", last, 8, ins.brass(60, tr.step * 6, bright=0.4, section=2, fall=4.0), 0.7, 0.2)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.15, delay=0.06),
        "lead2": Bus(-12, reverb=0.15),
        "brass": Bus(-12, reverb=0.15),
        "stabs": Bus(-12, reverb=0.15),
        "organ_lead": Bus(-8, reverb=0.2, delay=0.1),
        "organ": Bus(-15, pump=0.15),
        "skank": Bus(-13, delay=0.12),
        "pad": Bus(-18, reverb=0.25),
        "glock": Bus(-15, reverb=0.25),
        "bass": Bus(-8, pump=0.2, eq=(("hp", 45),)),
        "kick": Bus(-9, drive=1.4, eq=(("hp", 55), ("hp", 55), ("peak", 120, 4, 1.2))),
        "choir": Bus(-17, reverb=0.3),
        "snare": Bus(-12, reverb=0.15),
        "stamp": Bus(-12, drive=1.3, reverb=0.08, eq=(("hp", 60),)),
        "hats": Bus(-18),
        "perc": Bus(-20, reverb=0.1),
        "fx": Bus(-16, reverb=0.3),
    }, reverb_decay=1.3, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.28, pump_release=0.14)
    return finish(tr, mix), tr


SONG = Song("StampOut", "Ink Pad Ska", 160, 9, 37, stamp_out)
