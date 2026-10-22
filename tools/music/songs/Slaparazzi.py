"""Red Carpet Strut: the round song for Slaparazzi (see songkit.py for the rules every song keeps)."""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)

from score import Note  # noqa: E402 (a note of a melody line, for the brass section's harmony)


def under(notes, bar0, parts, spb=12):
    """The next horn down in the section: the nearest chord tone at least a minor third below."""
    changes = [(b * spb + st, ln, c) for p in parts for b, st, ln, c in p.changes]
    out = []
    for n in notes:
        pos = bar0 * spb + n.step
        c = next(c for start, ln, c in changes if start <= pos < start + ln)
        m = n.midi - 3
        while m % 12 not in c.tones():
            m -= 1
        out.append(Note(n.step, m, n.length, n.vel * 0.9))
    return out


def muted_trumpet(midi: float, length: float) -> np.ndarray:
    """A trumpet with a plunger mute: a nasal, buzzy tone that opens on every note with a sassy 'wah'."""
    tone = np.asarray(ins.brass(midi, length, bright=1.0, section=1, vibrato=0.1)).copy()
    t = np.arange(tone.shape[-1]) / s.SR
    tone = ins.tv_lowpass(tone, 650 + 2300 * np.clip(t / 0.11, 0, 1), q=2.4)
    return ins.normalize(ins.eq(tone, ("hp", 480), ("peak", 1650, 5, 1.6), ("lp", 5200)))


def shutter(variant: int = 0) -> np.ndarray:
    """A press camera firing: the mirror's clack, the curtain's tick and the motor winding on."""
    n = s.samples(0.2)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(300 + variant)
    out = np.zeros(n)
    for start, gain, tone in ((0.0, 1.0, 2100.0 + 90 * variant), (0.032, 0.6, 3000.0)):
        k = s.samples(start)
        tt = t[: n - k]
        click = s.bandpass(rng.uniform(-1, 1, n - k), 1200, 6500) * np.exp(-tt / 0.0025)
        out[k:] += (click + np.sin(2 * np.pi * tone * tt) * np.exp(-tt / 0.006) * 0.5) * gain
    k = s.samples(0.06)
    tt = t[: n - k]
    whirr = s.square(np.full(n - k, 210.0), n - k, 0.3) * np.exp(-tt / 0.04) * np.clip(tt / 0.005, 0, 1) * 0.12
    out[k:] += ins.eq(whirr, ("hp", 400), ("lp", 3000))
    return ins.normalize(ins.eq(out, ("lp", 6500)))


def flash_whine(length: float = 0.9) -> np.ndarray:
    """A flashgun charging: a thin whine that climbs."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    tone = s.sine(1500 * 2.5 ** (t / length), n) * (0.65 + 0.35 * np.sin(2 * np.pi * 9 * t))
    e = np.clip(t / 0.05, 0, 1) * np.clip((length - t) / 0.03, 0, 1)
    return ins.normalize(ins.eq(tone * e, ("lp", 4500)))


def slapstick() -> np.ndarray:
    """A slapstick's two boards clapping shut: a bright crack with a woody body (the SLAP)."""
    n = s.samples(0.15)
    t = np.arange(n) / s.SR
    crack = s.bandpass(np.random.default_rng(55).uniform(-1, 1, n), 900, 6000) * np.exp(-t / 0.005)
    body = np.sin(2 * np.pi * 260 * t) * np.exp(-t / 0.02) * 0.5 + np.sin(2 * np.pi * 610 * t) * np.exp(-t / 0.012) * 0.3
    return ins.normalize(crack + body)


def crowd(length: float) -> np.ndarray:
    """The red-carpet crowd's murmur: bands of filtered noise chattering at speaking pace. Stereo."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(77)
    out = np.zeros((2, n))
    for _ in range(10):
        lo = rng.uniform(250, 600)
        band = s.bandpass(rng.uniform(-1, 1, n), lo, lo * rng.uniform(2.5, 4.0))
        chatter = np.clip(np.sin(2 * np.pi * rng.uniform(3, 6) * t + rng.uniform(0, 6)) + rng.uniform(-0.2, 0.4), 0, None) ** 1.5
        out += s.pan(band * chatter, rng.uniform(-0.8, 0.8))
    return ins.normalize(ins.eq(out, ("lp", 3200), ("hp", 220)))


def red_carpet_strut():
    """Red Carpet Strut (120 bpm shuffle, F minor): the premiere's house band. A plunger-muted trumpet
    struts the tune with the brass section answering, over a swung backbeat with finger snaps and the
    press cameras' shutters clicking in time; the trumpet opens up over organ, strings and harp for a
    glamorous middle in A flat. The shout chorus goes up a half step to F sharp minor with the whole
    section on the tune, and its last hit lands on the 7th photo (47.5 s after GO, beat 4 of the 24th
    bar after GO); a chromatic "that's a wrap" turnaround leads back to F minor for the loop. At 120 bpm
    every photo falls on a backbeat."""
    tr = Track(bpm=120, bars=35, spb=12)
    parts = plan(tr, [
        ("intro", 7, "Fm | Fm | Fm | Fm | Fm | Db7 | C7"),
        ("A", 8, "Fm | Fm | Bbm | Bbm | Fm | Db7 | C7 | C7"),
        ("B", 8, "Abmaj7 | Fm7 | Bbm7 | Eb7 | Abmaj7 | Fm7 | Bbm7 Eb7 | C#7"),
        ("shout", 8, "F#m | F#m | Bm | Bm | F#m | D7 | C#7 | C#7"),
        ("tag", 4, "F#m | D7 | Db7 | C7"),
    ])
    strut = melody("""C5:2 Eb5:1 F5:2 Ab5:1 F5:6 | r:12 | Db5:2 F5:1 Bb5:2 Db6:1 Bb5:6 | r:12 |
                      C6:3 B5:2 Bb5:1 Ab5:3 F5:3 | Ab5:2 F5:1 Eb5:2 Db5:1 B4:6 | r:3 E5:2 G5:1 Bb5:3 G5:2 E5:1 | Db6:3 C6:6 r:3""", 12)
    glam = melody("""Eb5:3 G5:3 C6:6 | Ab5:3 C6:2 Eb6:1 Eb6:6 | Db6:3 C6:2 Bb5:1 Ab5:3 F5:3 | G5:6 r:3 Bb5:3 |
                     C6:3 Bb5:2 Ab5:1 G5:3 Eb5:3 | F5:3 Ab5:3 C6:3 Eb6:3 | Db6:3 Bb5:3 G5:3 Bb5:3 | F5:3 G#5:3 B5:3 C#6:3""", 12)
    wrap = melody("C#5:2 E5:1 F#5:2 A5:1 F#5:6 | A5:6 F#5:3 D5:3 | Ab5:6 F5:3 Db5:3 | G5:3 E5:3 Bb4:3 B4:3", 12)
    answer = ((3, 2, 0.9), (5, 1, 0.75), (9, 3, 1.0))  # "do-ba DAH" (step, length, accent)

    def trumpet(m, sec):
        return ins.brass(m, sec, bright=1.0, section=3)

    def trombone(m, sec):
        return ins.brass(m, sec, bright=0.55, section=3)

    kick, clap, snare = s.kick(0.9, 0.4), s.clap(), ins.snare2(210.0, 0.85)
    ride, foot, crash = ins.ride(1.0, 0.35), s.hat(False), s.crash(2.0)
    snap, rim = ins.finger_snap(), ins.rim_click(1600.0)
    shutters = [shutter(v) for v in range(4)]
    slap = slapstick()
    toms = [ins.tom(p, 0.4) for p in (110.0, 150.0, 200.0)]
    rng = np.random.default_rng(13)

    def flurry(bar, step, count, gain=0.8, spread=3.0):
        """Paparazzi: a burst of shutters from all sides."""
        for k in range(count):
            tr.add("camera", bar, step + rng.uniform(0, spread), shutters[k % 4], gain * rng.uniform(0.6, 1.0), rng.uniform(-0.8, 0.8))

    # before GO: the crowd on the red carpet, cameras warming up, a drumroll and a fanfare
    tr.add("crowd", 0, 0, crowd(tr.bar * 5), 1.0)
    for bar, step in ((0, 7), (1, 2), (1, 8), (2, 5), (3, 1), (3, 10), (4, 4)):
        tr.add("camera", bar, step, shutters[(bar + step) % 4], 0.5 + 0.08 * bar, rng.uniform(-0.7, 0.7))
    tr.add("fx", 0, 6, flash_whine(), 0.5, 0.4)
    tr.add("fx", 2, 0, flash_whine(), 0.6, -0.4)
    for k in range(24):
        tr.add("snare", 2, k / 2, snare, 0.12 + 0.012 * k, 0.05)
    for st, ln, g in ((0, 1, 0.8), (2, 9, 1.0)):  # TA-DAAA
        strum(tr, "brass", 3, st, [65, 68, 72, 77], trumpet, ln * tr.step, 0.7 * g, spread=0.0, pan=0.1)
        strum(tr, "bones", 3, st, [53, 56, 60], trombone, ln * tr.step, 0.7 * g, spread=0.0, pan=-0.15)
    tr.add("drums", 3, 0, crash, 0.6, 0.2)

    # every chord in order, and the one after each (after the last comes the drop's, where the loop goes)
    song_changes = [ch for p in parts for ch in p.changes]
    after = {(b, st): song_changes[i + 1][3] if i + 1 < len(song_changes) else parts[1].changes[0][3]
             for i, (b, st, _, _) in enumerate(song_changes)}
    prev = None
    for part in parts:
        name = part.name
        changes = part.changes
        for bar, step, length, c in changes:
            local = bar - part.first
            root = bass_note(c, 29) + 12  # F2 .. E3
            notes = voicing(c, 60, 72, prev, size=3)
            prev = notes
            nxt = after[(bar, step)]
            # bass: a strut (root, fifth, seventh, fifth, then a step into the next root) or a walk
            if name in ("A", "tag") or (name == "intro" and local >= 4):
                seventh = 10 if "maj" not in c.name else 11
                target = bass_note(nxt, 29) + 12
                line = [(0, root, 2), (3, root + 7, 2), (5, root + 12, 1), (6, root + seventh, 2), (9, root + 7, 2), (11, target - 1 if target - 1 != root + 7 else target + 1, 1)]
                for st, m, ln in line:
                    if st < length:
                        tr.add("bass", bar, step + st, ins.bass_guitar(m, tr.step * ln * 0.95, bright=0.45), (1.0 if st % 3 == 0 else 0.75) * (0.6 if name == "intro" else 1.0))
        if name in ("B", "shout"):
            walking_bass(tr, "bass", part, lambda m, sec: ins.bass_guitar(m, sec, bright=0.45), 1.0, low=29 + 12)

        prev_chord = None
        for bar, step, length, c in changes:
            local = bar - part.first
            notes = voicing(c, 60, 72, prev_chord, size=3)
            prev_chord = notes
            if name == "A" and local in (1, 3):  # the section answers the trumpet
                for st, ln, g in answer:
                    strum(tr, "brass", bar, st, [m + 12 for m in notes], trumpet, ln * tr.step, g, spread=0.0, pan=0.1)
                    strum(tr, "bones", bar, st, notes, trombone, ln * tr.step, g * 0.9, spread=0.0, pan=-0.15)
            elif name in ("A", "tag") and step + length == 12 and local not in (1, 3):
                strum(tr, "bones", bar, 11, notes, trombone, tr.step * 1.2, 0.8, spread=0.0, pan=-0.15)
            if name == "B":  # Hollywood glamour: organ and strings, a harp sweeping up every bar
                tr.add("organ", bar, step, sum_organ(notes, length * tr.step), 1.0)
                tr.add("strings", bar, step, ins.strings(tuple(notes + [notes[0] + 12]), length * tr.step, attack=0.3, bright=0.5), 1.0)
                if step == 0:
                    for k, m in enumerate(sorted({x + 12 * o for x in notes for o in (0, 1)})):
                        tr.add("harp", bar, 6 + k * 0.5, ins.harp(m, 0.9, variant=k), 0.55 + 0.06 * k, -0.35 + 0.12 * k)
            if name == "shout" and local in (1, 3):
                for st, ln, g in answer:
                    strum(tr, "brass", bar, st, [m + 12 for m in notes] + [notes[0] + 24], trumpet, ln * tr.step, g * 1.1, spread=0.0, pan=0.1)
                    strum(tr, "bones", bar, st, notes, trombone, ln * tr.step, g, spread=0.0, pan=-0.15)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.drum("drums", bar, "...x.....x..", snap, 0.6 + 0.1 * (local - 4), 0.3)
                    tr.drum("ride", bar, "x..x.xx..x.x", ride, 0.35 + 0.1 * (local - 4), -0.3)
                if local >= 5:
                    tr.kick("kick", bar, "X.....X.....", kick, 0.6 + 0.15 * (local - 5))
                if local == 6:
                    for k, st in enumerate((6, 8, 9, 10, 11)):
                        tr.add("toms", bar, st, toms[2 - min(2, k // 2)], 0.6 + 0.07 * k)
                    tr.add("drums", bar, 9, slap, 0.9, -0.1)
                    flurry(bar, 3, 6, 0.6)
                    tr.add("fx", bar, 0, flash_whine(tr.beat * 3.4), 0.7, 0.3)
                continue
            shout = name == "shout"
            tr.kick("kick", bar, "X.....X....x" if name in ("A", "tag") else ("X..X..X..X.." if shout else "X.....X....."), kick, 1.0)
            tr.drum("snare", bar, "...X.....X..", snare if name != "B" else rim, 0.9, 0.05)
            if name != "B":
                tr.drum("snare", bar, "...X.....X..", clap, 0.75, -0.05)
            tr.drum("ride", bar, "x..x.xx..x.x", ride, 0.85 if shout else 0.7, -0.3)
            tr.drum("ride", bar, "...x.....x..", foot, 0.6, 0.3)
            if name == "A":
                tr.drum("drums", bar, "...x.....x..", snap, 0.8, 0.3)
            if name in ("A", "shout") and local % 2 == 1:
                tr.add("camera", bar, 11, shutters[local % 4], 0.7, 0.6 if local % 4 == 1 else -0.6)
            if name == "B" and local % 2 == 1:
                tr.add("camera", bar, 8, shutters[(local + 1) % 4], 0.5, 0.5)
            if local == 0:
                tr.add("drums", bar, 0, crash, 1.5, 0.2)
            if shout and local % 2 == 0 and local:
                tr.add("drums", bar, 0, crash, 1.0, -0.2)
            if local == part.bars - 1 and name in ("A", "B"):
                for k, st in enumerate((6, 8, 9, 11)):
                    tr.add("toms", bar, st, toms[2 - min(2, k)], 0.75)
                tr.add("drums", bar, 9, slap, 1.0, -0.1)
                flurry(bar, 6, 5, 0.65)
            if shout and local == 6:  # the flashgun charging for the last photo...
                tr.add("fx", bar, 3, flash_whine(tr.bar * 0.85 + tr.beat * 2), 0.8, 0.3)
            if shout and local == 7:  # ...and the big button on beat 4: photo seven
                strum(tr, "brass", bar, 9, [m + 12 for m in voicing(chord_at(parts, bar), 60, 72, size=3)] + [85], trumpet, tr.step * 2.5, 1.3, spread=0.0, pan=0.1)
                strum(tr, "bones", bar, 9, voicing(chord_at(parts, bar), 52, 64, size=3), trombone, tr.step * 2.5, 1.2, spread=0.0, pan=-0.15)
                tr.add("drums", bar, 9, crash, 1.6)
                tr.add("drums", bar, 9, slap, 1.0)
                flurry(bar, 9, 8, 0.8, spread=2.5)
            if name == "tag" and local == 3:
                for k, st in enumerate((6, 8, 9, 10, 11)):
                    tr.add("toms", bar, st, toms[2 - min(2, k // 2)], 0.75)

    tr.play("mute", 7, strut, muted_trumpet)
    tr.play("lead", 15, glam, trumpet)
    tr.play("bones", 15, shift(glam, -12), trombone, 0.45, pan=-0.15)
    tr.play("lead", 23, shift(strut, 1), trumpet)
    tr.play("section", 23, under(shift(strut, 1), 23, parts), trumpet, 0.85, pan=0.25)
    tr.play("bones", 23, shift(strut, 1 - 12), trombone, 0.9, pan=-0.15)
    tr.play("lead", 31, wrap, trumpet)
    tr.play("bones", 31, shift(wrap, -12), trombone, 0.8, pan=-0.15)

    mix = Mix(buses={
        "mute": Bus(-5, reverb=0.16, delay=0.06, eq=(("high", 3500, -2),)),
        "lead": Bus(-5, reverb=0.16, delay=0.05, eq=(("high", 2800, -4), ("lp", 7000))),
        "section": Bus(-11, reverb=0.16, eq=(("high", 2800, -4), ("lp", 7000))),
        "brass": Bus(-10, reverb=0.14, eq=(("high", 3000, -3), ("lp", 7500))),
        "bones": Bus(-11, reverb=0.14),
        "organ": Bus(-16, reverb=0.2, pump=0.1),
        "strings": Bus(-15, reverb=0.3, pump=0.1),
        "harp": Bus(-16, reverb=0.3, delay=0.1),
        "bass": Bus(-8, eq=(("lp", 1800),)),
        "kick": Bus(-10, drive=1.3),
        "snare": Bus(-12, reverb=0.14),
        "toms": Bus(-13, reverb=0.12),
        "ride": Bus(-18),
        "drums": Bus(-15, reverb=0.12),
        "camera": Bus(-17, reverb=0.12),
        "crowd": Bus(-19, reverb=0.15),
        "fx": Bus(-19, reverb=0.25),
    }, reverb_decay=1.5, reverb_tone=6000, delay_time=tr.beat * 2 / 3, delay_feedback=0.25)
    return finish(tr, mix), tr


def sum_organ(notes, length):
    """A soft jazz-organ chord (drawbars 8' 4' and a little 2 2/3', the rotary speaker turning slow)."""
    out = None
    for m in notes:
        x = np.asarray(ins.organ(m, length, drawbars=(0, 0, 8, 6, 3, 0, 0, 0, 0), leslie=1.2, click=0.2))
        out = x.copy() if out is None else out + x
    return out / len(notes) ** 0.7


def chord_at(parts, bar):
    """The chord that starts the given bar."""
    for part in parts:
        for b, step, length, c in part.changes:
            if b == bar:
                return c
    raise ValueError(bar)


SONG = Song("Slaparazzi", "Red Carpet Strut", 120, 7, 35, red_carpet_strut)
