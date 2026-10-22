"""Hobby Horse Hop - the round track for RockinRaceway (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum


def rockin_raceway():
    """Hobby Horse Hop (168 bpm, A major): a rock'n'roll band at the fairground oval. Slapped upright
    bass walking a boogie, a honky-tonk piano, a growling tenor sax with the hook, twangy guitar and
    coconut hooves galloping under it all. A 12-bar verse, a stop-time bridge (the hurdles: hit, hop,
    land) for the twang guitar, then up a step to B for the home stretch (about when the first riders
    are home and the finish clock runs) and a shout chorus to the finish line."""
    tr = Track(bpm=168, bars=52)
    parts = plan(tr, [
        ("intro", 10, "A | A | A | A | D | D | A | A | E7 | E7"),
        ("verse", 12, "A | A | A | A | D | D | A | A | E7 | D | A | E7"),
        ("bridge", 8, "D | D | A | A | B7 | B7 | E | F#7"),
        ("finale", 12, "B | B | B | B | E | E | B | B | F#7 | E | B | F#7"),
        ("rideout", 10, "B | B | B | B | E | E | B | B | F#7 | B"),
    ])
    hook = melody("""A4:2 C#5:2 E5:2 F#5:4 E5:2 C5:2 C#5:2 | A4:6 r:2 E5:2 A5:2 r:2 G5:2 | A4:2 C#5:2 E5:2 F#5:4 E5:2 C5:2 C#5:2 | E5:8 r:4 C#5:2 E5:2 |
                     D5:2 F#5:2 A5:2 B5:4 A5:2 F5:2 F#5:2 | D5:6 r:2 A5:2 D6:2 r:2 C6:2 | A5:2 G5:2 E5:2 C#5:2 E5:4 C#5:2 A4:2 | A4:8 r:4 B4:2 C#5:2 |
                     E5:4 G#5:2 B5:2 D6:4 B5:4 | D6:2 C6:2 A5:2 F#5:2 A5:4 F#5:2 D5:2 | C#5:2 E5:2 A5:2 C#6:2 r:2 A5:2 r:2 E5:2 | D5:2 E5:2 G#5:2 B5:2 E5:8""")
    twang = melody("""F#5:4 A5:4 D6:6 C#6:2 | B5:4 A5:4 F#5:8 | E5:4 A5:4 C#6:6 B5:2 | A5:12 r:4 |
                      D#5:4 F#5:4 B5:6 A5:2 | A5:4 F#5:4 D#5:8 | E5:4 G#5:4 B5:4 E6:4 | F#5:2 A#5:2 C#6:2 E6:2 C#6:2 A#5:2 F#5:4""")
    ending = melody("B5:2 B5:2 r:2 B5:2 r:2 A5:2 F#5:2 E5:2")  # the last bar's shout, then a run down

    def tenor(m, sec):
        return ins.sax(m, sec, growl=0.35)

    def twangy(m, sec):
        return ins.electric_guitar(m, sec)

    kick, chat, ohat, clap = s.kick(1.0, 0.35), s.hat(False), s.hat(True), s.clap()
    snare = ins.snare2(210.0, 1.0, 0.24)
    ghost = ins.snare2(210.0, 0.7, 0.12, variant=1)
    clip, clop = ins.woodblock(820.0, 0.1), ins.woodblock(610.0, 0.12)
    slap = ins.rim_click(2400.0)
    ride = ins.ride(1.0, 0.4)

    # the fairground far away: a carousel's glockenspiel turning, a bell for the riders
    for bar in range(4):
        for k, m in enumerate((69, 73, 76, 81, 76, 73)):
            tr.add("glock", bar, 2 + k * 2, ins.glock(m + (0 if bar % 2 == 0 else 2 if k in (1, 4) else 0), 0.5), 0.35 + 0.1 * bar, 0.4)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            notes = voicing(c, 60, 72, prev)
            prev = notes
            root = bass_note(c, 40)
            seconds = length * tr.step
            sixth, seventh = (9, 10)
            boogie = [0, 4, 7, sixth, seventh, sixth, 7, 4]
            if name == "intro":
                if 4 <= local < 8:
                    for k, off in enumerate(boogie):
                        tr.add("bass", bar, k * 2, ins.upright(root + off, tr.step * 1.8, variant=k), 0.55 + 0.1 * (local - 4))
                elif local >= 8:
                    tr.add("bass", bar, 0, ins.upright(root, tr.step * 3), 1.0)
                    strum(tr, "piano", bar, 0, [n + 12 for n in notes], ins.honky_piano, tr.step * 3, 1.0, spread=0.004)
                if 6 <= local < 8:
                    for k in range(0, 16, 2):
                        tr.add("piano", bar, k, ins.honky_piano(notes[-1] + 12 + (0 if k % 4 == 0 else 2), tr.step * 2), 0.5 + 0.05 * k / 2, 0.2)
                continue
            if name == "bridge":
                # stop-time: the band hits and the riders hop the hurdle
                for k in (0, 6):
                    tr.add("bass", bar, k, ins.upright(root, tr.step * 3), 1.0)
                    strum(tr, "piano", bar, k, [n + 12 for n in notes], ins.honky_piano, tr.step * 3, 1.0, spread=0.004)
                    strum(tr, "rhythm", bar, k, [root + 12] + notes, ins.acoustic_guitar, tr.step * 3, 1.0, spread=0.008, pan=-0.3)
                if local % 2 == 1:
                    for k, m in enumerate((notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24)):
                        tr.add("piano", bar, 8 + k, ins.honky_piano(m, tr.step * 2), 0.7, 0.25)
                continue
            if bar == tr.bars - 1:
                for k in (0, 6):
                    tr.add("bass", bar, k, ins.upright(root, tr.step * 2), 1.0)
                    strum(tr, "piano", bar, k, [n + 12 for n in notes], ins.honky_piano, tr.step * 2, 1.0, spread=0.004)
                    strum(tr, "rhythm", bar, k, [root + 12] + notes, ins.acoustic_guitar, tr.step * 2, 1.0, spread=0.008, pan=-0.3)
                tr.add("pad", bar, 0, ins.choir(tuple(notes[:3]), tr.step * 6, "ah", attack=0.05), 1.0)
                continue
            for k, off in enumerate(boogie):
                tr.add("bass", bar, step + k * 2, ins.upright(root + off, tr.step * 1.8, variant=k), 1.0 if k % 2 == 0 else 0.85)
            for k in (4, 12):
                strum(tr, "rhythm", bar, step + k, [root + 12] + notes, ins.acoustic_guitar, tr.step * 2, 1.0, spread=0.008, pan=-0.3)
            if name == "verse":
                for k in (2, 6, 10, 14):
                    strum(tr, "piano", bar, step + k, [n + 12 for n in notes], ins.honky_piano, tr.step * 1.5, 0.8, spread=0.003, pan=0.2)
            else:
                # the piano rolls triplet-ish 8ths over the top and glisses into each new chord
                for k in range(0, 16, 2):
                    strum(tr, "piano", bar, step + k, [n + 12 for n in notes], ins.honky_piano, tr.step * 1.5, 0.9 if k % 4 else 1.0, spread=0.003, pan=0.2)
                if local % 4 == 3:
                    for k in range(8):
                        tr.add("piano", bar, 8 + k, ins.honky_piano(bass_note(c, 79) + (0, 2, 4, 5, 7, 9, 11, 12)[k], tr.step), 0.5, 0.3)
                tr.add("pad", bar, step, ins.choir(tuple(notes[:3]), seconds, "ah", attack=0.08), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                # hooves: a slow walk, then a trot, then the gallop
                pattern = "X.......x......." if local < 2 else ("X...x...X...x..." if local < 4 else "X.xxX.xxX.xxX.xx")
                tr.drum("hooves", bar, pattern, clip, 0.4 + 0.06 * local, -0.25)
                tr.drum("hooves", bar, pattern.replace("X", ".").replace("x", "o") if local >= 4 else "....x.......x...", clop, 0.4 + 0.06 * local, 0.25)
                if local >= 6:
                    tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.4 + 0.1 * (local - 6), -0.2)
                    tr.drum("snare", bar, "....X.......X...", slap, 0.5, 0.15)
                if local == 8:
                    tr.drum("snare", bar, "X...............", snare, 1.0)
                    tr.kick("kick", bar, "X...............", kick, 1.0)
                    tr.add("hats", bar, 0, s.crash(), 1.2, 0.2)
                if local == 9:
                    tr.kick("kick", bar, "X...............", kick, 1.0)
                    for k in range(4, 16):
                        tr.add("snare", bar, k, snare if k % 2 == 0 else ghost, 0.35 + 0.05 * k, 0.05)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.5)
                continue
            if name == "bridge":
                tr.kick("kick", bar, "X.....X.........", kick, 1.0)
                tr.drum("snare", bar, "X.....X.........", snare, 0.9)
                tr.add("hats", bar, 0, s.crash(1.4), 0.9 if local % 2 == 0 else 0.6, 0.25)
                tr.drum("hooves", bar, "........X.xxX.xx", clip, 0.7, -0.25)
                if local % 2 == 1:
                    tr.add("fx", bar, 9, ins.slide_whistle(72, 84, tr.step * 3), 0.6, 0.2)  # hop!
                    tr.add("fx", bar, 12, ins.slide_whistle(84, 76, tr.step * 2), 0.45, 0.2)
                if local == 7:
                    for k in range(8, 16):
                        tr.add("snare", bar, k, snare, 0.5 + 0.06 * (k - 8), 0.05)
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.5)
                continue
            big = name in ("finale", "rideout")
            if bar == tr.bars - 1:
                tr.kick("kick", bar, "X.....X.........", kick, 1.0)
                tr.drum("snare", bar, "X.....X.........", snare, 1.0)
                tr.add("hats", bar, 0, s.crash(), 1.6, 0.2)
                continue
            tr.kick("kick", bar, "X.....x.X.....x." if not big else "X...X...X...X...", kick, 1.0 if big else 0.9)
            tr.drum("snare", bar, "....X.......X...", snare, 1.0, 0.05)
            tr.drum("snare", bar, "..o..o.o..o..o.o" if big else "..o.......o.....", ghost, 0.8, 0.05)
            tr.drum("hooves", bar, "X.xxX.xxX.xxX.xx", clip, 0.6 if not big else 0.75, -0.3)
            tr.drum("hooves", bar, "..o...o...o...o.", clop, 0.6, 0.3)
            tr.drum("perc", bar, "....x.......x...", slap, 0.7, 0.2)
            if big:
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", ride, 0.7, 0.25)
                tr.drum("clap", bar, "....X.......X...", clap, 1.0)
            else:
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.7, -0.2)
            if local % 4 == 0:
                tr.add("hats", bar, 0, s.crash(), 1.8 if local == 0 else 1.2, 0.2)
            if local == part.bars - 1 and name != "rideout":
                for k, step in enumerate((12, 13, 14, 15)):
                    tr.add("snare", bar, step, snare, 0.6 + 0.1 * k, 0.05)

    tr.play("lead", 4, melody("r:8 E5:4 F#5:4 | A5:16 | r:16 | r:8 C#5:2 E5:2 G5:2 G#5:2 | B4:4 r:12 | r:16"), tenor, 0.6)
    tr.play("lead", 9, melody("r:4 E4:2 G#4:2 B4:2 D5:2 E5:2 G#5:2"), tenor, 0.9)
    first = parts[1].first
    tr.play("lead", first, hook, tenor)
    tr.play("twang", first, melody("r:16 | r:16 | r:16 | r:8 E5:2 C5:2 A4:4 | r:16 | r:16 | r:16 | r:8 A5:2 G5:2 E5:4 | r:16 | r:16 | r:16 | r:16"), twangy, 0.9, pan=0.3)
    first = parts[2].first
    tr.play("twang", first, twang, twangy)
    tr.play("lead2", first, shift(twang, -12), lambda m, sec: ins.sax(m, sec, growl=0.1), 0.6, pan=-0.2)
    first = parts[3].first
    tr.play("lead", first, shift(hook, 2), tenor, 1.1)
    tr.play("twang", first, shift(hook, -10), twangy, 0.9, pan=0.3)
    tr.play("lead2", first, shift(hook, 14), lambda m, sec: ins.honky_piano(m, sec), 0.6, pan=-0.2)
    first = parts[4].first
    riff = [n for n in shift(hook, 2) if n.step < 9 * 16]
    tr.play("lead", first, riff, tenor, 1.15)
    tr.play("lead2", first, shift(riff, -12), lambda m, sec: ins.sax(m, sec, growl=0.5), 0.9, pan=-0.2)
    tr.play("twang", first, shift(riff, -8), twangy, 0.9, pan=0.3)
    last = tr.bars - 1
    tr.play("lead", last, ending, tenor, 1.1)
    tr.play("twang", last, shift(ending, -12), twangy, 1.0, pan=0.3)
    tr.add("lead", 0, 0, tenor(57, tr.bar * 0.75), 0.45)
    tr.add("bass", 0, 0, ins.upright(45, tr.bar * 0.5), 0.5)
    # the finish bell
    for k in range(4):
        tr.add("glock", parts[3].first, k * 2, ins.glock(88, 0.3), 0.8, 0.3)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.15, delay=0.05),
        "lead2": Bus(-13, reverb=0.15),
        "twang": Bus(-11, reverb=0.1, delay=0.18),
        "piano": Bus(-12, reverb=0.12),
        "rhythm": Bus(-15, reverb=0.1),
        "pad": Bus(-19, reverb=0.3),
        "glock": Bus(-15, reverb=0.3),
        "bass": Bus(-8, eq=(("hp", 45),)),
        "kick": Bus(-11, drive=1.4, eq=(("hp", 55), ("hp", 55), ("peak", 120, 4, 1.2))),
        "snare": Bus(-11, reverb=0.15),
        "clap": Bus(-16, reverb=0.15),
        "hooves": Bus(-15, reverb=0.08),
        "perc": Bus(-19),
        "hats": Bus(-18),
        "fx": Bus(-16, reverb=0.3),
    }, reverb_decay=1.2, reverb_tone=6000, delay_time=0.11, delay_feedback=0.2, pump_release=0.14)
    return finish(tr, mix), tr


SONG = Song("RockinRaceway", "Hobby Horse Hop", 168, 10, 52, rockin_raceway)
