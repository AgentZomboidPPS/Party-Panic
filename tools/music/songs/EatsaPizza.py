"""Mozzarella Tarantella: the round song for EatsaPizza (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def _sealed(x: np.ndarray) -> np.ndarray:
    x.setflags(write=False)  # cached notes are shared: nobody changes them in place
    return x


def _damp(x: np.ndarray, gate: float, release: float = 0.05) -> np.ndarray:
    """Stops a ringing string `gate` seconds in."""
    g = s.samples(gate)
    if g >= x.shape[-1]:
        return x
    out = x.copy()
    out[..., g:] *= np.exp(-np.arange(x.shape[-1] - g) / (s.samples(release) / 4.6))
    return out


@lru_cache(maxsize=None)
def mandolin(midi: float, length: float, variant: int = 0) -> np.ndarray:
    """A Neapolitan mandolin: two steel strings to a course, struck together with a pick; bright, short
    and a little nasal from its small bowl."""
    a = np.asarray(ins.ks(midi, length + 0.35, bright=0.75, decay=1.1, pick=0.12, soft=0.08, variant=variant))
    b = np.asarray(ins.ks(midi + 0.05, length + 0.35, bright=0.75, decay=1.0, pick=0.14, soft=0.08, variant=variant + 40))
    tone = ins.formant(a + 0.8 * b, [(650, 3, 1.2), (1900, 4, 1.6), (3300, 2, 2.0)])
    tone = ins.eq(tone, ("hp", 260), ("lp", 5800))
    return _sealed(ins.normalize(_damp(tone, length + 0.03, 0.06)))


@lru_cache(maxsize=None)
def tamburello(hit: bool, variant: int = 0) -> np.ndarray:
    """The tarantella's frame drum: a slap on the skin with its jingles, or just a shake of the jingles."""
    n = s.samples(0.22)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(50 + variant + (10 if hit else 0))
    jingle = np.asarray(ins.jingles(0.2 if hit else 0.12, 0.6, variant))
    out = np.zeros(n)
    out[: min(n, len(jingle))] += jingle[:n] * (0.8 if hit else 0.6)
    if hit:
        skin = s.bandpass(rng.uniform(-1, 1, n), 180, 1300) * np.exp(-t / 0.022)
        thump = np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.045)
        out += skin + thump * 0.7
    return _sealed(ins.normalize(ins.eq(out, ("lp", 7200))))


@lru_cache(maxsize=None)
def chomp(big: bool = False) -> np.ndarray:
    """A bite of pizza: the jaw's thump and a crunch of crust."""
    n = s.samples(0.3 if big else 0.15)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(77 + big)
    crunch = np.zeros(n)
    for _ in range(16 if big else 8):
        start = int(rng.uniform(0, 0.08 if big else 0.035) * s.SR)
        m = min(n - start, 320)
        crunch[start:start + m] += rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / 45) * rng.uniform(0.3, 1)
    crunch = s.bandpass(crunch, 700, 4800)
    jaw = s.sine(140 * (1 + 0.7 * np.exp(-t / 0.015)), n) * np.exp(-t / (0.06 if big else 0.04))
    out = ins.normalize(crunch + jaw * 0.8)
    out[-s.samples(0.008):] *= np.linspace(1, 0, s.samples(0.008))  # no click at the end
    return _sealed(out)


def eatsa_pizza():
    """Mozzarella Tarantella (176 bpm in 12/8, A minor): a pizzeria band for a pizza the size of a swimming
    pool. Tremolo mandolin and a cheeky clarinet over an oom-pah of bass and guitar, a frame drum's
    jingles, and crunching bites; the intro clears its throat like a serenade, the middle goes
    'nom-nom CHOMP' in C major, and a breathless stretta races to an A major finish as the time runs out."""
    tr = Track(bpm=176, bars=32, spb=12)
    parts = plan(tr, [
        ("intro", 10, "Am | Am | Dm | E7 | Am | Am | Dm | E7 | E7 | E7"),
        ("A", 8, "Am | Am | E7 | E7 | Am | Dm | E7 | Am"),
        ("B", 6, "C | G7 | C | F | D7 G7 | E7"),
        ("stretta", 6, "Am | E7 | Am | E7 | Dm | E7"),
        ("finale", 2, "A | A A E7 E7"),
    ])
    theme = melody("""E5:2 E5:1 E5:2 E5:1 F5:1 E5:1 D#5:1 E5:3 | C6:2 B5:1 A5:2 G#5:1 A5:3 E5:3 |
                      D5:2 D5:1 D5:2 D5:1 E5:1 D5:1 C#5:1 D5:3 | B5:2 A5:1 G#5:2 F5:1 E5:3 r:3 |
                      E5:2 E5:1 E5:2 E5:1 F5:1 E5:1 D#5:1 E5:3 | F5:2 A5:1 D6:2 C6:1 B5:1 A5:1 G#5:1 A5:3 |
                      B5:2 G#5:1 E5:2 G#5:1 B5:2 D6:1 C6:2 B5:1 | A5:3 E5:3 A4:3 r:3""", 12)
    munch = melody("""G4:1 r:1 G4:1 C5:3 E5:1 r:1 E5:1 G5:3 | F5:1 r:1 F5:1 D5:3 B4:1 r:1 B4:1 G4:3 |
                      G4:1 r:1 G4:1 C5:3 E5:1 r:1 E5:1 G5:3 | A5:1 r:1 A5:1 C6:3 A5:2 F5:1 C5:3 |
                      F#5:2 A5:1 D6:2 C6:1 B5:2 G5:1 F5:2 D5:1 | D6:2 C6:1 B5:2 A5:1 G#5:2 F5:1 D5:3""", 12)
    stretta = melody("""E5:1 F5:1 E5:1 D#5:1 E5:1 F5:1 E5:1 A5:1 C6:1 E6:1 C6:1 A5:1 |
                        D5:1 E5:1 D5:1 C#5:1 D5:1 E5:1 D5:1 G#5:1 B5:1 D6:1 B5:1 G#5:1 |
                        E5:1 F5:1 E5:1 D#5:1 E5:1 F5:1 E5:1 A5:1 C6:1 E6:1 D6:1 C6:1 |
                        B5:1 C6:1 B5:1 A5:1 G#5:1 A5:1 B5:1 D6:1 E6:1 D6:1 B5:1 G#5:1 |
                        A5:1 D6:1 F6:1 E6:1 D6:1 C6:1 B5:1 C6:1 D6:1 C6:1 A5:1 F5:1 |
                        E5:1 G#5:1 B5:1 D6:1 E6:1 D6:1 B5:1 G#5:1 E5:1 G#5:1 B5:1 D6:1""", 12)
    finale = melody("A5:1 G#5:1 A5:1 B5:1 A5:1 G#5:1 A5:1 B5:1 C#6:1 D6:1 D#6:1 E6:1 | A6:3! r:3 E6:1 D6:1 B5:1 G#5:1 F5:1 D5:1", 12)
    aria = melody("A5:6 F5:3 D5:3 | E5:6 G#5:3 B5:3 | C6:6 B5:3 A5:3 | E5:9 r:3 | F5:3 A5:3 D6:6 | B5:3 G#5:3 E5:6", 12)
    # the stretta's clarinet: the tune's long notes under the mandolin's whirl
    stretta_low = melody("E5:6 A5:6 | D5:6 G#5:6 | E5:6 A5:6 | B5:6 G#5:6 | F5:6 D5:6 | E5:6 B4:6", 12)

    kick = s.kick(0.9, 0.3)

    def mando(bar, notes, gain=1.0, pan=0.0, stem="lead", rate=0.5, tremolo_from=3):
        """Picks every note; notes `tremolo_from` steps or longer are tremolo-picked every `rate` steps."""
        for i, n in enumerate(notes):
            if n.length >= tremolo_from:
                k = 0.0
                while k < n.length - 1e-6:
                    stroke = int(round(k / rate))
                    sec = round(min(rate, n.length - k) * tr.step * 1.4, 3)
                    tr.add(stem, bar, n.step + k, mandolin(n.midi, sec, stroke % 4), gain * n.vel * (1.0 if stroke % 2 == 0 else 0.78), pan)
                    k += rate
            else:
                tr.add(stem, bar, n.step, mandolin(n.midi, round(n.length * tr.step, 3), i % 4), gain * n.vel, pan)

    def guitar(bar, step, notes, gain=1.0):
        strum(tr, "strum", bar, step, notes, ins.nylon, tr.step * 1.2, gain, spread=0.008, pan=0.2)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 36)
            fifth = root + 7 if root + 7 <= 50 else root - 5  # the fifth, below the root when it would sit high
            notes = voicing(c, 57, 69, prev)
            prev = notes
            if name == "intro":
                if local < 4:  # a serenade's tremolo chord to clear the throat
                    for m in voicing(c, 64, 76):
                        k = 0.0
                        while k < 12:
                            stroke = int(round(k / 0.5))
                            tr.add("trem", bar, k, mandolin(m, 0.092, stroke % 4), (0.38 + 0.1 * local) * (1.0 if stroke % 2 == 0 else 0.78), 0.25)
                            k += 0.5
                elif local < 8:
                    g = 0.55 + 0.08 * (local - 4)
                    tr.add("bass", bar, 0, ins.upright(root, tr.step * 2.5), g)
                    tr.add("bass", bar, 6, ins.upright(fifth, tr.step * 2.5), g * 0.85)
                    for k in (3, 9):
                        guitar(bar, k, notes, g)
                else:  # the dominant pedal: the dance gathering speed, then a breath before GO
                    for k in ((0, 6) if local == 8 else (0, 3, 6, 9)):
                        tr.add("bass", bar, k, ins.upright(root if k % 6 == 0 else root + 12, tr.step * 2), 0.65 + 0.15 * (local - 8))
                    for k in ((3, 9) if local == 8 else (1, 2, 4, 5, 7, 8, 10)):
                        guitar(bar, k, notes, 0.6 + 0.1 * (local - 8) + (0.1 if k % 3 == 0 else 0.0))
                continue
            if name in ("A", "B"):
                for k in range(0, int(length), 6):  # oom (bass on 1 and 3) - pah (guitar on 2 and 4)
                    tr.add("bass", bar, step + k, ins.upright(root if k == 0 else fifth, tr.step * 2.5), 1.0)
                    guitar(bar, step + k + 3, notes, 1.0)
                if name == "B":  # the mandolins strum a tremolo chord under the clarinet
                    for m in voicing(c, 64, 76):
                        k = 0.0
                        while k < length - 1e-6:
                            stroke = int(round(k / 0.5))
                            tr.add("trem", bar, step + k, mandolin(m, 0.092, stroke % 4), (0.8 if k % 3 == 0 else 0.55), 0.3)
                            k += 0.5
            elif name == "stretta":
                for k in range(0, 12, 3):
                    tr.add("bass", bar, k, ins.upright(root if k % 6 == 0 else fifth, tr.step * 2), 1.0)
                    guitar(bar, k + 1, notes, 0.8)
                    guitar(bar, k + 2, notes, 0.65)
            elif name == "finale":
                if local == 0:
                    for k in range(0, 12, 3):
                        tr.add("bass", bar, k, ins.upright(root if k % 6 == 0 else fifth, tr.step * 2), 1.0)
                        guitar(bar, k + 1, notes, 0.8)
                        guitar(bar, k + 2, notes, 0.65)
                elif step == 0:  # the last bite: everybody on one A major chord
                    tr.add("bass", bar, 0, ins.upright(root, tr.step * 3), 1.0)
                    strum(tr, "strum", bar, 0, notes + [notes[0] + 12], ins.nylon, tr.step * 3, 1.3, spread=0.006)
                    for m in voicing(c, 64, 81, size=4):
                        tr.add("trem", bar, 0, mandolin(m, 0.35, 1), 0.9, 0.2)
                elif step == 6:
                    tr.add("bass", bar, 6, ins.upright(root, tr.step * 2), 0.8)
                    tr.add("bass", bar, 9, ins.upright(root + 12, tr.step * 2), 0.8)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local == 1:
                    for k in range(12):
                        tr.add("tamb", bar, k, tamburello(False, k % 3), 0.15 + 0.02 * k, -0.25)
                if 4 <= local < 8:
                    tr.drum("tamb", bar, "X.....x.....", tamburello(True, local % 3), 0.5 + 0.08 * (local - 4), -0.25)
                    tr.drum("tamb", bar, "..x..x..x..x" if local >= 6 else "...x.....x..", tamburello(False, local % 3), 0.45, -0.25)
                if local >= 8:
                    tr.drum("tamb", bar, "X.....X....." if local == 8 else "X..X..X..X..", tamburello(True, local % 3), 0.6 + 0.15 * (local - 8), -0.25)
                    tr.drum("tamb", bar, "..x..x..x..x" if local == 8 else ".xx.xx.xx.x.", tamburello(False, local % 3), 0.45 + 0.1 * (local - 8), -0.25)
                    if local == 9:
                        tr.kick("kick", bar, "X..X..X..X..", kick, 0.65)
                if local == 9:
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.3)
                continue
            if local == 0 and name != "finale":
                tr.add("cymbal", bar, 0, s.crash(), 1.6, 0.25)
            if name == "A":
                tr.drum("tamb", bar, "X.....X.....", tamburello(True, local % 3), 0.95, -0.25)
                tr.drum("tamb", bar, "...x.....x..", tamburello(True, (local + 1) % 3), 0.6, -0.25)
                tr.drum("tamb", bar, ".xx.xx.xx.xx", tamburello(False, local % 3), 0.55, -0.25)
                tr.kick("kick", bar, "X.....X.....", kick, 0.8)
                if local == 0:
                    tr.add("chomp", bar, 0, chomp(True), 1.0)
            elif name == "B":
                tr.drum("tamb", bar, "X.....X.....", tamburello(True, local % 3), 0.8, -0.25)
                tr.drum("tamb", bar, ".x..x..x..x.", tamburello(False, local % 3), 0.45, -0.25)
                if local < 4:
                    tr.drum("chomp", bar, "...X.....X..", chomp(), 0.9, 0.15)  # nom-nom CHOMP
                tr.kick("kick", bar, "X.....X.....", kick, 0.6)
            elif name == "stretta":
                tr.drum("tamb", bar, "X..X..X..X..", tamburello(True, local % 3), 0.9, -0.25)
                tr.drum("tamb", bar, ".xx.xx.xx.xx", tamburello(False, local % 3), 0.6, -0.25)
                tr.kick("kick", bar, "X..X..X..X..", kick, 0.9)
                if local % 2 == 1:
                    tr.add("chomp", bar, 9, chomp(), 0.7, -0.15)
            elif name == "finale":
                if local == 0:
                    tr.drum("tamb", bar, "X.xX.xX.xX.x", tamburello(True, 0), 0.9, -0.25)
                    tr.kick("kick", bar, "X..X..X..X..", kick, 1.0)
                    for k in range(6, 12):
                        tr.add("tamb", bar, k, tamburello(False, k % 3), 0.5 + 0.08 * (k - 6), 0.25)
                else:
                    tr.kick("kick", bar, "X...........", kick, 1.0)
                    tr.add("tamb", bar, 0, tamburello(True, 1), 1.0, -0.25)
                    tr.add("cymbal", bar, 0, s.crash(2.0), 2.0, 0.25)
                    tr.add("chomp", bar, 0, chomp(True), 1.0)
                    tr.drum("tamb", bar, "......xxxxxx", tamburello(False, 2), 0.5, 0.25)

    tr.play("clar", 2, [n for n in aria if n.step < 24], ins.clarinet, 0.5)  # softly at first, then growing
    tr.play("clar", 2, [n for n in aria if n.step >= 24], ins.clarinet, 0.65)
    mando(8, melody("E5:1 E5:1 E5:1 E5:1 E5:1 E5:1 E5:1 E5:1 E5:1 F5:1 F5:1 F5:1 | E5:1 F5:1 E5:1 F5:1 E5:1 F5:1 G#5:1 A5:1 B5:1 C6:1 D6:1 r:1", 12), 0.75)
    tr.play("clar", 8, melody("E4:6 G#4:6 | B4:6 D5:3 r:3", 12), ins.clarinet, 0.7)
    mando(10, theme)
    tr.play("clar", 10, shift(theme, -12), ins.clarinet, 0.55)
    tr.play("clar", 18, munch, ins.clarinet)
    mando(18, [n for n in shift(munch, 12) if n.length >= 3], 0.35, -0.3)  # the mandolin echoes the CHOMPs
    mando(24, stretta)
    tr.play("clar", 24, stretta_low, ins.clarinet, 0.75)
    mando(30, finale)
    tr.play("clar", 30, shift(finale, -12), ins.clarinet, 0.7)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.16, delay=0.04, eq=(("high", 5000, -2.5),)),
        "clar": Bus(-7, reverb=0.18),
        "trem": Bus(-13, reverb=0.2),
        "strum": Bus(-12, reverb=0.12),
        "bass": Bus(-9),
        "tamb": Bus(-15, reverb=0.1),
        "chomp": Bus(-13, reverb=0.08),
        "kick": Bus(-14, drive=1.3, eq=(("hp", 45),)),
        "cymbal": Bus(-20, reverb=0.1, eq=(("lp", 9000),)),
        "fx": Bus(-16, reverb=0.3, eq=(("lp", 6500),)),
    }, reverb_decay=1.4, reverb_tone=5500, delay_time=tr.beat / 3 * 2, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("EatsaPizza", "Mozzarella Tarantella", 176, 10, 32, eatsa_pizza)
