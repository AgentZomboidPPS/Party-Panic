"""Toy Box Tumble - the round track for MessyMemory (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum


def messy_memory():
    """Toy Box Tumble (102.9 bpm shuffle, G major): a toy-shop jug band of ukulele, tuba, toy piano,
    xylophone and a kazoo. Its bars are 7/3 s long so the music follows the round's fixed phases:
    the toy piano plays the tune softly while everyone studies the shelf (0-7 s), the mischief-makers
    burst in exactly on bar 3 (7 s: a crash, a slide whistle and a tumbling xylophone), the kazoo band
    plays while the toys go back (9.3-39.7 s), a drum roll for the reveal (39.7 s) and the ta-da as the
    last toy is shown (44.3 s), then a soft tag back into the wind-up intro."""
    tr = Track(bpm=720 / 7, bars=29, spb=12)
    parts = plan(tr, [
        ("intro", 6, "G | Em | C | D7 | G | D7"),
        ("study", 3, "G | E7 | Am D7"),
        ("mess", 1, "Eb7 D7"),
        ("A", 8, "G | E7 | Am | D7 | G | E7 | Am D7 | G"),
        ("B", 4, "Em | C | Am | D7"),
        ("call", 1, "D7"),
        ("reveal", 2, "C | D7sus4 D7"),
        ("tada", 2, "G | C D7"),
        ("tag", 2, "G | D7"),
    ])
    hook = melody("""D5:3 G5:2 A5:1 B5:3 G5:3 | G#5:2 A5:1 B5:3 E5:6 | C6:3 B5:2 A5:1 E5:3 C5:3 | D5:2 E5:1 F#5:3 A5:3 C6:3 |
                     B5:3 A5:2 G5:1 D5:3 G5:3 | G#5:2 B5:1 D6:3 B5:3 G#5:3 | A5:2 C6:1 E6:3 F#5:2 A5:1 C6:3 | B5:6 G5:3 r:3""", 12)
    thinking = melody("B5:6 G5:3 E5:3 | E5:3 G5:3 C6:6 | A5:6 C6:3 E6:3 | D6:3 C6:3 A5:3 F#5:3", 12)
    lullaby = melody("B5:6 D6:6 | G5:6 B5:6 | E5:6 G5:6 | F#5:6 A5:6 | G5:3 B5:3 D6:3 G6:3 | F#6:6 r:6", 12)
    call = melody("D5:1 E5:1 F#5:1 G5:1 A5:1 B5:1 C6:3 r:3", 12)
    suspense = melody("E5:3 G5:3 C6:3 E6:3 | G6:6 F#6:6", 12)
    tada = melody("D5:2 G5:1 B5:3 D6:6 | E6:3 C6:2 A5:1 F#5:3 A5:3", 12)
    tag = melody("D5:3 G5:2 A5:1 B5:3 G5:3 | F#5:6 A5:3 C6:3", 12)

    tick, tock = ins.woodblock(1300.0, 0.08), ins.woodblock(900.0, 0.1)
    snare = ins.snare2(260.0, 0.6, 0.2)
    kick = s.kick(0.8, 0.3)
    toms = [ins.tom(p, 0.35) for p in (260.0, 200.0, 150.0, 110.0)]

    def uke(m, sec):
        return ins.nylon(m, sec)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            notes = voicing(c, 62, 74, prev)
            prev = notes
            root = bass_note(c, 36)
            fifth = root + 7 if root + 7 <= 48 else root - 5
            seconds = length * tr.step
            step, length = int(step), int(length)
            if name == "intro":
                if local >= 1:
                    for k in range(0, 12, 6):
                        strum(tr, "uke", bar, k, notes, uke, tr.step * 4, 0.35 + 0.1 * local, spread=0.015)
                if local >= 3:
                    tr.add("bass", bar, 0, ins.tuba(root, tr.step * 4), 0.5 + 0.12 * (local - 3))
                    tr.add("bass", bar, 6, ins.tuba(fifth, tr.step * 4), 0.45 + 0.12 * (local - 3))
                continue
            if name in ("study", "tag"):
                for k in range(step, step + length, 3):
                    strum(tr, "uke", bar, k, notes, uke, tr.step * 2, 0.75 if k % 6 else 0.9, spread=0.012, down=k % 6 == 0)
                tr.add("bass", bar, step, ins.tuba(root, tr.step * 3), 0.85)
                if length > 6:
                    tr.add("bass", bar, 6, ins.tuba(fifth, tr.step * 3), 0.75)
                continue
            if name == "mess":
                strum(tr, "uke", bar, step, notes, uke, tr.step * 5, 1.0, spread=0.03)
                tr.add("bass", bar, step, ins.tuba(root, tr.step * 5), 1.0)
                strum(tr, "brass", bar, step, [n - 12 for n in notes[:3]], lambda m, sec: ins.brass(m, sec, bright=0.6, section=2, fall=2.0), seconds * 0.8, 1.0, spread=0.0)
                continue
            if name == "reveal":
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.4, bright=0.45), 1.0)
                tr.add("bass", bar, step, ins.tuba(root, seconds * 0.5), 0.8)
                for k in range(step, step + length, 2):
                    tr.add("uke", bar, k, uke(notes[(k // 2) % len(notes)] + 12, tr.step * 2), 0.7, 0.2)
                continue
            # the oom-pah shuffle: tuba on 1 and 3, ukulele chops, toy piano on the off-beats
            for k in range(step, step + length, 6):
                tr.add("bass", bar, k, ins.tuba(root if (k // 6) % 2 == 0 else fifth, tr.step * 4), 1.0)
            for k in range(step, step + length, 3):
                strum(tr, "uke", bar, k, notes, uke, tr.step * 1.5, 1.0 if k % 6 == 0 else 0.8, spread=0.01, down=k % 6 == 0, pan=-0.25)
                strum(tr, "uke", bar, k + 2, notes, uke, tr.step * 1.0, 0.55, spread=0.008, down=False, pan=-0.25)
            for k in range(step + 3, step + length, 6):
                strum(tr, "toys", bar, k, [n + 12 for n in notes], ins.toy_piano, tr.step * 2, 0.7, spread=0.0, pan=0.3)
            if name in ("B", "tada"):
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.15, bright=0.5), 1.0)
            if name == "tada":
                tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "ah", attack=0.05), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local == 0:
                    for k in (1, 4):
                        tr.add("fx", bar, k, ins.ratchet(0.35, 9), 0.4, -0.3)  # winding the toy up
                    for k, m in enumerate((79, 83, 86, 91)):
                        tr.add("toys", bar, 7 + k, ins.toy_piano(m, 0.4), 0.35, 0.3)
                if local >= 1:
                    tr.drum("clock", bar, "x.....x.....", tick, 0.3 + 0.06 * local, 0.3)
                    tr.drum("clock", bar, "...x.....x..", tock, 0.25 + 0.06 * local, -0.3)
                if local == 5:
                    for k in range(12):
                        tr.add("drums", bar, k, snare, 0.25 + 0.06 * k, 0.05)
                    tr.add("fx", bar, 6, ins.slide_whistle(62, 86, tr.step * 6), 0.7, 0.2)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.35)
                continue
            if name == "study":
                tr.drum("clock", bar, "x.....x.....", tick, 0.7, 0.3)
                tr.drum("clock", bar, "...x.....x..", tock, 0.6, -0.3)
                tr.drum("drums", bar, "...x.....x..", ins.brush(0.2), 0.6, 0.1)
                tr.kick("kick", bar, "x.....x.....", kick, 0.5)
                continue
            if name == "mess":
                tr.add("cymbal", bar, 0, s.crash(), 2.0, 0.2)
                tr.add("fx", bar, 0, ins.timpani(43, 1.4, 1.0), 1.0)
                tr.add("fx", bar, 1, ins.slide_whistle(88, 58, tr.step * 5), 0.9, -0.2)
                tr.add("fx", bar, 0, ins.whoosh(0.9), 0.6, 0.3)  # the puff of smoke
                for k in range(12):
                    tr.add("xylo", bar, k, ins.xylophone(91 - k * 2 - (k % 2), 0.15), 0.9 - 0.03 * k, -0.4 + 0.07 * k)
                for k, step in enumerate((6, 7, 8, 9, 10, 11)):
                    tr.add("drums", bar, step, toms[min(3, k * 2 // 3)], 0.7 + 0.05 * k, 0.3 - 0.12 * k)
                tr.add("fx", bar, 9, ins.jaw_harp(43, 0.4), 0.6, 0.1)
                continue
            if name == "tag":
                tr.drum("clock", bar, "x.....x.....", tick, 0.6, 0.3)
                tr.drum("clock", bar, "...x.....x..", tock, 0.5, -0.3)
                tr.drum("drums", bar, "...x.....x..", ins.brush(0.2), 0.5, 0.1)
                continue
            if name == "reveal":
                # the drum roll: who remembered?
                for k in range(24):
                    tr.add("drums", bar, k / 2, snare, (0.3 + 0.012 * (local * 24 + k)) * (0.8 if k % 2 else 1.0), 0.05)
                tr.kick("kick", bar, "x.....x.....", kick, 0.7 + 0.15 * local)
                tr.add("fx", bar, 0, ins.timpani(43 + 2 * local, 1.2, 0.6), 0.6)
                if local == 1:
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.4)
                continue
            big = name == "tada"
            tr.kick("kick", bar, "x.....x....." if not big else "x..x..x..x..", kick, 1.0)
            tr.drum("drums", bar, "...x.....x..", snare, 1.0, 0.05)
            tr.drum("hats", bar, "x.xx.xx.xx.x", ins.brush(0.15), 0.7, -0.2)
            tr.drum("clock", bar, "..x..x..x..x", tick, 0.45, 0.35)
            if local == 0 or (big and local == 1):
                tr.add("cymbal", bar, 0, s.crash(), 1.8 if big else 1.3, 0.2)
            if name == "A" and local in (3, 7):
                for k, m in enumerate((79, 83, 86, 91)):
                    tr.add("xylo", bar, 8 + k, ins.xylophone(m, 0.2), 0.8, 0.35)
            if name == "call":
                for k in range(6, 12):
                    tr.add("drums", bar, k, toms[min(3, (k - 6) // 2 + 1)], 0.8, 0.2)

    tr.play("toys", 1, lullaby, ins.toy_piano, 0.7)
    tr.play("lead", 5, melody("r:6 D5:2 E5:1 F#5:3", 12), ins.kazoo, 0.7)
    first = parts[1].first
    tr.play("toys", first, [n for n in hook if n.step < 3 * 12], ins.toy_piano)
    tr.play("xylo", first, [n for n in shift(hook, 12) if n.step < 3 * 12], ins.xylophone, 0.35, pan=0.3)
    first = parts[3].first
    tr.play("lead", first, hook, ins.kazoo)
    tr.play("xylo", first + 4, [n for n in shift(hook, 12) if n.step >= 4 * 12], ins.xylophone, 0.5, pan=0.35)
    first = parts[4].first
    tr.play("lead2", first, thinking, ins.clarinet)
    tr.play("xylo", first, shift(thinking, 12), ins.xylophone, 0.45, pan=0.35)
    tr.play("lead", parts[5].first, call, ins.kazoo)
    tr.play("toys", parts[6].first, suspense, ins.toy_piano, 1.0)
    tr.play("xylo", parts[6].first, shift(suspense, -12), ins.xylophone, 0.6, pan=0.3)
    first = parts[7].first
    tr.play("lead", first, tada, ins.kazoo, 1.1)
    tr.play("brass", first, shift(tada, -12), lambda m, sec: ins.brass(m, sec, bright=0.8, section=3), 0.9)
    tr.play("xylo", first, shift(tada, 12), ins.xylophone, 0.6, pan=0.35)
    first = parts[8].first
    tr.play("toys", first, tag, ins.toy_piano, 0.8)

    mix = Mix(buses={
        "lead": Bus(-7, reverb=0.18),
        "lead2": Bus(-9, reverb=0.2),
        "toys": Bus(-10, reverb=0.2),
        "xylo": Bus(-15, reverb=0.2),
        "uke": Bus(-12, reverb=0.12),
        "bass": Bus(-9),
        "brass": Bus(-13, reverb=0.2),
        "pad": Bus(-17, reverb=0.25),
        "choir": Bus(-17, reverb=0.3),
        "kick": Bus(-14, eq=(("hp", 55), ("hp", 55), ("peak", 120, 4, 1.2))),
        "drums": Bus(-13, reverb=0.15),
        "hats": Bus(-20),
        "clock": Bus(-18, reverb=0.1),
        "cymbal": Bus(-19, reverb=0.1),
        "fx": Bus(-13, reverb=0.25),
    }, reverb_decay=1.3, reverb_tone=6000, delay_time=tr.beat * 2 / 3, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("MessyMemory", "Toy Box Tumble", 720 / 7, 6, 29, messy_memory)
