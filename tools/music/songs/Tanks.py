"""Toy Box Battalion - the round track for Tanks (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan


def tanks():
    """Toy Box Battalion (116 bpm, C minor): a toy-soldier march played by an old 8-bit console
    (pulse leads, a triangle bass, noise drums) and the toy box itself (a tin snare drum, toy piano,
    xylophone), with pop-gun cannon shots. A cheeky E flat major B section, a drum-corps break
    with cannons going off, then the march climbs to D minor for the last tanks rolling: the
    finale fills the end of the 75 s round and a victory fanfare turns back to C minor for the loop."""
    tr = Track(bpm=116, bars=45)
    parts = plan(tr, [
        ("intro", 7, "Cm | Cm | Ab | Bb | Cm | Ab | G7"),
        ("A1", 8, "Cm | Cm | Ab | Bb | Cm | Cm | Ab Bb | G7"),
        ("A2", 8, "Cm | Cm | Ab | Bb | Cm | Cm | Ab Bb | G7"),
        ("B", 8, "Eb | Bb/D | Cm | Ab | Eb | Bb | Ab Bb | Eb"),
        ("break", 4, "Cm | Ab | Fm | G7"),
        ("finale", 8, "Dm | Dm | Bb | C | Dm | Dm | Bb C | A7"),
        ("victory", 2, "Bb C | G7"),
    ])
    hook = melody("""C5:3 C5:1 G4:2 C5:2 Eb5:4 D5:2 C5:2 | D5:3 Eb5:1 D5:2 Bb4:2 G4:8 |
                     Ab4:3 C5:1 Eb5:2 Ab5:2 G5:4 F5:2 Eb5:2 | F5:3 G5:1 F5:2 D5:2 Bb4:8 |
                     C5:3 C5:1 G4:2 C5:2 Eb5:4 G5:2 C6:2 | Bb5:3 G5:1 Eb5:2 G5:2 C6:8 |
                     Ab5:4 G5:2 F5:2 D5:4 F5:2 Bb5:2 | B5:4 G5:2 D5:2 B4:4 r:4""")
    cheeky = melody("""G5:2 Bb5:2 G5:2 Eb5:2 F5:2 G5:2 Ab5:4 | F5:2 D5:2 Bb4:4 D5:4 F5:4 |
                       Eb5:2 G5:2 Eb5:2 C5:2 D5:2 Eb5:2 F5:4 | Eb5:8 C5:8 |
                       G5:2 Bb5:2 G5:2 Eb5:2 F5:2 G5:2 Ab5:4 | Bb5:4 D6:4 F6:8 | Eb6:4 C6:4 D6:4 Bb5:4 | Eb6:12 r:4""")
    bugle = melody("G4:3 G4:1 C5:4 Eb5:2 C5:2 G5:4 | Ab5:3 G5:1 Eb5:4 C5:8 | F5:3 F5:1 Ab5:4 C6:2 Ab5:2 F5:4 | G5:4 B5:4 D6:4 F6:4")
    victory = melody("D6:4 C6:4 Bb5:4 C6:4 | B5:12 r:4")
    counter = melody("""G4:8 Eb4:8 | F4:8 D4:8 | C4:8 Eb4:8 | D4:8 F4:8 | G4:8 Eb4:8 | G4:8 Eb4:8 | C4:8 D4:8 | D4:8 F4:8""")
    intro_tune = melody("r:16 | r:16 | r:16 | r:16 | C5:3 C5:1 G4:2 C5:2 Eb5:4 D5:2 C5:2 | Ab4:3 C5:1 Eb5:2 Ab5:2 G5:8 | r:12 G4:1 B4:1 D5:1 F5:1")

    def lead(m, sec):
        return ins.chip(m, sec, duty=0.25, vibrato=0.15 if sec > 0.4 else 0.0)

    def lead_thin(m, sec):
        return ins.chip(m, sec, duty=0.125)

    def harmony(m, sec):
        return ins.chip(m, sec, duty=0.5)

    kick = s.kick(0.8, 0.35)
    nsnare = [ins.chip_noise(0.12, 1.0, v) for v in range(3)]
    nhat = ins.chip_noise(0.04, 2.0)
    tin = [ins.snare2(330.0, 1.0, 0.18, v) for v in range(3)]  # a toy drum: high and rattly
    cannon = ins.tom(75.0, 0.6)
    pop = ins.chip_noise(0.35, 0.6)

    def shot(bar, step, gain=1.0, pan=0.0):
        tr.add("cannon", bar, step, cannon, gain, pan)
        tr.add("cannon", bar, step, pop, gain * 0.6, pan)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 36)
            notes = voicing(c, 67, 79, prev, size=3)
            prev = notes
            # arpeggios: up-down 16ths through the chord (soft in the intro)
            if name in ("intro", "A1", "A2", "finale", "break"):
                order = [notes[0], notes[1], notes[2], notes[0] + 12, notes[2], notes[1]]
                g = 0.55 + 0.06 * local if name == "intro" else (0.8 if name != "finale" else 1.0)
                for k in range(int(length)):
                    tr.add("arp", bar, step + k, ins.chip(order[k % 6], tr.step * 0.7, duty=0.125), g * (1.0 if k % 4 == 0 else 0.7), 0.3)
            if name in ("B", "victory"):
                for k in range(0, int(length), 2):
                    tr.add("toy", bar, step + k, ins.toy_piano(notes[(k // 2) % 3] if k % 4 else notes[0] - 12, 0.3), 0.7, 0.3)
            # triangle bass: octave-jumping 8ths (whole notes in the intro)
            if name == "intro":
                if local >= 4:
                    tr.add("bass", bar, step, ins.chip_tri(root, length * tr.step * 0.9), 0.8)
            elif name == "break":
                for k in range(0, 16, 4):
                    tr.add("bass", bar, k, ins.chip_tri(root, tr.step * 2.5), 1.0)
            else:
                for k in range(0, int(length), 2):
                    m = root if k % 4 == 0 else root + 12
                    tr.add("bass", bar, step + k, ins.chip_tri(m, tr.step * 1.6), 1.0 if k % 4 == 0 else 0.8)
            if name in ("B", "finale", "victory"):
                tr.add("pad", bar, step, ins.strings(tuple(notes), length * tr.step, attack=0.1, bright=0.4), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                # the tin drum marches in from far off
                tr.drum("tin", bar, "x.......x.x.x..." if local < 4 else "x...x.x.x...x.x.", tin[local % 3], 0.45 + 0.06 * local, -0.2)
                if local >= 4:
                    tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", nhat, 0.5, 0.3)
                if local >= 5:
                    tr.kick("kick", bar, "X.......X.......", kick, 0.6)
                if local == 6:
                    for k in range(16):
                        tr.add("tin", bar, k, tin[k % 3], 0.35 + 0.04 * k, -0.2)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.4)
                continue
            if name == "break":
                tr.kick("kick", bar, "X.......X.......", kick, 1.0)
                tr.drum("tin", bar, "x.xxx.xxx.xxx.xx" if local < 3 else "xxxxxxxxxxxxxxxx", tin[local % 3], 0.8, -0.2)
                tr.drum("snare", bar, "....X.......X...", nsnare[local % 3], 1.0, 0.1)
                shot(bar, 0, 1.0, -0.4 + 0.25 * local)
                shot(bar, 10, 0.8, 0.4 - 0.25 * local)
                if local == 3:
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.55)
                continue
            big = name in ("finale", "victory")
            tr.kick("kick", bar, "X...X...X...X..." if big else "X.......X.......", kick, 1.0)
            tr.drum("snare", bar, "....X.......X...", nsnare[local % 3], 1.0, 0.1)
            tr.drum("tin", bar, "..x...x.x.x...xx" if not big else "x.xxx.xxx.xxx.xx", tin[local % 3], 0.55, -0.2)
            tr.drum("hats", bar, "x.x.x.x.x.x.x.x." if name != "A2" and not big else "xxxxxxxxxxxxxxxx", nhat, 0.55, 0.3)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(2.0), 1.2, 0.2)
                shot(bar, 0, 0.8)
            if name in ("A2", "finale") and local % 4 == 3:
                shot(bar, 12, 0.7, -0.4)
                shot(bar, 14, 0.7, 0.4)
            if big and local % 2 == 0 and local > 0:
                tr.add("cymbal", bar, 0, s.crash(2.0), 1.0, -0.2)
            if name == "victory" and local == 1:
                tr.add("fx", bar, 0, ins.orchestra_hit((67, 71, 74, 77), 0.8), 0.8)
                tr.add("cymbal", bar, 0, s.crash(3.0), 1.5)

    tr.play("lead", 0, intro_tune, lead, 0.7)
    tr.play("lead", 7, hook, lead)
    tr.play("xylo", 7, [n for n in shift(hook, 12) if (n.step // 16) % 2 == 1], ins.xylophone, 0.6, pan=-0.3)
    tr.play("lead", 15, hook, lead)
    tr.play("lead2", 15, counter, harmony, 0.8, pan=-0.25)
    tr.play("xylo", 15, shift(hook, 12), ins.xylophone, 0.6, pan=-0.3)
    tr.play("lead", 23, cheeky, lead_thin)
    tr.play("lead2", 23, shift(cheeky, -12), ins.toy_piano, 0.8, pan=-0.25)
    tr.play("brass", 31, bugle, lambda m, sec: ins.brass(m, sec, bright=0.9, section=1), 1.1)
    tr.play("lead", 31, [n for n in bugle if n.step >= 48], lead, 0.6)
    tr.play("lead", 35, shift(hook, 2), lead, 1.15)
    tr.play("lead2", 35, shift(hook, 2 - 12), harmony, 0.9, pan=-0.25)
    tr.play("xylo", 35, shift(hook, 14), ins.xylophone, 0.7, pan=-0.3)
    tr.play("brass", 35, shift(counter, 2 - 12), lambda m, sec: ins.brass(m, sec, bright=0.6, section=3), 0.8, pan=0.25)
    tr.play("lead", 43, victory, lead, 1.15)
    tr.play("lead2", 43, shift(victory, -12), harmony, 0.9, pan=-0.25)
    tr.play("brass", 43, shift(victory, -12), lambda m, sec: ins.brass(m, sec, bright=0.8, section=3), 1.0, pan=0.25)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.12, delay=0.1),
        "lead2": Bus(-12, reverb=0.12),
        "xylo": Bus(-15, reverb=0.2),
        "brass": Bus(-13, reverb=0.18),
        "arp": Bus(-14, delay=0.12),
        "toy": Bus(-14, reverb=0.15),
        "pad": Bus(-16, reverb=0.25),
        "bass": Bus(-8, eq=(("peak", 500, 3, 0.8),)),
        "kick": Bus(-11, drive=1.3),
        "snare": Bus(-12, reverb=0.1),
        "tin": Bus(-15, reverb=0.1),
        "hats": Bus(-19),
        "cymbal": Bus(-20, reverb=0.1),
        "cannon": Bus(-13, reverb=0.2, drive=1.4),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=1.2, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.28, pump_release=0.15)
    return finish(tr, mix), tr


SONG = Song("Tanks", "Toy Box Battalion", 116, 7, 45, tanks)
