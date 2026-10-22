"""Tiki Bumper Bash - the round track for BumperBallers (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum


def bumper_ballers():
    """Tiki Bumper Bash (128 bpm soca, G major): the party islet in the lagoon, balls rolling round
    the tiki bar. A steel band (a tenor pan with a bouncy 3-3-2 hook, a second pan comping, rolled
    pans for the sunset B tune), soca drums with the iron, congas and log drums, a ukulele and a
    horn section; the finale jumps up to A major exactly at BIG BUMPS (45 s into the round)."""
    tr = Track(bpm=128, bars=44)  # 1.875 s a bar: GO at bar 8 (15 s), BIG BUMPS at bar 32 (45 s in)
    parts = plan(tr, [
        ("intro", 8, "G | G | C | D | G | Em | C | D"),
        ("A1", 8, "G | C | D | G | G | C | D | G"),
        ("A2", 8, "G | C | D | G | G | C | D | G"),
        ("B", 8, "Em | C | G | D | Em | C | Am | D7"),
        ("finale", 12, "A | D | E | A | A | D | E | A | F#m | D | C | D7"),
    ])
    hook = melody("""D5:3 G5:3 B5:2 A5:2 G5:2 E5:2 D5:2 | E5:3 G5:3 C6:2 B5:4 A5:4 | F#5:3 A5:3 D6:2 C6:2 B5:2 A5:2 F#5:2 | B5:6 A5:2 G5:8 |
                     D5:3 G5:3 B5:2 D6:2 B5:2 G5:2 B5:2 | C6:3 B5:3 A5:2 G5:4 E5:4 | F#5:2 G5:2 A5:2 B5:2 C6:3 B5:3 A5:2 | G5:8 r:4 D5:2 F#5:2""")
    sunset = melody("""B5:6 A5:2 G5:4 E5:4 | G5:6 E5:2 C5:8 | D5:4 G5:4 B5:4 D6:4 | C6:6 B5:2 A5:8 |
                       B5:6 A5:2 G5:4 E5:4 | E6:6 D6:2 C6:8 | C6:4 B5:4 A5:4 E5:4 | F#5:8 A5:4 C6:4""")
    answer = melody("""r:8 B4:2 D5:2 r:4 | r:8 C5:2 E5:2 r:4 | r:8 D5:2 F#5:2 r:4 | r:4 D5:2 B4:2 G4:8 |
                       r:8 B4:2 D5:2 r:4 | r:8 C5:2 E5:2 r:4 | r:8 A4:2 C5:2 r:4 | r:16""")
    tag = melody("F#5:3 A5:3 C#6:2 B5:4 A5:4 | F#5:3 A5:3 D6:2 C#6:4 A5:4 | G5:3 C6:3 E6:2 D6:2 C6:2 B5:2 C6:2 | r:16")
    teaser = melody("D5:3 G5:3 B5:2 r:8 | E5:3 G5:3 C6:2 r:8 | F#5:3 A5:3 D6:2 r:8 | B5:6 A5:2 G5:8")

    def pan_roll(m, sec):
        return ins.steel_pan(m, sec)

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.8, section=3)

    def play_rolled(stem, bar, notes, gain=1.0, pan=0.0):
        """Steel-pan style: short notes struck once, long ones rolled (re-struck every 16th)."""
        for n in notes:
            if n.length >= 4:
                k = 0
                while k < n.length - 0.5:
                    tr.add(stem, bar, n.step + k, ins.steel_pan(n.midi, tr.step * 1.2), gain * n.vel * (1.0 if k == 0 else 0.62 + 0.1 * (k % 2)), pan)
                    k += 1
            else:
                tr.add(stem, bar, n.step, ins.steel_pan(n.midi, n.length * tr.step), gain * n.vel, pan)

    kick, clap, ohat, chat, shake = s.kick(1.0, 0.4), s.clap(), s.hat(True), s.hat(False), s.shaker()
    snare = ins.snare2(230.0, 0.8, 0.22)
    irons = [ins.iron(0.18, v) for v in range(3)]
    logs = [ins.log_drum(p) for p in (330.0, 247.0, 196.0)]
    congas = [ins.conga(330.0), ins.conga(250.0, slap=True), ins.conga(196.0)]
    toms = [ins.tom(p, 0.4) for p in (120.0, 160.0, 210.0)]

    # The intro: surf on the reef and a lone pan teasing the hook, then the island wakes up.
    tr.add("fx", 0, 0, ins.waves(tr.bar * 6), 0.9)
    tr.add("fx", 43, 0, ins.waves(tr.bar * 2), 0.5)  # rolls on round the loop into the next intro
    play_rolled("lead", 2, teaser, 0.75)
    tr.play("lead", 6, melody("D5:3 G5:3 B5:2 A5:2 G5:2 E5:2 D5:2 | E5:3 G5:3 C6:2 D6:2 C6:2 B5:2 A5:2", 16), ins.steel_pan, 0.85)
    tr.add("fx", 6, 0, s.riser(tr.bar * 2), 0.5)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 28)
            notes = voicing(c, 62, 74, prev)
            prev = notes
            seconds = length * tr.step
            fifth = root + 7
            # bass: the soca 3-3-2 bounce, roots and octaves (E2..D#3, so a phone carries it)
            if name == "intro":
                if local >= 6:
                    for st in (0, 6, 12):
                        tr.add("bass", bar, step + st, ins.synth_bass(root + 12, tr.step * 2.5, cutoff=600, env_amt=900, sub=0.35), 0.8)
            elif name == "finale" and local == 11:
                tr.add("bass", bar, 0, ins.synth_bass(root + 12, tr.step * 3, cutoff=700, env_amt=1200, sub=0.35), 1.0)
            else:
                pattern = ((0, 0), (3, 12), (6, 0), (8, 7), (11, 12), (14, 7)) if name in ("A2", "finale") else ((0, 0), (3, 12), (6, 0), (8, 7), (11, 0), (14, 12))
                if name == "B":
                    pattern = ((0, 0), (6, 0), (8, 7), (12, 12))
                for st, off in pattern:
                    if st < length:
                        tr.add("bass", bar, step + st, ins.synth_bass(root + 12 + off, tr.step * 2.2, cutoff=750, env_amt=1300, sub=0.35), 1.0 if st in (0, 8) else 0.8)
            # the second pan comps on the off-beats (the "strum" of a steel band)
            if name == "intro" and local >= 4:
                for st in (2, 6, 10, 14):
                    strum(tr, "comp", bar, st, notes, ins.steel_pan, tr.step * 1.2, 0.55 + 0.08 * (local - 4), spread=0.008, pan=-0.3)
            elif name in ("A1", "A2", "finale") and not (name == "finale" and local == 11):
                for st in (2, 6, 10, 14):
                    strum(tr, "comp", bar, st, notes, ins.steel_pan, tr.step * 1.2, 1.0 if st in (6, 14) else 0.8, spread=0.008, pan=-0.3)
            elif name == "B":
                for st in range(0, 16, 2):  # rolled chords under the sunset tune
                    strum(tr, "comp", bar, st, notes, ins.steel_pan, tr.step * 2, 0.45 + (0.2 if st % 8 == 0 else 0), spread=0.02, pan=-0.3)
                tr.add("pad", bar, 0, ins.strings(tuple(n - 12 for n in notes[:3]), seconds, attack=0.4, bright=0.35), 0.6)
            # ukulele strum: down, down-up, up-down-up
            if name in ("A2", "finale") and not (name == "finale" and local == 11):
                for st, down in ((0, True), (4, True), (6, False), (10, False), (12, True), (14, False)):
                    strum(tr, "uke", bar, st, [n + 12 if n < 64 else n for n in notes], ins.nylon, tr.step * 1.8, 1.0 if down else 0.75, spread=0.01, down=down, pan=0.3)
            if name == "finale" and local < 11:
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.15, bright=0.55), 1.4)
                tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "ah", attack=0.1), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.drum("perc", bar, "x..x..x...x.x...", logs[0], 0.5 + 0.08 * (local - 4), 0.3)
                    tr.drum("perc", bar, "......x.......x.", logs[2], 0.5, -0.3)
                if local >= 5:
                    tr.drum("shaker", bar, "xoxoxoxoxoxoxoxo", shake, 0.5 + 0.15 * (local - 5), 0.35)
                if local >= 6:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.55 + 0.25 * (local - 6))
                    tr.drum("iron", bar, "x.xxx.xxx.xxx.xx", irons[local % 3], 0.5, -0.2)
                if local == 7:
                    for k in range(8, 16):
                        tr.add("drums", bar, k, snare, 0.3 + 0.08 * (k - 8), 0.05)
                    for k, st in enumerate((12, 13, 14, 15)):
                        tr.add("drums", bar, st, toms[2 - k // 2], 0.7)
                continue
            last = name == "finale" and local == 11
            if last:  # the band stops on the downbeat, a pan rolls the D7 back to the beach
                tr.kick("kick", bar, "X...............", kick, 1.0)
                tr.add("cymbal", bar, 0, s.crash(), 1.4, 0.2)
                strum(tr, "comp", bar, 0, voicing(part.changes[-1][3], 62, 74), ins.steel_pan, tr.step * 3, 1.0, spread=0.0)
                for k, m in enumerate((62, 66, 69, 72, 74, 78)):
                    tr.add("lead", bar, 6 + k * 1.5, ins.steel_pan(m, 0.4), 0.55 - 0.05 * k, -0.2 + 0.08 * k)
                continue
            half = name == "B" and local < 4
            lift = {"A1": 0.8, "A2": 0.9, "B": 0.8, "finale": 1.1}[name]
            tr.kick("kick", bar, "X...X...X...X..." if not half else "X.......X.......", kick, lift)
            tr.drum("drums", bar, "....X.......X..." if not half else "........X.......", snare, lift, 0.05)
            tr.drum("drums", bar, "......o..o....o." if name != "B" else "..............o.", snare, 0.5, 0.05)
            if name == "finale":
                tr.drum("drums", bar, "....X.......X...", clap, 0.9, -0.05)
            tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.8, 0.25)
            tr.drum("shaker", bar, "xoxoxoxoxoxoxoxo" if name != "finale" else "xxxxxxxxxxxxxxxx", shake, 0.9, 0.35)
            tr.drum("iron", bar, "x.xxx.xxx.xxx.xx" if name != "B" else "x...x...x...x.x.", irons[local % 3], 0.9, -0.2)
            if name in ("A2", "B", "finale"):
                tr.drum("perc", bar, "..x..x.x..x..x.x", congas[0], 0.7, 0.4)
                tr.drum("perc", bar, "......x.......x.", congas[1], 0.8, 0.4)
                tr.drum("perc", bar, "x.......x.......", congas[2], 0.6, 0.4)
            if name in ("A1", "B"):
                tr.drum("perc", bar, "x..x..x...x.x...", logs[local % 2], 0.5, -0.35)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.5, 0.2)
            if local == part.bars - 1 and name in ("A1", "A2", "B"):
                for k, st in enumerate((12, 13, 14, 15)):
                    tr.add("drums", bar, st, toms[2 - k // 2], 0.75)
            if name == "B" and local == 7:
                tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.6)

    # BIG BUMPS: a referee's whistle, a boom, and the horns lift the hook a tone higher.
    tr.add("fx", 32, 0, s.impact(), 0.9)
    for k, st in enumerate((0, 3, 6)):
        tr.add("whistle", 31, 8 + st, ins.whistle(91, tr.step * (2 if k < 2 else 2.5)), 0.9, 0.2)
    for bar in (33, 35, 37, 39, 41):
        tr.add("fx", bar, 14, ins.bloop(180.0, 2.5, 0.16), 0.5, 0.4)  # a "boing" off the bumpers

    tr.play("lead", 8, hook, ins.steel_pan, 0.85)
    tr.play("lead", 16, hook, ins.steel_pan, 0.95)
    tr.play("lead2", 16, shift(hook, -12), ins.marimba, pan=0.25)
    tr.play("horns", 16, answer, horn, pan=-0.15)
    play_rolled("lead", 24, sunset, 0.85)
    tr.play("lead2", 24, shift(sunset, -12), lambda m, sec: ins.flute(m + 12, sec, vibrato=0.1), 0.6, pan=0.25)
    tr.play("lead", 32, shift(hook, 2), ins.steel_pan, 1.15)
    tr.play("horns", 32, shift(hook, 2 - 12), horn, pan=-0.15)
    tr.play("lead2", 32, shift(answer, 2 + 12), ins.steel_pan, 0.8, pan=0.3)
    tr.play("lead", 40, tag, ins.steel_pan, 1.15)
    tr.play("horns", 40, shift(tag, -12), horn, pan=-0.15)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.18, delay=0.1),
        "lead2": Bus(-15, reverb=0.2),
        "horns": Bus(-11, reverb=0.18),
        "comp": Bus(-13, pump=0.2, reverb=0.15),
        "uke": Bus(-16, pump=0.2),
        "pad": Bus(-17, pump=0.25, reverb=0.25),
        "choir": Bus(-18, pump=0.2, reverb=0.3),
        "bass": Bus(-8, pump=0.3),
        "kick": Bus(-9, drive=1.4),
        "drums": Bus(-13, reverb=0.12),
        "hats": Bus(-19),
        "shaker": Bus(-21),
        "iron": Bus(-18, reverb=0.08),
        "perc": Bus(-15, reverb=0.1),
        "cymbal": Bus(-20, reverb=0.1),
        "whistle": Bus(-14, reverb=0.25),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=1.5, reverb_tone=6500, delay_time=tr.beat * 0.75, delay_feedback=0.3, pump_release=0.16)
    return finish(tr, mix), tr


SONG = Song("BumperBallers", "Tiki Bumper Bash", 128, 8, 44, bumper_ballers)
