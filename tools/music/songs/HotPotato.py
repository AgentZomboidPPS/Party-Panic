"""Mambo Kaboom: the round song for HotPotato (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def _sealed(x: np.ndarray) -> np.ndarray:
    x.setflags(write=False)  # cached notes are shared: nobody changes them in place
    return x


def _faded(x: np.ndarray, seconds: float = 0.006) -> np.ndarray:
    """Brings a sound's last few milliseconds down to silence, so it never ends on a click."""
    x = np.array(x, dtype=float)
    k = min(x.shape[-1], s.samples(seconds))
    x[..., -k:] *= np.linspace(1, 0, k)
    return x


def _damp(x: np.ndarray, gate: float, release: float = 0.05) -> np.ndarray:
    """Stops a ringing string `gate` seconds in (a lifted finger)."""
    g = s.samples(gate)
    if g >= x.shape[-1]:
        return np.array(x, dtype=float)
    out = np.array(x, dtype=float)
    out[..., g:] *= np.exp(-np.arange(x.shape[-1] - g) / (s.samples(release) / 4.6))
    return out


def _t(n: int) -> np.ndarray:
    return np.arange(n) / s.SR


def _noise(n: int, *key) -> np.ndarray:
    return ins._rng("hotpotato", *key).uniform(-1, 1, n)


# ---------------------------------------------------------------- the band

@lru_cache(maxsize=None)
def tres(midi: float, length: float, variant: int = 0) -> np.ndarray:
    """The Cuban tres: three courses of paired steel strings (the outer pairs an octave apart), picked
    hard near the bridge, so it's bright, jangly and percussive. The song's nervous plucky voice."""
    ring = length + 0.3
    a = np.asarray(ins.ks(midi, ring, bright=0.8, decay=1.1, pick=0.11, soft=0.05, variant=variant))
    b = np.asarray(ins.ks(midi + 0.09, ring, bright=0.76, decay=1.0, pick=0.13, soft=0.05, variant=variant + 31))
    c = np.asarray(ins.ks(midi - 12 + 0.05, ring, bright=0.6, decay=1.2, pick=0.2, soft=0.1, variant=variant + 57))
    tone = ins.formant(a + 0.75 * b + 0.3 * c, [(250, 3, 1.2), (560, 2, 1.4), (1500, 3, 1.6), (2900, 2, 2.0)])
    tone = ins.eq(tone, ("hp", 170), ("lp", 7200))
    return _sealed(_faded(ins.normalize(_damp(tone, length + 0.03, 0.06))))


@lru_cache(maxsize=None)
def flute(midi: float, length: float, trill: int = 0, slide: float = 0.0, flutter: float = 0.0) -> np.ndarray:
    """A charanga flute, high and bright: a breathy chiff on every note and a little vibrato on the long
    ones. `trill` trills the note with the one that many semitones above (in sixteenths, nervously),
    `slide` slides it that many semitones up over its length (a 'fweee!'), `flutter` flutter-tongues it."""
    n = s.samples(length + 0.1)
    t = _t(n)
    pitch = midi + ins._vibrato(t, 0.09, 5.6, 0.22, 0.25)
    if trill:
        pitch = pitch + trill * (0.5 + 0.5 * np.tanh(-5 * np.cos(2 * np.pi * 12.8 * t)))
    if slide:
        pitch = pitch + slide * np.clip(t / max(length, 1e-3), 0, 1) ** 1.6
    phase = 2 * np.pi * np.cumsum(s.midi_hz(pitch)) / s.SR
    tone = np.sin(phase) + 0.28 * np.sin(2 * phase) + 0.11 * np.sin(3 * phase) + 0.04 * np.sin(4 * phase)
    f = s.midi_hz(midi)
    air = s.bandpass(_noise(n, "air", midi, length), max(500.0, f * 1.2), min(10000.0, f * 5))
    e = ins.env(n, 0.022, 0.25, 0.85, 0.06, gate=length)
    out = (tone + air * (0.06 + 0.35 * np.exp(-t / 0.018))) * e
    if flutter:
        out = out * (1 - flutter * 0.5 * (1 + np.sin(2 * np.pi * 26 * t)))
    return _sealed(_faded(ins.normalize(out)))


@lru_cache(maxsize=None)
def trombone(midi: float, length: float, glide_from: float | None = None, glide: float = 0.08,
             swell: float = 0.0, wobble: float = 0.0) -> np.ndarray:
    """A salsa trombone pair, a hair apart: a brassy bloom with a blat at the front. `glide_from` slides
    in from that note over `glide` seconds (a rip, or the long slide up), `swell` fades the note in over
    that many seconds, `wobble` is the sad trombone's slow, wide 'wah-wah'."""
    n = s.samples(length + 0.18)
    t = _t(n)
    out = np.zeros(n)
    for i, d in enumerate((-0.06, 0.06)):
        pitch = midi + d - 0.3 * np.exp(-t / 0.025) + ins._vibrato(t, 0.07 + 0.45 * wobble, 5.0 - 1.4 * wobble, 0.2, 0.2)
        if glide_from is not None:
            pitch = pitch + (glide_from - midi) * np.clip(1 - t / glide, 0, 1) ** 2
        out += s.saw(s.midi_hz(pitch), n, start=0.37 * i)
    e = ins.env(n, 0.03, 0.3, 0.78, 0.1, gate=length)
    if swell:
        e = e * np.clip(t / swell, 0, 1) ** 1.5
    cutoff = 250 + 2600 * np.clip(e * 1.2, 0, 1.2) + s.midi_hz(midi) * 2
    if wobble:
        cutoff = cutoff * (0.35 + 0.65 * (0.5 + 0.5 * np.cos(2 * np.pi * 3.6 * t)))
    tone = ins.tv_lowpass(out / 2 * e, cutoff, q=1.1)
    tone = ins.eq(tone, ("peak", 520, 3, 1.0), ("peak", 1250, 2.5, 1.3), ("hp", 85), ("lp", 6000))
    return _sealed(_faded(ins.normalize(tone)))


@lru_cache(maxsize=None)
def baby_bass(midi: float, length: float) -> np.ndarray:
    """An Ampeg baby bass, salsa's electric upright: a round, woody thump that blooms and holds, with its
    second and third harmonics up front so a phone hears the line."""
    n = s.samples(length + 0.1)
    t = _t(n)
    f = s.midi_hz(midi)
    pluck = np.asarray(ins.ks(midi, length + 0.1, bright=0.4, decay=2.2, pick=0.2, soft=0.4))[:n]
    phase = 2 * np.pi * f * t
    body = sum(a * np.sin(k * phase) * np.exp(-t / d) for k, a, d in
               ((1, 1.0, 9.0), (2, 0.8, 0.8), (3, 0.6, 0.5), (4, 0.42, 0.35), (5, 0.3, 0.25), (6, 0.2, 0.18)))
    thump = s.lowpass(_noise(n, "thump", midi), 500) * np.exp(-t / 0.01) * 0.5
    e = ins.env(n, 0.005, 0.4, 0.6, 0.07, gate=length)
    tone = ins.drive(pluck * 0.6 + body * e + thump, 1.6)
    tone = ins.eq(tone, ("lp", 2000), ("low", 90, -3), ("peak", 700, 2, 1.0), ("hp", 45))
    return _sealed(_faded(ins.normalize(_damp(tone, length + 0.02, 0.06))))


# ---------------------------------------------------------------- the percussion

@lru_cache(maxsize=None)
def conga(stroke: str, variant: int = 0) -> np.ndarray:
    """The conga and the tumba: an 'open' tone that sings, a sharp 'slap', a muffled 'touch' (the heel
    and the toe) and the deep 'tumba'."""
    n = s.samples(0.32)
    t = _t(n)
    pitch = {"open": 215.0, "slap": 230.0, "touch": 200.0, "tumba": 158.0}[stroke] * (1 + 0.005 * variant)
    hiss = _noise(n, "conga", stroke, variant)
    if stroke == "touch":
        out = s.sine(pitch * (1 + 0.1 * np.exp(-t / 0.005)), n) * np.exp(-t / 0.018)
        out += s.bandpass(hiss, 300, 1800) * np.exp(-t / 0.006) * 0.4
    elif stroke == "slap":
        out = s.sine(pitch * (1 + 0.3 * np.exp(-t / 0.006)), n) * np.exp(-t / 0.04) * 0.6
        out += s.bandpass(hiss, 1200, 6000) * np.exp(-t / 0.008) * 0.9
    else:
        out = s.sine(pitch * (1 + 0.12 * np.exp(-t / 0.012)), n) * np.exp(-t / 0.11)
        out += 0.3 * s.sine(pitch * 1.52 * (1 + 0.1 * np.exp(-t / 0.01)), n) * np.exp(-t / 0.05)
        out += s.bandpass(hiss, 900, 4500) * np.exp(-t / 0.005) * 0.35
    return _sealed(_faded(ins.normalize(out)))


@lru_cache(maxsize=None)
def bongo(high: bool, stroke: str = "open", variant: int = 0) -> np.ndarray:
    """The bongos' martillo: the little macho (high) and the bigger hembra, played with the fingertips."""
    n = s.samples(0.22)
    t = _t(n)
    pitch = (480.0 if high else 335.0) * (1 + 0.004 * (variant - 1))
    decay = {"open": 0.07, "slap": 0.035, "soft": 0.03}[stroke]
    out = s.sine(pitch * (1 + 0.25 * np.exp(-t / 0.006)), n) * np.exp(-t / decay)
    out += s.bandpass(_noise(n, "bongo", high, stroke, variant), 1500, 7000) * np.exp(-t / 0.004) * {"open": 0.35, "slap": 0.9, "soft": 0.15}[stroke]
    return _sealed(_faded(ins.normalize(out)))


@lru_cache(maxsize=None)
def timbal(high: bool, rim: bool = False, variant: int = 0) -> np.ndarray:
    """A timbal: a thin, high-tuned head on a metal shell, so it rings with a steely edge; a rimshot cracks."""
    n = s.samples(0.45)
    t = _t(n)
    pitch = 385.0 if high else 290.0
    out = s.sine(pitch * (1 + 0.1 * np.exp(-t / 0.01)), n) * np.exp(-t / 0.13)
    out += 0.4 * s.sine(pitch * 1.59 * (1 + 0.1 * np.exp(-t / 0.01)), n) * np.exp(-t / 0.07)
    for f, a, d, p in ((1180, 0.25, 0.12, 0.3), (2310, 0.18, 0.09, 1.1), (3870, 0.12, 0.06, 2.0)):
        out += a * (1.6 if rim else 1.0) * np.sin(2 * np.pi * f * t + p) * np.exp(-t / d)
    out += s.bandpass(_noise(n, "timbal", high, rim, variant), 1500, 8000) * np.exp(-t / (0.006 if rim else 0.003)) * (1.2 if rim else 0.5)
    return _sealed(_faded(ins.normalize(out)))


@lru_cache(maxsize=None)
def cascara(accent: bool = True, variant: int = 0) -> np.ndarray:
    """A stick on the timbales' metal shell (the cáscara): a dry, ticking click."""
    n = s.samples(0.07)
    t = _t(n)
    click = s.bandpass(_noise(n, "shell", accent, variant), 1800, 7000) * np.exp(-t / 0.0022)
    ping = np.sin(2 * np.pi * 2950 * t) * np.exp(-t / 0.009) * 0.35 + np.sin(2 * np.pi * 4630 * t) * np.exp(-t / 0.005) * 0.2
    knock = np.sin(2 * np.pi * 880 * t) * np.exp(-t / 0.007) * 0.45
    return _sealed(_faded(ins.normalize(click + ping + knock)))


@lru_cache(maxsize=None)
def bell(pitch: float, mouth: bool = True) -> np.ndarray:
    """A cowbell, struck at its mouth (open, ringing) or on its neck (short and closed)."""
    n = s.samples(0.35 if mouth else 0.12)
    t = _t(n)
    tone = s.square(np.full(n, pitch), n, 0.5) + 0.75 * s.square(np.full(n, pitch * 1.49), n, 0.5)
    tone = s.bandpass(tone, pitch * 0.8, pitch * 4.5) * np.exp(-t / (0.09 if mouth else 0.025))
    stick = s.bandpass(_noise(n, "bell", pitch, mouth), 2000, 7000) * np.exp(-t / 0.002) * 0.3
    return _sealed(_faded(ins.normalize(tone + stick)))


@lru_cache(maxsize=None)
def claves() -> np.ndarray:
    """Two rosewood claves knocked together: a pure, piercing 'tock'."""
    n = s.samples(0.11)
    t = _t(n)
    tone = np.sin(2 * np.pi * 2380 * t) * np.exp(-t / 0.03) + 0.22 * np.sin(2 * np.pi * 6450 * t) * np.exp(-t / 0.007)
    click = s.bandpass(_noise(n, "clave"), 3000, 9000) * np.exp(-t / 0.0012) * 0.25
    return _sealed(_faded(ins.normalize(tone + click)))


@lru_cache(maxsize=None)
def guiro(length: float, variant: int = 0) -> np.ndarray:
    """A gourd güiro, its stick raked over the ridges (a long stroke, or a short flick): a quick run of
    clicks through the hollow gourd, like a scraper on the hot grill."""
    n = s.samples(length + 0.02)
    out = np.zeros(n)
    rng = ins._rng("guiro", length, variant)
    when = 0.0
    while when < length:
        start = s.samples(when)
        m = min(n - start, 60)
        speed = np.sin(np.pi * min(1.0, when / length)) ** 0.5
        out[start:start + m] += rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / 8.0) * (0.3 + 0.7 * speed)
        when += rng.uniform(0.85, 1.15) / 150.0
    tone = ins.formant(s.bandpass(out, 1200, 7000), [(2600, 8, 3.0), (4300, 4, 3.0)])
    return _sealed(_faded(ins.normalize(tone)))


@lru_cache(maxsize=None)
def maraca(accent: bool, variant: int = 0) -> np.ndarray:
    """A shake of the maracas: a crisp 'shk' of seeds."""
    n = s.samples(0.07)
    t = _t(n)
    shake = s.bandpass(_noise(n, "maraca", accent, variant), 3500, 11000)
    return _sealed(_faded(ins.normalize(shake * np.clip(t / 0.004, 0, 1) * np.exp(-t / (0.022 if accent else 0.014)))))


# ---------------------------------------------------------------- the cookout

@lru_cache(maxsize=None)
def timer(high: bool = True) -> np.ndarray:
    """The wind-up kitchen timer on the picnic table: its escapement's dry plastic tick (or tock)."""
    n = s.samples(0.045)
    t = _t(n)
    click = s.bandpass(_noise(n, "timer", high), 1500, 6000) * np.exp(-t / 0.0014)
    body = np.sin(2 * np.pi * (1720 if high else 1390) * t) * np.exp(-t / 0.0065) * 0.6
    body += np.sin(2 * np.pi * (4100 if high else 3500) * t) * np.exp(-t / 0.0025) * 0.3
    return _sealed(_faded(ins.normalize(click + body)))


@lru_cache(maxsize=None)
def fuse(length: float, rise: float = 0.0, seed: int = 0) -> np.ndarray:
    """A lit fuse: a spitting hiss full of sparks. With `rise` it burns hotter towards its end (louder,
    with more sparks): a riser into the bang. Stereo, the sparks spitting both ways."""
    n = s.samples(length)
    t = _t(n)
    rng = ins._rng("fuse", length, rise, seed)
    out = np.zeros((2, n))
    for ch in range(2):
        hiss = ins.eq(rng.uniform(-1, 1, n), ("hp", 3000), ("lp", 9500), ("peak", 5200, 4, 1.5))
        flicker = s.lowpass(rng.uniform(-1, 1, n), 14.0)
        flicker = 0.6 + 0.4 * flicker / (np.max(np.abs(flicker)) + 1e-9)
        sparks = np.zeros(n)
        for _ in range(int(length * (30 + 60 * rise))):
            start = int(rng.uniform(0, 1) ** (1 / (1 + 1.5 * rise)) * (n - 200))
            sparks[start:start + 200] += rng.uniform(-1, 1, 200) * np.exp(-np.arange(200) / rng.uniform(8, 30)) * rng.uniform(0.2, 1.0)
        out[ch] = hiss * flicker * 0.5 + s.bandpass(sparks, 1500, 9000) * 0.9
    shape = np.clip(t / 0.06, 0, 1) * np.clip((length - t) / 0.03, 0, 1)
    if rise:
        shape = shape * (0.25 + 0.75 * (t / length) ** 2.2)
    return _sealed(ins.normalize(out * shape))


@lru_cache(maxsize=None)
def match_strike() -> np.ndarray:
    """A match struck on the box: a scratchy scrape, then the head flaring up with a soft 'fwoomp'."""
    n = s.samples(0.6)
    t = _t(n)
    rasp = 0.6 + 0.4 * np.tanh(4 * np.sin(2 * np.pi * 85 * t))
    scrape = s.bandpass(_noise(n, "match"), 1800, 7000) * np.clip(t / 0.005, 0, 1) * np.exp(-t / 0.05) * rasp
    flare = s.bandpass(_noise(n, "flare"), 250, 2400) * np.clip((t - 0.06) / 0.04, 0, 1) * np.exp(-np.clip(t - 0.1, 0, None) / 0.18)
    return _sealed(_faded(ins.normalize(scrape * 0.8 + flare * 0.7)))


@lru_cache(maxsize=None)
def pop(midi: float) -> np.ndarray:
    """A popcorn kernel bursting, tuned: a hollow 'pok' that jumps up to its note."""
    n = s.samples(0.08)
    t = _t(n)
    tone = s.sine(s.midi_hz(midi) * (0.55 + 0.45 * (1 - np.exp(-t / 0.004))), n) * np.exp(-t / 0.022)
    click = s.bandpass(_noise(n, "pop", midi), 2000, 8000) * np.exp(-t / 0.0008) * 0.4
    return _sealed(_faded(ins.normalize(tone + click)))


@lru_cache(maxsize=None)
def kaboom(big: bool = False) -> np.ndarray:
    """A cartoon blast: a deep thump (with its octave, for phones), a roar of smoke that darkens as it
    rolls away and a shower of crackling bits. The big one ends the round. Stereo."""
    length = 2.4 if big else 0.9
    n = s.samples(length)
    t = _t(n)
    rng = ins._rng("kaboom", big)
    f = 72 + 130 * np.exp(-t / 0.05)
    hold = 0.45 if big else 0.2
    thump = sum(a * s.sine(f * k, n) * np.exp(-t / (hold / k ** 0.5)) for k, a in ((1, 0.8), (2, 0.6), (3, 0.3)))
    out = np.zeros((2, n))
    for ch in range(2):
        cutoff = 400 + 8000 * np.exp(-t / (0.5 if big else 0.15))
        roar = ins.tv_lowpass(rng.uniform(-1, 1, n), cutoff, q=0.8) * np.clip(t / 0.004, 0, 1) * np.exp(-t / (0.9 if big else 0.28))
        whoomp = s.bandpass(rng.uniform(-1, 1, n), 100, 600) * np.exp(-t / (0.4 if big else 0.15))  # the fireball's body
        bits = np.zeros(n)
        for _ in range(60 if big else 12):
            start = int(rng.uniform(0.02, 0.6 if big else 0.35) * n)
            m = min(400, n - start)
            bits[start:start + m] += rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / rng.uniform(15, 60)) * rng.uniform(0.2, 1)
        out[ch] = roar * 0.9 + whoomp * 0.8 + s.bandpass(bits, 900, 7000) * 0.35
    out = ins.drive(out + thump, 1.8)  # saturated, so it's loud for its peak
    return _sealed(_faded(ins.normalize(ins.eq(out, ("hp", 45))), 0.05))


@lru_cache(maxsize=None)
def cymbal(length: float = 1.6) -> np.ndarray:
    """The timbalero's crash: a bright splash that rings out (faded, so it never clicks off)."""
    n = s.samples(length)
    t = _t(n)
    metal = sum(s.square(np.full(n, f), n) for f in (3150, 3920, 4730, 5810, 6990)) / 5
    wash = ins.eq(metal * 0.35 + _noise(n, "cymbal", length) * 0.65, ("hp", 4200), ("lp", 11500))
    return _sealed(_faded(ins.normalize(wash * np.clip(t / 0.002, 0, 1) * np.exp(-t / (length * 0.3))), 0.08))


@lru_cache(maxsize=None)
def launch(length: float = 0.9) -> np.ndarray:
    """Someone blown sky-high: a flute 'fweee!' sliding up and away, fluttering as it goes."""
    x = np.array(flute(85, length, slide=19.0, flutter=0.25))
    x *= np.clip(1.15 - _t(x.shape[-1]) / length, 0, 1) ** 1.5
    return _sealed(_faded(x))


# ---------------------------------------------------------------- the song

def mambo_kaboom():
    """Mambo Kaboom (192 bpm, B minor): a backyard mambo for hot potato round the grill. A Cuban tres
    picks the nervous tune and a charanga flute answers it, over a baby bass's tumbao, congas, bongos,
    timbales, cowbells, claves, maracas and a güiro scraping like the grill, with trombones for the brass
    and the cookout joining in: a kitchen timer ticking, a fuse fizzing and popcorn popping. The tune is
    the potato, a tick-tock, a fizz and a POP!, and the band tosses it from the tres (left) to the flute
    (right) faster and faster: every two bars, every bar, every half bar, every beat, every eighth note.
    In the intro the timer ticks, a match lights the fuse and the band creeps in. GO starts the tune in
    B minor; it freezes, beeping, and goes BOOM at 20 s into a D major fiesta; BOOM at 40 s, the mambo's
    trombone riffs; up to C minor at 50 s; BOOM at 60 s and a stop-time 'freeze!' with the potato passed
    beat by beat, then a build; up to C sharp minor for the finale at 70 s, BOOM at 80 s, then a countdown
    of stabs (every beat, every eighth, every sixteenth), a hush with only the fuse, and the round ends
    (90 s, when every potato still held blows) on the KABOOM: someone flies sky-high, a sad trombone goes
    wah-wah-waaah, and the run-up from the intro leads back into the drop."""
    tr = Track(bpm=192, bars=88)
    parts = plan(tr, [
        ("intro", 12, "Bm | Bm | Bm | Bm | Bm | Bm | Bm | F#7 | Bm | F#7 | F#7 | F#7"),
        ("A1", 8, "Bm | Bm | F#7 | F#7 | G | C#m7b5 F#7 | Bm | F#7"),
        ("A2", 8, "Bm | Bm | F#7 | F#7 | G | Em7 F#7b9 | Bm | F#7"),
        ("B1", 8, "D | D | G | A7 | Bm | G | Em7 A7 | D"),
        ("B2", 8, "D | D | G | A7 | Bm | G | C#m7b5 | F#7"),
        ("mambo", 8, "Bm | F#7 | Bm | F#7 | Em | F#7 | Bm | G7"),
        ("A3", 8, "Cm | Cm | G7 | G7 | Ab | Fm7 G7b9 | Cm | G7"),
        ("freeze", 8, "Cm | Cm | Fm | Fm | G#7 | G#7 | G#7 | G#7"),
        ("finale", 16, "C#m | C#m | G#7 | G#7 | A | D#m7b5 G#7 | C#m | G#7 | C#m | G#7 | C#m | G#7 | A | F#m7 | D#m7b5 | G#7b9"),
        ("tag", 4, "C#m | C#m7b5 | F#7 | F#7"),
    ])
    first = {p.name: p.first for p in parts}
    drop = first["A1"]
    changes = [ch for p in parts for ch in p.changes]

    def chord_at(bar, step=0.0):
        bar, step = bar + int(step // 16), step % 16
        if bar >= tr.bars:  # after the last bar the game loops back to the drop
            bar = drop + (bar - tr.bars) % (tr.bars - drop)
        for b, st, ln, c in changes:
            if b == bar and st <= step < st + ln:
                return c
        raise ValueError(f"no chord at bar {bar} step {step}")

    # ------------------------------------------------ the tunes (written in B minor; shifted up later)
    potato = melody("F#5:2 B4:2 F#5:2 B4:2 D5:1 E5:1 F5:1 F#5:1 B5:2! r:2")  # tick-tock, tick-tock, fizz... POP!
    potato_v = melody("C#5:2 F#4:2 C#5:2 F#4:2 A#4:1 B4:1 C5:1 C#5:1 F#5:2! r:2")  # the same on the F#7
    tumble = melody("B5:2 A#5:1 A5:1 G#5:1 G5:1 F#5:2 r:2 D5:2 E5:2 F#5:2")  # and away it tumbles
    tumble_v = melody("F#5:2 F5:1 E5:1 D#5:1 D5:1 C#5:2 r:2 A#4:2 B4:2 D5:2")
    chorus = melody("""B5:4 A5:2 G5:2 r:2 D5:2 G5:2 B5:2 | C#6:4 B5:2 G5:2 A#5:2 C#6:2 E6:4 |
                       F#6:2 B5:2 F#6:2 B5:2 D6:1 E6:1 F6:1 F#6:1 B6:2! r:2 | A#5:2 C#6:2 E6:2 C#6:2 A#5:2 F#5:2 E5:2 C#5:2""")
    chorus2 = melody("""D6:4 B5:2 G5:2 r:2 B5:2 E6:2 D6:2 | E6:4 D6:2 B5:2 A#5:2 G5:2 E5:2 C#5:2 |
                        D5:2 F#5:2 B5:2 D6:2 F#6:4! r:4 | C#6:2! r:14""")
    warning = melody("r:4 C#5:2 C#5:2 C#5:1 C#5:1 C#5:1 C#5:1 C#5:1 C#5:1 C#5:1 C#5:1")  # beeping faster...
    fiesta = melody("F#5:3 A5:3 D6:2 r:2 C#6:2 D6:2 E6:2 | F#6:6 E6:2 D6:4 r:4")
    fiesta_answer = melody("r:2 B3:2 D4:2 G4:2 r:2 F#4:2 G4:2 B4:2 | A4:6 G4:2 E4:4 C#4:4")
    fiesta2 = melody("F#5:3 B5:3 D6:2 r:2 C#6:2 B5:2 A5:2 | B5:6 A5:2 G5:4 r:4")
    fiesta_end = melody("G5:2 F#5:2 E5:2 G5:2 A5:2 C#6:2 E6:2 G6:2 | F#6:4! D6:2 A5:2 F#5:4 r:4")
    fiesta_climb = melody("E5:2 G5:2 B5:2 C#6:2 E6:2 C#6:2 B5:2 G5:2 | F#5:2 A#5:2 C#6:2 E6:2 F#6:4! r:4")
    riff_i = melody("B3:2! r:4 B3:2 D4:2 r:2 F#4:2! r:2")  # the mambo's trombone riff: on the Bm...
    riff_v = melody("r:4 E4:2! r:2 C#4:2! r:2 A#3:2 F#3:2")  # ...and on the F#7
    riff = riff_i + shift(riff_v, steps=16)
    riff_iv = melody("E3:2! r:4 E3:2 G3:2 r:2 B3:2! r:2")
    riff_lift = melody("r:4 F4:2! r:2 D4:2! r:2 B3:2 G3:2")
    sad = melody("G4:3 F#4:3 F4:3 E4:7")

    # ------------------------------------------------ the kit
    touch = [conga("touch", v) for v in range(3)]
    slap = [conga("slap", v) for v in range(2)]
    tone = [conga("open", v) for v in range(2)]
    tumba = [conga("tumba", v) for v in range(2)]
    macho = [bongo(True, "open", v) for v in range(3)]
    thumb = [bongo(True, "soft", v) for v in range(3)]
    hembra = [bongo(False, "open", v) for v in range(2)]
    shell = [cascara(True, v) for v in range(3)]
    shell_soft = [cascara(False, v) for v in range(3)]
    tick, tock = timer(True), timer(False)

    CLAVE = ("X.....X.....X...", "....X...X.......")  # son clave, three-side first
    CASCARA = ("X...x.x...x...x.", "X...x...x.x...x.")
    MAMBO_BELL = ("X.x.x.X.x.x.X.x.", "x.x.X.x.X.x.x.x.")
    KITS = {
        "congas": {"h": (touch, 0.5), "t": (touch, 0.38), "S": (slap, 0.85), "O": (tone, 0.9), "U": (tumba, 1.0)},
        "bongos": {"X": (macho, 0.9), "o": (thumb, 0.45), "x": (macho, 0.65), "H": (hembra, 0.85)},
        "timbales": {"X": (shell, 0.9), "x": (shell_soft, 0.7)},
        "campana": {"X": ([bell(640.0, True)], 1.0), "x": ([bell(640.0, True)], 0.7), "o": ([bell(640.0, False)], 0.5)},
        "mambo_bell": {"X": ([bell(980.0, True)], 0.9), "x": ([bell(980.0, False)], 0.6)},
        "clave": {"X": ([claves()], 1.0)},
        "guiro": {"L": ([guiro(0.13, v) for v in range(3)], 0.9), "s": ([guiro(0.045, v) for v in range(3)], 0.6)},
        "maracas": {"X": ([maraca(True, v) for v in range(3)], 0.9), "x": ([maraca(False, v) for v in range(3)], 0.55)},
    }
    PANS = {"congas": 0.25, "bongos": -0.35, "timbales": -0.15, "campana": -0.35, "mambo_bell": -0.1, "clave": 0.1,
            "guiro": 0.45, "maracas": -0.45}
    STEMS = {"campana": "bells", "mambo_bell": "shell", "timbales": "shell"}  # (the timbal heads have their own stem)

    def groove(name, bar, text, level=1.0):
        """One bar of a percussion pattern; each letter names a stroke, '.' rests. Strokes cycle through a
        few recordings of themselves so no two hits in a row are the very same sound."""
        for step, ch in enumerate(text):
            if ch in KITS[name]:
                sounds, g = KITS[name][ch]
                tr.add(STEMS.get(name, name), bar, step, sounds[(bar * 16 + step) % len(sounds)], level * g, PANS[name])

    def band(bar, level=1.0, bongos="martillo", timbales="cascara", conga_part="h.t.S.t.h.t.O.U.", guiro_=True):
        side = bar % 2  # every section has an even number of bars, so even bars are the clave's three-side
        groove("clave", bar, CLAVE[side], level)
        groove("congas", bar, conga_part, level)
        if bongos == "martillo":
            groove("bongos", bar, "X.o.x.H.X.o.x.H.", level)
        elif bongos == "campana":
            groove("campana", bar, "X.o.x.o.X.o.x.o.", level)
        if timbales == "cascara":
            groove("timbales", bar, CASCARA[side], level)
        elif timbales == "bell":
            groove("mambo_bell", bar, MAMBO_BELL[side], level)
        if guiro_:
            groove("guiro", bar, "L.ssL.ssL.ssL.ss", level)
        groove("maracas", bar, "x.X.x.X.x.X.x.X.", level)

    def ticking(bar, every, gain, start=0.0, end=16.0):
        """The kitchen timer, ticking every `every` steps."""
        k, step = 0, start
        while step < end - 1e-6:
            tr.add("timer", bar, step, tick if k % 2 == 0 else tock, gain * (1.0 if k % 2 == 0 else 0.8))
            step, k = step + every, k + 1

    def tumbao(bar, gain=1.0, approach=False):
        """The baby bass's tumbao: nothing on the one; the '&' of 2 and then beat 4, tied over the bar
        line, both landing early on the chord to come."""
        here, mid, nxt = chord_at(bar, 0), chord_at(bar, 8), chord_at(bar + 1, 0)
        root = bass_note(mid, 35)
        up = mid.intervals[2] % 12 if len(mid.intervals) > 2 else 7  # the chord's own fifth (flat in a m7b5)
        fifth = root + up if root + up <= 47 else root + up - 12
        target = bass_note(nxt, 35)
        tr.add("bass", bar, 6, baby_bass(fifth if here is mid else root, tr.step * 5.5), gain * 0.9)
        if approach:  # a pickup a half step under the anticipated root
            tr.add("bass", bar, 10, baby_bass(target - 1 if target - 1 >= 35 else target + 1, tr.step * 1.8), gain * 0.75)
        tr.add("bass", bar, 12, baby_bass(target, tr.step * 9.5), gain)

    GUAJEO = (
        [(0, (0, 1)), (2, (2,)), (6, (1, 2)), (8, (3,)), (10, (2,)), (12, (1, 3)), (14, (0, 2))],
        [(2, (2,)), (4, (1, 2)), (6, (3,)), (8, (0, 2)), (10, (1,)), (12, (2,)), (14, (1, 3))],
    )
    held = [None]

    def guajeo(bar, gain=1.0):
        """The second tres's guajeo: a syncopated ostinato that talks with the clave; on the '&' of 2 and
        of 4 it already plays the chord to come."""
        side = bar % 2
        for step, which in GUAJEO[side]:
            c = chord_at(bar, step + (2 if step in (6, 14) else 0))
            v = voicing(c, 59, 71, held[0], size=3)  # under the lead tres, so the tune stays clear on top
            held[0] = v
            notes = v + [v[0] + 12, v[1] + 12]
            accent = step in ((0, 6, 12), (4, 8))[side]
            for k, i in enumerate(which):
                tr.add("guajeo", bar, step + k * 0.08, tres(notes[i], 0.13, (bar + step + i) % 4),
                       gain * (0.95 if accent else 0.7) / len(which) ** 0.5, 0.2)

    def hit(bar, step, c, gain=1.0, length=0.25, bass=True):
        """The whole band on one chord: trombones, the tres's strum, the bass, a rimshot and a slap."""
        for m in voicing(c, 52, 65, None, 3):
            tr.add("bones", bar, step, trombone(m, length), gain * 0.55)
        strum(tr, "guajeo", bar, step, voicing(c, 64, 76, None, 3), lambda m, sec: tres(m, sec), length, gain * 1.1, spread=0.006)
        if bass:
            tr.add("bass", bar, step, baby_bass(bass_note(c, 35), length + 0.1), gain)
        tr.add("timbales", bar, step, timbal(True, True), gain * 0.9, -0.15)
        tr.add("congas", bar, step, slap[0], gain * 0.8, 0.25)

    def boom(bar, big=False):
        tr.add("boom", bar, 0, kaboom(big), 2.4 if big else 1.0)
        tr.add("cymbal", bar, 0, cymbal(2.2 if big else 1.4), 1.0, 0.3)

    def roll(bar, start=12.0, gain=1.0):
        """The timbalero's abanico: a crescendo of quick strokes into the next downbeat."""
        k, i = start, 0
        while k < 16 - 1e-6:
            tr.add("timbales", bar, k, timbal(True, False, i % 3), gain * (0.35 + 0.6 * (k - start) / (16 - start)), -0.15)
            k, i = k + 0.5, i + 1

    def twinkle(bar, step):
        """...and they're a star now, far up in the sky."""
        tr.add("fx", bar, step, ins.glock(100, 0.3), 0.5, 0.5)
        tr.add("fx", bar, step + 1, ins.glock(107, 0.3), 0.35, 0.6)

    VOICES = {"tres": (lambda m, sec: tres(m, sec), -0.35), "flute": (lambda m, sec: flute(m, sec), 0.35),
              "bones": (lambda m, sec: trombone(m, sec), 0.05)}

    def lift(stem, midi):
        """A flute's low notes are soft: lift them, so a pass from the tres keeps its level."""
        return 1 + 0.35 * float(np.clip((84 - midi) / 12, 0, 1)) if stem == "flute" else 1.0

    def lead(stem, bar, notes, gain=1.0, legato=0.85):
        voice, pan = VOICES[stem]
        for n in notes:
            tr.add(stem, bar, n.step, voice(n.midi, max(0.03, n.length * tr.step * legato)), gain * n.vel * lift(stem, n.midi), pan)

    def one(stem, bar, step, midi, steps, gain=1.0, legato=0.75):
        voice, pan = VOICES[stem]
        tr.add(stem, bar, step, voice(midi, max(0.03, steps * tr.step * legato)), gain * 0.85 * lift(stem, midi), pan)

    def passed(bar, notes, every, order=("tres", "flute"), octave=None, gain=1.0):
        """The potato passed round the band: the tune hops to the next player every `every` steps."""
        octave = octave or {}
        for n in notes:
            who = order[int(n.step // every) % len(order)]
            lead(who, bar, shift([n], octave.get(who, 0)), gain)

    def pops_on(bar, notes, gain=0.8):
        """A popcorn pop on every accented note (the tune's POP!)."""
        for n in notes:
            if n.vel >= 1.0:
                tr.add("pops", bar, n.step, pop(n.midi), gain, 0.15)

    def stabs(bar, steps, gain=0.7, length=0.18):
        """The trombones' short chord stabs."""
        for st in steps:
            for m in voicing(chord_at(bar, st), 52, 65, None, 3):
                tr.add("bones", bar, st, trombone(m, length), gain * 0.55)

    def pads(bar, gain=0.5, swell=0.0):
        """The trombones holding the harmony (one long note per chord)."""
        for _, st, ln, c in [ch for ch in changes if ch[0] == bar]:
            for m in voicing(c, 50, 64, None, 3):
                tr.add("bones", bar, st, trombone(m, ln * tr.step * 0.95, swell=swell), gain * 0.5)

    def run_up(bar):
        """The two bars into the drop (in the intro and again at the end, so the loop is seamless): the
        band in full, the trombones swelling on the F#7, the timer and the fuse hurrying, the tres
        beeping faster and a roll into GO."""
        held[0] = None
        for k in range(2):
            band(bar + k, 0.95)
            guajeo(bar + k, 0.9)
            tumbao(bar + k, 0.95, approach=k == 1)
            ticking(bar + k, 2 if k == 0 else 1, 0.55)
        for m in voicing(chord_at(bar), 50, 64, None, 4):
            tr.add("bones", bar, 0, trombone(m, tr.bar * 1.9, swell=tr.bar * 1.7), 0.42)
        tr.add("fuse", bar, 0, fuse(tr.bar * 2, rise=1.0, seed=1), 0.7)
        tr.add("flute", bar + 1, 0, flute(85, tr.step * 7.5, trill=1), 0.55, 0.35)
        lead("tres", bar + 1, warning, 0.65, legato=0.6)
        roll(bar + 1, 12.0, 0.65)

    # ------------------------------------------------ the intro: a timer, a match, a fuse, and the band creeping in
    rng = np.random.default_rng(27)
    for bar in range(10):
        ticking(bar, 4 if bar < 3 else 2, 0.3 + 0.03 * bar)
    tr.add("fx", 1, 8, match_strike(), 0.8, 0.3)
    tr.add("fuse", 1, 10, fuse(tr.bar * 9.1 - tr.step * 10, seed=0), 0.55)  # burns until the run-up's own fuse takes over
    for bar in range(2, 10):  # popcorn on the grill
        for _ in range(1 + bar % 2):
            tr.add("pops", bar, float(rng.integers(0, 16)), pop(float(rng.choice([79, 83, 86, 88, 91]))), 0.25 + 0.04 * bar, rng.uniform(-0.6, 0.6))
    for bar in range(4, 10):
        groove("clave", bar, CLAVE[bar % 2], 0.45 + 0.08 * (bar - 4))
    for bar in range(6, 10):
        guajeo(bar, 0.45 + 0.12 * (bar - 6))
        groove("maracas", bar, "x.X.x.X.x.X.x.X.", 0.4 + 0.1 * (bar - 6))
    tumbao(7, 0.7)
    for bar in (8, 9):
        tumbao(bar, 0.85)
        groove("congas", bar, "h.t.S.t.h.t.O.U.", 0.7 + 0.1 * (bar - 8))
        groove("guiro", bar, "L.ssL.ssL.ssL.ss", 0.65 + 0.1 * (bar - 8))
    lead("tres", 8, potato, 0.7, legato=0.75)
    lead("flute", 9, shift(potato_v, 12), 0.6)
    run_up(10)

    # ------------------------------------------------ A1 (0-10 s after GO): the potato drops, passed every two bars
    a = first["A1"]
    for bar in range(a, a + 8):
        band(bar, 0.9)
        guajeo(bar, 0.85)
        tumbao(bar, 1.0, approach=bar == a + 7)
        ticking(bar, 4, 0.4)
    tr.add("cymbal", a, 0, cymbal(1.2), 0.8, 0.3)
    hit(a, 0, chord_at(a), 0.9, 0.2, bass=False)  # GO!
    lead("tres", a, potato, 1.0, legato=0.75)
    lead("tres", a + 1, tumble, 0.95, legato=0.75)
    lead("flute", a + 2, shift(potato_v, 12), 1.0)
    lead("flute", a + 3, shift(tumble_v, 12), 0.95)
    pops_on(a, potato)
    pops_on(a + 2, shift(potato_v, 12))
    lead("flute", a + 4, chorus, 0.9)
    lead("tres", a + 4, shift(chorus, -12), 0.85, legato=0.75)

    # ------------------------------------------------ A2 (10-20 s): passed every bar, trombones join, then FREEZE... BOOM
    a = first["A2"]
    for bar in range(a, a + 7):
        band(bar, 0.95)
        guajeo(bar, 0.85)
        tumbao(bar, 1.0)
        ticking(bar, 2, 0.4)
    for k, (who, notes) in enumerate((("tres", potato), ("flute", shift(potato, 12)), ("tres", potato_v), ("flute", shift(potato_v, 12)))):
        lead(who, a + k, notes, 1.0, legato=0.75 if who == "tres" else 0.85)
        pops_on(a + k, notes)
        stabs(a + k, (12,), 0.7)
    lead("flute", a + 4, chorus2, 0.9)
    lead("tres", a + 4, shift(chorus2, -12), 0.85, legato=0.75)
    for bar in range(a + 4, a + 7):
        pads(bar, 0.5)
    freeze = a + 7  # the band stops dead on the one: the timer and the fuse, the tres beeping faster
    hit(freeze, 0, chord_at(freeze))
    lead("tres", freeze, warning, 0.9, legato=0.6)
    ticking(freeze, 1, 0.55)
    tr.add("fuse", freeze, 2, fuse(tr.step * 14, rise=1.0, seed=2), 0.8)

    # ------------------------------------------------ B1 (20-30 s): BOOM! and the party carries on in D major
    b = first["B1"]
    boom(b)
    hit(b, 0, chord_at(b), 0.9)
    twinkle(b, 13)
    for bar in range(b, b + 8):
        band(bar, 0.85, bongos="campana")
        guajeo(bar, 0.9)
        tumbao(bar, 1.0, approach=bar in (b + 3, b + 7))
    lead("flute", b, fiesta)
    lead("bones", b + 2, fiesta_answer, 0.9)
    lead("flute", b + 4, fiesta2)
    lead("flute", b + 6, fiesta_end)
    lead("bones", b + 6, shift(fiesta_end, -24), 0.8)
    lead("tres", b + 6, shift(fiesta_end, -12), 0.6, legato=0.75)

    # ------------------------------------------------ B2 (30-40 s): the trombones sing it, the tres answers, a climb... BOOM
    b = first["B2"]
    for bar in range(b, b + 8):
        band(bar, 0.9, bongos="campana")
        guajeo(bar, 0.9)
        tumbao(bar, 1.0, approach=bar == b + 3)
        ticking(bar, 4, 0.35)
    lead("bones", b, shift(fiesta, -24), 0.95)
    tr.add("flute", b + 1, 8, flute(81, tr.step * 7.5, trill=2), 0.7, 0.35)
    lead("tres", b + 2, shift(fiesta_answer, 12), 0.95, legato=0.75)
    pads(b + 2, 0.45)
    pads(b + 3, 0.45)
    lead("flute", b + 4, fiesta2)
    lead("tres", b + 4, shift(fiesta2, -12), 0.7, legato=0.75)
    lead("bones", b + 4, shift(fiesta2, -24), 0.75)
    lead("flute", b + 6, fiesta_climb)
    lead("tres", b + 6, shift(fiesta_climb, -12), 0.75, legato=0.75)
    stabs(b + 7, (0, 4, 8), 0.8)
    roll(b + 7, 12.0, 0.9)
    tr.add("fuse", b + 7, 0, fuse(tr.bar, rise=1.0, seed=3), 0.7)

    # ------------------------------------------------ the mambo (40-50 s): BOOM! trombone riffs, flute trills, cowbells
    m = first["mambo"]
    boom(m)
    tr.add("fx", m, 2, launch(), 0.8, 0.4)
    for bar in range(m, m + 8):
        band(bar, 1.0, bongos="campana", timbales="bell", conga_part="h.t.S.t.h.tSO.U.")
        guajeo(bar, 1.0)
        tumbao(bar, 1.0, approach=bar in (m + 3, m + 6))
        ticking(bar, 2, 0.4)
    for k, line in enumerate((riff_i, riff_v, riff_i, riff_v, riff_iv, riff_v, riff_i, riff_lift)):  # the last: G7, a half step up into C minor
        lead("bones", m + k, line, 1.0)
        lead("bones", m + k, shift(line, 12), 0.45)
    tr.add("flute", m + 2, 0, flute(90, tr.step * 7.6, trill=1), 0.9, 0.35)
    lead("flute", m + 2, melody("r:8 D6:1 C#6:1 B5:1 A#5:1 B5:1 C#6:1 D6:1 E6:1 | C#6:2 A#5:2 F#5:2 A#5:2 C#6:2 E6:2 F#6:4"))
    tr.add("flute", m + 6, 0, flute(86, tr.step * 7.6, trill=2), 0.9, 0.35)
    lead("flute", m + 6, melody("r:8 D6:1 E6:1 F#6:1 D6:1 B5:1 C#6:1 D6:1 F6:1 | D6:2 B5:2 G5:2 B5:2 D6:4! r:4"))
    roll(m + 7, 12.0, 0.9)

    # ------------------------------------------------ A3 (50-60 s): up a half step, passed every half bar... FREEZE... BOOM
    a = first["A3"]
    tr.add("cymbal", a, 0, cymbal(1.4), 0.9, 0.3)
    for bar in range(a, a + 7):
        band(bar, 1.0, bongos="martillo", timbales="cascara", conga_part="h.t.S.t.h.tSO.U.")
        groove("campana", bar, "X...x...X...x...", 0.8)
        guajeo(bar, 0.95)
        tumbao(bar, 1.0)
        ticking(bar, 2, 0.45)
    passed(a, shift(potato, 1), 8)
    passed(a + 1, shift(tumble, 1), 8, order=("flute", "tres"))
    passed(a + 2, shift(potato_v, 1), 8, octave={"flute": 12})
    passed(a + 3, shift(tumble_v, 1), 8, order=("flute", "tres"))
    for k, notes in enumerate((shift(potato, 1), shift(tumble, 1), shift(potato_v, 1), shift(tumble_v, 1))):
        pops_on(a + k, notes)
        stabs(a + k, (12,) if k % 2 == 0 else (6,), 0.8)
    lead("flute", a + 4, shift(chorus2, 1), 0.95)
    lead("tres", a + 4, shift(chorus2, -11), 0.85, legato=0.75)
    for bar in range(a + 4, a + 7):
        pads(bar, 0.55)
    freeze = a + 7
    hit(freeze, 0, chord_at(freeze))
    passed(freeze, shift(warning, 1), 2, order=("tres", "flute"), octave={"flute": 12})
    ticking(freeze, 1, 0.6)
    tr.add("fuse", freeze, 2, fuse(tr.step * 14, rise=1.0, seed=4), 0.85)

    # ------------------------------------------------ freeze! (60-70 s): BOOM, stop-time, the potato passed every beat; then the build
    f = first["freeze"]
    boom(f)
    tr.add("fx", f, 3, launch(), 0.8, -0.3)
    tr.add("fuse", f, 4, fuse(tr.bar * 4 - tr.step * 4, seed=5), 0.6)
    for k in range(4):
        bar = f + k
        c = chord_at(bar)
        for st in (0, 6, 12) if bar % 2 == 0 else (4, 8):  # the band only on the clave
            hit(bar, st, c, 0.85 if st else 1.0, 0.16)
            tr.add("clave", bar, st, claves(), 0.9, 0.1)
        ticking(bar, 2, 0.6)
        top, low = (67, 60) if k < 2 else (72, 65)  # tick-tock: G-C on the C minor, C-F on the F minor
        for beat in range(4):  # left, right, left, right: the tres and the flute toss it back and forth
            who = ("tres", "flute")[beat % 2]
            one(who, bar, beat * 4, top, 2, 0.95)
            one(who, bar, beat * 4 + 2, low, 2, 0.85)
    for k in range(4):  # the build on G#7: the drums back in one by one, the flute trilling higher every bar
        bar = f + 4 + k
        band(bar, 0.75 + 0.08 * k, bongos="martillo" if k >= 1 else None, timbales="cascara" if k >= 2 else None)
        guajeo(bar, 0.8 + 0.06 * k)
        tumbao(bar, 1.0, approach=k == 3)
        ticking(bar, 2 if k < 2 else 1, 0.5 + 0.05 * k)
        note, up = ((80, 2), (84, 1), (87, 1), (90, 2))[k]
        tr.add("flute", bar, 0, flute(note, tr.step * (15.5 if k < 3 else 11.5), trill=up), (0.75, 0.75, 0.75, 0.7)[k], 0.35)
        if k < 3:
            for mm in voicing(chord_at(bar), 50, 64, None, 4):
                tr.add("bones", bar, 0, trombone(mm, tr.bar * 0.95, swell=tr.bar * 0.6), 0.32 + 0.06 * k)
    tr.add("bones", f + 7, 0, trombone(68, tr.bar * 0.9, glide_from=56, glide=tr.bar * 0.85), 0.5)
    tr.add("bones", f + 7, 0, trombone(56, tr.bar * 0.9, glide_from=44, glide=tr.bar * 0.85), 0.38)
    lead("tres", f + 7, shift(warning, 2), 0.7, legato=0.6)
    roll(f + 7, 8.0, 0.5)
    tr.add("fuse", f + 6, 0, fuse(tr.bar * 2, rise=1.0, seed=6), 0.7)

    # ------------------------------------------------ the finale (70-90 s): C sharp minor, everybody, the countdown... KABOOM
    g = first["finale"]
    boom(g)
    hit(g, 0, chord_at(g), 1.0, 0.25, bass=False)
    for bar in range(g, g + 12):
        band(bar, 1.0, bongos="campana" if bar >= g + 8 else "martillo", timbales="bell", conga_part="h.t.S.t.h.tSO.U.")
        guajeo(bar, 1.0)
        tumbao(bar, 1.0, approach=bar in (g + 7, g + 11))
        ticking(bar, 2, 0.45)
    # now the potato's a blur: it changes hands every eighth note, with the trombones carrying the line under it
    for k, notes in enumerate((shift(potato, 2), shift(tumble, 2), shift(potato_v, 2), shift(tumble_v, 2))):
        passed(g + k, notes, 2, order=("tres", "flute") if k % 2 == 0 else ("flute", "tres"))
        lead("bones", g + k, shift(notes, -12), 0.5)
        pops_on(g + k, notes)
        stabs(g + k, (12,) if k % 2 == 0 else (6, 12), 0.85)
    lead("flute", g + 4, shift(chorus, 2), 0.95)
    lead("tres", g + 4, shift(chorus, -10), 0.9, legato=0.75)
    lead("bones", g + 4, shift(chorus, -22), 0.55)
    tr.add("cymbal", g + 4, 0, cymbal(1.2), 0.7, 0.3)
    # the moña (80-85 s): BOOM, and three riffs at once
    boom(g + 8)
    twinkle(g + 8, 13)
    for k in (0, 2):
        lead("bones", g + 8 + k, shift(riff, 2), 1.0)
        lead("bones", g + 8 + k, shift(riff, 14), 0.5)
        tr.add("flute", g + 8 + k, 0, flute(92 if k == 0 else 88, tr.step * 7.6, trill=1 if k == 0 else 2), 0.9, 0.35)
    lead("flute", g + 8, melody("r:8 E6:1 D#6:1 C#6:1 C6:1 C#6:1 D#6:1 E6:1 F#6:1 | D#6:2 C6:2 G#5:2 C6:2 D#6:2 F#6:2 G#6:4"))
    lead("flute", g + 10, melody("r:8 E6:1 D#6:1 C#6:1 D#6:1 E6:1 F#6:1 G#6:1 F#6:1 | D#6:2 C6:2 G#5:2 C6:2 D#6:4! r:4"))
    lead("tres", g + 8, melody("G#5:2 C#5:2 G#5:2 C#5:2 r:8"), 0.85, legato=0.75)
    lead("tres", g + 10, melody("G#5:2 C#5:2 G#5:2 C#5:2 r:8"), 0.85, legato=0.75)
    # the countdown (85-90 s): stabs on every beat, then every eighth, then sixteenths... and the fuse
    for k in range(4):
        bar = g + 12 + k
        c = chord_at(bar)
        every = (4, 4, 2, 1)[k]
        last = 8 if k == 3 else 16
        st = 0
        while st < last:
            hit(bar, st, c, (0.9, 0.93, 0.9, 0.75)[k], (0.22, 0.22, 0.14, 0.08)[k])
            tr.add("flute", bar, st, flute(85 if k < 3 else 84, tr.step * every * 0.6), 0.85, 0.35)
            st += every
        if k < 2:  # the drums keep the groove under the first stabs
            band(bar, 0.75, bongos="campana", timbales="bell", conga_part="h.t.S.t.h.tSO.U.")
        ticking(bar, 1, 0.6)
        groove("clave", bar, CLAVE[bar % 2], 0.9)
    tr.add("cymbal", g + 12, 0, cymbal(1.2), 0.8, 0.3)
    tr.add("fuse", g + 14, 0, fuse(tr.bar * 2, rise=1.0, seed=7), 1.0)

    # ------------------------------------------------ the tag (90 s, the round's end): KABOOM, sky-high, a sad trombone, and round again
    t = first["tag"]
    boom(t, big=True)
    hit(t, 0, chord_at(t), 1.4, 0.9)  # the band holds the last chord under the blast
    tr.add("congas", t, 0, tumba[0], 1.0, 0.25)
    tr.add("cymbal", t, 0.3, cymbal(1.8), 0.8, -0.4)
    tr.add("fx", t, 2, launch(1.2), 1.0, 0.3)
    twinkle(t, 14)
    for n in sad:  # wah, wah, wah, waaah (the last one wobbles)
        tr.add("bones", t + 1, n.step, trombone(n.midi, n.length * tr.step * 0.95, wobble=1.0 if n.length > 4 else 0.0), 0.9 * n.vel, 0.05)
    for k, mm in enumerate((96, 91, 88, 84, 79)):  # the bits come raining down
        tr.add("pops", t + 1, 1 + k * 2.5, pop(mm), 0.5, (-0.5, 0.4, -0.2, 0.6, 0.0)[k])
    ticking(t + 1, 4, 0.35, start=8)
    run_up(t + 2)

    mix = Mix(buses={
        "tres": Bus(-7, reverb=0.12, delay=0.06),
        "flute": Bus(-7, reverb=0.18, delay=0.08),
        "bones": Bus(-9, reverb=0.15),
        "guajeo": Bus(-13, reverb=0.1),
        "bass": Bus(-8),
        "congas": Bus(-10, reverb=0.08),
        "bongos": Bus(-13, reverb=0.08),
        "timbales": Bus(-13, reverb=0.1),
        "shell": Bus(-15, reverb=0.06),
        "bells": Bus(-17, reverb=0.08),
        "clave": Bus(-15, reverb=0.1),
        "guiro": Bus(-18),
        "maracas": Bus(-20),
        "timer": Bus(-17),
        "fuse": Bus(-18, eq=(("lp", 9000),)),
        "pops": Bus(-15, reverb=0.12),
        "boom": Bus(-9, reverb=0.2),
        "fx": Bus(-14, reverb=0.25, delay=0.1),
        "cymbal": Bus(-18, eq=(("lp", 10000),)),
    }, reverb_decay=1.3, reverb_tone=5000, delay_time=tr.beat * 0.75, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("HotPotato", "Mambo Kaboom", 192, 12, 88, mambo_kaboom)
