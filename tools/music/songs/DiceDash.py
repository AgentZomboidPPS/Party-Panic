"""Lucky Roll Cha-Cha: the round song for DiceDash (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def _sealed(x: np.ndarray) -> np.ndarray:
    x.setflags(write=False)  # cached notes are shared: nobody changes them in place
    return x


def _faded(x, seconds: float = 0.006) -> np.ndarray:
    """A copy of a one-shot whose last few milliseconds fall to silence, so it never ends on a click."""
    x = np.array(x, dtype=float)
    k = min(x.shape[-1], s.samples(seconds))
    x[..., -k:] *= np.linspace(1.0, 0.0, k)
    return x


def _t(n: int) -> np.ndarray:
    return np.arange(n) / s.SR


# ---------------------------------------------------------------- the band

@lru_cache(maxsize=None)
def flute(midi: float, length: float, trill: float = 0.0) -> np.ndarray:
    """A charanga flute: bright and a little breathy, a tongued chiff on every note and a quick
    vibrato on the long ones. `trill` semitones above, it shakes like dice in a cup."""
    n = s.samples(length + 0.12)
    t = _t(n)
    pitch = midi + 0.13 * np.clip((t - 0.16) / 0.2, 0, 1) * np.sin(2 * np.pi * 5.8 * t)
    if trill:
        shake = 0.5 + 0.5 * np.tanh(3.5 * np.sin(2 * np.pi * 7.5 * (t - 0.06) - np.pi / 2))
        pitch = pitch + trill * shake * (t > 0.06)
    phase = 2 * np.pi * np.cumsum(s.midi_hz(pitch)) / s.SR
    tone = np.sin(phase) + 0.34 * np.sin(2 * phase) + 0.13 * np.sin(3 * phase) + 0.05 * np.sin(4 * phase)
    f0 = s.midi_hz(midi)
    air = s.bandpass(np.random.default_rng(int(midi) * 13 + 1).uniform(-1, 1, n), max(500.0, f0 * 1.2), min(10000.0, f0 * 6))
    chiff = np.exp(-t / 0.025)
    e = ins.env(n, 0.02, 0.18, 0.85, 0.07, gate=length)
    x = (tone * (1 + 0.15 * chiff) + air * (0.05 + 0.25 * chiff)) * e
    return _sealed(_faded(ins.normalize(ins.eq(x, ("hp", 200), ("lp", 9000)))))


@lru_cache(maxsize=None)
def piano(midi: float, length: float) -> np.ndarray:
    """A bright parlour grand for the montuno: two strings a hair apart, stretched partials that all
    start together at the hammer's strike and die faster the higher they are, a felt thump, and the
    damper falling as the key comes up."""
    hold = max(0.05, min(length, 2.5))
    n = s.samples(hold + 0.3)
    t = _t(n)
    f0 = s.midi_hz(midi)
    rng = np.random.default_rng(int(midi) * 31 + 5)
    stretch = 0.0001 + 0.0004 * np.clip((midi - 40) / 50, 0, 1)
    tau = 1.8 * (261.6 / f0) ** 0.45
    out = np.zeros(n)
    for cents in (-1.5, 1.5):
        f = f0 * 2 ** (cents / 1200)
        for k in range(1, 28):
            fk = k * f * np.sqrt(1 + stretch * k * k)
            if fk > 9500:
                break
            out += k ** -1.1 * np.exp(-fk / 5000) * np.sin(2 * np.pi * fk * t) * np.exp(-t * (1 + 0.35 * (k - 1)) / tau)
    out *= np.clip(t / 0.0015, 0, 1)
    out /= np.max(np.abs(out)) + 1e-9
    out = out + s.lowpass(rng.uniform(-1, 1, n), 3000) * np.exp(-t / 0.005) * 0.18
    out *= np.where(t < hold, 1.0, np.exp(-(t - hold) / 0.05))
    return _sealed(_faded(ins.normalize(ins.eq(out, ("hp", 60), ("peak", 2500, 2, 1.0), ("lp", 8000)))))


@lru_cache(maxsize=None)
def baby_bass(midi: float, length: float) -> np.ndarray:
    """The Latin band's baby bass (an electric upright): a round, woody thump that rings a little, with
    its octave and twelfth up front so a phone hears every step of the line."""
    n = s.samples(length + 0.1)
    t = _t(n)
    phase = 2 * np.pi * np.cumsum(s.midi_hz(midi) * (1 + 0.01 * np.exp(-t / 0.012))) / s.SR
    tone = (np.sin(phase) + 0.7 * np.exp(-t / 0.5) * np.sin(2 * phase) + 0.5 * np.exp(-t / 0.3) * np.sin(3 * phase)
            + 0.3 * np.exp(-t / 0.2) * np.sin(4 * phase) + 0.15 * np.exp(-t / 0.12) * np.sin(5 * phase)
            + 0.08 * np.exp(-t / 0.08) * np.sin(6 * phase))
    thump = s.bandpass(np.random.default_rng(int(midi) + 900).uniform(-1, 1, n), 100, 900) * np.exp(-t / 0.01) * 0.3
    x = ins.drive((tone + thump) * ins.env(n, 0.004, 0.3, 0.5, 0.06, gate=length), 1.5)
    return _sealed(_faded(ins.normalize(ins.eq(x, ("hp", 40), ("lp", 2500)))))


@lru_cache(maxsize=None)
def trumpet(midi: float, length: float, fall: float = 0.0) -> np.ndarray:
    """The mambo trumpets: bright, three players a hair apart."""
    return ins.brass(midi, length, bright=1.15, section=3, vibrato=0.05, fall=fall)


@lru_cache(maxsize=None)
def trombone(midi: float, length: float) -> np.ndarray:
    """The trombones: warm and round under the tune, sly on the mambo."""
    return ins.brass(midi, length, bright=0.55, section=2, vibrato=0.05)


@lru_cache(maxsize=None)
def wah_bone(midi: float, length: float, last: bool = False) -> np.ndarray:
    """The trombone behind a plunger: every note opens 'wah' and closes again; the last one wobbles
    and sags (the TRAPDOOR's 'wah-wah-wah-waaah')."""
    x = np.asarray(ins.brass(midi, length, bright=0.65, section=2, vibrato=0.45 if last else 0.04, fall=2.5 if last else 0.0))
    t = _t(x.shape[-1])
    opening = np.clip(t / (0.18 if last else 0.1), 0, 1) * np.clip((length + 0.05 - t) / 0.12, 0.15, 1)
    return _sealed(_faded(ins.normalize(ins.tv_lowpass(x, 300 + 2300 * opening, q=3.0)), 0.02))


# ---------------------------------------------------------------- the percussion

@lru_cache(maxsize=None)
def dice_cup(accent: float = 1.0, variant: int = 0) -> np.ndarray:
    """Two dice shaken in a leather cup: they smack the wall in a burst of hard little clicks over the
    cup's hollow ring, then rattle back."""
    n = s.samples(0.15)
    rng = np.random.default_rng(500 + 17 * variant + int(round(accent * 10)))
    out = np.zeros(n)
    m = s.samples(0.006)
    tt = _t(m)
    for when, size in ((0.0, 1.0), (0.05, 0.4)):
        for _ in range(int((8 + 10 * accent) * size)):
            start = when + rng.exponential(0.007)
            i = s.samples(start)
            if i + m >= n:
                continue
            tick = np.sin(2 * np.pi * rng.uniform(2800, 8000) * tt + rng.uniform(0, 6.3)) * np.exp(-tt / rng.uniform(0.0004, 0.0011))
            grit = rng.uniform(-1, 1, m) * np.exp(-tt / 0.00025)
            out[i:i + m] += (tick + 0.6 * grit) * rng.uniform(0.35, 1.0) * size * np.exp(-(start - when) / 0.02)
    cup = ins.formant(out, [(900, 9, 2.0), (2200, 5, 3.0)])
    return _sealed(_faded(ins.normalize(ins.eq(cup, ("hp", 500), ("lp", 11000)))))


@lru_cache(maxsize=None)
def dice_throw(variant: int = 0) -> np.ndarray:
    """Two giant dice thrown onto the board: a clack as each lands, bounces that come quicker and
    smaller, and a rocking settle on an edge."""
    n = s.samples(0.9)
    rng = np.random.default_rng(600 + variant)
    out = np.zeros(n)
    m = s.samples(0.05)
    tt = _t(m)

    def impact(when, amp, bright):
        i = s.samples(when)
        if i + m >= n:
            return
        click = np.sin(2 * np.pi * rng.uniform(3000, 5200) * tt) * np.exp(-tt / 0.0008)
        grit = rng.uniform(-1, 1, m) * np.exp(-tt / 0.0003)
        knock = np.sin(2 * np.pi * rng.uniform(1050, 1650) * tt) * np.exp(-tt / 0.007)
        thud = np.sin(2 * np.pi * rng.uniform(170, 230) * tt) * np.exp(-tt / 0.018)
        out[i:i + m] += amp * (bright * (click + 0.5 * grit) + 0.6 * knock + 0.5 * amp * thud)

    for die in range(2):
        when, gap, amp = die * rng.uniform(0.02, 0.04), 0.13, 1.0 - 0.15 * die
        while gap > 0.014 and when < 0.7:
            impact(when, amp, 1.0)
            when += gap * rng.uniform(0.9, 1.1)
            gap *= 0.7
            amp *= 0.68
        for k in range(2):
            impact(when + 0.025 * k, amp * 0.8, 0.5)
    return _sealed(_faded(ins.normalize(ins.eq(out, ("hp", 120), ("lp", 9500))), 0.02))


@lru_cache(maxsize=None)
def guiro(length: float, variant: int = 0) -> np.ndarray:
    """A güiro: a stick scraped along the gourd's ridges, a buzzy 'rrrip' that speeds up through the
    stroke (a long scrape on the beat, short ones between)."""
    n = s.samples(length + 0.04)
    t = _t(n)
    rng = np.random.default_rng(300 + variant + int(length * 1000))
    stroke = np.clip(t / length, 0, 1)
    rate = (175.0 if length < 0.15 else 135.0) * (0.55 + 0.45 * np.sin(np.pi * stroke))
    ridges = np.nonzero(np.diff(np.floor(np.cumsum(rate) / s.SR)) > 0)[0] + 1
    ridges = ridges[t[ridges] < length]
    k = s.samples(0.002)
    burst = np.sin(np.pi * np.arange(k) / k) * np.exp(-np.arange(k) / (k / 3))
    shape = np.sin(np.pi * stroke) ** 0.35
    out = np.zeros(n)
    for i in ridges:
        j = min(k, n - i)
        out[i:i + j] += rng.uniform(-1, 1, j) * burst[:j] * shape[i] * rng.uniform(0.7, 1.0)
    out = ins.formant(out, [(1300, 5, 2.0), (2700, 8, 2.5), (4300, 4, 3.0)])
    return _sealed(_faded(ins.normalize(ins.eq(out, ("hp", 900), ("lp", 8000), ("lp", 9000)))))


_STROKES = {"open": 0, "rim": 1, "ghost": 2, "shell": 3}
# The drums are tuned to notes that sit well in all three of the song's keys (E flat, C minor, F):
MACHO, HEMBRA = 392.0, 261.6  # the small and the big timbal, G4 and C4


@lru_cache(maxsize=None)
def timbal(pitch: float = HEMBRA, kind: str = "open", variant: int = 0) -> np.ndarray:
    """Timbales, the Latin band's shallow steel drums: 'open' rings, 'rim' cracks (a rimshot), 'ghost'
    is a soft tap and 'shell' the stick on the metal shell (the cascara)."""
    n = s.samples(0.12 if kind == "shell" else 0.7)
    t = _t(n)
    noise_ = np.random.default_rng(700 + int(pitch) + 31 * _STROKES[kind] + 7 * variant).uniform(-1, 1, n)
    if kind == "shell":
        ring = np.sin(2 * np.pi * 2140 * t) + 0.6 * np.sin(2 * np.pi * 3070 * t) + 0.3 * np.sin(2 * np.pi * 4460 * t)
        x = s.bandpass(noise_, 2000, 7500) * np.exp(-t / 0.003) + 0.35 * ring * np.exp(-t / 0.022) + 0.12 * np.sin(2 * np.pi * pitch * t) * np.exp(-t / 0.03)
    else:
        f = pitch * (1 + 0.05 * np.exp(-t / 0.01))
        decay = 0.06 if kind == "ghost" else 0.2
        head = (s.sine(f, n) * np.exp(-t / decay) + 0.45 * s.sine(f * 1.59, n) * np.exp(-t / (decay * 0.5))
                + 0.3 * s.sine(f * 2.28, n) * np.exp(-t / (decay * 0.35)) + 0.2 * s.sine(f * 2.92, n) * np.exp(-t / (decay * 0.25)))
        shell = (np.sin(2 * np.pi * 1830 * t) + 0.7 * np.sin(2 * np.pi * 2460 * t) + 0.5 * np.sin(2 * np.pi * 3390 * t)
                 + 0.3 * np.sin(2 * np.pi * 4710 * t)) * np.exp(-t / (0.035 if kind == "ghost" else 0.15))
        x = head + 0.45 * shell + 0.6 * s.bandpass(noise_, 1500, 8000) * np.exp(-t / 0.003)
        if kind == "rim":
            x = x + 1.1 * s.bandpass(noise_, 900, 6000) * np.exp(-t / 0.008) + 0.25 * shell
    return _sealed(_faded(ins.normalize(ins.eq(x, ("hp", 150), ("lp", 10000))), 0.01))


@lru_cache(maxsize=None)
def bell(open_: bool = True) -> np.ndarray:
    """The cha-cha bell on the timbales: struck on its mouth it rings, near the handle it clucks."""
    n = s.samples(0.4 if open_ else 0.14)
    t = _t(n)
    tone = s.square(np.full(n, 523.3), n, 0.5) + 0.75 * s.square(np.full(n, 784.0), n, 0.5)  # C5 and G5
    tone = s.bandpass(tone, 520, 3600) * np.exp(-t / (0.1 if open_ else 0.028))
    stick = s.bandpass(np.random.default_rng(66 + open_).uniform(-1, 1, n), 2000, 6000) * np.exp(-t / 0.002)
    return _sealed(_faded(ins.normalize(tone + 0.5 * stick)))


@lru_cache(maxsize=None)
def conga(stroke: str) -> np.ndarray:
    """Conga and tumba: the slap on 2, the open tones on 4 and its 'and', and muffled heel-toe ghosts."""
    if stroke == "slap":
        x = ins.conga(233.1, slap=True)  # tuned to B flat 3 ...
    elif stroke == "open":
        x = ins.conga(233.1)
    elif stroke == "tumba":
        x = ins.conga(174.6)  # ... and F3
    else:
        x = ins.eq(np.asarray(ins.conga(233.1)), ("lp", 900))
    return _sealed(_faded(x, 0.02))


@lru_cache(maxsize=None)
def bombo() -> np.ndarray:
    """A soft bass drum under the band, round at 64 Hz and up, where a phone can still play it."""
    n = s.samples(0.32)
    t = _t(n)
    body = s.sine(65.4 + 80 * np.exp(-t / 0.02), n) * np.exp(-t / 0.12)  # settles on C2
    beater = s.bandpass(np.random.default_rng(41).uniform(-1, 1, n), 700, 3500) * np.exp(-t / 0.003) * 0.25
    return _sealed(_faded(ins.normalize(ins.drive(body + beater, 1.5)), 0.02))


@lru_cache(maxsize=None)
def clave() -> np.ndarray:
    return _sealed(_faded(ins.woodblock(2093.0, 0.1)))  # C7


@lru_cache(maxsize=None)
def crash(length: float = 1.8) -> np.ndarray:
    n = s.samples(length)
    t = _t(n)
    metal = sum(s.square(np.full(n, f), n) for f in (3150.0, 4230.0, 5370.0, 6810.0)) / 4
    x = ins.eq(np.random.default_rng(950).uniform(-1, 1, n) * 0.7 + metal * 0.3, ("hp", 4000), ("lp", 12000))
    return _sealed(_faded(ins.normalize(x * np.exp(-t / 0.55) * np.clip(t / 0.001, 0, 1)), 0.05))


@lru_cache(maxsize=None)
def splash() -> np.ndarray:
    return _sealed(_faded(ins.splash(0.9), 0.05))


@lru_cache(maxsize=None)
def vibraslap() -> np.ndarray:
    """A vibraslap: a ball knocks a wooden box of loose metal teeth into a cheeky rattle that runs down."""
    n = s.samples(0.95)
    rng = np.random.default_rng(801)
    out = np.zeros(n)
    m = s.samples(0.006)
    tt = _t(m)
    when, rate = 0.0, 31.0
    while when < 0.85:
        i = s.samples(when)
        tick = rng.uniform(-1, 1, m) * np.exp(-tt / 0.0012) + 0.6 * np.sin(2 * np.pi * rng.uniform(2200, 2600) * tt) * np.exp(-tt / 0.003)
        out[i:i + m] += tick * np.exp(-when / 0.24) * rng.uniform(0.7, 1.0)
        when += 1 / rate
        rate *= 0.988
    box = ins.formant(out, [(430, 7, 2.0), (1500, 4, 2.5), (2400, 6, 3.0)])
    return _sealed(_faded(ins.normalize(ins.eq(box, ("hp", 250), ("lp", 9000))), 0.02))


@lru_cache(maxsize=None)
def boing(midi: float = 60.0, length: float = 0.75) -> np.ndarray:
    """The BOOST springboard: a big coil spring going 'boi-yoi-yoing' as it flings you up the board."""
    n = s.samples(length)
    t = _t(n)
    pitch = midi + 7 * np.clip(t / length, 0, 1) ** 1.6 + 1.8 * np.exp(-t / 0.2) * np.sin(2 * np.pi * 15 * t)
    phase = 2 * np.pi * np.cumsum(s.midi_hz(pitch)) / s.SR
    tone = (np.sin(phase) + 0.45 * np.sin(2 * phase) + 0.2 * np.sin(3 * phase)) * np.clip(t / 0.003, 0, 1) * np.exp(-t / (length * 0.4))
    twang = s.bandpass(np.random.default_rng(77).uniform(-1, 1, n), 1500, 5000) * np.exp(-t / 0.006)
    return _sealed(_faded(ins.normalize(ins.eq(tone + 0.5 * twang, ("hp", 150), ("lp", 6000))), 0.02))


# ---------------------------------------------------------------- the song

A_THEME = [
    "G5:3 Gb5:1 G5:2 Bb5:2 Eb6:4! D6:2 C6:2",
    "Bb5:4 r:2 G5:2 E5:4 r:4",
    "Ab5:3 G5:1 Ab5:2 C6:2 F6:4! Eb6:2 D6:2",
    "C6:4 r:2 Ab5:2 F5:4 r:4",
    "G5:3 Gb5:1 G5:2 Bb5:2 Eb6:4! F6:2 F#6:2",
    "G6:2! E6:2 C6:2 Bb5:2 G5:2 E5:2 C5:2 E5:2",
    "F5:2 Ab5:2 C6:2 F6:2 D6:2 C6:2 Bb5:2 Ab5:2",
]


def lucky_roll():
    """Lucky Roll Cha-Cha (128 bpm, E flat major): a casino cha-cha-cha for the giant board game. A
    charanga flute hops and tumbles through the tune and trills like dice rattling in a cup, over a
    piano montuno, a baby bass that steps 'cha-cha' into every chord and mambo trumpets answering
    'cha-cha-CHA'; the dice cup shakes along with the guiro, the cha-cha bell, congas, claves and
    timbales. The intro shakes the dice and rolls the timbales into GO, where the dice land. The tune
    comes round twice (0-30 s after GO), then a sly trombone takes a minor mambo (30-45 s) where the
    flute and trombone SWAP places, a TRAPDOOR goes 'wah-wah-wah-waaah' and it's back to the start of
    the roll, until a springboard BOOSTs the band up to F major for the home stretch (45-60 s). Its
    last 'cha-cha-CHA' lands the big finish on the round's 60 s, and a turnaround steps back down
    into the drop for the loop."""
    tr = Track(bpm=128, bars=41)
    parts = plan(tr, [
        ("intro", 7, "Eb | Eb | Ab | Bb7 | Eb | C7 | Fm7 Bb7"),
        ("A1", 8, "Eb | C7 | Fm7 | Bb7 | Eb | C7 | Fm7 Bb7 | Eb"),
        ("A2", 8, "Eb | C7 | Fm7 | Bb7 | Eb | C7 | Fm7 Bb7 | Eb G7b9"),
        ("B", 8, "Cm7 | F7 | Cm7 | F7 | Ab7 | G7 | Cm7 | C7"),
        ("finale", 8, "F | D7 | Gm7 | C7 | F | D7 | Gm7 C7 | C7"),
        ("tag", 2, "F6 | Fm7 Bb7"),
    ])
    first = {p.name: p.first for p in parts}
    flat = [(p, change) for p in parts for change in p.changes]
    drop_chord = parts[1].changes[0][3]

    def lead(stem, bar, notes, voice, gain=1.0, legato=0.85, pan=0.0, trills=None):
        """Plays notes; `trills` maps (bar offset, step) to a trill interval (flute only)."""
        for n in notes:
            sec = round(max(0.05, n.length * tr.step * legato), 3)
            key = (int(n.step // 16), n.step % 16)
            if trills is not None:
                sound = voice(n.midi, sec, trills.get(key, 0.0))
            else:
                sound = voice(n.midi, sec)
            tr.add(stem, bar, n.step, sound, gain * n.vel, pan)

    def hit(stem, bar, step, notes, steps, voice, gain, pan=0.0):
        sec = round(steps * tr.step, 3)
        for m in notes:
            tr.add(stem, bar, step, voice(m, sec), gain / len(notes) ** 0.5, pan)

    def hits(stem, bar, pattern, kit, gain=1.0, pan=0.0):
        """A 16-step pattern; each character plays its (sound or variants, velocity) from `kit`."""
        assert len(pattern) == 16, pattern
        used = 0
        for step, ch in enumerate(pattern):
            if ch in kit:
                sounds, vel = kit[ch]
                tr.add(stem, bar, step, sounds[used % len(sounds)] if isinstance(sounds, list) else sounds, gain * vel, pan)
                used += 1

    dice = {"X": ([dice_cup(1.0, v) for v in range(3)], 1.0), "x": ([dice_cup(0.6, v) for v in range(3)], 0.7),
            "o": ([dice_cup(0.35, v) for v in range(3)], 0.45)}
    scrape = {"L": ([guiro(0.26, v) for v in range(2)], 1.0), "s": ([guiro(0.085, v) for v in range(3)], 0.75)}
    bells = {"X": (bell(True), 1.0), "x": (bell(False), 0.7)}
    congas = {"g": (conga("ghost"), 0.3), "S": (conga("slap"), 0.9), "O": (conga("open"), 0.85), "T": (conga("tumba"), 0.9)}
    kick = {"X": (bombo(), 1.0), "x": (bombo(), 0.7)}
    claves = {"x": (clave(), 1.0)}
    shells = {"x": ([timbal(MACHO, "shell", v) for v in range(2)], 0.7), "X": ([timbal(MACHO, "shell", 2)], 1.0)}

    def son_clave(bar, gain):
        hits("clave", bar, "....x...x......." if bar % 2 else "x.....x.....x...", claves, gain, 0.5)

    def roll(bar, start, end, g0, g1, pitch=HEMBRA):
        """A timbale roll in 32nds, swelling: the game show's drumroll, Latin style."""
        k, i = start, 0
        while k < end - 1e-6:
            frac = (k - start) / max(end - start, 1e-6)
            tr.add("timbal", bar, k, timbal(pitch, "open", i % 4), g0 + (g1 - g0) * frac ** 1.3, -0.1)
            k += 0.5
            i += 1

    def abanico(bar, step=12.0, gain=1.0):
        """The timbalero's fill into a new section: a rimshot, a quick roll and the big drum."""
        tr.add("timbal", bar, step, timbal(MACHO, "rim", 0), gain, -0.1)
        for k, (dt, kind, p) in enumerate(((1.0, "ghost", MACHO), (1.5, "ghost", MACHO), (2.0, "open", HEMBRA), (2.5, "ghost", HEMBRA), (3.0, "open", HEMBRA))):
            tr.add("timbal", bar, step + dt, timbal(p, kind, k), gain * (0.5 + 0.1 * k), -0.1)

    def cha_bass(bar, step, length, c, nxt, gain, hop=False):
        """Root, fifth, root, then two steps 'cha-cha' into the next chord's root."""
        root, target = bass_note(c, 36), bass_note(nxt, 36)
        fifth = root + 7 if root + 7 <= 50 else root - 5
        a1, a2 = (target - 2, target - 1) if target > root else (target + 2, target + 1)
        if length >= 16:
            line = [(0, root, 3, 1.0), (6, fifth, 2, 0.8), (8, root, 3, 0.9), (12, a1, 1.5, 0.75), (14, a2, 1.5, 0.85)]
            if hop:  # a hop up the octave and back
                line[2:3] = [(8, root, 2, 0.9), (10, root + 12, 1.5, 0.7)]
        else:
            line = [(0, root, 3, 1.0), (4, a1, 1.5, 0.75), (6, a2, 1.5, 0.85)]
        for k, m, ln, g in line:
            tr.add("bass", bar, step + k, baby_bass(m, round(ln * tr.step * 0.92, 3)), gain * g)

    def bass_line(bar, line, gain):
        for k, m, ln, g in line:
            tr.add("bass", bar, k, baby_bass(m, round(ln * tr.step * 0.92, 3)), gain * g)

    def montuno(bar, step, length, notes, nxt_notes, gain, style="cha", bright=False):
        """The piano's montuno: broken chords in eighths, the top note on a 3-3-2 lilt, and the last
        eighth anticipating the next chord."""
        top, low, mid = notes[-1], notes[:2], notes[1:3]
        if style == "mambo":
            plan_ = [(0, [top], 1.0), (3, low, 0.7), (6, [top], 0.9), (8, mid, 0.7), (11, [top], 0.9), (14, nxt_notes[:2], 0.8)]
        elif length >= 16:
            plan_ = [(0, [top], 1.0), (2, low, 0.6), (4, mid, 0.7), (6, [top], 0.9), (8, low, 0.6), (10, mid, 0.7), (12, [top], 0.95), (14, nxt_notes[1:3], 0.75)]
        else:
            plan_ = [(0, [top], 1.0), (2, low, 0.65), (4, [top], 0.85), (6, nxt_notes[1:3], 0.75)]
        for k, ns, g in plan_:
            if bright and len(ns) == 1:
                ns = ns + [ns[0] + 12]
            for m in ns:
                tr.add("piano", bar, step + k, piano(m, 0.16), gain * g / len(ns) ** 0.5, -0.3)

    def stab_voicing(c, low=62, high=74):
        return voicing(c, low, high, size=3)

    def hop_up(c, nxt, low=72):
        """A xylophone's 'hop, hop, HOP': two of this chord's tones a leap apart, then the next
        chord's tone higher still."""
        a = next(m for m in range(low, low + 12) if m % 12 in c.tones())
        b = next(m for m in range(a + 3, a + 15) if m % 12 in c.tones())
        return [a, b, next(m for m in range(b + 3, b + 15) if m % 12 in nxt.tones())]

    def cha_cha_cha(stem, bar, c, nxt, voice, gain, low=62, high=74, fall=False):
        """The band's answer on 4, its 'and' and the next 1: 'cha-cha-CHA!'."""
        here, there = stab_voicing(c, low, high), stab_voicing(nxt, low, high)
        hit(stem, bar, 12, here, 1.4, voice, gain * 0.8)
        hit(stem, bar, 14, here, 1.4, voice, gain * 0.85)
        if fall:
            for m in there:
                tr.add(stem, bar + 1, 0, trumpet(m, round(2.5 * tr.step, 3), 1.5), gain / len(there) ** 0.5)
        else:
            hit(stem, bar + 1, 0, there, 2.5, voice, gain)

    # ------------------------------------------------ chords: bass, piano, brass pads
    prev = None
    for index, (part, (bar, step, length, c)) in enumerate(flat):
        name, local = part.name, bar - part.first
        nxt = flat[index + 1][1][3] if index + 1 < len(flat) else drop_chord
        notes = voicing(c, 55, 68, prev)
        prev = notes
        nxt_notes = voicing(nxt, 55, 68, notes)
        pad = voicing(c, 50, 63, size=3)
        if name == "intro":
            if local >= 2:
                cha_bass(bar, step, length, c, nxt, 0.45 + 0.1 * (local - 2))
            montuno(bar, step, length, notes, nxt_notes, 0.3 + 0.08 * local)
            if local == 4:  # the trombones swell in
                for m in pad:
                    x = np.array(trombone(m, round(15 * tr.step, 3)))
                    x *= np.clip(_t(x.shape[-1]) / 1.4, 0, 1) ** 1.5
                    tr.add("bone", bar, 0, _sealed(x), 0.5 / 3 ** 0.5, -0.25)
            if local == 5:
                hit("bone", bar, 0, pad, 3, trombone, 0.45, -0.25)
                hit("bone", bar, 8, pad, 6, trombone, 0.5, -0.25)
        elif name in ("A1", "A2"):
            cha_bass(bar, step, length, c, nxt, 1.0, hop=name == "A2")
            montuno(bar, step, length, notes, nxt_notes, 0.85)
            if 4 <= local <= 6:  # the trombones hold the chords under the tune's second half
                hit("bone", bar, step, pad, length * 0.92, trombone, 0.42, -0.25)
        elif name == "B":
            if local < 4:  # the tumbao: the fifth on 2-and, the next root pushed early on 4
                root, fifth, target = bass_note(c, 36), bass_note(c, 36) + 7, bass_note(nxt, 36)
                line = [(6, fifth, 5, 0.85), (12, target, 4, 1.0)]
                if local == 0:
                    line.insert(0, (0, root, 2, 0.9))
                bass_line(bar, line, 1.0)
                montuno(bar, step, length, notes, nxt_notes, 0.85, style="mambo")
            elif local == 4:
                cha_bass(bar, step, length, c, nxt, 1.0)
                montuno(bar, step, length, notes, nxt_notes, 0.7, style="mambo")
            elif local == 5:  # the trapdoor: the band holds its breath
                bass_line(bar, [(0, bass_note(c, 36), 6, 1.0)], 1.0)
                hit("piano", bar, 0, notes, 3, piano, 0.75, -0.3)
            elif local == 6:  # back to START: the roll begins again
                cha_bass(bar, step, length, c, nxt, 0.95)
                montuno(bar, step, length, notes, nxt_notes, 0.8)
            else:  # BOOST: the bass climbs into F
                bass_line(bar, [(0, 36, 2, 1.0), (4, 40, 2, 0.8), (8, 43, 2, 0.85), (12, 39, 1.5, 0.8), (14, 40, 1.5, 0.9)], 1.0)
                hit("piano", bar, 0, notes, 2, piano, 0.8, -0.3)
        elif name == "finale":
            if local < 7:
                cha_bass(bar, step, length, c, nxt, 1.0, hop=True)
                montuno(bar, step, length, notes, nxt_notes, 0.9, bright=True)
                hit("bone", bar, step, pad, length * 0.92, trombone, 0.4, -0.25)
            else:  # the stop before the finish: one hit, a drumroll, then everyone climbs
                bass_line(bar, [(0, 36, 2, 1.0), (8, 36, 1.5, 0.8), (10, 38, 1.5, 0.8), (12, 39, 1.5, 0.85), (14, 40, 1.5, 0.95)], 1.0)
                hit("piano", bar, 0, notes, 2, piano, 0.9, -0.3)
        elif name == "tag":
            if local == 0:  # the big finish
                bass_line(bar, [(0, 41, 10, 1.0)], 1.0)
                hit("piano", bar, 0, [53, 57, 60, 62, 65], 8, piano, 1.0, -0.3)
            else:  # and the turnaround that steps back down into the drop
                cha_bass(bar, step, length, c, nxt, 0.9)
                montuno(bar, step, length, notes, nxt_notes, 0.8)
                hit("bone", bar, step, pad, length * 0.7, trombone, 0.4, -0.25)

    # ------------------------------------------------ percussion, bar by bar
    for part in parts:
        name = part.name
        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local < 6:
                    hits("dice", bar, "x.o.x.o.x.o.x.oo" if local < 2 else "X.x.X.x.X.x.X.xx", dice, 0.35 + 0.08 * local, 0.25)
                else:  # the dice shake harder and harder
                    for k in range(16):
                        tr.add("dice", bar, k, dice_cup(0.6 + 0.4 * (k % 2 == 0), k % 3), 0.45 + 0.5 * k / 15, 0.25)
                if local >= 1:
                    hits("guiro", bar, "L...s.s.L...s.s.", scrape, 0.45 + 0.08 * local, -0.45)
                    son_clave(bar, 0.5 + 0.06 * local)
                if local >= 2:
                    hits("conga", bar, "g.g.S.g.g.g.O.T.", congas, 0.5 + 0.08 * local, 0.35)
                if local >= 4:
                    hits("bell", bar, "X...x...X...x...", bells, 0.5 + 0.12 * (local - 4), -0.2)
                if local == 5:
                    hits("timbal", bar, "x.xx.x.xx.x.xx.x", shells, 0.5, -0.1)
                if local >= 5:
                    hits("kick", bar, "X.......X.......", kick, 0.55 + 0.2 * (local - 5))
                if local == 6:
                    roll(bar, 0, 16, 0.12, 0.85)
                continue
            if name in ("A1", "A2"):
                second = name == "A2"
                hits("dice", bar, "X.xxX.x.X.xxX.xx" if second else "X.x.X.x.X.x.X.xx", dice, 0.85, 0.25)
                hits("guiro", bar, "L...s.s.L...s.s.", scrape, 0.8, -0.45)
                hits("bell", bar, "X...x...X...x.x." if second else "X...x...X...x...", bells, 0.85, -0.2)
                hits("conga", bar, "g.g.S.gOg.g.O.T." if second and local % 2 else "g.g.S.g.g.g.O.T.", congas, 0.9, 0.35)
                hits("kick", bar, "X.......X.......", kick, 1.0)
                if second:
                    son_clave(bar, 0.8)
                if local == 7:
                    abanico(bar, 12.0, 0.8)
                continue
            if name == "B":
                if local < 5:
                    hits("dice", bar, "x.x.x.x.x.x.x.x.", dice, 0.7, 0.25)
                    hits("guiro", bar, "s.s.s.s.s.s.s.s.", scrape, 0.75, -0.45)
                    hits("bell", bar, "X.x.X.xxX.x.X.x." if local % 2 else "X.x.X.x.X.x.X.x.", bells, 0.8, -0.2)
                    hits("conga", bar, "gOg.S.gOg.g.O.T.", congas, 0.9, 0.35)
                    hits("kick", bar, "X.....x.X.......", kick, 1.0)
                elif local == 5:  # TRAPDOOR: the band tiptoes under the trombone
                    hits("dice", bar, "o.o.o.o.o.o.o.o.", dice, 0.6, 0.25)
                    hits("bell", bar, "x...x...x...x...", bells, 0.5, -0.2)
                    hits("conga", bar, "g.g.g.g.g.g.g.g.", congas, 1.0, 0.35)
                    hits("kick", bar, "X.......X.......", kick, 0.8)
                elif local == 6:  # back to START: the dice shake again
                    hits("dice", bar, "X.x.X.x.X.xxXxxx", dice, 0.8, 0.25)
                    hits("guiro", bar, "L...s.s.L...s.s.", scrape, 0.8, -0.45)
                    hits("bell", bar, "X...x...X...x...", bells, 0.8, -0.2)
                    hits("conga", bar, "g.g.S.g.g.g.O.T.", congas, 0.9, 0.35)
                    hits("kick", bar, "X.......X.......", kick, 0.95)
                    roll(bar, 8, 16, 0.15, 0.45)
                else:
                    for k in range(16):
                        tr.add("dice", bar, k, dice_cup(0.6 + 0.4 * (k % 2 == 0), k % 3), 0.5 + 0.45 * k / 15, 0.25)
                    hits("conga", bar, "g.g.S.g.g.g.O.T.", congas, 0.85, 0.35)
                    hits("kick", bar, "X...X...X...X...", kick, 0.9)
                    roll(bar, 0, 12, 0.35, 0.9)
                    tr.add("timbal", bar, 12, timbal(MACHO, "rim", 1), 0.9, -0.1)
                    tr.add("timbal", bar, 14, timbal(MACHO, "rim", 2), 1.0, -0.1)
                continue
            if name == "finale":
                if local < 7:
                    hits("dice", bar, "XxxxXxxxXxxxXxxx", dice, 0.8, 0.25)
                    hits("guiro", bar, "L...s.s.L...s.s.", scrape, 0.85, -0.45)
                    hits("bell", bar, "X...x.x.X...x.x.", bells, 0.9, -0.2)
                    hits("conga", bar, "g.g.S.gOg.g.O.TT", congas, 0.95, 0.35)
                    hits("kick", bar, "X.....x.X.....x.", kick, 1.0)
                    son_clave(bar, 0.85)
                    if local == 3:
                        abanico(bar, 12.0, 0.7)
                else:
                    for k in range(16):
                        tr.add("dice", bar, k, dice_cup(0.6 + 0.4 * (k % 2 == 0), k % 3), 0.55 + 0.45 * k / 15, 0.25)
                    hits("kick", bar, "X...........X.X.", kick, 1.0)
                    roll(bar, 1, 12, 0.3, 0.85)
                    tr.add("timbal", bar, 12, timbal(MACHO, "rim", 1), 0.9, -0.1)
                    tr.add("timbal", bar, 14, timbal(MACHO, "rim", 2), 1.0, -0.1)
                continue
            if name == "tag":
                if local == 0:
                    hits("kick", bar, "X...............", kick, 1.0)
                    tr.add("timbal", bar, 0, timbal(MACHO, "rim", 3), 1.0, -0.1)
                    tr.add("timbal", bar, 0, timbal(HEMBRA, "open", 1), 0.7, -0.1)
                else:  # its fill is all quick, muffled strokes: nothing rings on past the end of the loop
                    hits("dice", bar, "x.x.x.x.x.xxxxxx", dice, 0.8, 0.25)
                    hits("guiro", bar, "L...s.s.L...s.s.", scrape, 0.8, -0.45)
                    hits("bell", bar, "X...x...X...x...", bells, 0.8, -0.2)
                    hits("conga", bar, "g.g.S.g.g.g.O...", congas, 0.9, 0.35)
                    hits("kick", bar, "X.......X.......", kick, 0.9)
                    tr.add("timbal", bar, 12, timbal(MACHO, "rim", 0), 0.8, -0.1)
                    for k, dt in enumerate((1.0, 1.5, 2.0, 2.5, 3.0, 3.5)):
                        tr.add("timbal", bar, 12 + dt, timbal(MACHO if k < 3 else HEMBRA, "ghost", k), 0.45 + 0.08 * k, -0.1)

    # ------------------------------------------------ the tunes
    a1 = melody(" | ".join(A_THEME + ["G5:4 r:6 Eb5:2 F5:2 F#5:2"]))
    a2 = melody(" | ".join(A_THEME + ["G5:4 r:4 B5:2 D6:2 F6:2 Ab6:2"]))
    up = shift(melody(" | ".join(A_THEME)), 2)  # the home stretch, a step up in F
    run = melody("Bb5:8 C6:1 D6:1 E6:1 F6:1 G6:2 G#6:2 | A6:8! r:8")

    # the intro: the flute rattles the dice, hops up, and trills through the drumroll
    lead("flute", 3, melody("Bb5:6 Ab5:1 G5:1 F5:1 D5:1 r:2 Bb5:2 r:2"), flute, 0.7, trills={(0, 0): 2.0})
    lead("flute", 5, melody("r:8 E5:2 G5:2 Bb5:2 C6:2"), flute, 0.75)
    lead("xylo", 5, melody("r:8 E6:2 G6:2 Bb6:2 C7:2"), lambda m, sec: ins.xylophone(m, 0.15), 0.6, pan=0.3)
    lead("flute", 6, melody("C6:12 r:4"), flute, 0.8, trills={(0, 0): 2.0})
    # the band rips up into GO, where the dice land
    for k, (bone_note, trumpet_note) in enumerate(((46, 58), (50, 62), (53, 65), (56, 68))):
        tr.add("bone", 6, 12 + k, trombone(bone_note, round(tr.step, 3)), 0.45 + 0.08 * k, -0.25)
        tr.add("trumpet", 6, 12 + k, trumpet(trumpet_note, round(tr.step, 3)), 0.45 + 0.08 * k, 0.2)

    # A1: the tune, the trumpets answering 'cha-cha-CHA'
    A1, A2, B, F = first["A1"], first["A2"], first["B"], first["finale"]
    lead("flute", A1, a1, flute)
    hit("trumpet", A1, 0, [63, 67, 70], 3, trumpet, 1.0, 0.2)
    hit("bone", A1, 0, [51, 55, 58], 3, trombone, 0.8, -0.25)
    for local in (1, 3):
        bar = A1 + local
        c, nxt = parts[1].changes[local][3], parts[1].changes[local + 1][3]
        cha_cha_cha("trumpet", bar, c, nxt, trumpet, 1.25, fall=local == 3)
    hit("trumpet", A1 + 7, 4, [63, 67, 70], 2, trumpet, 0.8, 0.2)
    hit("bone", A1 + 7, 8, voicing(chords("Eb")[0][2], 50, 63, size=3), 2, trombone, 0.6, -0.25)
    hit("bone", A1 + 7, 12, voicing(chords("Bb7")[0][2], 50, 63, size=3), 2, trombone, 0.65, -0.25)

    # A2: the trumpets double the tune an octave down; the trombones and a xylophone answer
    lead("flute", A2, a2, flute, trills={(1, 0): 2.0, (3, 0): 2.0})
    lead("trumpet", A2, shift(a2, -12), trumpet, 0.75, pan=0.2)
    for local in (1, 3):
        bar = A2 + local
        c, nxt = parts[2].changes[local][3], parts[2].changes[local + 1][3]
        cha_cha_cha("bone", bar, c, nxt, trombone, 0.8, low=50, high=63)
        for k, m in zip((12, 14, 16), hop_up(c, nxt)):
            tr.add("xylo", bar, k, ins.xylophone(m, 0.15), 0.6 + 0.15 * (k == 16), 0.3)
    hit("bone", A2 + 7, 8, [43, 47, 50, 53], 2, trombone, 0.6, -0.25)

    # B: the sly trombone's mambo; the flute answers with a rattle; they SWAP; the TRAPDOOR; the BOOST
    riff = melody("""G3:3 C4:3 Eb4:2 D4:3 C4:3 Bb3:2 | A3:3 C4:3 Eb4:2 F4:3 Eb4:3 C4:2 |
                     G3:3 C4:3 Eb4:2 G4:3 F4:3 Eb4:2 | F4:3 Eb4:3 C4:2 A3:6 r:2 |
                     Eb3:1 Gb3:1 Ab3:1 C4:1 Eb4:1 Gb4:1 Ab4:1 C5:1 C5:4 r:4""")
    lead("bone_lead", B, riff, trombone, 1.0, legato=0.8, pan=-0.1)
    answers = melody("""G6:2 r:14 | r:8 Eb6:6 D6:1 C6:1 | r:16 | r:8 F6:6 Eb6:1 C6:1 |
                        Eb6:1 C6:1 Ab5:1 Gb5:1 Eb5:1 C5:1 Ab4:1 Gb4:1 Eb4:4 r:4 | r:16 |
                        G5:6 F5:1 Eb5:1 D5:1 C5:1 r:2 G5:2 r:2 | r:8 C5:1 D5:1 E5:1 F5:1 G5:2 G#5:2""")
    lead("flute", B, answers, flute, 0.85, trills={(1, 8): 2.0, (3, 8): 2.0, (6, 0): 2.0})
    for local in (0, 2):
        for k in (6, 14):
            hit("trumpet", B + local, k, [75, 79, 82], 1.5, trumpet, 0.7, 0.2)
    tr.add("fx", B + 4, 0, ins.whoosh(0.6, up=True), 0.7, -0.3)
    hit("trumpet", B + 4, 12, [68, 72, 75], 2, trumpet, 0.8, 0.2)
    for k, (m, steps) in enumerate(((62, 3), (61, 3), (60, 3), (59, 7))):
        tr.add("bone_lead", B + 5, k * 3, wah_bone(m, round(steps * tr.step * 0.9, 3), k == 3), 1.25, -0.1)
    tr.add("fx", B + 6, 0, vibraslap(), 0.8, 0.3)
    tr.add("fx", B + 7, 0, boing(60.0, 0.75), 0.9, 0.0)
    hit("trumpet", B + 7, 0, [64, 67, 70], 2, trumpet, 0.85, 0.2)
    hit("bone", B + 7, 0, [48, 52, 55], 2, trombone, 0.7, -0.25)
    cha_cha_cha("trumpet", B + 7, chords("C7")[0][2], chords("F")[0][2], trumpet, 0.85)
    cha_cha_cha("bone", B + 7, chords("C7")[0][2], chords("F")[0][2], trombone, 0.6, low=50, high=63)

    # the home stretch in F: flute and trumpets in octaves, everyone answering, then the finish
    lead("flute", F, up, flute, trills={(1, 0): 2.0, (3, 0): 2.0})
    lead("trumpet", F, shift(up, -12), trumpet, 0.8, pan=0.2)
    for local in (1, 3):
        bar = F + local
        c, nxt = parts[4].changes[local][3], parts[4].changes[local + 1][3]
        cha_cha_cha("bone", bar, c, nxt, trombone, 0.8, low=50, high=63)
        for k, m in zip((12, 14, 16), hop_up(c, nxt)):
            tr.add("xylo", bar, k, ins.xylophone(m, 0.15), 0.65 + 0.15 * (k == 16), 0.3)
    lead("flute", F + 7, run, flute, trills={(0, 0): 2.0, (1, 0): 1.0})
    lead("trumpet", F + 7, melody("r:8 C5:1 D5:1 E5:1 F5:1 G5:2 G#5:2"), trumpet, 0.85, pan=0.2)
    lead("xylo", F + 7, melody("r:8 C6:1 D6:1 E6:1 F6:1 G6:2 G#6:2 | A6:4 r:12"), lambda m, sec: ins.xylophone(m, 0.15), 0.6, pan=0.3)
    hit("trumpet", F + 7, 0, [64, 67, 70], 2, trumpet, 0.9, 0.2)
    hit("bone", F + 7, 0, [48, 52, 58], 2, trombone, 0.75, -0.25)
    hit("bone", F + 7, 12, [48, 52, 58], 1.4, trombone, 0.65, -0.25)
    hit("bone", F + 7, 14, [48, 52, 58], 1.4, trombone, 0.7, -0.25)
    # CHA! on the round's 60 s: the band's last chord, a shake and a fall, the dice landing
    T = first["tag"]
    for m in (69, 72, 74, 77):
        tr.add("trumpet", T, 0, trumpet(m, round(7 * tr.step, 3), 3.0), 1.0 / 2, 0.2)
    hit("bone", T, 0, [48, 53, 57, 60], 7, trombone, 0.9, -0.25)
    tr.add("fx", T, 9, vibraslap(), 0.55, 0.3)
    lead("flute", T + 1, melody("C6:12 r:4"), flute, 0.75, trills={(0, 0): 2.0})

    # the dice land on GO, on the home stretch and on the finish; cymbals on the big downbeats
    for bar, variant, gain in ((A1, 0, 1.0), (F, 1, 1.0), (T, 2, 1.0)):
        tr.add("fx", bar, 0, dice_throw(variant), gain, 0.15)
    for bar, sound, gain, pan in ((A1, crash(), 1.0, -0.3), (A2, splash(), 0.6, 0.3), (B, splash(), 0.7, -0.3),
                                  (F, crash(), 1.0, 0.3), (F + 4, splash(), 0.6, -0.3), (T, crash(), 1.0, -0.3)):
        tr.add("crash", bar, 0, sound, gain, pan)

    mix = Mix(buses={
        "flute": Bus(-5, reverb=0.18, delay=0.07),
        "trumpet": Bus(-9, reverb=0.16),
        "bone": Bus(-13, reverb=0.15),
        "bone_lead": Bus(-6, reverb=0.16),
        "piano": Bus(-12, reverb=0.12),
        "xylo": Bus(-15, reverb=0.18),
        "bass": Bus(-9),
        "kick": Bus(-14),
        "conga": Bus(-13, reverb=0.08),
        "guiro": Bus(-18, reverb=0.05),
        "dice": Bus(-15, reverb=0.06, eq=(("high", 6000, 3),)),
        "bell": Bus(-18, reverb=0.06),
        "timbal": Bus(-14, reverb=0.12),
        "clave": Bus(-21, reverb=0.1),
        "fx": Bus(-11, reverb=0.2),
        "crash": Bus(-18, eq=(("lp", 11000),)),
    }, reverb_decay=1.4, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("DiceDash", "Lucky Roll Cha-Cha", 128, 7, 41, lucky_roll)
