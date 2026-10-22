"""Crystal Cave Express: the round song for MinecartMayhem (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from score import Note

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def faded(x, seconds=0.01):
    """A short fade at the very end, so a tail that's cut off doesn't click."""
    x = np.array(x, dtype=float)
    k = min(x.shape[-1], s.samples(seconds))
    x[..., -k:] *= np.linspace(1.0, 0.0, k)
    return x


def sealed(x):
    x.setflags(write=False)  # cached notes are shared: nobody changes them in place
    return x


def aimed(x, position):
    """A sound moved towards one side (-1 left .. 1 right); a stereo one keeps its own spread."""
    x = np.asarray(x)
    if x.ndim == 1:
        return s.pan(x, position)
    return np.vstack([x[0] * min(1.0, 1.0 - position), x[1] * min(1.0, 1.0 + position)])


def harmony(notes, first, parts, spb=16):
    """A second voice under a tune: for every note, the nearest chord tone at least a minor third
    below it (in the chord under that note), so the second line never rubs against the band."""
    changes = [(b * spb + st, ln, c) for p in parts for b, st, ln, c in p.changes]
    out = []
    for n in notes:
        pos = first * spb + n.step
        c = next(c for start, ln, c in changes if start <= pos < start + ln)
        m = n.midi - 3
        while m % 12 not in c.tones():
            m -= 1
        out.append(Note(n.step, m, n.length, n.vel * 0.85))
    return out


# ---------------------------------------------------------------- the band

@lru_cache(maxsize=None)
def dulcimer(midi, ring, variant=0):
    """A hammered dulcimer (a cimbalom): a course of three steel strings tuned a fraction of a hertz
    apart, so every note shimmers slowly, struck with a hard hammer. It has no dampers: the strings
    ring on for `ring` seconds, over the notes after them, then fade. Stereo (the course spreads a
    little across)."""
    length = ring + 0.4
    f = s.midi_hz(midi)
    a, b, c = (np.asarray(ins.ks(round(midi + 12 * np.log2((f + hz) / f), 5), length, bright=0.8, decay=4.5, pick=0.12,
                                 soft=0.2, variant=variant * 3 + k)) for k, hz in enumerate((-0.3, 0.0, 0.4)))
    n = min(len(a), len(b), len(c))
    a, b, c = a[:n], b[:n], c[:n]
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(int(midi * 7) + variant)
    hammer = ins.eq(rng.uniform(-1, 1, n), ("hp", 300), ("lp", 3500)) * np.exp(-t / 0.004) * 0.35
    thump = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.02) * 0.3
    tone = np.vstack([0.8 * a + 0.55 * b + 0.3 * c + hammer + thump, 0.3 * a + 0.55 * b + 0.8 * c + hammer + thump])
    tone = ins.formant(tone, [(240, 3, 1.2), (1150, 2, 1.5), (2900, 3, 1.4)])
    tone = ins.eq(tone, ("hp", 110), ("lp", 9500)) * np.clip(t / 0.0006, 0, 1)
    return sealed(faded(ins.normalize(ins._gate(tone, ring, 0.25)), 0.02))


@lru_cache(maxsize=None)
def crystal(midi, ring=1.6):
    """A crystal in the cave wall, struck: a glassy FM bell with a quieter twin a couple of cents
    off on each side, so it shimmers as it rings (gently, even on a phone's one speaker)."""
    n = s.samples(ring + 0.4)
    t = np.arange(n) / s.SR
    f = s.midi_hz(midi)

    def bell(ff):
        return np.sin(2 * np.pi * ff * t + 1.4 * np.exp(-t / 0.18) * np.sin(2 * np.pi * ff * 3.5 * t))

    centre = bell(f)
    out = np.zeros((2, n))
    for ch, cents in enumerate((-2.0, 2.0)):
        glass = 0.35 * np.sin(2 * np.pi * f * 2.76 * t + ch) * np.exp(-t / 0.09)
        out[ch] = (centre + 0.3 * bell(f * 2 ** (cents / 1200)) + glass) * np.exp(-t / (ring * 0.4))
    out = ins.eq(out * np.clip(t / 0.0015, 0, 1), ("hp", 400), ("lp", 11000))
    return sealed(faded(ins.normalize(out), 0.05))


@lru_cache(maxsize=None)
def grit_bass(midi, sec, bright=1.0):
    """A gritty synth bass: a saw and a narrow pulse through a snapping filter, then driven hard so it
    growls (its upper harmonics carry the line on a phone), over a round sine."""
    n = s.samples(sec + 0.08)
    t = np.arange(n) / s.SR
    f = s.midi_hz(midi)
    e = ins.env(n, 0.003, 0.12, 0.7, 0.05, gate=sec)
    osc = 0.65 * s.saw(f, n) + 0.35 * s.square(f, n, 0.28)
    tone = ins.tv_lowpass(osc * e, 220 + 2.5 * f + 1700 * bright * np.exp(-t / 0.07), q=1.5)
    grit = ins.eq(ins.drive(tone * 2.6, 2.2), ("hp", 70), ("peak", 950, 3, 1.1), ("lp", 4200))
    return sealed(faded(ins.normalize(grit * 0.85 + s.sine(f, n) * e * 0.5), 0.012))


@lru_cache(maxsize=None)
def bass_bones(midi, sec, growl=0.0):
    """Bass trombones down in the depths: dark brass, a little driven, with a flutter-tongued growl
    on the long notes."""
    tone = np.array(ins.brass(midi, sec, bright=0.55, section=3, vibrato=0.0))
    t = np.arange(tone.shape[-1]) / s.SR
    if growl:
        tone *= 1 - growl * (0.5 + 0.5 * np.sin(2 * np.pi * 26 * t)) * np.clip((t - 0.1) / 0.15, 0, 1)
    tone = ins.eq(ins.drive(tone * 1.7, 1.5), ("hp", 75), ("peak", 600, 2.5, 1.0), ("lp", 5200))
    return sealed(faded(ins.normalize(tone), 0.02))


@lru_cache(maxsize=None)
def horns(midi, sec):
    """The horn section that greets the daylight: trumpets and trombones together, bright and round."""
    return ins.brass(midi, sec, bright=0.8, section=3, vibrato=0.06)


@lru_cache(maxsize=None)
def steam_whistle(notes, sec):
    """The mine train's steam whistle: pipes sounding a chord, each scooping up as the steam hits it,
    with the steam's hiss around them."""
    n = s.samples(sec + 0.3)
    t = np.arange(n) / s.SR
    out = np.zeros(n)
    for k, m in enumerate(notes):
        pitch = m - 1.0 * np.exp(-t / (0.07 + 0.02 * k)) + 0.06 * np.sin(2 * np.pi * (5.5 + 0.4 * k) * t)
        phase = 2 * np.pi * np.cumsum(s.midi_hz(pitch)) / s.SR
        out += np.sin(phase) + 0.3 * np.sin(2 * phase) + 0.12 * np.sin(3 * phase)
    hiss = ins.eq(np.random.default_rng(77).uniform(-1, 1, n), ("hp", 1800), ("lp", 7000)) * 0.15
    x = ins.eq((out / len(notes) + hiss) * ins.env(n, 0.06, 0.4, 0.85, 0.22, gate=sec), ("hp", 250), ("lp", 7500))
    return sealed(faded(ins.normalize(x), 0.05))


# ---------------------------------------------------------------- the rails and the drums

@lru_cache(maxsize=None)
def cart_kick():
    """The bass drum: a round boom at 65-140 Hz, where a phone can still play it."""
    n = s.samples(0.32)
    t = np.arange(n) / s.SR
    body = s.sine(66 + 75 * np.exp(-t / 0.028), n) * np.exp(-t / 0.13)
    beater = ins.eq(np.random.default_rng(3).uniform(-1, 1, n), ("hp", 300), ("lp", 2600)) * np.exp(-t / 0.008) * 0.35
    return sealed(faded(ins.normalize(np.tanh((body + beater) * 1.5))))


@lru_cache(maxsize=None)
def brush_tap(accent=False, variant=0):
    """The train beat's brush on the snare: a quick swish-tap, and a fuller 'chuff' on the accents."""
    n = s.samples(0.15 if accent else 0.09)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(300 + variant + (50 if accent else 0))
    hiss = ins.eq(rng.uniform(-1, 1, n), ("hp", 1600 if accent else 2400), ("lp", 8500), ("peak", 4200, 3, 1.0))
    e = np.clip(t / (0.004 if accent else 0.002), 0, 1) * np.exp(-t / (0.05 if accent else 0.022))
    head = np.sin(2 * np.pi * 220 * t) * np.exp(-t / 0.03) * (0.3 if accent else 0.08)
    return sealed(faded(ins.normalize(hiss * e + head)))


@lru_cache(maxsize=None)
def rail_clack(pitch=1900.0, variant=0):
    """A cart's wheel over a rail joint: the steel rail's bright 'tink' and the iron wheel's knock."""
    n = s.samples(0.18)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(500 + variant)
    tink = sum(a * np.sin(2 * np.pi * pitch * r * t) * np.exp(-t / d)
               for r, a, d in ((1.0, 1.0, 0.04), (1.47, 0.55, 0.022), (2.33, 0.4, 0.014), (3.58, 0.22, 0.008)))
    knock = s.bandpass(rng.uniform(-1, 1, n), 500, 3000) * np.exp(-t / 0.005)
    thunk = np.sin(2 * np.pi * 240 * (1 + 0.3 * np.exp(-t / 0.006)) * t) * np.exp(-t / 0.018)
    x = ins.drive(tink * 0.5 + knock * 0.8 + thunk * 0.6, 1.3) * np.clip(t / 0.0008, 0, 1)
    return sealed(faded(ins.normalize(ins.eq(x, ("hp", 150), ("lp", 9000)))))


@lru_cache(maxsize=None)
def claps(variant=0):
    """The riders clapping along in the sunshine: a few hands a hair apart."""
    n = s.samples(0.25)
    out = np.zeros(n)
    rng = np.random.default_rng(40 + variant)
    for delay, low, high in ((0.0, 900, 2600), (0.006, 1100, 3300), (0.012, 800, 2300)):
        a = s.samples(delay)
        m = n - a
        tt = np.arange(m) / s.SR
        e = np.zeros(m)
        for offset, g in ((0.0, 0.7), (0.008, 0.6), (0.016, 1.0)):
            o = s.samples(offset)
            e[o:] += g * np.exp(-tt[: m - o] / (0.01 if g < 1 else 0.06))
        out[a:] += s.bandpass(rng.uniform(-1, 1, m), low, high) * e
    return sealed(faded(ins.normalize(out)))


@lru_cache(maxsize=None)
def thoom():
    """A jump's big drum: a deep, round 'thoom' (a bass drum and a floor tom at once), above the
    phone's floor."""
    n = s.samples(0.9)
    t = np.arange(n) / s.SR
    body = s.sine(68 + 90 * np.exp(-t / 0.05), n) * np.exp(-t / 0.28)
    tom = s.sine(130 * (1 + 0.3 * np.exp(-t / 0.03)), n) * np.exp(-t / 0.18) * 0.5
    skin = ins.eq(np.random.default_rng(13).uniform(-1, 1, n), ("hp", 200), ("lp", 2500)) * np.exp(-t / 0.015) * 0.4
    return sealed(faded(ins.normalize(ins.drive(body + tom + skin, 1.5)), 0.05))


# ---------------------------------------------------------------- the cave

@lru_cache(maxsize=None)
def cave_air(length):
    """The cave breathing: a hollow, slowly swelling hush with a bottle-like resonance."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(29)
    out = np.zeros((2, n))
    for ch in range(2):
        hush = ins.eq(rng.uniform(-1, 1, n), ("hp", 160), ("lp", 1400))
        hollow = ins.eq(rng.uniform(-1, 1, n), ("peak", 330 + 40 * ch, 12, 8.0), ("hp", 200), ("lp", 900))
        out[ch] = (hush * 0.6 + hollow * 0.4) * (0.6 + 0.4 * np.sin(2 * np.pi * t / (4.1 + 0.7 * ch) + ch * 1.7))
    shape = np.clip(t / 2.5, 0, 1) ** 2 * np.clip((length - t) / 1.5, 0, 1)
    return sealed(faded(ins.normalize(out * shape)))


@lru_cache(maxsize=None)
def drip(pitch=1400.0):
    """A water drop falling into a pool in the dark: a tiny swoop up."""
    n = s.samples(0.14)
    t = np.arange(n) / s.SR
    f = pitch * (1 + 0.8 * np.clip(t / 0.025, 0, 1) ** 0.6)
    tone = np.sin(2 * np.pi * np.cumsum(f) / s.SR) * np.exp(-t / 0.035) * np.clip(t / 0.001, 0, 1)
    return sealed(faded(ins.normalize(tone)))


@lru_cache(maxsize=None)
def rumble(length):
    """The cart starting to roll: an iron rumble that flutters with the wheels, kept above the phone's floor."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(61)
    out = np.zeros((2, n))
    for ch in range(2):
        base = ins.eq(rng.uniform(-1, 1, n), ("hp", 110), ("lp", 650), ("peak", 260, 4, 2.0))
        out[ch] = base * (0.75 + 0.25 * np.sin(2 * np.pi * 7.5 * t + ch))
    shape = np.clip(t / 1.0, 0, 1) * np.clip((length - t) / 0.4, 0, 1)
    return sealed(faded(ins.normalize(out * shape)))


@lru_cache(maxsize=None)
def takeoff(length):
    """The cart leaving the lip of a broken bridge: air rushing up into the jump."""
    n = s.samples(length)
    t = np.linspace(0, 1, n)
    rng = np.random.default_rng(71)
    air = ins.tv_lowpass(rng.uniform(-1, 1, n), 500 * 14 ** t, q=1.8) - ins.tv_lowpass(rng.uniform(-1, 1, n), 250 * 14 ** t, q=0.7) * 0.5
    shape = np.clip(t / 0.92, 0, 1) ** 1.6 * np.clip((1 - t) / 0.08, 0, 1)  # up to the lip, then gone
    return sealed(faded(ins.normalize(ins.eq(air, ("hp", 300)) * shape), 0.006))


@lru_cache(maxsize=None)
def shatter(variant=0):
    """Crystals showering down after a big hit: a quick cascade of glassy tings (on B, C sharp, E and
    F sharp, which sit in every chord they meet)."""
    n = s.samples(1.4)
    out = np.zeros((2, n))
    rng = np.random.default_rng(700 + variant)
    pool = (83, 85, 88, 90, 95, 97, 100, 102)  # B5 C#6 E6 F#6 B6 C#7 E7 F#7
    for i in range(14):
        start = s.samples(0.45 * (i / 14) ** 1.3 + rng.uniform(0, 0.02))
        m = pool[(len(pool) - 1 - i + int(rng.integers(0, 3))) % len(pool)]
        x = aimed(crystal(m, 0.5), rng.uniform(-0.8, 0.8)) * rng.uniform(0.35, 1.0) * (1 - 0.5 * i / 14)
        end = min(n, start + x.shape[1])
        out[:, start:end] += x[:, : end - start]
    return sealed(faded(ins.normalize(out), 0.1))


@lru_cache(maxsize=None)
def fuse(length):
    """A TNT fuse fizzing down: a hot sizzle that spits sparks, hotter as it burns."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(81)
    flicker = 0.5 + 0.5 * ins.normalize(ins.eq(rng.uniform(-1, 1, n), ("lp", 25.0)))
    sizzle = ins.eq(rng.uniform(-1, 1, n), ("hp", 2500), ("lp", 9000)) * (0.4 + flicker)
    sparks = np.zeros(n)
    for _ in range(int(length * 14)):
        a = int(rng.uniform(0, n - 300))
        sparks[a:a + 300] += rng.uniform(-1, 1, 300) * np.exp(-np.arange(300) / 25) * rng.uniform(0.3, 1)
    x = (sizzle * 0.7 + ins.eq(sparks, ("hp", 1500)) * 0.6) * np.clip(t / 0.05, 0, 1) * (0.4 + 0.6 * t / length)
    return sealed(faded(ins.normalize(x), 0.03))


@lru_cache(maxsize=None)
def kaboom():
    """The TNT goes off: a crack, a boom (kept above the phone's floor), the blast rolling away down
    the tunnel and rocks clattering after it."""
    n = s.samples(1.8)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(91)
    boom = s.sine(70 + 130 * np.exp(-t / 0.045), n) * np.exp(-t / 0.32)
    blast = s.sweep_lowpass(rng.uniform(-1, 1, n), 7000, 300, blocks=48) * np.exp(-t / 0.45)
    whump = ins.eq(rng.uniform(-1, 1, n), ("hp", 250), ("lp", 1600)) * np.exp(-t / 0.12)
    crack = ins.eq(rng.uniform(-1, 1, n), ("hp", 900), ("lp", 6000)) * np.exp(-t / 0.015)
    rocks = np.zeros(n)
    for _ in range(45):
        a = int((rng.uniform(0.08, 1.3) ** 1.4) * s.SR)
        m = min(700, n - a)
        rocks[a:a + m] += rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / 90) * rng.uniform(0.2, 1)
    x = ins.drive(boom * 1.0 + blast * 1.0 + whump * 0.6 + crack * 1.0 + ins.eq(rocks, ("hp", 500), ("lp", 5000)) * 0.45, 1.6)
    return sealed(faded(ins.normalize(ins.eq(x, ("hp", 58), ("hp", 58))), 0.2))


# ---------------------------------------------------------------- the song

def minecart_mayhem():
    """Crystal Cave Express (160 bpm, B minor, out into B major): a runaway mine cart through the
    crystal cave. Water drips and crystals ring in the dark until a cart starts to roll; then the
    wheels clatter over the rail joints ('clickety-CLACK') on a brushed train beat with a gritty synth
    bass, and a hammered dulcimer (a cimbalom) rattles out the tune, clacking up each climb and
    tumbling down each drop, its echo ringing round the cave. The depths (24-36 s after GO) are a
    growling bass-trombone tune with LEFT-or-RIGHT calls from either side at the junctions; the jumps
    (36-48 s) are band hits where the rails fall silent while the cart flies, and a TNT fuse and its
    KABOOM. Then a light at the end of the tunnel: the bass climbs a half step a bar (48-54 s) into
    daylight, a steam whistle and the tune in B major (54 s, as the first carts come out), a horn
    anthem (66 s) and the whole band for the finish, whose last hit lands at 87 s, just before the
    round's 90 s time-out; a heave from the low brass pushes back into the drop."""
    tr = Track(bpm=160, bars=70)
    order = plan(tr, [
        ("intro", 10, "Bm | Bm | Bm | Bm | G | Em | Em | Bm | F#sus4 | F#7"),
        ("cave1", 8, "Bm | G | D | A | Bm | G | Em | F#"),
        ("cave2", 8, "Bm | G | D | A | Bm | G | Em | F#"),
        ("depths", 8, "Bm | A | G | F# | Em | G | C | F#7"),
        ("jumps", 8, "Bm | Bm | G | G | Em | Em | F# | F#"),
        ("glimmer", 4, "G | E/G# | A | F#/A#"),
        ("day1", 8, "B | G#m | E | F# | B | G#m | E | F#"),
        ("day2", 8, "B | F# | G#m | E | B | F#7/A# | E | F#"),
        ("finale", 7, "B | G#m | E | F# | E | F#7 | B"),
        ("turn", 1, "F#7"),
    ])
    parts = {p.name: p for p in order}
    changes = [(b, st, ln, c) for p in order for b, st, ln, c in p.changes]

    def chord_at(bar, step=0.0):
        return next(c for b, st, ln, c in changes if b == bar and st <= step < st + ln)

    # The tune: up each climb a snapping 'clickety-CLACK' arpeggio, down each drop a tumbling run.
    hook = melody("""B4:1' B4:3 D5:1' D5:3 F#5:1' F#5:3 B5:4 | G5:1 F#5:1 E5:1 D5:1 B4:1 A4:1 G4:1 F#4:1 G4:4 B4:2 D5:2 |
                     A4:1' A4:3 D5:1' D5:3 F#5:1' F#5:3 A5:4 | A5:1 G5:1 F#5:1 E5:1 C#5:1 B4:1 A4:1 G4:1 A4:4 r:4 |
                     B4:1' B4:3 D5:1' D5:3 F#5:1' F#5:3 B5:2 C#6:2 | D6:1 C#6:1 B5:1 A5:1 G5:1 F#5:1 E5:1 D5:1 B4:4 G4:4 |
                     E5:1' E5:3 G5:1' G5:3 B5:1' B5:3 D6:2 C#6:2 | A#5:2 F#5:2 C#5:2 A#4:2 F#4:4 r:4""")
    # ...and the same tune out in the daylight, in B major.
    sunny = melody("""B4:1' B4:3 D#5:1' D#5:3 F#5:1' F#5:3 B5:4 | G#5:1 F#5:1 E5:1 D#5:1 B4:1 A#4:1 G#4:1 F#4:1 G#4:4 B4:2 D#5:2 |
                      G#4:1' G#4:3 B4:1' B4:3 E5:1' E5:3 G#5:4 | A#5:1 G#5:1 F#5:1 E5:1 C#5:1 B4:1 A#4:1 G#4:1 A#4:4 r:4 |
                      B4:1' B4:3 D#5:1' D#5:3 F#5:1' F#5:3 B5:2 C#6:2 | D#6:1 C#6:1 B5:1 A#5:1 G#5:1 F#5:1 E5:1 D#5:1 B4:4 G#4:4 |
                      E5:1' E5:3 G#5:1' G#5:3 B5:1' B5:3 D#6:2 C#6:2 | A#5:2 F#5:2 C#5:2 A#4:2 F#4:4 r:4""")
    # The depths: the bass trombones walk down into the dark and climb back out.
    deep = melody("""F#3:6 E3:2 D3:4 C#3:4 | C#3:6 B2:2 A2:4 E3:4 | D3:6 C#3:2 B2:4 G2:4 | A#2:8 C#3:4 F#3:4 |
                     E3:4 G3:4 B3:6 A3:2 | G3:4 B3:4 D4:8 | E4:6 D4:2 C4:4 G3:4 | F#3:4 A#3:4 C#4:4 E4:4""")
    counter = melody("F#3:16 | G3:16 | F#3:16 | E3:16 | D3:16 | D3:16 | E3:8 G3:8 | F#3:8 C#3:8")
    glimmer_tune = melody("""B4:1' B4:3 D5:1' D5:3 G5:1' G5:3 B5:4 | B4:1' B4:3 E5:1' E5:3 G#5:1' G#5:3 B5:4 |
                             C#5:1' C#5:3 E5:1' E5:3 A5:1' A5:3 C#6:4 | C#5:1' C#5:3 F#5:1' F#5:3 A#5:1' A#5:3 C#6:2 E6:2""")
    anthem = melody("""B4:2 B4:2 B4:2 A#4:2 B4:4 F#4:4 | C#5:2 C#5:2 C#5:2 B4:2 A#4:4 F#4:4 | D#5:2 D#5:2 D#5:2 C#5:2 B4:4 G#4:4 |
                       E5:4 D#5:4 B4:8 | B4:2 B4:2 B4:2 A#4:2 B4:4 D#5:4 | F#5:4 E5:2 C#5:2 A#4:8 | G#4:2 B4:2 E5:6 B4:2 G#4:4 |
                       A#4:4 C#5:4 F#5:8""")
    day_counter = melody("D#3:16 | C#3:16 | B2:16 | B2:16 | D#3:16 | C#3:16 | B2:8 G#2:8 | A#2:16")
    last = melody("""B4:1' B4:3 D#5:1' D#5:3 F#5:1' F#5:3 B5:4 | G#5:1 F#5:1 E5:1 D#5:1 B4:1 A#4:1 G#4:1 F#4:1 G#4:4 B4:2 D#5:2 |
                     G#4:1' G#4:3 B4:1' B4:3 E5:1' E5:3 G#5:4 | A#5:1 G#5:1 F#5:1 E5:1 C#5:1 B4:1 A#4:1 G#4:1 A#4:4 C#5:2 D#5:2 |
                     E5:4 G#5:4 B5:8 | F#5:2 F#5:2 A#5:2 A#5:2 C#6:2 C#6:2 E6:2 r:2 | D#6:16""")

    kick = cart_kick()
    snares = [ins.snare2(205.0, 0.8, 0.22, v) for v in range(3)]
    taps = [brush_tap(False, v) for v in range(3)]
    chuffs = [brush_tap(True, v) for v in range(2)]
    clacks = [rail_clack(1900.0, 0), rail_clack(1650.0, 1)]
    hands = [claps(v) for v in range(2)]
    crash, splash, ride = s.crash(1.8), ins.splash(0.7), ins.ride(1.0, 0.35)
    toms = [ins.tom(p, 0.45, i) for i, p in enumerate((210.0, 160.0, 120.0))]

    def hits(stem, bar, pattern, sounds, gain=1.0, pan=0.0):
        for k, (step, vel) in enumerate((i, {"X": 1.0, "x": 0.8, "o": 0.45}[ch]) for i, ch in enumerate(pattern) if ch != "."):
            tr.add(stem, bar, step, sounds[k % len(sounds)], gain * vel, pan)

    def brushes(bar, level=1.0, start=0, end=16, accents=(2, 6, 10, 14)):
        """The train beat on the snare: brushed sixteenths with the engine's 'chuff' on the off-beats,
        the in-between ones a hair late (a shuffle's lilt)."""
        for k in range(start, end):
            when = k + (0.15 if k % 2 else 0.0)
            if k in accents:
                tr.add("brush", bar, when, chuffs[(bar + k) % 2], level, -0.25)
            else:
                tr.add("brush", bar, when, taps[(bar * 3 + k) % 3], level * 0.42, -0.25)

    def rails(bar, pattern, gain=1.0):
        """The wheels over the rail joints: each pair is the cart's front and back axle."""
        hits("rails", bar, pattern, clacks, gain, 0.3)

    def roll(bar, start, end, g0, g1):
        """A snare roll in 32nds, swelling."""
        k = start
        while k < end - 1e-6:
            tr.add("snare", bar, k, snares[int(k * 2) % 3], g0 + (g1 - g0) * (k - start) / (end - start))
            k += 0.5

    def train_beat(bar, level=1.0, kicks="X.......X.......", snare="....X.......X...", wheels="......xX......xX", brush=0.85):
        tr.kick("kick", bar, kicks, kick, level)
        hits("snare", bar, snare, snares, level)
        brushes(bar, brush * level)
        rails(bar, wheels, level)

    CHUG = ((0, "R", 1.0), (2, "R", 0.7), (4, "O", 0.8), (6, "R", 0.7), (8, "R", 0.95), (10, "R", 0.7), (12, "O", 0.8), (14, "F", 0.75))
    DEEP = ((0, "R", 1.0), (8, "R", 0.9), (14, "F", 0.7))  # room for the trombones' passing notes
    SUN = ((0, "R", 1.0), (2, "O", 0.75), (4, "R", 0.85), (6, "F", 0.75), (8, "R", 0.95), (10, "O", 0.75), (12, "R", 0.85), (14, "F", 0.8))

    def bass_line(bar, c, pattern, gain=1.0, bright=1.0, sec=1.6, start=0, end=16):
        root = bass_note(c, 40)
        fifth = root + 7 if root + 7 <= 54 else root - 5
        for k, which, vel in pattern:
            if start <= k < end:
                m = {"R": root, "O": root + 12, "F": fifth}[which]
                tr.add("bass", bar, k, grit_bass(m, round(tr.step * sec, 3), bright), gain * vel)

    def ring_of(sec):
        return round(min(1.6, 0.22 + sec * 1.4) * 20) / 20

    def dulc(stem, bar, notes, gain=1.0, pos=0.0, ring=None):
        for k, n in enumerate(notes):
            x = dulcimer(n.midi, ring or ring_of(n.length * tr.step), k % 2)
            tr.add(stem, bar, n.step, aimed(x, pos) if pos else x, gain * n.vel)

    def chime(bar, notes, gain=1.0, ring=1.6, spread=0.6):
        for k, n in enumerate(notes):
            tr.add("chimes", bar, n.step, aimed(crystal(n.midi, ring), spread if k % 2 else -spread), gain * n.vel)

    def blow(stem, bar, notes, voice, gain=1.0, pan=0.0):
        for n in notes:
            tr.add(stem, bar, n.step, voice(n.midi, round(n.length * tr.step * 0.92, 3)), gain * n.vel, pan)

    def growl(m, sec):
        return bass_bones(m, sec, 0.35 if sec > 0.5 else 0.0)

    def jump_hit(bar, step, c, top, air):
        """The cart leaves the rails: the band hits together (a crash, a big drum, the low brass, a
        dulcimer chord and a shower of crystals), then only the crystals and the wind while it flies."""
        root = bass_note(c, 40)
        tr.add("kick", bar, step, kick, 1.0)
        tr.add("boom", bar, step, thoom(), 1.0)
        tr.add("cymbal", bar, step, crash, 1.0, -0.3)
        for m in (root, root + 7, root + 12):
            tr.add("bones", bar, step, bass_bones(m, round(tr.step * 3, 3)), 0.75)
        tr.add("bass", bar, step, grit_bass(root, round(tr.step * air, 3), 0.6), 1.0)
        strum(tr, "dulc", bar, step, voicing(c, 66, 79) + [top], lambda m, sec: dulcimer(m, 1.2, 0), 1.2, 1.0, spread=0.01)
        tr.add("chimes", bar, step + 1, shatter(bar % 3), 0.7)
        tr.add("fx", bar, step + 1, ins.whoosh(round(tr.step * (air - 1), 3), up=False), 0.35, 0.2)

    def landing(bar, step):
        tr.add("kick", bar, step, kick, 0.9)
        tr.add("snare", bar, step, snares[0], 0.9)
        tr.add("snare", bar, step - 0.3, snares[1], 0.4)
        tr.add("cymbal", bar, step, splash, 0.7, 0.3)

    def lift(length):
        """A riser that stops clean (a short fade at its top)."""
        return faded(s.riser(length), 0.02)

    def launch(bar):
        """The push into the ride (the intro's last bar, and the last bar before the loop goes round):
        the low brass heave, the bass walks up, a tom run and a snare roll, the dulcimer runs up to the
        leading note, then an eighth's breath before the drop, so nothing rings across it."""
        for m, g in ((42, 0.8), (49, 0.7)):
            tr.add("bones", bar, 0, bass_bones(m, round(tr.step * 3, 3)), g)
        tr.add("bones", bar, 8, bass_bones(54, round(tr.step * 5.5, 3), 0.3), 0.55)
        for k, m, sec in ((0, 42, 3.5), (8, 42, 1.6), (10, 46, 1.6), (12, 49, 1.2)):
            tr.add("bass", bar, k, grit_bass(m, round(tr.step * sec, 3)), 0.9)
        tr.kick("kick", bar, "X.......X.......", kick)
        hits("toms", bar, "....X.X.X.......", toms, 0.7, -0.1)
        for k in range(9, 14):  # the fill, then the breath
            tr.add("snare", bar, k, snares[k % 3], 0.35 + 0.11 * (k - 9))
        brushes(bar, 0.6, end=8)
        rails(bar, "......xX........", 0.85)
        run = melody("C#4:2 F#4:2 A#4:2 C#5:2 E5:1 F#5:1 E5:1 C#5:1 A#4:2 r:2")
        for k, n in enumerate(run):
            ring = ring_of(n.length * tr.step) if n.step < 8 else (0.2 if n.step < 12 else 0.12)
            tr.add("lead", bar, n.step, dulcimer(n.midi, ring, k % 2), 0.8 * n.vel)

    # ------------------------------------------------ the intro: the dark, then a cart starts to roll
    # (bar 0 is a pre-roll: the pack keeps the 13.5 s before the drop, so it is trimmed away, and with
    # it the tails of the last bar that the loop wraps round onto the start)
    i0 = parts["intro"].first + 1
    tr.add("air", i0, 0, cave_air(round(tr.bar * 8.6, 3)), 1.0)
    for bar, step, pos, pitch in ((0, 6, -0.5, 1500.0), (1, 13, 0.4, 1250.0), (3, 3, -0.3, 1700.0), (5, 9, 0.5, 1400.0)):
        tr.add("drips", i0 + bar, step, drip(pitch), 0.8, pos)
    chime(i0, melody("r:11 F#6:5"), 0.35, ring=2.0)
    chime(i0 + 1, melody("B5:2' B5:6 D6:2' D6:6 | F#6:2' F#6:6 B6:8"), 0.4, ring=2.2)
    chime(i0 + 3, melody("G6:4 D6:4 B5:8 | E6:8 B5:8"), 0.45, ring=2.0)
    for bar, low, high, g in ((2, 47, 54, 0.32), (3, 43, 50, 0.32), (4, 40, 47, 0.3), (5, 40, 47, 0.34)):  # the depths hum
        tr.add("lowpad", i0 + bar, 0, bass_bones(low, round(tr.bar * 0.95, 3)), g)
        tr.add("lowpad", i0 + bar, 0, bass_bones(high, round(tr.bar * 0.95, 3)), g * 0.8)
    rails(i0 + 3, "............x.X.", 0.4)
    rails(i0 + 4, "xX..............", 0.65)
    rails(i0 + 5, "xX......xX......", 0.75)
    rails(i0 + 6, "......xX......xX", 0.8)
    rails(i0 + 7, "......xX......xX", 0.85)
    tr.add("fx", i0 + 4, 0, rumble(round(tr.bar * 4.9, 3)), 0.55)
    tr.add("bass", i0 + 4, 0, grit_bass(40, round(tr.step * 14, 3), 0.15), 0.75)
    for k in (0, 4, 8, 12):
        tr.add("bass", i0 + 5, k, grit_bass(40, round(tr.step * 3, 3), 0.3), 0.8)
    for k in range(0, 16, 2):
        tr.add("bass", i0 + 6, k, grit_bass(47, round(tr.step * 1.6, 3), 0.5), 0.8 if k % 4 == 0 else 0.7)
        tr.add("bass", i0 + 7, k, grit_bass(42, round(tr.step * 1.6, 3), 0.7), 0.9 if k % 4 == 0 else 0.8)
    brushes(i0 + 5, 0.25)
    brushes(i0 + 6, 0.4)
    brushes(i0 + 7, 0.6)
    tr.kick("kick", i0 + 7, "X.......X.......", kick, 0.7)
    tr.add("lowpad", i0 + 6, 0, bass_bones(47, round(tr.bar * 0.95, 3), 0.2), 0.45)
    tr.add("lowpad", i0 + 7, 0, bass_bones(42, round(tr.bar * 0.95, 3), 0.25), 0.5)
    tr.add("lowpad", i0 + 7, 0, bass_bones(49, round(tr.bar * 0.95, 3), 0.25), 0.45)
    dulc("dulc", i0 + 6, melody("B3:2 D4:2 F#4:2 B4:10"), 0.6)
    dulc("lead", i0 + 7, melody("B4:1' B4:3 C#5:1' C#5:3 F#5:1' F#5:3 B5:4"), 0.75)
    tr.add("fx", i0 + 7, 0, lift(round(tr.bar * 2 - tr.step * 2, 3)), 0.45)
    launch(i0 + 8)

    # ------------------------------------------------ the cave: the tune twice
    for name in ("cave1", "cave2"):
        part = parts[name]
        first, second = part.first, name == "cave2"
        dulc("lead", first, hook)
        tr.add("cymbal", first, 0, crash, 1.0, -0.3)
        tr.add("cymbal", first + 4, 0, splash, 0.8, 0.3)
        for m in (47, 54, 59):  # the drop: the low brass with the band
            tr.add("bones", first, 0, bass_bones(m, round(tr.step * 2.5, 3)), 1.0 if not second else 0.8)
        if not second:  # GO!
            tr.add("boom", first, 0, thoom(), 0.9)
        for local in range(8):
            bar = first + local
            c = chord_at(bar)
            if second and local == 7:  # the cart dives into the depths
                bass_line(bar, c, CHUG, end=8)
                tr.kick("kick", bar, "X...............", kick)
                hits("snare", bar, "....X...........", snares)
                brushes(bar, 0.85, end=8)
                hits("toms", bar, "........X.X.XxXx", [toms[0], toms[1], toms[1], toms[2]], 0.85, -0.1)
                tr.add("fx", bar, 6, ins.whoosh(round(tr.step * 10, 3), up=False), 0.6, -0.2)
                tr.add("bass", bar, 8, grit_bass(42, round(tr.step * 7.5, 3), 0.8), 0.9)
                continue
            bass_line(bar, c, CHUG, 0.9 if not second else 1.0)
            train_beat(bar, 0.95 if not second else 1.0,
                       kicks="X.......X.....x." if local % 4 == 3 else "X.......X.......",
                       snare="....X.......X.x." if local == 7 else "....X.......X...")
            if second:
                hits("cymbal", bar, "x...x...x...x...", [ride], 0.5, 0.3)
        if not second:
            chime(first + 3, melody("r:12 E6:1' A6:1 C#7:2"), 0.6)
            chime(first + 7, melody("r:12 C#6:1' F#6:1 A#6:2"), 0.6)
        else:
            chime(first, shift([n for n in hook if n.length >= 3], 12), 0.4, ring=1.2)
            blow("lowpad", first, counter, lambda m, sec: bass_bones(m, sec, 0.15), 0.8)

    # ------------------------------------------------ the depths: low brass, and a junction every four bars
    part = parts["depths"]
    blow("bones", part.first, deep, growl)
    for local in range(8):
        bar = part.first + local
        c = chord_at(bar)
        junction = local in (3, 7)
        bass_line(bar, c, DEEP, 0.85, bright=0.45, sec=3.0)
        tr.kick("kick", bar, "X.........X.....", kick, 0.9)
        hits("snare", bar, "........X.......", snares, 0.9)
        brushes(bar, 0.55)
        rails(bar, "......xX......xX", 0.7)
        notes = voicing(c, 59, 71)
        for k in range(0, 8 if junction else 16, 2):  # the dulcimer's broken chords
            idx = (0, 1, 2, 1, 0, 1, 2, 1)[k // 2]
            tr.add("dulc", bar, k, dulcimer(notes[idx], 0.45, (k // 2) % 2), 0.7 if k % 4 == 0 else 0.55)
        if junction:  # LEFT ... or RIGHT?
            dulc("dulc", bar, melody("r:8 C#5:1 F#5:1 A#5:2 r:4"), 1.0, pos=-0.85)
            dulc("dulc", bar, melody("r:12 A#5:1 F#5:1 C#5:2"), 1.0, pos=0.85)
            hits("toms", bar, "........x...x...", [toms[1], toms[0]], 0.6)
    chime(part.first + 1, melody("r:8 E6:2' C#6:2 A5:4"), 0.55)
    chime(part.first + 5, melody("r:8 D6:2' B5:2 G5:4"), 0.55)
    chime(part.first + 6, melody("r:8 G6:2' E6:2 C6:4"), 0.5)

    # ------------------------------------------------ the jumps: broken bridges and a TNT track
    part = parts["jumps"]
    ramps = {0: "B4:1' B4:3 D5:1' D5:3 F#5:1' F#5:3 B5:4", 2: "B4:1' B4:3 D5:1' D5:3 G5:1' G5:3 B5:4",
             4: "G4:1' G4:3 B4:1' B4:3 E5:1' E5:3 G5:4", 6: "C#5:1' C#5:3 F#5:1' F#5:3 A#5:1' A#5:3 C#6:4"}
    for local in range(8):
        bar = part.first + local
        c = chord_at(bar)
        if local % 2 == 0:  # up the ramp
            dulc("lead", bar, melody(ramps[local]))
            bass_line(bar, c, CHUG)
            train_beat(bar, kicks="X.......X...X..." if local < 6 else "X.......X...X.X.")
            if local in (0, 2):
                tr.add("fx", bar, 8, takeoff(round(tr.step * 8, 3)), 0.7, -0.2)
            if local == 4:
                tr.add("tnt", bar, 4, fuse(round(tr.step * 12, 3)), 0.22, 0.4)
            if local == 6:
                tr.add("fx", bar, 4, takeoff(round(tr.step * 12, 3)), 0.8, -0.2)
                hits("toms", bar, "............XxXx", [toms[0], toms[1], toms[2], toms[2]], 0.8, -0.1)
            continue
        top = {1: 83, 3: 86, 5: 88, 7: 90}[local]  # B5, D6, E6, F#6
        if local == 1:  # a jump over a gap: three beats in the air
            jump_hit(bar, 0, c, top, 12)
            chime(bar, melody("r:3 F#6:1 r:2 B6:1 r:3 C#7:1 r:5"), 0.45, ring=0.8)
            landing(bar, 12)
            bass_line(bar, c, CHUG, start=12)
            brushes(bar, 0.85, start=12)
            rails(bar, "..............xX")
        elif local == 3:  # a shorter one: two beats
            jump_hit(bar, 0, c, top, 8)
            chime(bar, melody("r:2 D6:1 r:2 G6:1 r:10"), 0.45, ring=0.8)
            landing(bar, 8)
            bass_line(bar, c, CHUG, start=8)
            dulc("lead", bar, melody("r:8 G5:1 F#5:1 E5:1 D5:1 B4:1 A4:1 G4:1 F#4:1"))
            tr.kick("kick", bar, "............X...", kick)
            hits("snare", bar, "............X...", snares)
            brushes(bar, 0.85, start=9)
            rails(bar, "......xX......xX")
        elif local == 5:  # the TNT track: KABOOM, and the band answers it
            tr.add("tnt", bar, 0, kaboom(), 1.0)
            tr.add("cymbal", bar, 0, crash, 1.0, 0.3)
            tr.add("kick", bar, 0, kick, 1.0)
            for m in (40, 47, 52):
                tr.add("bones", bar, 0, bass_bones(m, round(tr.step * 2, 3)), 0.8)
            strum(tr, "dulc", bar, 0, voicing(c, 66, 79) + [top], lambda m, sec: dulcimer(m, 1.0, 1), 1.0, 1.0, spread=0.01)
            for k in (6, 10):  # stop-time: 'and ... AND'
                for m in (40, 47, 52):
                    tr.add("bones", bar, k, bass_bones(m, round(tr.step * 1.5, 3)), 0.7)
                strum(tr, "dulc", bar, k, voicing(c, 66, 79), lambda m, sec: dulcimer(m, 0.5, 0), 0.5, 0.8, spread=0.008)
                tr.add("kick", bar, k, kick, 0.9)
                tr.add("snare", bar, k, snares[k % 3], 0.9)
                tr.add("bass", bar, k, grit_bass(40, round(tr.step * 1.5, 3)), 0.9)
            brushes(bar, 0.5)
            dulc("lead", bar, melody("r:12 E5:1 G5:1 B5:1 E6:1"))
            rails(bar, "............xXxX")
            tr.kick("kick", bar, "............X.X.", kick, 0.8)
        else:  # the big one: a whole bar in the air, and a light ahead
            jump_hit(bar, 0, c, top, 16)
            chime(bar, melody("r:2 A#6:1 r:3 C#7:1 r:2 F#6:1 r:6"), 0.45, ring=0.8)
            tr.add("fx", bar, 2, takeoff(round(tr.step * 14, 3)), 0.6, 0.2)
            roll(bar, 8, 16, 0.25, 0.9)
            tr.kick("kick", bar, "............X.X.", kick, 0.8)

    # ------------------------------------------------ light at the end of the tunnel: up a half step a bar
    part = parts["glimmer"]
    dulc("lead", part.first, glimmer_tune, 0.85)
    tr.add("fx", part.first, 0, lift(tr.bar * 4), 0.4)
    prev = None
    for local in range(4):
        bar = part.first + local
        c = chord_at(bar)
        root = bass_note(c, 40)
        if local == 0:  # down from the big jump
            landing(bar, 0)
        for k in range(0, 16, 2):
            tr.add("bass", bar, k, grit_bass(root if k % 4 == 0 else root + 12, round(tr.step * 1.6, 3), 0.8 + 0.05 * local), 0.72 + 0.04 * local)
        tr.kick("kick", bar, "X...X...X...X...", kick, 0.85 + 0.05 * local)
        if local < 2:
            hits("snare", bar, "....X.......X...", snares, 0.85)
            hits("snare", bar, "x.x.x.x.x.x.x.x.", snares, 0.3 + 0.1 * local)
        elif local == 2:
            hits("snare", bar, "xxxxXxxxxxxxXxxx", snares, 0.45)
        else:
            roll(bar, 0, 16, 0.25, 0.65)
        brushes(bar, 0.8)
        rails(bar, "..xX..xX..xX..xX", 0.85)
        notes = voicing(c, 50, 62, prev)
        prev = notes
        for m in notes:
            tr.add("lowpad", bar, 0, bass_bones(m, round(tr.bar * 0.95, 3), 0.2), 0.4 + 0.06 * local)
        sparkle = voicing(c, 78, 92)
        for k in range(0, 16, 2 if local < 2 else 1):
            tr.add("chimes", bar, k, aimed(crystal(sparkle[k % len(sparkle)], 0.6), -0.5 if k % 2 else 0.5), 0.2 + 0.05 * local)

    # ------------------------------------------------ daylight: the steam whistle, and the tune in B major
    for name in ("day1", "day2"):
        part = parts[name]
        first, second = part.first, name == "day2"
        tr.add("cymbal", first, 0, crash, 1.0, -0.3)
        tr.add("cymbal", first + 4, 0, crash, 0.8, 0.3)
        if not second:
            dulc("lead_sun", first, sunny)
            tr.add("whistle", first, 0, steam_whistle((83, 87, 90), 0.42), 0.9)
            tr.add("whistle", first, 5, steam_whistle((83, 87, 90), 1.1), 1.0)
            tr.add("boom", first, 0, thoom(), 1.0)
            for m in voicing(chord_at(first), 63, 78):  # the band greets the daylight
                tr.add("horns", first, 0, horns(m, round(tr.step * 3, 3)), 0.9)
            for m in (47, 54, 59):
                tr.add("bones", first, 0, bass_bones(m, round(tr.step * 3, 3)), 0.9)
            tr.add("chimes", first, 0, shatter(5), 0.8)
            chime(first + 3, melody("r:12 C#6:1' F#6:1 A#6:2"), 0.55)
            chime(first + 7, melody("r:12 F#6:1' A#6:1 C#7:2"), 0.55)
        else:
            blow("horns", first, anthem, horns)
            blow("horns", first, harmony(anthem, first, order), horns, 0.8)
            blow("lowpad", first, day_counter, lambda m, sec: bass_bones(m, sec, 0.0), 0.85)
            chime(first, shift([n for n in anthem if n.length >= 8], 24), 0.4, ring=1.4)
        prev = None
        for local in range(8):
            bar = first + local
            c = chord_at(bar)
            bass_line(bar, c, SUN)
            train_beat(bar, kicks="X...X...X...X..." if second else "X.......X.....x.", wheels="..xX..xX..xX..xX", brush=0.75)
            hits("claps", bar, "....X.......X...", hands, 0.9)
            hits("cymbal", bar, "x.x.x.x.x.x.x.x.", [ride], 0.4, 0.3)
            notes = voicing(c, 59, 71, prev)
            prev = notes
            if not second:  # the horns hold the chords up in the sunshine
                for m in notes:
                    tr.add("hornpad", bar, 0, horns(m, round(tr.bar * 0.9, 3)), 0.5)
            else:  # the dulcimer glitters on the chords, clacking like the hook
                up = voicing(c, 66, 78)
                dulc("dulc", bar, [Note(0, up[0], 1, 0.5), Note(1, up[0], 3, 0.8), Note(4, up[1], 1, 0.5), Note(5, up[1], 3, 0.8),
                                   Note(8, up[2], 1, 0.5), Note(9, up[2], 3, 0.8), Note(12, up[0] + 12, 4, 0.8)], 0.8)
            if second and local == 7:
                hits("toms", bar, "............XXxx", [toms[0], toms[1], toms[2]], 0.8, -0.1)

    # ------------------------------------------------ the finish: the whole band, out into the sun
    part = parts["finale"]
    first = part.first
    dulc("lead_sun", first, [n for n in last if n.step < 6 * 16])
    for k in range(12):  # the last chord, tremolo, like a cimbalom's big finish
        for m in (78, 83, 87):
            tr.add("lead_sun", first + 6, k, dulcimer(m, 0.35 if k < 11 else 1.4, k % 2), (0.75 - 0.03 * k) * (1.0 if m == 87 else 0.7))
    big = [n for n in last if n.length >= 2 and n.step < 6 * 16]
    for k, n in enumerate(n for n in big if n.step >= 5 * 16):  # the climb to the finish swells
        n.vel = 0.45 + 0.05 * k
    blow("horns", first, big, horns)
    blow("horns", first, harmony(big, first, order), horns, 0.8)
    chime(first, shift([n for n in big if n.length >= 3], 12), 0.4, ring=1.2)
    prev = None
    for local in range(7):
        bar = first + local
        c = chord_at(bar)
        root = bass_note(c, 40)
        notes = voicing(c, 59, 71, prev)
        prev = notes
        if local < 4:
            bass_line(bar, c, SUN)
            train_beat(bar, kicks="X...X...X...X...", wheels="..xX..xX..xX..xX", brush=0.8)
            hits("claps", bar, "....X.......X...", hands, 1.0)
            hits("cymbal", bar, "x.x.x.x.x.x.x.x.", [ride], 0.45, 0.3)
            tr.add("lowpad", bar, 0, bass_bones(root, round(tr.bar * 0.9, 3)), 0.8)
            if local % 2 == 0:
                tr.add("cymbal", bar, 0, crash, 0.9, -0.3 if local else 0.3)
        elif local < 6:  # the climb to the finish: everybody on the eighths, then a breath before the last hit
            climb = local == 5
            bass_line(bar, c, ((0, "R", 1.0), (2, "R", 0.8), (4, "R", 0.85), (6, "R", 0.8), (8, "R", 0.9), (10, "R", 0.85), (12, "O", 0.9), (14, "O", 0.95)),
                      end=14 if climb else 16)
            tr.kick("kick", bar, "X.x.X.x.X.x.X..." if climb else "X...X...X...X...", kick)
            hits("snare", bar, "x.x.x.x.X.x....." if climb else "....X.......X...", snares, 0.9)
            brushes(bar, 0.8, end=12 if climb else 16)
            rails(bar, "..xX..xX..xX...." if climb else "..xX..xX..xX..xX")
            hits("claps", bar, "....X.......X...", hands, 1.0)
            if local == 4:
                for m in notes:
                    tr.add("hornpad", bar, 0, horns(m, round(tr.bar * 0.9, 3)), 0.55)
                tr.add("lowpad", bar, 0, bass_bones(root, round(tr.bar * 0.9, 3)), 0.85)
                tr.add("cymbal", bar, 0, crash, 0.9, 0.3)
            else:
                tr.add("lowpad", bar, 0, bass_bones(root, round(tr.step * 13, 3)), 0.6)
                roll(bar, 12, 13.5, 0.5, 0.8)
                tr.add("fx", bar, 0, lift(round(tr.bar - tr.step * 2, 3)), 0.35)
        else:  # out into the daylight: the last hit
            tr.add("kick", bar, 0, kick, 1.0)
            tr.add("boom", bar, 0, thoom(), 1.0)
            tr.add("cymbal", bar, 0, crash, 1.0, -0.3)
            tr.add("cymbal", bar, 0, crash, 0.8, 0.3)
            tr.add("chimes", bar, 0, shatter(7), 0.9)
            tr.add("whistle", bar, 0, steam_whistle((83, 87, 90), 1.2), 1.0)
            for m in voicing(c, 63, 78):
                tr.add("horns", bar, 0, horns(m, round(tr.step * 6, 3)), 1.0)
            for m in (47, 54, 59):
                tr.add("bones", bar, 0, bass_bones(m, round(tr.step * 8, 3)), 0.9)
            tr.add("bass", bar, 0, grit_bass(47, round(tr.step * 8, 3), 0.8), 1.0)
            tr.add("bass", bar, 12, grit_bass(47, round(tr.step * 1.6, 3), 0.8), 0.8)
            tr.add("bass", bar, 14, grit_bass(54, round(tr.step * 1.6, 3), 0.8), 0.8)
            brushes(bar, 0.5, start=8)
            rails(bar, "..........xX..xX", 0.9)
    launch(parts["turn"].first)
    tr.add("fx", parts["turn"].first, 0, lift(round(tr.bar - tr.step * 2, 3)), 0.45)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.2, delay=0.1),
        "lead_sun": Bus(-6, reverb=0.12, delay=0.04),
        "dulc": Bus(-12, reverb=0.2, delay=0.08),
        "chimes": Bus(-13, reverb=0.4, delay=0.3),
        "bones": Bus(-6, reverb=0.18),
        "lowpad": Bus(-13, reverb=0.2),
        "horns": Bus(-6, reverb=0.15),
        "hornpad": Bus(-13, reverb=0.2),
        "whistle": Bus(-10, reverb=0.3, delay=0.1),
        "bass": Bus(-7),
        "kick": Bus(-9.5),
        "snare": Bus(-11.5, reverb=0.1, eq=(("lp", 8500),)),
        "brush": Bus(-13.5, reverb=0.05),
        "rails": Bus(-11.5, reverb=0.15, delay=0.05),
        "claps": Bus(-15, reverb=0.12),
        "cymbal": Bus(-19, eq=(("lp", 9000),)),
        "toms": Bus(-15, reverb=0.12),
        "boom": Bus(-11, reverb=0.2),
        "tnt": Bus(-8, reverb=0.25),
        "fx": Bus(-15, reverb=0.25, eq=(("lp", 8000),)),
        "air": Bus(-22, reverb=0.3),
        "drips": Bus(-18, reverb=0.5, delay=0.4),
    }, reverb_decay=2.2, reverb_tone=5200, delay_time=tr.beat * 0.75, delay_feedback=0.38)
    return finish(tr, mix), tr


SONG = Song("MinecartMayhem", "Crystal Cave Express", 160, 10, 70, minecart_mayhem)
