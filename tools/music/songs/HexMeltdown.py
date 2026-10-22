"""Molten Showdown - the round track for HexMeltdown (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import numpy as np
import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum


def hex_meltdown():
    """Molten Showdown (124 bpm, E minor): the volcano crater's game show. A disco-funk band (slap bass,
    clavinet, brass, strings) with the referee robot's bleeps and lava bubbles; a big G major chorus,
    a lava-drama break, then up to F sharp minor as the calls come faster."""
    tr = Track(bpm=124, bars=56)
    parts = plan(tr, [
        ("intro", 8, "Em | Em | Em | Em | Em | Em | C | B7"),
        ("A1", 8, "Em7 | A7 | Em7 | A7 | Em7 | A7 | Cmaj7 | B7"),
        ("A2", 8, "Em7 | A7 | Em7 | A7 | Em7 | A7 | Cmaj7 | B7"),
        ("chorus", 8, "Cmaj7 | D | Bm7 | Em7 | Cmaj7 | D | B7sus4 | B7"),
        ("break", 4, "Em | C | Am | B7"),
        ("A3", 8, "Em7 | A7 | Em7 | A7 | Em7 | A7 | Cmaj7 | B7"),
        ("climax", 8, "Dmaj7 | E | C#m7 | F#m7 | Dmaj7 | E | C#7sus4 | C#7"),
        ("final", 4, "F#m7 | B7 | F#m7 | B7"),
    ])
    hook = melody("""r:2 B4:2 D5:2 E5:4 D5:2 B4:2 G4:2 | A4:4 r:2 C#5:2 E5:2 G5:4 r:2 | r:2 B4:2 D5:2 E5:4 G5:2 F#5:2 E5:2 | E5:6 C#5:2 A4:8 |
                     r:2 B4:2 D5:2 E5:4 D5:2 B4:2 G4:2 | A4:4 r:2 C#5:2 E5:2 A5:4 G5:2 | G5:4 E5:4 B4:4 G4:4 | F#5:4 D#5:4 B4:4 A4:4""")
    chorus = melody("""E5:6 G5:2 B5:8 | A5:6 F#5:2 D5:8 | F#5:4 A5:4 B5:4 D6:4 | B5:12 G5:4 |
                       E5:6 G5:2 B5:4 C6:4 | D6:6 C6:2 A5:4 F#5:4 | E5:8 F#5:8 | D#5:16""")
    fanfare = melody("B4:2 E5:2 G5:2 B5:10 | A5:2 G5:2 F#5:2 G5:2 E5:8 | G5:2 C6:2 E6:2 G6:6 F#6:2 E6:2 | D#6:4 F#6:4 A5:2 B5:6")
    strings_line = melody("B5:16 | C#6:16 | B5:16 | C#6:8 E6:8 | G6:16 | E6:16 | E6:8 G6:8 | F#6:16")

    def lead_brass(m, sec):
        return ins.brass(m, sec, bright=1.0, section=3)

    kick, clap, ohat, chat, shake = s.kick(1.1, 0.4), s.clap(), s.hat(True), s.hat(False), s.shaker()
    toms = [ins.tom(p, 0.4) for p in (110.0, 150.0, 200.0)]

    for bar in (0, 1):
        for k, step in enumerate((3, 9, 14)):
            tr.add("fx", bar, step, ins.bloop(90.0 + 30 * k, 2.2), 0.6, -0.3 + 0.3 * k)
    tr.add("fx", 2, 0, ins.orchestra_hit((52, 59, 64, 67)), 1.0)
    for k in range(32):
        tr.add("fx", 2, k / 2, ins.timpani(40, 0.6, 0.4), 0.15 + 0.01 * k)
    tr.play("brass", 4, fanfare, lead_brass)

    pent = [64, 67, 69, 71, 74, 76, 79, 81]
    rng = np.random.default_rng(5)
    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 28)
            notes = voicing(c, 60, 74, prev)
            prev = notes
            seconds = length * tr.step
            # bass
            if name == "intro":
                if local >= 2:
                    for k in range(8):
                        tr.add("bass", bar, k * 2, ins.synth_bass(root + 12, tr.step * 1.4, cutoff=500, env_amt=800 + 120 * local), 0.9)
            elif name == "break":
                tr.add("bass", bar, 0, ins.synth_bass(root + 12, tr.step * 12, cutoff=400, env_amt=400), 1.0)
            else:
                seventh = 10 if "7" in c.name and "maj" not in c.name else 7
                # disco octaves: a thumbed root, a popped octave (slap_bass adds it), the seventh near the end
                for st, off, pop in ((0, 0, False), (2, 0, True), (4, 0, False), (6, 0, True),
                                     (8, 0, False), (10, 0, True), (12, seventh, False), (14, 0, True)):
                    tr.add("bass", bar, step + st, ins.slap_bass(root + 12 + off, tr.step * 1.6, pop), 0.8 if pop else 1.0)
            # clav funk
            if name in ("A1", "A2", "A3", "final"):
                for k, ch in enumerate("x.xx.x.x..x.xx.x"):
                    if ch == "x":
                        if k % 4 == 0:
                            strum(tr, "clav", bar, k, notes, ins.clav, tr.step * 0.9, 1.0, spread=0.004)
                        else:
                            tr.add("clav", bar, k, ins.clav(notes[k % len(notes)], tr.step * 0.8), 0.75, 0.25)
            # pads
            if name in ("chorus", "climax"):
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.08, bright=0.6), 1.0)
                tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "ah", attack=0.15), 1.0)
            elif name == "break" or (name == "intro" and local >= 4):
                tr.add("pad", bar, step, ins.strings(tuple(n - 12 for n in notes[:3]), seconds, attack=0.6, bright=0.3), 1.0)
                if name == "break":
                    tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "oo", attack=0.4), 1.0)
            # brass stabs on the and-of-4, and the robot's call-board bleeps
            if name in ("A1", "A2", "A3", "final") and local % 2 == 1:
                strum(tr, "stabs", bar, 14, [n + 12 for n in notes[:3]], lambda m, sec: ins.brass(m, sec, bright=1.0, section=2), tr.step * 1.5, 1.0, spread=0.0)
            if name in ("intro", "break", "A3", "final") or (name == "A2" and local >= 4):
                density = 8 if name in ("intro", "A2") else 16
                for k in range(0, 16, 16 // density):
                    if rng.random() < 0.8:
                        tr.add("bleeps", bar, k, ins.blip(pent[rng.integers(len(pent))] + 12, tr.step * 0.6), 0.7 + 0.3 * rng.random(), 0.4 if k % 2 else -0.4)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.4 + 0.1 * (local - 4))
                if local >= 5:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.5 + 0.1 * (local - 5))
                if local == 7:
                    for k, step in enumerate(range(8, 16)):
                        tr.add("drums", bar, step, toms[2 - k // 3], 0.7 + 0.04 * k)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.6)
                continue
            if name == "break":
                tr.kick("kick", bar, "X.......X.......", kick, 0.8)
                for k in range(16):
                    tr.add("fx", bar, k, ins.timpani(40, 0.4, 0.3), 0.1 + (0.012 * k if local == 3 else 0))
                tr.add("fx", bar, 4, ins.bloop(80.0, 2.5, 0.25), 0.7, -0.4)
                tr.add("fx", bar, 11, ins.bloop(120.0, 2.0, 0.2), 0.6, 0.4)
                if local == 3:
                    for k in range(16):
                        tr.add("drums", bar, k, s.snare(0.15), 0.25 + 0.04 * k, 0.1)
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.6)
                continue
            tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
            tr.drum("drums", bar, "....X.......X...", clap, 1.0, 0.05)
            tr.drum("hats", bar, "..X...X...X...X.", ohat, 0.9, 0.25)
            tr.drum("hats", bar, "x.x.x.x.x.x.x.x." if name in ("A1", "chorus") else "xxxxxxxxxxxxxxxx", chat, 0.5, -0.25)
            tr.drum("perc", bar, "xoxoxoxoxoxoxoxo", shake, 1.0, 0.35)
            if local == 0:
                tr.add("hats", bar, 0, s.crash(), 2.0, 0.2)
                if name in ("A1", "chorus", "climax"):
                    tr.add("fx", bar, 0, ins.orchestra_hit(tuple(voicing(part.changes[0][3], 60, 76))), 0.8)
            if local == part.bars - 1 and name in ("A2", "A3", "climax"):
                for k, step in enumerate((12, 13, 14, 15)):
                    tr.add("drums", bar, step, toms[2 - k // 2], 0.8)

    tr.play("lead", 8, hook, lead_brass)
    tr.play("lead", 16, hook, lead_brass)
    tr.play("lead2", 16, shift(hook, 12), lambda m, sec: ins.synth_pluck(m, sec, bright=2500), pan=0.2)
    tr.play("strings", 16, strings_line, lambda m, sec: ins.strings((m,), sec, attack=0.2, bright=0.6))
    tr.play("lead", 24, chorus, lead_brass)
    tr.play("lead2", 24, shift(chorus, 12), ins.glock, pan=0.25)
    tr.play("lead", 36, hook, lead_brass)
    tr.play("lead2", 36, shift(hook, -3), lead_brass, pan=-0.2)
    tr.play("lead", 44, shift(chorus, 2), lead_brass)
    tr.play("lead2", 44, shift(chorus, 14), ins.glock, pan=0.25)
    tr.play("strings", 44, shift(chorus, -10), lambda m, sec: ins.strings((m,), sec, attack=0.1, bright=0.6))
    tr.play("lead", 52, [n for n in shift(hook, 2) if n.step < 4 * 16], lead_brass)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.15, delay=0.08),
        "lead2": Bus(-15, reverb=0.2),
        "strings": Bus(-14, reverb=0.25),
        "stabs": Bus(-13, reverb=0.15),
        "clav": Bus(-14, pump=0.15, delay=0.06),
        "bass": Bus(-8, pump=0.3),
        "pad": Bus(-15, pump=0.3, reverb=0.25),
        "choir": Bus(-16, pump=0.2, reverb=0.3),
        "bleeps": Bus(-19, delay=0.25),
        "kick": Bus(-8, drive=1.4),
        "drums": Bus(-12, reverb=0.12),
        "hats": Bus(-17),
        "perc": Bus(-20),
        "fx": Bus(-14, reverb=0.3),
    }, reverb_decay=1.6, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.32, pump_release=0.16)
    return finish(tr, mix), tr


SONG = Song("HexMeltdown", "Molten Showdown", 124, 8, 56, hex_meltdown)
