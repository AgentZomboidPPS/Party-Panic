"""Balloon Bandstand: the round song for PumpAndPop (see songkit.py for the rules every song keeps)."""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def pump_hiss(length: float = 0.3) -> np.ndarray:
    """A plunger pump's 'pssht': a burst of air down the hose."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    air = s.bandpass(np.random.default_rng(3).uniform(-1, 1, n), 1200, 5500)
    e = np.clip(t / 0.02, 0, 1) * np.exp(-t / (length * 0.35))
    return ins.normalize(ins.eq(air * e, ("peak", 2500, 3, 1.5), ("lp", 6000)))


def squeak(pitch: float = 1500.0, length: float = 0.16, variant: int = 0) -> np.ndarray:
    """A balloon's rubbery squeak as it stretches."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(60 + variant)
    wobble = 1 + 0.06 * np.sin(2 * np.pi * 28 * t + rng.uniform(0, 6)) + 0.18 * t / length
    tone = s.square(pitch * wobble, n, 0.3)
    e = np.sin(np.pi * np.clip(t / length, 0, 1)) ** 1.2
    return ins.normalize(ins.eq(tone * e, ("lp", 3800), ("hp", 600), ("peak", 1800, 4, 2.0)))


def balloon_pop() -> np.ndarray:
    """A balloon bursting: a sharp crack, a puff of air and a little thump."""
    n = s.samples(0.35)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(99)
    crack = rng.uniform(-1, 1, n) * np.exp(-t / 0.006)
    puff = s.lowpass(rng.uniform(-1, 1, n), 1200) * np.exp(-t / 0.06) * 0.6
    thump = s.sine(110 * (1 + np.exp(-t / 0.01)), n) * np.exp(-t / 0.05) * 0.7
    return ins.normalize(ins.eq(crack + puff + thump, ("lp", 6500)))


def balloon_bandstand():
    """Balloon Bandstand (120 bpm in 6/8, B flat major): a carnival brass band on the bandstand, a
    steam calliope with the tune, oom-pah tuba and horns, a 6/8 street snare, bass drum and cymbals,
    and slide whistles that swoop up like balloons filling. A chromatic breakstrain inflates (the bass
    climbs a half step every two beats) into a grandioso trio a step up in C, with trombones on a
    counter-melody and bells on the tune, for the last 16 seconds of the 40. A POP, and a slide whistle
    lets the air out back down into B flat for the loop."""
    tr = Track(bpm=120, bars=29, spb=12)
    parts = plan(tr, [
        ("intro", 7, "Bb | Bb | Eb | F7 | Bb | Eb | F7"),
        ("A", 8, "Bb | F7 | Bb | Eb | Bb | G7 | Cm F7 | Bb"),
        ("B", 4, "Bb Bdim7 | Cm C#dim7 | Dm Ebdim7 | G7"),
        ("C", 8, "C | G7 | C | F | C | A7 | Dm G7 | C"),
        ("tag", 2, "C | F7"),
    ])
    theme = melody("""F5:2 D5:1 F5:2 Bb5:1 D6:3 Bb5:3 | C6:2 A5:1 C6:2 Eb6:1 F6:3 C6:3 | D6:2 C6:1 Bb5:2 A5:1 Bb5:2 F5:1 D5:3 | Eb5:2 G5:1 Bb5:2 Eb6:1 G5:6 |
                      F5:2 D5:1 F5:2 Bb5:1 D6:3 Bb5:3 | B5:2 G5:1 B5:2 D6:1 F6:3 D6:3 | Eb6:2 D6:1 C6:2 Bb5:1 A5:2 Bb5:1 C6:3 | Bb5:6 F5:2 G5:1 A5:3""", 12)
    climb = melody("D5:2 F5:1 Bb5:3 D5:2 F5:1 Ab5:3 | Eb5:2 G5:1 C6:3 E5:2 G5:1 Bb5:3 | F5:2 A5:1 D6:3 F#5:2 A5:1 C6:3 | G5:3 B5:3 D6:3 F6:3", 12)
    counter = melody("G3:6 E4:3 C4:3 | B3:6 D4:3 F4:3 | E4:6 G4:3 E4:3 | F4:6 A4:3 F4:3 | E4:3 D4:3 C4:3 G3:3 | C#4:6 E4:3 G4:3 | F4:3 E4:3 D4:3 B3:3 | C4:12", 12)
    call = melody("F5:3 A5:3 C6:3 Eb6:3 | D6:6 Bb5:3 F5:3 | G5:3 Bb5:3 Eb6:6 | C6:1 D6:1 C6:1 D6:1 C6:1 D6:1 C6:1 D6:1 C6:1 Eb6:3", 12)
    tag_tune = melody("C6:3 r:9 | r:6 C5:2 D5:1 Eb5:3", 12)

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.45, section=2, vibrato=0.0)

    def trombone(m, sec):
        return ins.brass(m, sec, bright=0.6, section=3)

    snare = ins.snare2(230.0, 0.9)
    bass_drum = s.kick(0.55, 0.6)
    cymbal = ins.splash(0.6)
    crash = s.crash(1.8)
    hiss = pump_hiss()
    squeaks = [squeak(1300.0 + 260 * v, 0.14 + 0.03 * v, v) for v in range(4)]

    # before GO: the balloons being pumped up, then the band strikes up
    for bar in range(0, 3):
        for k, st in enumerate((0, 6)):
            tr.add("fx", bar, st, hiss, 0.5 + 0.15 * bar, -0.3 + 0.6 * k)
            rise = 62 + 4 * bar + 2 * k
            tr.add("whistle", bar, st + 2, ins.slide_whistle(rise, rise + 5, tr.beat * 0.8), 0.35 + 0.12 * bar, 0.3 - 0.6 * k)
    tr.play("lead", 3, call, ins.calliope, 0.5)
    tr.add("whistle", 5, 3, ins.slide_whistle(62, 86, tr.beat * 3), 0.7, 0.2)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            low = bass_note(c, 41)  # tuba from F2: low enough to boom, high enough for a phone
            fifth = low + 7 if low + 7 <= 52 else low - 5
            notes = voicing(c, 55, 68, prev, size=3)
            prev = notes
            # oom-pah: tuba on the beats, horns on the after-beats
            if name == "intro" and local < 1:
                continue
            oom = [(0, low), (6, fifth)] if length >= 12 and not (name == "tag" and local == 0) else [(0, low)]
            for st, m in oom:
                tr.add("tuba", bar, step + st, ins.tuba(m, tr.step * 2.2), (0.9 if name != "intro" else 0.32 + 0.07 * local))
            if name == "intro" and local < 2 or name == "tag" and local == 0:
                continue
            for st in range(3, int(length), 6):
                strum(tr, "pah", bar, step + st, notes, horn, tr.step * 1.6, 0.9 if name != "intro" else 0.4, spread=0.004)
        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 2:
                    tr.drum("snare", bar, "x.xx.xx.xx.x", snare, 0.2 + 0.06 * (local - 2), 0.05)
                if local >= 4:
                    tr.drum("drum", bar, "X.....X.....", bass_drum, 0.5 + 0.08 * (local - 4))
                    tr.drum("cymbal", bar, "X.....X.....", cymbal, 0.3, 0.3)
                if local == 6:
                    for k in range(12):
                        tr.add("snare", bar, k, snare, 0.25 + 0.045 * k, 0.05)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.3)
                    strum(tr, "pah", bar, 0, voicing(c, 60, 74, size=3), horn, tr.bar * 0.9, 0.6, spread=0.0)
                continue
            if name == "A":
                tr.drum("snare", bar, "X.xX.xX.xX.x", snare, 0.85, 0.05)
                tr.drum("drum", bar, "X.....X.....", bass_drum, 1.0)
                tr.drum("cymbal", bar, "X.....X.....", cymbal, 0.8, 0.3)
                if local in (3, 7):
                    tr.add("whistle", bar, 6, ins.slide_whistle(67, 79, tr.beat * 1.6), 0.8, 0.25)
                if local == 0:
                    tr.add("cymbal", bar, 0, crash, 1.4, -0.2)
            elif name == "B":
                for k in range(12):
                    tr.add("snare", bar, k, snare, 0.35 + 0.04 * k + 0.08 * local, 0.05)
                tr.drum("drum", bar, "X..X..X..X..", bass_drum, 0.9)
                tr.drum("cymbal", bar, "X.....X.....", cymbal, 0.7, 0.3)
                for k, st in enumerate((0, 6)):  # the balloon swells with every half bar
                    rise = 64 + 4 * (2 * local + k)
                    tr.add("whistle", bar, st + 1, ins.slide_whistle(rise, rise + 7, tr.beat * 1.4), 0.7, -0.3 + 0.6 * k)
                    tr.add("fx", bar, st + 4, squeaks[(2 * local + k) % 4], 0.4 + 0.1 * local, 0.35 - 0.7 * k)
                if local == 3:
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.35)
            elif name == "C":
                tr.drum("snare", bar, "X.xX.xX.xX.x", snare, 0.95, 0.05)
                tr.drum("drum", bar, "X..X..X..X..", bass_drum, 1.0)
                tr.drum("cymbal", bar, "X..X..X..X..", cymbal, 0.9, 0.3)
                if local == 0:
                    tr.add("cymbal", bar, 0, crash, 1.5, -0.2)
                if local in (3, 7):
                    tr.add("whistle", bar, 6, ins.slide_whistle(69, 84, tr.beat * 1.6), 0.8, 0.25)
                if local == 4:
                    tr.add("cymbal", bar, 0, crash, 1.1, 0.2)
            elif name == "tag":
                if local == 0:
                    tr.add("fx", bar, 0, balloon_pop(), 1.0)
                    tr.add("cymbal", bar, 0, crash, 1.6)
                    tr.add("drum", bar, 0, bass_drum, 1.0)
                    strum(tr, "pah", bar, 0, voicing(c, 60, 74, size=3), horn, tr.beat * 0.9, 1.1, spread=0.0)
                    tr.add("whistle", bar, 3, ins.slide_whistle(86, 58, tr.bar * 1.15), 0.9)  # the air goes out
                else:
                    tr.drum("snare", bar, "......x.xX.x", snare, 0.7, 0.05)
                    tr.drum("drum", bar, "......X.....", bass_drum, 0.8)

    tr.play("lead", 7, theme, ins.calliope)
    tr.play("lead", 15, climb, ins.calliope)
    tr.play("lead", 19, shift(theme, 2), ins.calliope)
    tr.play("bells", 19, shift(theme, 2), ins.glock, 0.8)
    tr.play("counter", 19, counter, trombone, pan=-0.2)
    tr.play("lead", 27, tag_tune, ins.calliope)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.18),
        "bells": Bus(-15, reverb=0.25),
        "counter": Bus(-10, reverb=0.18),
        "pah": Bus(-13, reverb=0.15),
        "tuba": Bus(-8),
        "snare": Bus(-13, reverb=0.15),
        "drum": Bus(-11, drive=1.3, reverb=0.1),
        "cymbal": Bus(-19, reverb=0.1),
        "whistle": Bus(-14, reverb=0.25),
        "fx": Bus(-16, reverb=0.2),
    }, reverb_decay=1.5, reverb_tone=6000)
    return finish(tr, mix), tr


SONG = Song("PumpAndPop", "Balloon Bandstand", 120, 7, 29, balloon_bandstand)
