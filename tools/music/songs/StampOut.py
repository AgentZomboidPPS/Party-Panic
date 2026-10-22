"""Rubber Stamp Rag: the round song for StampOut (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


@lru_cache(maxsize=None)
def tack_piano(midi: float, length: float) -> np.ndarray:
    """A tack piano (an old upright with thumbtacks in its hammers): bright and jangly, two strings a
    little apart beating against each other, a metal tick on every note."""
    hold = max(0.08, round(min(length, 1.8) / 0.05) * 0.05)
    n = s.samples(hold + 0.4)
    t = np.arange(n) / s.SR
    f0 = s.midi_hz(midi)
    rng = np.random.default_rng(int(midi * 10))
    stiff = 0.00015 + 0.0005 * np.clip((midi - 36) / 60, 0, 1)
    out = np.zeros(n)
    for cents in (-5.0, 5.0):
        f = f0 * 2 ** (cents / 1200)
        for k in range(1, 41):
            fk = k * f * np.sqrt(1 + stiff * k * k)
            if fk > 6500:
                break
            amp = k ** -0.9 * (1 + 0.35 * np.exp(-((fk - 2600) / 1400) ** 2))
            tau = 1.5 * (261.6 / f0) ** 0.35 / (1 + 0.25 * (k - 1))
            out += amp * np.sin(2 * np.pi * fk * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    out *= (0.75 + 0.25 * np.exp(-t / 0.09)) * np.clip(t / 0.0025, 0, 1)
    tick = s.bandpass(rng.uniform(-1, 1, n), 2000, 6000) * np.exp(-t / 0.004) * 0.16
    zing = sum(np.sin(2 * np.pi * fz * t) * np.exp(-t / 0.025) for fz in (3100.0, 4300.0, 5200.0)) * 0.03
    out = out / np.max(np.abs(out)) + tick + zing
    out *= np.where(t < hold, 1.0, np.exp(-(t - hold) / 0.07))
    x = ins.normalize(ins.eq(out, ("hp", 50), ("lp", 7000)))
    x.setflags(write=False)
    return x


@lru_cache(maxsize=None)
def kazoo(midi: float, length: float) -> np.ndarray:
    """A comb-and-paper kazoo: a hummed tune buzzing through a sheet of tissue paper."""
    n = s.samples(length + 0.08)
    t = np.arange(n) / s.SR
    pitch = midi - 0.5 * np.exp(-t / 0.04) + 0.12 * np.clip((t - 0.12) / 0.2, 0, 1) * np.sin(2 * np.pi * 5.6 * t)
    f = s.midi_hz(pitch)
    buzz = np.tanh(3 * s.saw(f, n))
    gate = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * np.cumsum(f) / s.SR))
    rattle = s.bandpass(np.random.default_rng(int(midi)).uniform(-1, 1, n), 2000, 5000) * gate * 0.15
    tone = ins.formant(buzz * 0.8 + rattle, [(550, 8, 3.0), (1250, 6, 4.0), (2700, 4, 5.0)])
    tone = ins.eq(tone, ("hp", 250), ("lp", 5000)) * ins.env(n, 0.025, 0.2, 0.9, 0.05, gate=length)
    x = ins.normalize(tone)
    x.setflags(write=False)
    return x


def typewriter_key(variant: int = 0) -> np.ndarray:
    """One typewriter key: the typebar's clack against the platen."""
    n = s.samples(0.09)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(400 + variant)
    k = 1 + 0.05 * (variant - 2)
    clack = s.bandpass(rng.uniform(-1, 1, n), 1500, 6000) * np.exp(-t / 0.003)
    body = np.sin(2 * np.pi * 1150 * k * t) * np.exp(-t / 0.012) * 0.5 + np.sin(2 * np.pi * 2650 * k * t) * np.exp(-t / 0.006) * 0.35
    thunk = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.015) * 0.4
    return ins.normalize(ins.eq(clack + body + thunk, ("lp", 6500)))


def typewriter_bell() -> np.ndarray:
    """The end-of-line bell: ding!"""
    n = s.samples(0.9)
    t = np.arange(n) / s.SR
    tone = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t / d) for f, a, d in ((1760.0, 1.0, 0.45), (4090.0, 0.35, 0.12), (2980.0, 0.2, 0.2)))
    return ins.normalize(ins.eq(tone * np.clip(t / 0.002, 0, 1), ("lp", 6000)))


def carriage_return(length: float = 0.45) -> np.ndarray:
    """The carriage flung back: a ratcheting zip that slows into the stop."""
    n = s.samples(length)
    out = np.zeros(n)
    rng = np.random.default_rng(8)
    clicks = 16
    for i in range(clicks):
        start = int(n * (i / clicks) ** 1.35)
        m = n - start
        out[start:] += rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / (s.SR * 0.0018)) * (0.5 + 0.5 * i / clicks)
    stop = s.samples(length * 0.92)
    out[stop:] += np.sin(2 * np.pi * 240 * np.arange(n - stop) / s.SR) * np.exp(-np.arange(n - stop) / (s.SR * 0.02))
    return ins.normalize(ins.eq(out, ("hp", 300), ("lp", 6000), ("peak", 2500, 3, 1.5)))


def rubber_stamp(big: bool = False) -> np.ndarray:
    """A rubber stamp pressed down onto paper on a wooden desk: a soft thunk with a papery puff."""
    n = s.samples(0.35)
    t = np.arange(n) / s.SR
    f = (105.0 if big else 140.0) * (1 + 0.35 * np.exp(-t / 0.012))
    body = s.sine(f, n) * np.exp(-t / (0.11 if big else 0.07))
    wood = np.sin(2 * np.pi * (420.0 if big else 480.0) * t) * np.exp(-t / 0.02) * 0.4
    puff = s.lowpass(np.random.default_rng(21 + big).uniform(-1, 1, n), 1500) * np.exp(-t / 0.02) * 0.5
    return ins.normalize(ins.drive(body + wood + puff, 1.5))


def stapler() -> np.ndarray:
    """A desk stapler: ka-CHUNK."""
    n = s.samples(0.2)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(31)
    spring = s.bandpass(rng.uniform(-1, 1, n), 2000, 6000) * np.exp(-t / 0.002) * 0.4
    k = s.samples(0.025)
    tt = t[: n - k]
    chunk = np.zeros(n)
    chunk[k:] = (np.sin(2 * np.pi * 170 * tt) * np.exp(-tt / 0.03)
                 + (np.sin(2 * np.pi * 2100 * tt) + 0.7 * np.sin(2 * np.pi * 3400 * tt)) * np.exp(-tt / 0.015) * 0.35
                 + s.bandpass(rng.uniform(-1, 1, n - k), 1000, 4000) * np.exp(-tt / 0.006) * 0.6)
    return ins.normalize(ins.eq(spring + chunk, ("lp", 6500)))


def ruler_twang(midi: float = 45.0, length: float = 0.55) -> np.ndarray:
    """A ruler held over the desk's edge and flicked: a buzzing twang that sags as it settles."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    f = s.midi_hz(midi) * (1 + 0.12 * np.exp(-t / 0.06))
    tone = s.square(f, n, 0.2) * np.exp(-t / 0.16)
    return ins.normalize(ins.eq(tone, ("hp", 90), ("peak", 620, 5, 1.5), ("lp", 3000)))


def scissors() -> np.ndarray:
    """Scissors: snip-snip."""
    n = s.samples(0.16)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(12)
    out = np.zeros(n)
    for start in (0.0, 0.07):
        k = s.samples(start)
        tt = t[: n - k]
        out[k:] += s.bandpass(rng.uniform(-1, 1, n - k), 2500, 7000) * np.exp(-tt / 0.003) + np.sin(2 * np.pi * 4100 * tt) * np.exp(-tt / 0.008) * 0.4
    return ins.normalize(ins.eq(out, ("lp", 7000)))


def rubber_stamp_rag():
    """Rubber Stamp Rag (128 bpm, C major): ragtime from the stationery cupboard on the giant desk. A
    tack piano struts a syncopated tune over a stride left hand, and the desk keeps time: rubber stamps
    thump on the beat, a stapler snaps the backbeat, a typewriter clacks along (its bell dings at the end
    of every line), a ruler twangs and scissors snip. A stomping minor strain in A minor, then BIG STAMPS
    (30 s after GO, bar 16 after GO): the trio in F with the tune back, a comb-and-paper kazoo on it and
    stamps on every beat, and a chromatic run straight back into the tune for the loop."""
    tr = Track(bpm=128, bars=29)
    parts = plan(tr, [
        ("intro", 7, "C | C | F | C | Am | D7 | G7"),
        ("A", 8, "C | C | G7 | G7 | C | A7 | D7 G7 | C"),
        ("B", 8, "Am | E7 | Am | A7 | Dm | Am | B7 E7 | Am C7"),
        ("C", 6, "F | F | C7 | C7 | F D7 | G7"),
    ])
    rag = melody("""G5:1 A5:2 G5:1 E5:4 C5:1 D5:2 C5:1 G4:4 | A4:2 B4:1 C5:2 E5:1 G5:2 C6:4 r:4 |
                    F5:1 G5:2 F5:1 D5:4 B4:1 C5:2 B4:1 G4:4 | F4:2 G4:1 B4:2 D5:1 F5:2 B5:4 r:4 |
                    G5:1 A5:2 G5:1 E5:4 C5:1 D5:2 C5:1 G4:4 | C#5:2 E5:1 G5:2 A5:1 C#6:4 Bb5:2 A5:2 G5:2 |
                    F#5:1 A5:2 F#5:1 D5:4 F5:1 G5:2 F5:1 B4:4 | C6:4 G5:2 E5:2 C5:4 r:4""")
    stomp = melody("""E5:2 E5:2 E5:1 F5:2 E5:1 C5:4 A4:4 | D5:2 D5:2 D5:1 E5:2 D5:1 B4:4 G#4:4 |
                      C5:2 C5:2 C5:1 D5:2 C5:1 A4:2 C5:2 E5:4 | G5:4 F5:2 E5:2 C#5:4 A4:4 |
                      F5:2 F5:2 F5:1 G5:2 F5:1 D5:4 A4:4 | E5:2 E5:2 E5:1 F5:2 E5:1 C5:4 A4:4 |
                      D#5:2 F#5:2 A5:2 B5:2 G#5:2 B5:2 D6:2 E6:2 | E6:4 C6:2 A5:2 G5:2 E5:2 C5:2 Bb4:2""")
    trio = shift([n for n in rag if n.step < 64], 5) + shift(melody(
        "A5:1 C6:2 A5:1 F5:4 F#5:1 A5:2 F#5:1 D5:4 | Eb6:2 D6:2 C#6:2 C6:2 B5:2 Bb5:2 A5:2 Ab5:2"), steps=64)
    lead_in = melody("E5:1 F5:2 E5:1 C5:4 A4:4 C5:4 | F#5:1 G5:2 F#5:1 D5:4 C5:4 A4:4 | G4:2 B4:2 D5:2 F5:2 G5:2 F5:2 D5:2 B4:2")

    keys = [typewriter_key(v) for v in range(5)]
    bell, zip_back = typewriter_bell(), carriage_return()
    stamp, big_stamp, staple = rubber_stamp(), rubber_stamp(True), stapler()
    twang, snip = ruler_twang(), scissors()
    tick, tock = ins.woodblock(1400.0), ins.woodblock(950.0)
    rng = np.random.default_rng(7)

    def typing(bar, pattern, gain):
        """Somebody typing along: every hit a different key, never quite even."""
        for step, vel in ((k, {"x": 1.0, "o": 0.55}[ch]) for k, ch in enumerate(pattern) if ch in "xo"):
            tr.add("typewriter", bar, step + rng.uniform(-0.06, 0.06), keys[rng.integers(5)], gain * vel * rng.uniform(0.75, 1.0), rng.uniform(-0.4, 0.4))

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            low = bass_note(c, 36)  # C2 .. B2, doubled an octave up
            fifth = low + 7 if low + 7 <= 47 else low - 5
            notes = voicing(c, 55, 67, prev, size=3)
            prev = notes
            if name == "intro" and local < 2:
                continue
            g = 1.0 if name != "intro" else 0.35 + 0.1 * (local - 2)
            booms = [(0, low), (8, fifth)] if length >= 16 else [(0, low)]
            for st, m in booms:  # stride: a bass octave on the beat, a chord on the off-beat
                tr.add("stride", bar, step + st, tack_piano(m, tr.beat * 0.9), g)
                tr.add("stride", bar, step + st, tack_piano(m + 12, tr.beat * 0.9), g * 0.7)
                strum(tr, "stride", bar, step + st + 4, notes, tack_piano, tr.beat * 0.5, g * (0.95 if name == "B" else 0.8), spread=0.004)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                tr.drum("wood", bar, "x...x...x...x..." if local < 4 else "x.x.x.x.x.x.x.x.", tick, 0.35 + 0.05 * local, 0.3)
                if local == 0:
                    tr.drum("wood", bar, "........x.......", tock, 0.35, -0.3)
                if local >= 1:
                    typing(bar, "..x...x..x....x." if local < 3 else "x.x.x.x.x.x.x.x.", 0.4 + 0.08 * local)
                if local == 1:
                    tr.add("bell", bar, 14, bell, 0.6)
                if local >= 4:
                    tr.drum("stamp", bar, "X.......X.......", stamp, 0.5 + 0.12 * (local - 4))
                if local >= 5:
                    tr.drum("staple", bar, "....X.......X...", staple, 0.55 + 0.15 * (local - 5))
                if local == 6:
                    typing(bar, "xoxoxoxoxoxo....", 0.9)
                    tr.add("bell", bar, 12, bell, 0.9)  # the end of the line: ding, and the carriage flies back
                    tr.add("fx", bar, 12.5, zip_back, 0.9, -0.2)
                continue
            if name == "A":
                tr.drum("stamp", bar, "X.......X.......", stamp, 1.0)
                tr.drum("staple", bar, "....X.......X...", staple, 0.9, 0.1)
                typing(bar, "x.x.x.x.x.x.x.x.", 0.7)
                if local in (1, 7):  # the end of a line: ding!
                    tr.add("bell", bar, 12, bell, 0.9, 0.2)
                    if local == 7:
                        tr.add("fx", bar, 12.5, zip_back, 0.8, -0.2)
                if local == 3:
                    tr.add("fx", bar, 12, snip, 0.9, 0.3)
                if local == 5:
                    tr.drum("stamp", bar, "............X.X.", stamp, 0.9)
            elif name == "B":
                tr.drum("stamp", bar, "X...X...X...X...", stamp, 1.0)
                tr.drum("staple", bar, "....X.......X...", staple, 0.9, 0.1)
                typing(bar, "xoxoxoxoxoxoxoxo", 0.7)
                tr.drum("wood", bar, "..x...x...x...x.", tock, 0.6, -0.3)
                if local in (3, 7):
                    tr.add("fx", bar, 12, twang, 0.9, -0.2)
                if local == 5:
                    tr.add("fx", bar, 12, snip, 0.9, 0.3)
                if local == 7:
                    tr.add("bell", bar, 14, bell, 0.9, 0.2)
            else:  # BIG STAMPS
                tr.drum("stamp", bar, "X...X...X...X.x.", big_stamp, 1.0)
                tr.drum("stamp", bar, "X.......X.......", stamp, 0.6)
                tr.drum("staple", bar, "....X.......X...", staple, 1.0, 0.1)
                typing(bar, "xoxxxoxxxoxxxoxx", 0.8)
                tr.drum("wood", bar, "..x...x...x...x.", tick, 0.6, 0.3)
                if local in (0, 4):
                    tr.add("crash", bar, 0, s.crash(1.4), 1.0, 0.2)
                if local in (1, 3):
                    tr.add("bell", bar, 12, bell, 0.9, 0.2)
                if local == 5:  # the end of the page: the carriage goes back for the next line (the loop)
                    tr.add("fx", bar, 0, twang, 0.8, -0.2)
                    tr.add("bell", bar, 12, bell, 0.8)
                    tr.add("fx", bar, 12.5, zip_back, 0.8, -0.2)

    tr.play("piano", 4, lead_in, tack_piano, 0.6)
    tr.play("piano", 7, rag, tack_piano)
    tr.play("piano", 15, stomp, tack_piano)
    tr.play("piano", 23, trio, tack_piano)
    tr.play("kazoo", 23, shift(trio, -12), kazoo, 1.0)

    mix = Mix(buses={
        "piano": Bus(-5, reverb=0.14, eq=(("high", 3500, -3),)),
        "stride": Bus(-9, reverb=0.12, eq=(("high", 3000, -4),)),
        "kazoo": Bus(-8, reverb=0.15),
        "stamp": Bus(-9, drive=1.3),
        "staple": Bus(-14, reverb=0.08),
        "typewriter": Bus(-17, reverb=0.06),
        "wood": Bus(-18, reverb=0.08),
        "bell": Bus(-16, reverb=0.25),
        "crash": Bus(-21),
        "fx": Bus(-15, reverb=0.15),
    }, reverb_decay=0.9, reverb_tone=6500)
    return finish(tr, mix), tr


SONG = Song("StampOut", "Rubber Stamp Rag", 128, 7, 29, rubber_stamp_rag)
