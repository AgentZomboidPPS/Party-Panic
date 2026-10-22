"""Canyon Grind - the round track for SkateEscape (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum, tremolo


def skate_escape():
    """Canyon Grind (180 bpm skate punk, E major): a wooden bridge over a lava canyon, crumbling
    behind the pack. A three-piece punk band and a lead guitar with the hook: a clean guitar riff
    over the lava's rumble and a stick count-in, then palm mutes, a sing-along chorus with gang
    shouts, a half-time bridge, a drum build as the collapse speeds up, and the chorus a tone higher
    (F sharp) for the last 15 seconds of the race."""
    tr = Track(bpm=180, bars=56)  # 1.333 s a bar: GO at bar 10 (13.3 s), the finale at bar 44 (45.3 s in)
    parts = plan(tr, [
        ("intro", 10, "E | E | E | E | E | E | E | E | E | B"),
        ("verse1", 8, "E | E | A | B | C#m | A | E | B"),
        ("chorus", 8, "A | B | G#m | C#m | A | B | E | E"),
        ("verse2", 8, "E | E | A | B | C#m | A | E | B"),
        ("bridge", 6, "C#m | A | E | B | C#m | B"),
        ("build", 4, "E | E | B | B"),
        ("finale", 12, "B | C# | A#m | D#m | B | C# | F# | F# | B | C# | D | E"),
    ])
    verse = melody("""B4:2 E5:2 G#5:2 B5:4 G#5:2 E5:2 F#5:2 | G#5:6 r:2 E5:2 F#5:2 G#5:4 | A5:2 C#6:2 B5:2 A5:2 E5:4 C#5:4 | D#5:4 F#5:4 B5:6 r:2 |
                      E5:2 G#5:2 C#6:2 B5:4 G#5:2 E5:2 C#5:2 | E5:4 C#5:2 E5:2 A5:8 | G#5:2 A5:2 B5:4 E6:4 B5:4 | A5:4 G#5:4 F#5:4 D#5:4""")
    chorus = melody("""C#5:2 E5:2 E5:2 E5:2 F#5:2 E5:2 C#5:4 | D#5:2 F#5:2 F#5:2 F#5:2 G#5:2 F#5:2 D#5:4 | B5:4 G#5:2 B5:2 D#6:4 B5:4 | C#6:8 B5:4 G#5:4 |
                       C#5:2 E5:2 E5:2 E5:2 F#5:2 E5:2 C#5:4 | D#5:2 F#5:2 F#5:2 F#5:2 A5:2 G#5:2 F#5:4 | G#5:4 F#5:2 E5:2 B5:8 | G#5:4 E5:4 r:8""")
    bridge = melody("G#5:8 E5:4 C#5:4 | E5:6 F#5:2 A5:8 | G#5:8 B5:4 E6:4 | D#6:12 r:4 | E6:4 D#6:4 C#6:4 B5:4 | F#5:16")
    outro = melody("D#6:4 C#6:4 A#5:4 F#5:4 | F5:4 G#5:4 C#6:8 | D6:2 A5:2 F#5:2 D6:2 A5:2 F#5:2 D6:4 | E6:4 r:12")
    riff = melody("""E4:2 B4:2 E5:2 B4:2 G#4:2 B4:2 E5:2 F#5:2 | G#5:4 F#5:2 E5:2 B4:4 G#4:4""")

    def lead(m, sec):
        return ins.lead_guitar(m, sec, bend_from=1.0 if sec > 0.5 else None)

    kick = s.kick(1.1, 0.35)
    snare = ins.snare2(210.0, 1.0, 0.25)
    chat, ohat = s.hat(False), s.hat(True)
    ride = ins.ride(0.9, 0.4)
    sticks = ins.rim_click(2100.0)
    toms = [ins.tom(p, 0.35) for p in (100.0, 140.0, 190.0)]

    # The intro: lava rumbling far below, a clean guitar riff, the band creeping in, a count-in.
    tr.add("fx", 0, 0, ins.crackle(tr.bar * 4), 0.6)
    tr.add("fx", 0, 0, ins.whoosh(tr.bar * 3, up=True), 0.5)
    tr.add("fx", 4, 0, ins.whoosh(tr.bar * 3, up=False), 0.4)
    tr.add("fx", 8, 0, s.riser(tr.bar * 2), 0.55)
    for bar in range(2, 10, 2):
        tr.play("clean", bar, riff, lambda m, sec: ins.electric_guitar(m, sec * 1.6), 0.55 + 0.1 * (bar - 2) / 2, pan=0.25)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 28) + 12  # E2..D#3: the bass guitar's open strings, clear on a phone
            groot = bass_note(c, 40)
            notes = voicing(c, 64, 76, prev)
            prev = notes
            seconds = length * tr.step
            if name == "intro":
                if local >= 6:
                    for k in range(0, 16, 4 if local < 8 else 2):
                        tr.add("bass", bar, k, ins.bass_guitar(root, tr.step * 1.8, 0.6), 0.6 + 0.08 * (local - 6))
                if local >= 8:
                    for k in range(0, 16, 2):
                        tr.add("gtr", bar, k, ins.power_chord(groot, tr.step * 1.6, mute=True, variant=k % 3), 0.45 + 0.12 * (local - 8) + 0.02 * k, -0.4 if k % 4 else 0.4)
                continue
            stop = name == "finale" and local == 11
            # bass: driving 8ths, a walk-up into each new chord
            if stop:
                tr.add("bass", bar, 0, ins.bass_guitar(root, tr.bar * 0.7, 0.6), 1.0)
            elif name == "bridge":
                tr.add("bass", bar, 0, ins.bass_guitar(root, tr.step * 7, 0.5), 1.0)
                tr.add("bass", bar, 8, ins.bass_guitar(root + 7 if root + 7 < 52 else root - 5, tr.step * 7, 0.5), 0.85)
            else:
                for k in range(0, 16, 2):
                    m = root
                    if k == 14 and name != "build":
                        m = root + (2 if local % 2 else 7)
                    tr.add("bass", bar, k, ins.bass_guitar(m, tr.step * 1.8, 0.65), 1.0 if k % 4 == 0 else 0.85)
            # rhythm guitars: palm-muted 8ths in the verses, open ringing chords in the choruses
            if stop:
                strum(tr, "gtr", bar, 0, [groot, groot + 7, groot + 12], ins.electric_guitar, tr.bar * 0.8, 1.0, spread=0.008)
                tr.add("gtr", bar, 0, ins.power_chord(groot, tr.bar * 0.9, variant=1), 1.0, -0.4)
                tr.add("gtr", bar, 0, ins.power_chord(groot, tr.bar * 0.9, variant=2), 1.0, 0.4)
            elif name in ("verse1", "verse2", "build"):
                accents = (0, 6, 10) if name != "build" else (0, 4, 8, 12)
                for k in range(0, 16, 2):
                    open_ = k in accents and name in ("verse2", "build")
                    tr.add("gtr", bar, k, ins.power_chord(groot, tr.step * (3 if open_ else 1.6), mute=not open_, variant=k % 3),
                           (1.0 if k in accents else 0.75) * {"verse1": 0.85, "verse2": 1.0, "build": 1.0 + 0.1 * local}[name], -0.4 if k % 4 else 0.4)
            elif name in ("chorus", "finale"):
                for k in range(0, 16, 2):
                    tr.add("gtr", bar, step + k, ins.power_chord(groot, tr.step * 2.2, variant=k % 3), 1.0 if k % 4 == 0 else 0.85, -0.45)
                    if name == "finale":
                        tr.add("gtr", bar, step + k, ins.power_chord(groot + 12 if groot < 45 else groot, tr.step * 2.2, variant=3 + k % 3), 0.85, 0.45)
                    else:
                        tr.add("gtr", bar, step + k, ins.power_chord(groot, tr.step * 2.2, variant=3 + k % 3), 0.6, 0.45)
            elif name == "bridge":
                tr.add("gtr", bar, 0, ins.power_chord(groot, tr.step * 14, variant=local), 0.9, -0.4)
                strum(tr, "clean", bar, 0, notes, lambda m, sec: ins.electric_guitar(m, sec), tr.step * 8, 0.9, spread=0.02, pan=0.3)
                strum(tr, "clean", bar, 8, notes, lambda m, sec: ins.electric_guitar(m, sec), tr.step * 8, 0.7, spread=0.02, down=False, pan=0.3)
            if name in ("chorus", "finale") and not stop:
                tr.add("pad", bar, step, ins.organ(notes[0], seconds, drawbars=(0, 0, 8, 6, 0, 4, 0, 0, 0), leslie=6.0, click=0.2), 0.5)
                tr.add("pad", bar, step, ins.organ(notes[1], seconds, drawbars=(0, 0, 8, 6, 0, 4, 0, 0, 0), leslie=6.0, click=0.2), 0.5)
                tr.add("pad", bar, step, ins.organ(notes[2], seconds, drawbars=(0, 0, 8, 6, 0, 4, 0, 0, 0), leslie=6.0, click=0.2), 0.5)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.4 + 0.06 * (local - 4))
                if local >= 6:
                    tr.drum("toms", bar, "X.......X.......", toms[0], 0.6 + 0.05 * (local - 6))
                if local == 8:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.7)
                if local == 9:
                    tr.drum("perc", bar, "X...X...X...X...", sticks, 0.9)  # the drummer's count-in: 1, 2, 3, 4
                    for k in range(8, 16):
                        tr.add("drums", bar, k, snare, 0.35 + 0.07 * (k - 8), 0.05)
                continue
            if name == "finale" and local == 11:
                tr.kick("kick", bar, "X...............", kick, 1.0)
                tr.add("drums", bar, 0, snare, 1.0, 0.05)
                tr.add("cymbal", bar, 0, s.crash(2.4), 1.6, 0.25)
                tr.add("cymbal", bar, 0, s.crash(2.4), 1.2, -0.25)
                continue
            if name == "verse1":
                tr.kick("kick", bar, "X.....x.X.......", kick, 0.9)
                tr.drum("drums", bar, "....X.......X...", snare, 0.9, 0.05)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.8)
            elif name == "bridge":
                tr.kick("kick", bar, "X.......X.x.....", kick, 0.9)
                tr.drum("drums", bar, "........X.......", snare, 1.0, 0.05)
                tr.drum("hats", bar, "x...x...x...x...", ohat, 0.6)
                if local % 2 == 0:
                    tr.add("cymbal", bar, 0, s.crash(), 1.0, 0.25)
            elif name == "build":
                tr.kick("kick", bar, "X...X...X...X...", kick, 0.85 + 0.05 * local)
                fill = ("..X...X...X...X.", "..X...X...X...X.", "..X.X.X.X.X.X.X.", "X.X.X.X.XXXXXXXX")[local]
                tr.drum("drums", bar, fill, snare, 0.6 + 0.1 * local, 0.05)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.7)
                if local == 2:
                    tr.add("fx", bar, 0, s.riser(tr.bar * 2), 0.6)
                if local == 3:
                    for k, st in enumerate((12, 13, 14, 15)):
                        tr.add("toms", bar, st, toms[2 - k // 2], 0.9)
            else:  # the skate-punk beat: kick on the beat, snare on every "and"
                tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
                tr.drum("drums", bar, "..X...X...X...X.", snare, 0.95, 0.05)
                if name == "verse2":
                    tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.9)
                else:
                    tr.drum("cymbal", bar, "x...x...x...x...", ride, 0.8, -0.25)
                    tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.5, 0.25)
            if local == 0 and name != "bridge":
                tr.add("cymbal", bar, 0, s.crash(), 1.5, 0.25)
            if local == part.bars - 1 and name in ("verse1", "chorus", "verse2"):
                for k, st in enumerate((8, 10, 12, 14)):
                    tr.add("toms", bar, st, toms[2 - min(2, k)], 0.85)
            # gang shouts in the choruses: "HEY!" on the and-of-4 every other bar
            if name in ("chorus", "finale") and local % 2 == 1 and local < 10:
                tr.add("gang", bar, 14, ins.choir((64, 68, 71), 0.16, "eh", attack=0.01), 1.0)
                tr.add("perc", bar, 14, s.clap(), 0.8)

    tr.play("lead", 10, verse, lead, 0.85)
    tr.play("lead", 18, chorus, lead, 0.92)
    tr.play("lead2", 18, shift(chorus, -12), lambda m, sec: ins.lead_guitar(m, sec, variant=1), 0.7, pan=-0.3)
    tr.play("lead", 26, verse, lead, 0.9)
    tr.play("lead2", 26, shift(verse, -5), lambda m, sec: ins.lead_guitar(m, sec, variant=1), 0.55, pan=-0.3)
    tr.play("lead", 34, bridge, lead)
    tremolo(tr, "lead", 40, melody("B4:16 | E5:16 | F#5:16 | A#5:8 B5:8"), lambda m, sec: ins.lead_guitar(m, sec, variant=2), 1, 0.75)
    tr.play("lead", 44, shift(chorus, 2), lead, 1.1)
    tr.play("lead2", 44, shift(chorus, 2 - 12), lambda m, sec: ins.lead_guitar(m, sec, variant=1), 0.8, pan=-0.3)
    tr.play("gang", 44, [n for n in shift(chorus, 2 - 12) if n.length >= 4], lambda m, sec: ins.choir((m, m + 12), sec, "ah", attack=0.05), 0.7)
    tr.play("lead", 52, outro, lead, 1.1)
    tr.play("lead2", 52, shift(outro, -12), lambda m, sec: ins.lead_guitar(m, sec, variant=1), 0.8, pan=-0.3)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.15, delay=0.12),
        "lead2": Bus(-14, reverb=0.15),
        "clean": Bus(-12, reverb=0.25, delay=0.2),
        "gtr": Bus(-9, eq=(("hp", 120), ("peak", 2800, -2, 1.0), ("lp", 6000))),
        "pad": Bus(-19, reverb=0.2),
        "gang": Bus(-15, reverb=0.25),
        "bass": Bus(-9, pump=0.15),
        "kick": Bus(-10, drive=1.4),
        "drums": Bus(-11, reverb=0.12),
        "toms": Bus(-14, reverb=0.12),
        "hats": Bus(-20),
        "cymbal": Bus(-20, reverb=0.08),
        "perc": Bus(-17, reverb=0.1),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=1.4, reverb_tone=5500, delay_time=tr.beat * 0.75, delay_feedback=0.25, pump_release=0.12)
    return finish(tr, mix), tr


SONG = Song("SkateEscape", "Canyon Grind", 180, 10, 56, skate_escape)
