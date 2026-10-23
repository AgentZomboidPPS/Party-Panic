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


# ---------------------------------------------------------------- the big band

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
def trumpets(midi: float, length: float, rip: float = 0.0, shake: int = 0, fall: float = 0.0) -> np.ndarray:
    """The big band's trumpet section, three players a hair apart, screaming up top: blaring saws with a
    blat at the front. `rip` smears up into the note from that many semitones under it, `shake` shakes
    it (the wide lip trill that many semitones up, in time) and `fall` drops off the end of it."""
    n = s.samples(length + (0.32 if fall else 0.14))
    t = _t(n)
    out = np.zeros(n)
    for i, d in enumerate((-0.07, 0.0, 0.07)):
        pitch = midi + d - 0.25 * np.exp(-t / 0.018) + ins._vibrato(t, 0.07, 5.8, 0.28, 0.2)
        if rip:
            pitch = pitch - rip * np.clip(1 - t / 0.1, 0, 1) ** 1.5
        if shake:
            pitch = pitch + shake * (0.5 + 0.5 * np.tanh(4 * np.sin(2 * np.pi * 9.6 * (t - 0.08) - np.pi / 2))) * (t > 0.08)
        if fall:
            pitch = pitch - fall * np.clip((t - length) / 0.22, 0, 1) ** 1.3
        out += s.saw(s.midi_hz(pitch), n, start=0.29 * i)
    e = ins.env(n, 0.018, 0.25, 0.85, 0.1, gate=length + (0.2 if fall else 0.0))
    cutoff = 700 + 5000 * np.clip(e * 1.15, 0, 1.15) + s.midi_hz(midi) * 2.5
    tone = ins.drive(ins.tv_lowpass(out / 3 * e, cutoff, q=1.3) * 2.0, 1.5)  # the blare
    tone = ins.eq(tone, ("peak", 1400, 4, 1.2), ("peak", 2900, 2.5, 1.5), ("hp", 220), ("lp", 9000))
    return _sealed(_faded(ins.normalize(tone)))


@lru_cache(maxsize=None)
def trombone(midi: float, length: float, glide_from: float | None = None, glide: float = 0.08,
             swell: float = 0.0, wobble: float = 0.0) -> np.ndarray:
    """A pair of trombones, a hair apart: a brassy bloom with a blat at the front. `glide_from` slides
    in from that note over `glide` seconds (a rip, or the long slide up), `swell` fades the note in over
    that many seconds, `wobble` is the sad trombones' slow, wide 'wah-wah'."""
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
def bari(midi: float, length: float) -> np.ndarray:
    """The baritone sax honking the riffs: a reedy, buzzy low voice (a conical bore, so every harmonic)
    with a bark at the front of each note and a little growl."""
    n = s.samples(length + 0.12)
    t = _t(n)
    pitch = midi - 0.4 * np.exp(-t / 0.03) + ins._vibrato(t, 0.06, 5.0, 0.3, 0.3)
    growl = 1 + 0.15 * np.sin(2 * np.pi * 31 * t) * np.exp(-t / 0.12)
    e = ins.env(n, 0.012, 0.2, 0.8, 0.06, gate=length)
    cutoff = 400 + 2600 * np.clip(e, 0, 1) ** 1.5 + s.midi_hz(midi) * 3
    tone = ins.tv_lowpass(s.saw(s.midi_hz(pitch), n) * e * growl, cutoff, q=1.5)
    breath = s.bandpass(_noise(n, "bari", midi), 1500, 5000) * e * 0.04
    tone = ins.formant(tone + breath, [(480, 6, 1.5), (1100, 4, 2.0), (2500, 3, 2.5)])
    return _sealed(_faded(ins.normalize(ins.eq(ins.drive(tone * 1.3, 1.5), ("hp", 60), ("lp", 6000)))))


@lru_cache(maxsize=None)
def upright(midi: float, length: float) -> np.ndarray:
    """The big band's upright bass, plucked hard: a woody thump with the string's growl and a click of
    the finger, its octave and twelfth up front so a phone hears the line."""
    tone = np.asarray(ins.ks(midi, length + 0.3, bright=0.45, decay=1.6, pick=0.18, soft=0.3))
    n = tone.shape[-1]
    t = _t(n)
    phase = 2 * np.pi * s.midi_hz(midi) * t
    body = sum(a * np.sin(k * phase) * np.exp(-t / d) for k, a, d in ((1, 0.9, 0.6), (2, 0.75, 0.45), (3, 0.5, 0.3), (4, 0.3, 0.2)))
    click = s.bandpass(_noise(n, "finger", midi), 1200, 5000) * np.exp(-t / 0.004) * 0.35
    x = ins.drive(tone * 0.8 + body + click, 1.5)
    x = ins.eq(x, ("low", 90, -3), ("peak", 650, 2, 1.0), ("hp", 45), ("lp", 2400))
    return _sealed(_faded(ins.normalize(_damp(x, length + 0.02, 0.07))))


@lru_cache(maxsize=None)
def ugh(variant: int = 0) -> np.ndarray:
    """The band's grunt on the big hits: 'UGH!' (two of the players, gruff and short). Stereo."""
    length = 0.22
    n = s.samples(length + 0.05)
    out = np.zeros((2, n))
    rng = ins._rng("ugh", variant)
    for base, side in ((47.0, -0.3), (43.0, 0.3)):  # about B2 and G2
        start = s.samples(rng.uniform(0, 0.012))
        m = n - start
        tt = _t(m)
        contour = base + rng.uniform(-1, 1) + 1.5 * np.exp(-tt / 0.03) - 3.0 * np.clip(tt / length, 0, 1) ** 1.5
        f = s.midi_hz(contour)
        source = s.saw(f, m, start=rng.random()) + 0.3 * s.square(f, m, 0.3)
        e = np.clip(tt / 0.008, 0, 1) * np.clip((length - tt) / 0.03, 0, 1) * (1 - 0.3 * np.clip(tt / length, 0, 1))
        catch = s.bandpass(rng.uniform(-1, 1, m), 400, 3000) * np.exp(-tt / 0.006) * 0.5  # the throat catching
        out[:, start:] += s.pan(ins.formant(source * e, [(640, 14, 5), (1190, 10, 6), (2390, 6, 7)]) + catch, side)
    return _sealed(_faded(ins.normalize(ins.eq(out, ("hp", 120), ("lp", 4500)))))


# ---------------------------------------------------------------- the cookout's percussion

@lru_cache(maxsize=None)
def pot(stroke: str, variant: int = 0) -> np.ndarray:
    """The cookout's congas: two big cooking pots turned over and played by hand. 'open' booms with a
    little steel ring, 'slap' cracks near the rim, 'touch' is a muffled tap, 'low' is the stockpot."""
    n = s.samples(0.3)
    t = _t(n)
    f = {"open": 205.0, "slap": 215.0, "touch": 200.0, "low": 148.0}[stroke] * (1 + 0.006 * variant)
    thud = s.sine(f * (1 + 0.15 * np.exp(-t / 0.008)), n) * np.exp(-t / (0.02 if stroke == "touch" else 0.075))
    ring = sum(a * np.sin(2 * np.pi * f * r * t + p) * np.exp(-t / d) for r, a, d, p in
               ((2.31, 0.35, 0.09, 0.4), (3.87, 0.22, 0.06, 1.3), (5.42, 0.14, 0.04, 2.2)))
    hand = s.bandpass(_noise(n, "pot", stroke, variant), 800, 5000) * np.exp(-t / 0.004)
    thud_g, ring_g, hand_g = {"slap": (0.5, 1.3, 1.2), "touch": (0.6, 0.2, 0.3)}.get(stroke, (1.0, 1.0, 0.4))
    out = (thud * thud_g + ring * ring_g + hand * hand_g) * np.clip(t / 0.001, 0, 1)
    return _sealed(_faded(ins.normalize(ins.eq(out, ("hp", 90), ("lp", 7000)))))


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
def tongs(variant: int = 0) -> np.ndarray:
    """Barbecue tongs clacked shut: two thin steel arms snapping together, with a tiny bounce."""
    n = s.samples(0.08)
    out = np.zeros(n)
    for delay, gain in ((0.0, 1.0), (0.007, 0.45)):
        k = s.samples(delay)
        tt = _t(n - k)
        click = s.bandpass(_noise(n - k, "tongs", variant, delay), 2500, 9000) * np.exp(-tt / 0.0012)
        ring = (np.sin(2 * np.pi * 3150 * tt) + 0.6 * np.sin(2 * np.pi * 5230 * tt)) * np.exp(-tt / 0.012)
        out[k:] += gain * (click + 0.5 * ring)
    return _sealed(_faded(ins.normalize(out)))


@lru_cache(maxsize=None)
def spatula(accent: bool = True, variant: int = 0) -> np.ndarray:
    """A spatula tapped on the grill grate: a thin, bright 'tink' that rings a moment."""
    n = s.samples(0.07)
    t = _t(n)
    ring = (np.sin(2 * np.pi * 2620 * t) + 0.5 * np.sin(2 * np.pi * 4410 * t) + 0.3 * np.sin(2 * np.pi * 6930 * t)) * np.exp(-t / 0.018)
    click = s.bandpass(_noise(n, "spatula", accent, variant), 3000, 9000) * np.exp(-t / 0.001)
    return _sealed(_faded(ins.normalize(ring * 0.6 + click)))


@lru_cache(maxsize=None)
def sizzle(accent: bool, variant: int = 0) -> np.ndarray:
    """The grill sizzling in time like a hi-hat: a hiss with a few spitting pops in it."""
    n = s.samples(0.11 if accent else 0.06)
    t = _t(n)
    rng = ins._rng("sizzle", accent, variant)
    hiss = ins.eq(rng.uniform(-1, 1, n), ("hp", 4000), ("lp", 10000))
    spits = np.zeros(n)
    for _ in range(4 if accent else 2):
        i = int(rng.uniform(0, n * 0.6))
        spits[i:i + 60] += rng.uniform(-1, 1, 60) * np.exp(-np.arange(60) / 6) * rng.uniform(0.5, 1.0)
    e = np.clip(t / 0.004, 0, 1) * np.exp(-t / (0.035 if accent else 0.015))
    return _sealed(_faded(ins.normalize((hiss + s.bandpass(spits, 2000, 9000) * 1.5) * e)))


@lru_cache(maxsize=None)
def frying_pan(variant: int = 0) -> np.ndarray:
    """The cartoon frying pan: BONK! A heavy iron ring over a dull clank."""
    n = s.samples(0.5)
    t = _t(n)
    f = 330.0 * (1 + 0.01 * variant)
    ring = sum(a * np.sin(2 * np.pi * f * r * (1 + 0.02 * np.exp(-t / 0.01)) * t + p) * np.exp(-t / d) for r, a, d, p in
               ((1.0, 1.0, 0.16, 0.0), (2.08, 0.6, 0.11, 0.7), (3.41, 0.4, 0.07, 1.9), (4.96, 0.25, 0.05, 0.3)))
    clank = s.bandpass(_noise(n, "pan", variant), 1500, 6000) * np.exp(-t / 0.006) * 0.6
    thud = s.sine(110 * (1 + np.exp(-t / 0.01)), n) * np.exp(-t / 0.04) * 0.5
    return _sealed(_faded(ins.normalize(ins.drive((ring + clank + thud) * np.clip(t / 0.001, 0, 1), 1.3))))


@lru_cache(maxsize=None)
def lid(length: float = 1.4) -> np.ndarray:
    """A pot lid clanged like a cymbal: a bright, wobbly steel ring and a splash of noise."""
    n = s.samples(length)
    t = _t(n)
    rng = ins._rng("lid", length)
    ring = np.zeros(n)
    for _ in range(14):
        f = rng.uniform(900, 7000)
        wobble = 1 + 0.003 * np.sin(2 * np.pi * rng.uniform(3, 8) * t)
        ring += rng.uniform(0.3, 1.0) * np.sin(2 * np.pi * f * wobble * t + rng.uniform(0, 6)) * np.exp(-t / rng.uniform(0.15, length * 0.35))
    wash = ins.eq(rng.uniform(-1, 1, n), ("hp", 3500), ("lp", 11000)) * np.exp(-t / (length * 0.22))
    return _sealed(_faded(ins.normalize((ring / 6 + wash * 0.8) * np.clip(t / 0.002, 0, 1)), 0.08))


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
def rocket(length: float = 0.9) -> np.ndarray:
    """Someone blown sky-high, like a bottle rocket off the picnic table: a whistle screaming up and away
    over the hiss of its trail, warbling as it spins."""
    n = s.samples(length)
    t = _t(n)
    u = np.clip(t / length, 0, 1)
    f = 900 * 2 ** (2.2 * u ** 1.3) * (1 + 0.012 * np.sin(2 * np.pi * 23 * t))
    whistle = s.sine(f, n) + 0.15 * s.sine(2 * f, n)
    hiss = s.bandpass(_noise(n, "rocket", length), 2500, 9000) * 0.25
    return _sealed(_faded(ins.normalize((whistle + hiss) * np.clip(t / 0.03, 0, 1) * (1 - u) ** 1.2)))


# ---------------------------------------------------------------- the song

def mambo_kaboom():
    """Mambo Kaboom (192 bpm, B minor): a backyard big-band mambo for hot potato round the grill. A Cuban
    tres picks the nervous tune and a screaming trumpet section blares it back, over trombones and a
    honking baritone sax, an upright bass's tumbao and bongos; the rest of the percussion is the cookout
    itself: pots played like congas, barbecue tongs clacking the clave, a spatula ticking on the grill,
    the grill's sizzle, a frying pan, pot lids, a kitchen timer ticking, a fuse fizzing and popcorn
    popping, and the band grunts 'UGH!' on the big hits. The tune is the potato, a tick-tock, a fizz and
    a POP!, tossed from the tres (left) to the trumpets (right) faster and faster: every two bars, every
    bar, every half bar, every beat, every eighth note. In the intro the timer ticks, a match lights the
    fuse and the band creeps in. GO starts the tune in B minor; it freezes, beeping, and goes BOOM at
    20 s into a D major fiesta; BOOM, UGH! at 40 s, the mambo's trombone and bari riffs; up to C minor at
    50 s; BOOM at 60 s and a stop-time 'freeze!' with the potato passed beat by beat, then a build; up to
    C sharp minor for the finale at 70 s, BOOM at 80 s, then a countdown of stabs (every beat, every
    eighth, every sixteenth), a hush with only the fuse, and the round ends (90 s, when every potato still
    held blows) on the KABOOM: someone flies sky-high like a bottle rocket, the trombones slide down a
    sad 'wah-wah-wah-waaah', and the run-up from the intro leads back into the drop."""
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

    def octave_down(notes, start, end):
        """The tune with the notes from step `start` to `end` an octave lower (where it would climb out
        of an instrument's range)."""
        return [n for n in notes if not start <= n.step < end] + shift([n for n in notes if start <= n.step < end], -12)

    # ------------------------------------------------ the tunes (written in B minor; shifted up later)
    potato = melody("F#5:2 B4:2 F#5:2 B4:2 D5:1 E5:1 F5:1 F#5:1 B5:2! r:2")  # tick-tock, tick-tock, fizz... POP!
    potato_v = melody("C#5:2 F#4:2 C#5:2 F#4:2 A#4:1 B4:1 C5:1 C#5:1 F#5:2! r:2")  # the same on the F#7
    tumble = melody("B5:2 A#5:1 A5:1 G#5:1 G5:1 F#5:2 r:2 D5:2 E5:2 F#5:2")  # and away it tumbles
    tumble_v = melody("F#5:2 F5:1 E5:1 D#5:1 D5:1 C#5:2 r:2 A#4:2 B4:2 D5:2")
    chorus = melody("""B5:4 A5:2 G5:2 r:2 D5:2 G5:2 B5:2 | C#6:4 B5:2 G5:2 A#5:2 C#6:2 E6:4 |
                       F#6:2 B5:2 F#6:2 B5:2 D6:1 E6:1 F6:1 F#6:1 B6:2! r:2 | A#5:2 C#6:2 E6:2 C#6:2 A#5:2 F#5:2 E5:2 C#5:2""")
    chorus2 = melody("""D6:4 B5:2 G5:2 r:2 B5:2 E6:2 D6:2 | E6:4 D6:2 B5:2 A#5:2 G5:2 E5:2 C#5:2 |
                        D5:2 F#5:2 B5:2 D6:2 F#6:4! r:4 | C#6:2! r:14""")
    tres_chorus = octave_down(chorus, 32, 48)  # the tres an octave over the trumpets, but its third bar (the potato) where it was
    warning = melody("r:4 C#5:2 C#5:2 C#5:1 C#5:1 C#5:1 C#5:1 C#5:1 C#5:1 C#5:1 C#5:1")  # beeping faster...
    fiesta = melody("F#5:3 A5:3 D6:2 r:2 C#6:2 D6:2 E6:2 | F#6:6 E6:2 D6:4 r:4")
    fiesta_answer = melody("r:2 B3:2 D4:2 G4:2 r:2 F#4:2 G4:2 B4:2 | A4:6 G4:2 E4:4 C#4:4")
    fiesta2 = melody("F#5:3 B5:3 D6:2 r:2 C#6:2 B5:2 A5:2 | B5:6 A5:2 G5:4 r:4")
    fiesta_end = melody("G5:2 F#5:2 E5:2 G5:2 A5:2 C#6:2 E6:2 G6:2 | F#6:4! D6:2 A5:2 F#5:4 r:4")
    fiesta_climb = melody("E5:2 G5:2 B5:2 C#6:2 E6:2 C#6:2 B5:2 G5:2 | F#5:2 A#5:2 C#6:2 E6:2 F#6:4! r:4")
    riff_i = melody("B3:2! r:4 B3:2 D4:2 r:2 F#4:2! r:2")  # the mambo's riff for trombones and bari: on the Bm...
    riff_v = melody("r:4 E4:2! r:2 C#4:2! A#3:2 r:2 F#3:2")  # ...and on the F#7
    riff = riff_i + shift(riff_v, steps=16)
    riff_iv = melody("E3:2! r:4 E3:2 G3:2 r:2 B3:2! r:2")
    riff_lift = melody("r:4 F4:2! r:2 D4:2! B3:2 r:2 G3:2")
    sad = melody("G4:3 F#4:3 F4:3 E4:7")

    # ------------------------------------------------ the kit
    CLAVE = ("X.....X.....X...", "....X...X.......")  # son clave, three-side first (on the tongs)
    CASCARA = ("X...x.x...x...x.", "X...x...x.x...x.")  # (the spatula on the grill)
    EIGHTHS = ("X.x.x.X.x.x.X.x.", "x.x.X.x.X.x.x.x.")
    POTS = "h.t.S.t.h.t.O.U."  # the conga tumbao, on the pots
    KITS = {
        "pots": {"h": ([pot("touch", v) for v in range(3)], 0.5), "t": ([pot("touch", v + 3) for v in range(3)], 0.38),
                 "S": ([pot("slap", v) for v in range(2)], 0.85), "O": ([pot("open", v) for v in range(2)], 0.9),
                 "U": ([pot("low", v) for v in range(2)], 1.0)},
        "bongos": {"X": ([bongo(True, "open", v) for v in range(3)], 0.9), "o": ([bongo(True, "soft", v) for v in range(3)], 0.45),
                   "x": ([bongo(True, "open", v) for v in range(3)], 0.65), "H": ([bongo(False, "open", v) for v in range(2)], 0.85)},
        "tongs": {"X": ([tongs(v) for v in range(2)], 1.0)},
        "spatula": {"X": ([spatula(True, v) for v in range(3)], 0.9), "x": ([spatula(False, v) for v in range(3)], 0.65)},
        "sizzle": {"X": ([sizzle(True, v) for v in range(3)], 0.9), "x": ([sizzle(False, v) for v in range(3)], 0.55)},
    }
    PANS = {"pots": 0.25, "bongos": -0.35, "tongs": 0.1, "spatula": -0.15, "sizzle": -0.45}
    tick, tock = timer(True), timer(False)

    def groove(name, bar, text, level=1.0):
        """One bar of a percussion pattern; each letter names a stroke, '.' rests. Strokes cycle through a
        few recordings of themselves so no two hits in a row are the very same sound."""
        for step, ch in enumerate(text):
            if ch in KITS[name]:
                sounds, g = KITS[name][ch]
                tr.add(name, bar, step, sounds[(bar * 16 + step) % len(sounds)], level * g, PANS[name])

    def band(bar, level=1.0, bongos=True, grate="cascara", pots=POTS):
        side = bar % 2  # every section has an even number of bars, so even bars are the clave's three-side
        groove("tongs", bar, CLAVE[side], level)
        groove("pots", bar, pots, level)
        if bongos:
            groove("bongos", bar, "X.o.x.H.X.o.x.H.", level)
        if grate:
            groove("spatula", bar, (CASCARA if grate == "cascara" else EIGHTHS)[side], level)
        groove("sizzle", bar, "x.X.x.X.x.X.x.X.", level)

    def ticking(bar, every, gain, start=0.0, end=16.0):
        """The kitchen timer, ticking every `every` steps."""
        k, step = 0, start
        while step < end - 1e-6:
            tr.add("timer", bar, step, tick if k % 2 == 0 else tock, gain * (1.0 if k % 2 == 0 else 0.8))
            step, k = step + every, k + 1

    def tumbao(bar, gain=1.0, approach=False, honk=False):
        """The upright's tumbao: nothing on the one; the '&' of 2 and then beat 4, tied over the bar line,
        both landing early on the chord to come. With `honk` the bari punches beat 4 with it."""
        here, mid, nxt = chord_at(bar, 0), chord_at(bar, 8), chord_at(bar + 1, 0)
        root = bass_note(mid, 35)
        up = mid.intervals[2] % 12 if len(mid.intervals) > 2 else 7  # the chord's own fifth (flat in a m7b5)
        fifth = root + up if root + up <= 47 else root + up - 12
        target = bass_note(nxt, 35)
        tr.add("bass", bar, 6, upright(fifth if here is mid else root, tr.step * 5.5), gain * 0.9)
        if approach:  # a pickup a half step under the anticipated root
            tr.add("bass", bar, 10, upright(target - 1 if target - 1 >= 35 else target + 1, tr.step * 1.8), gain * 0.75)
        tr.add("bass", bar, 12, upright(target, tr.step * 9.5), gain)
        if honk:
            tr.add("bari", bar, 12, bari(target + 12, tr.step * 2.5), gain * 0.7, -0.1)

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
        """The whole band on one chord: trumpets on top, trombones, the bari, the tres's strum, the bass
        and a slap on the pots."""
        for m in voicing(c, 70, 82, None, 3):
            tr.add("trumpets", bar, step, trumpets(m, length), gain * 0.45, 0.35)
        for m in voicing(c, 52, 65, None, 3):
            tr.add("bones", bar, step, trombone(m, length), gain * 0.5)
        tr.add("bari", bar, step, bari(bass_note(c, 40), length), gain * 0.6, -0.1)
        strum(tr, "guajeo", bar, step, voicing(c, 64, 76, None, 3), lambda m, sec: tres(m, sec), length, gain * 1.1, spread=0.006)
        if bass:
            tr.add("bass", bar, step, upright(bass_note(c, 35), length + 0.1), gain)
        tr.add("pots", bar, step, pot("slap", 0), gain * 0.8, 0.25)

    def boom(bar, big=False, grunt=None):
        """A potato goes off: the blast, a pot lid crashing, the frying pan, and maybe the band's 'UGH!'."""
        tr.add("boom", bar, 0, kaboom(big), 2.4 if big else 1.0)
        tr.add("pans", bar, 0, lid(2.2 if big else 1.4), 1.0, 0.3)
        tr.add("pans", bar, 0, frying_pan(0 if big else 1), 0.7, -0.2)
        if grunt is not None:
            tr.add("ugh", bar, 0, ugh(grunt), 1.0)

    def roll(bar, start=12.0, gain=1.0):
        """A bongo roll into the next downbeat: quick strokes swapping drums, swelling."""
        k, i = start, 0
        while k < 16 - 1e-6:
            tr.add("bongos", bar, k, bongo(i % 2 == 0, "open", i % 3), gain * (0.35 + 0.6 * (k - start) / (16 - start)), -0.35)
            k, i = k + 0.5, i + 1

    def twinkle(bar, step):
        """...and they're a star now, far up in the sky."""
        tr.add("fx", bar, step, ins.glock(100, 0.3), 0.5, 0.5)
        tr.add("fx", bar, step + 1, ins.glock(107, 0.3), 0.35, 0.6)

    PAN = {"tres": -0.35, "trumpets": 0.35, "bones": 0.05, "bari": -0.1}

    def sound(stem, midi, sec, accent=False):
        if stem == "tres":
            return tres(midi, sec)
        if stem == "trumpets":
            return trumpets(midi, sec, rip=4.0 if accent else 0.0)  # the accents ripped up into
        if stem == "bones":
            return trombone(midi, sec)
        return bari(midi, sec)

    def lead(stem, bar, notes, gain=1.0, legato=0.85):
        if stem == "trumpets":  # (in unison they're well under their harmonised soli: lift them to the tres)
            gain *= 1.4
        for n in notes:
            tr.add(stem, bar, n.step, sound(stem, n.midi, max(0.03, n.length * tr.step * legato), n.vel >= 1.0), gain * n.vel, PAN[stem])

    def one(stem, bar, step, midi, steps, gain=1.0, legato=0.75):
        tr.add(stem, bar, step, sound(stem, midi, max(0.03, steps * tr.step * legato)), gain * 0.85, PAN[stem])

    def passed(bar, notes, every, order=("tres", "trumpets"), gain=1.0):
        """The potato passed round the band: the tune hops to the next player every `every` steps."""
        for n in notes:
            who = order[int(n.step // every) % len(order)]
            lead(who, bar, [n], gain, legato=0.75 if who == "tres" else 0.8)

    def soli(bar, notes, gain=1.0, shakes=True):
        """The trumpet section on a tune: the lead on top and two more on chord tones under its longer
        notes (unison on the quick ones), ripping up into the accents and shaking the long notes."""
        for n in notes:
            c = chord_at(bar, n.step)
            sec = n.length * tr.step * 0.85
            rip = 4.0 if n.vel >= 1.0 else 0.0
            shake = 2 if shakes and n.length >= 4 else 0
            tr.add("trumpets", bar, n.step, trumpets(n.midi, sec, rip=rip, shake=shake), gain * n.vel, 0.35)
            if n.length >= 2 and n.midi % 12 in c.tones():
                under = [m for m in range(n.midi - 1, n.midi - 10, -1) if m % 12 in c.tones()][:2]
                for k, m in enumerate(under):
                    tr.add("trumpets", bar, n.step, trumpets(m, sec, rip=rip, shake=shake), gain * n.vel * (0.5 - 0.1 * k), 0.25 - 0.1 * k)

    def shake_chord(bar, step, top, width, steps, gain=1.0):
        """The trumpets' screaming shake: the whole section shaking a chord, the lead on `top`."""
        c = chord_at(bar, step)
        under = [m for m in range(top - 1, top - 10, -1) if m % 12 in c.tones()][:2]
        for k, m in enumerate([top] + under):
            tr.add("trumpets", bar, step, trumpets(m, steps * tr.step, shake=width), gain * (1.0, 0.6, 0.5)[k], 0.35 - 0.1 * k)

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

    def pads(bar, gain=0.5):
        """The trombones holding the harmony (one long note per chord)."""
        for _, st, ln, c in [ch for ch in changes if ch[0] == bar]:
            for m in voicing(c, 50, 64, None, 3):
                tr.add("bones", bar, st, trombone(m, ln * tr.step * 0.95), gain * 0.5)

    def run_up(bar):
        """The two bars into the drop (in the intro and again at the end, so the loop is seamless): the
        band in full, the trombones swelling on the F#7, the timer and the fuse hurrying, the trumpets
        shaking, the tres beeping faster and a bongo roll into GO."""
        held[0] = None
        for k in range(2):
            band(bar + k, 0.95)
            guajeo(bar + k, 0.9)
            tumbao(bar + k, 0.95, approach=k == 1)
            ticking(bar + k, 2 if k == 0 else 1, 0.55)
        for m in voicing(chord_at(bar), 50, 64, None, 4):
            tr.add("bones", bar, 0, trombone(m, tr.bar * 1.9, swell=tr.bar * 1.7), 0.42)
        tr.add("fuse", bar, 0, fuse(tr.bar * 2, rise=1.0, seed=1), 0.7)
        shake_chord(bar + 1, 0, 73, 2, 7.5, 0.5)
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
        groove("tongs", bar, CLAVE[bar % 2], 0.45 + 0.08 * (bar - 4))
    for bar in range(6, 10):
        guajeo(bar, 0.45 + 0.12 * (bar - 6))
        groove("sizzle", bar, "x.X.x.X.x.X.x.X.", 0.4 + 0.1 * (bar - 6))
    tumbao(7, 0.7)
    for bar in (8, 9):
        tumbao(bar, 0.85)
        groove("pots", bar, POTS, 0.7 + 0.1 * (bar - 8))
        groove("spatula", bar, CASCARA[bar % 2], 0.6 + 0.1 * (bar - 8))
    lead("tres", 8, potato, 0.7, legato=0.75)
    lead("trumpets", 9, potato_v, 0.5, legato=0.8)
    run_up(10)

    # ------------------------------------------------ A1 (0-10 s after GO): the potato drops, passed every two bars
    a = first["A1"]
    for bar in range(a, a + 8):
        band(bar, 0.9)
        guajeo(bar, 0.85)
        tumbao(bar, 1.0, approach=bar == a + 7)
        ticking(bar, 4, 0.4)
    tr.add("pans", a, 0, lid(1.2), 0.8, 0.3)
    hit(a, 0, chord_at(a), 0.9, 0.2, bass=False)  # GO!
    lead("tres", a, potato, 1.0, legato=0.75)
    lead("tres", a + 1, tumble, 0.95, legato=0.75)
    lead("trumpets", a + 2, potato_v, 0.9, legato=0.8)
    lead("trumpets", a + 3, tumble_v, 0.85, legato=0.8)
    pops_on(a, potato)
    pops_on(a + 2, potato_v)
    soli(a + 4, shift(chorus, -12), 0.85)
    lead("tres", a + 4, tres_chorus, 0.85, legato=0.75)

    # ------------------------------------------------ A2 (10-20 s): passed every bar, the bari honks, then FREEZE... BOOM
    a = first["A2"]
    for bar in range(a, a + 7):
        band(bar, 0.95)
        guajeo(bar, 0.85)
        tumbao(bar, 1.0, honk=True)
        ticking(bar, 2, 0.4)
    for k, (who, notes) in enumerate((("tres", potato), ("trumpets", potato), ("tres", potato_v), ("trumpets", potato_v))):
        lead(who, a + k, notes, 1.0 if who == "tres" else 0.9, legato=0.75 if who == "tres" else 0.8)
        pops_on(a + k, notes)
        stabs(a + k, (12,), 0.7)
    lead("tres", a + 4, chorus2, 0.85, legato=0.75)
    soli(a + 4, shift(chorus2, -12), 0.85)
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
        band(bar, 0.85, grate=None)
        guajeo(bar, 0.9)
        tumbao(bar, 1.0, approach=bar in (b + 3, b + 7))
    soli(b, shift(fiesta, -12), 0.9)
    lead("bones", b + 2, fiesta_answer, 0.9)
    soli(b + 4, shift(fiesta2, -12), 0.9)
    soli(b + 6, shift(fiesta_end, -12), 0.9)
    lead("tres", b + 6, fiesta_end, 0.6, legato=0.75)
    lead("bones", b + 6, shift(fiesta_end, -24), 0.8)
    lead("bari", b + 6, shift(fiesta_end, -36), 0.6)

    # ------------------------------------------------ B2 (30-40 s): trombones and bari sing it, the tres answers, a climb... BOOM
    b = first["B2"]
    for bar in range(b, b + 8):
        band(bar, 0.9, grate=None)
        guajeo(bar, 0.9)
        tumbao(bar, 1.0, approach=bar == b + 3)
        ticking(bar, 4, 0.35)
    lead("bones", b, shift(fiesta, -24), 0.95)
    lead("bari", b, shift(fiesta, -36), 0.8)
    shake_chord(b + 1, 8, 69, 2, 7.5, 0.7)  # the trumpets shake an answer
    lead("tres", b + 2, shift(fiesta_answer, 12), 0.95, legato=0.75)
    pads(b + 2, 0.45)
    pads(b + 3, 0.45)
    soli(b + 4, shift(fiesta2, -12), 0.9)
    lead("tres", b + 4, fiesta2, 0.7, legato=0.75)
    lead("bones", b + 4, shift(fiesta2, -24), 0.75)
    soli(b + 6, shift(fiesta_climb, -12), 0.9)
    lead("tres", b + 6, fiesta_climb, 0.75, legato=0.75)
    stabs(b + 7, (0, 4, 8), 0.8)
    roll(b + 7, 12.0, 0.9)
    tr.add("fuse", b + 7, 0, fuse(tr.bar, rise=1.0, seed=3), 0.7)

    # ------------------------------------------------ the mambo (40-50 s): BOOM, UGH! trombone and bari riffs, screaming trumpets
    m = first["mambo"]
    boom(m, grunt=0)
    tr.add("fx", m, 2, rocket(), 0.8, 0.4)
    for bar in range(m, m + 8):
        band(bar, 1.0, grate="eighths", pots="h.t.S.t.h.tSO.U.")
        guajeo(bar, 1.0)
        tumbao(bar, 1.0, approach=bar in (m + 3, m + 6))
        ticking(bar, 2, 0.4)
    for k, line in enumerate((riff_i, riff_v, riff_i, riff_v, riff_iv, riff_v, riff_i, riff_lift)):  # the last: G7, a half step up into C minor
        lead("bones", m + k, line, 1.0)
        lead("bones", m + k, shift(line, 12), 0.45)
        lead("bari", m + k, shift(line, -12), 0.9)
    shake_chord(m + 2, 0, 78, 3, 7.6, 0.9)
    lead("trumpets", m + 2, melody("r:8 D5:1 C#5:1 B4:1 A#4:1 B4:1 C#5:1 D5:1 E5:1 | C#5:2 A#4:2 F#4:2 A#4:2 C#5:2 E5:2 F#5:4!"), 0.9)
    shake_chord(m + 6, 0, 74, 2, 7.6, 0.9)
    lead("trumpets", m + 6, melody("r:8 D5:1 E5:1 F#5:1 D5:1 B4:1 C#5:1 D5:1 F5:1 | D5:2 B4:2 G4:2 B4:2 D5:4! r:4"), 0.9)
    roll(m + 7, 12.0, 0.9)

    # ------------------------------------------------ A3 (50-60 s): up a half step, passed every half bar... FREEZE... BOOM
    a = first["A3"]
    tr.add("pans", a, 0, lid(1.4), 0.9, 0.3)
    for bar in range(a, a + 7):
        band(bar, 1.0, pots="h.t.S.t.h.tSO.U.")
        guajeo(bar, 0.95)
        tumbao(bar, 1.0, honk=True)
        ticking(bar, 2, 0.45)
    passed(a, shift(potato, 1), 8)
    passed(a + 1, shift(tumble, 1), 8, order=("trumpets", "tres"))
    passed(a + 2, shift(potato_v, 1), 8)
    passed(a + 3, shift(tumble_v, 1), 8, order=("trumpets", "tres"))
    for k, notes in enumerate((shift(potato, 1), shift(tumble, 1), shift(potato_v, 1), shift(tumble_v, 1))):
        pops_on(a + k, notes)
        stabs(a + k, (12,) if k % 2 == 0 else (6,), 0.8)
    lead("tres", a + 4, shift(chorus2, 1), 0.85, legato=0.75)
    soli(a + 4, shift(chorus2, -11), 0.9)
    for bar in range(a + 4, a + 7):
        pads(bar, 0.55)
    freeze = a + 7
    hit(freeze, 0, chord_at(freeze))
    passed(freeze, shift(warning, 1), 2)
    ticking(freeze, 1, 0.6)
    tr.add("fuse", freeze, 2, fuse(tr.step * 14, rise=1.0, seed=4), 0.85)

    # ------------------------------------------------ freeze! (60-70 s): BOOM, stop-time, the potato passed every beat; then the build
    f = first["freeze"]
    boom(f)
    tr.add("fx", f, 3, rocket(), 0.8, -0.3)
    tr.add("fuse", f, 4, fuse(tr.bar * 4 - tr.step * 4, seed=5), 0.6)
    for k in range(4):
        bar = f + k
        c = chord_at(bar)
        for st in (0, 6, 12) if bar % 2 == 0 else (4, 8):  # the band only on the clave
            hit(bar, st, c, 0.85 if st else 1.0, 0.16)
            tr.add("tongs", bar, st, tongs(0), 0.9, 0.1)
        ticking(bar, 2, 0.6)
        top, low = (67, 60) if k < 2 else (72, 65)  # tick-tock: G-C on the C minor, C-F on the F minor
        for beat in range(4):  # left, right, left, right: the tres and the trumpets toss it back and forth
            who = ("tres", "trumpets")[beat % 2]
            one(who, bar, beat * 4, top, 2, 0.95 if who == "tres" else 0.8)
            one(who, bar, beat * 4 + 2, low, 2, 0.85 if who == "tres" else 0.7)
    for k in range(4):  # the build on G#7: the drums back in one by one, the trumpets shaking higher every bar
        bar = f + 4 + k
        band(bar, 0.75 + 0.08 * k, bongos=k >= 1, grate="cascara" if k >= 2 else None)
        guajeo(bar, 0.8 + 0.06 * k)
        tumbao(bar, 1.0, approach=k == 3)
        ticking(bar, 2 if k < 2 else 1, 0.5 + 0.05 * k)
        top, width = ((68, 2), (72, 1), (75, 2), (78, 2))[k]
        shake_chord(bar, 0, top, width, 15.5 if k < 3 else 11.5, (0.6, 0.65, 0.7, 0.7)[k])
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
    boom(g, grunt=1)
    hit(g, 0, chord_at(g), 1.0, 0.25, bass=False)
    for bar in range(g, g + 12):
        band(bar, 1.0, grate="eighths", pots="h.t.S.t.h.tSO.U.")
        guajeo(bar, 1.0)
        tumbao(bar, 1.0, approach=bar in (g + 7, g + 11), honk=bar < g + 8)
        ticking(bar, 2, 0.45)
    # now the potato's a blur: it changes hands every eighth note, with the trombones carrying the line under it
    for k, notes in enumerate((shift(potato, 2), shift(tumble, 2), shift(potato_v, 2), shift(tumble_v, 2))):
        passed(g + k, notes, 2, order=("tres", "trumpets") if k % 2 == 0 else ("trumpets", "tres"))
        lead("bones", g + k, shift(notes, -12), 0.5)
        pops_on(g + k, notes)
        stabs(g + k, (12,) if k % 2 == 0 else (6, 12), 0.85)
    lead("tres", g + 4, shift(tres_chorus, 2), 0.9, legato=0.75)
    soli(g + 4, shift(chorus, -10), 0.95)
    lead("bones", g + 4, shift(chorus, -22), 0.55)
    tr.add("pans", g + 4, 0, lid(1.2), 0.7, 0.3)
    # the moña (80-85 s): BOOM, and riffs piled on riffs
    boom(g + 8)
    twinkle(g + 8, 13)
    for k in (0, 2):
        lead("bones", g + 8 + k, shift(riff, 2), 1.0)
        lead("bones", g + 8 + k, shift(riff, 14), 0.5)
        lead("bari", g + 8 + k, shift(riff, -10), 0.9)
        shake_chord(g + 8 + k, 0, 80 if k == 0 else 76, 3 if k == 0 else 2, 7.6, 0.9)
    lead("trumpets", g + 8, melody("r:8 E5:1 D#5:1 C#5:1 C5:1 C#5:1 D#5:1 E5:1 F#5:1 | D#5:2 C5:2 G#4:2 C5:2 D#5:2 F#5:2 G#5:4!"), 0.9)
    lead("trumpets", g + 10, melody("r:8 E5:1 D#5:1 C#5:1 D#5:1 E5:1 F#5:1 G#5:1 F#5:1 | D#5:2 C5:2 G#4:2 C5:2 D#5:4! r:4"), 0.9)
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
            tr.add("trumpets", bar, st, trumpets(85 if k < 3 else 84, tr.step * every * 0.6), 0.75, 0.35)  # screaming on top
            st += every
        if k < 2:  # the drums keep the groove under the first stabs
            band(bar, 0.75, grate="eighths", pots="h.t.S.t.h.tSO.U.")
        ticking(bar, 1, 0.6)
        groove("tongs", bar, CLAVE[bar % 2], 0.9)
    tr.add("pans", g + 12, 0, lid(1.2), 0.8, 0.3)
    tr.add("fuse", g + 14, 0, fuse(tr.bar * 2, rise=1.0, seed=7), 1.0)

    # ------------------------------------------------ the tag (90 s, the round's end): KABOOM, sky-high, the sad trombones, and round again
    t = first["tag"]
    boom(t, big=True, grunt=2)
    hit(t, 0, chord_at(t), 1.4, 0.9)  # the band holds the last chord under the blast
    tr.add("pots", t, 0, pot("low", 0), 1.0, 0.25)
    tr.add("pans", t, 0.3, lid(1.8), 0.8, -0.4)
    tr.add("fx", t, 2, rocket(1.2), 1.0, 0.3)
    twinkle(t, 14)
    for n in sad:  # wah, wah, wah, waaah: the trombones sliding down in diminished chords, the bari under them
        wob = 1.0 if n.length > 4 else 0.0
        sec = n.length * tr.step * 0.95
        for k, m in enumerate((n.midi, n.midi - 3, n.midi - 6)):
            tr.add("bones", t + 1, n.step, trombone(m, sec, wobble=wob), 0.9 * n.vel * (1.0, 0.7, 0.6)[k], 0.05)
        tr.add("bari", t + 1, n.step, bari(n.midi - 15, sec), 0.7 * n.vel, -0.1)
    for k, mm in enumerate((96, 91, 88, 84, 79)):  # the bits come raining down
        tr.add("pops", t + 1, 1 + k * 2.5, pop(mm), 0.5, (-0.5, 0.4, -0.2, 0.6, 0.0)[k])
    ticking(t + 1, 4, 0.35, start=8)
    run_up(t + 2)

    mix = Mix(buses={
        "tres": Bus(-7, reverb=0.12, delay=0.06),
        "trumpets": Bus(-8, reverb=0.16),
        "bones": Bus(-9, reverb=0.15),
        "bari": Bus(-10, reverb=0.1),
        "guajeo": Bus(-13, reverb=0.1),
        "bass": Bus(-8),
        "pots": Bus(-11, reverb=0.08),
        "bongos": Bus(-13, reverb=0.08),
        "tongs": Bus(-16, reverb=0.1),
        "spatula": Bus(-17, reverb=0.06),
        "sizzle": Bus(-18),
        "pans": Bus(-14, reverb=0.15),
        "timer": Bus(-17),
        "fuse": Bus(-18, eq=(("lp", 9000),)),
        "pops": Bus(-15, reverb=0.12),
        "boom": Bus(-9, reverb=0.2),
        "ugh": Bus(-11, reverb=0.15),
        "fx": Bus(-14, reverb=0.25, delay=0.1),
    }, reverb_decay=1.3, reverb_tone=5000, delay_time=tr.beat * 0.75, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("HotPotato", "Mambo Kaboom", 192, 12, 88, mambo_kaboom)
