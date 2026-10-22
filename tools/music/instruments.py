"""More instruments for the mini-games' own round tracks (tools/music/modes.py).

Owner: "put in the backlog custom music for each mini game". Thirteen arenas need thirteen bands:
temple drums and a bamboo flute, a game-show funk band, a meadow's pizzicato and bassoon, a tiki
steel band, skate punk, a desert's oud and darbuka, a castle's fife and fanfare, a carnival
calliope, a farmyard banjo and fiddle, a bake-off jazz trio, a toy factory, sleigh bells and surf
guitar. Like synth.py, every sound here is built from math (oscillators, filtered noise, FM and
Karplus-Strong plucked strings), so the music stays original and free of licensing concerns.

Each function returns a mono array (or a stereo one, shape (2, n)) at synth.SR that starts at the
note's onset and includes its release tail. Notes are cached (a song plays the same note many
times), so the arrays come back read-only: copy one before changing it in place.
"""

from __future__ import annotations

import zlib
from functools import lru_cache

import numpy as np
from scipy import signal

import synth as s

SR = s.SR


def _frozen(x: np.ndarray) -> np.ndarray:
    x.setflags(write=False)
    return x


def _rng(*key) -> np.random.Generator:
    """A generator seeded from the note, so a note sounds the same on every render (str hashes
    change from run to run, so the seed is a CRC of the key's text)."""
    text = repr(tuple(round(k, 4) if isinstance(k, float) else k for k in key))
    return np.random.default_rng(zlib.crc32(text.encode()))


def _t(n: int) -> np.ndarray:
    return np.arange(n) / SR


# ---------------------------------------------------------------- envelopes & filters

def env(n: int, attack: float, decay: float, sustain: float, release: float, gate: float | None = None) -> np.ndarray:
    """Exponential envelope: a linear attack, an exponential fall towards `sustain` (time constant
    `decay`) while the note is held for `gate` seconds, then an exponential release."""
    t = _t(n)
    gate = n / SR if gate is None else gate
    a = max(attack, 1e-4)
    held = np.where(t < a, t / a, sustain + (1 - sustain) * np.exp(-(t - a) / max(decay, 1e-4)))
    if gate < a:
        level = gate / a
    else:
        level = sustain + (1 - sustain) * np.exp(-(gate - a) / max(decay, 1e-4))
    out = np.where(t < gate, held, level * np.exp(-(t - gate) / max(release / 4.6, 1e-4)))
    return out


def biquad_peak(f0: float, gain_db: float, q: float) -> np.ndarray:
    a_ = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * min(f0, SR * 0.45) / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a_, -2 * np.cos(w0), 1 - alpha * a_]
    a = [1 + alpha / a_, -2 * np.cos(w0), 1 - alpha / a_]
    return np.array([[b[0] / a[0], b[1] / a[0], b[2] / a[0], 1.0, a[1] / a[0], a[2] / a[0]]])


def biquad_shelf(f0: float, gain_db: float, high: bool, slope: float = 1.0) -> np.ndarray:
    a_ = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * min(f0, SR * 0.45) / SR
    cos, sin = np.cos(w0), np.sin(w0)
    alpha = sin / 2 * np.sqrt((a_ + 1 / a_) * (1 / slope - 1) + 2)
    root = 2 * np.sqrt(a_) * alpha
    if high:
        b = [a_ * ((a_ + 1) + (a_ - 1) * cos + root), -2 * a_ * ((a_ - 1) + (a_ + 1) * cos), a_ * ((a_ + 1) + (a_ - 1) * cos - root)]
        a = [(a_ + 1) - (a_ - 1) * cos + root, 2 * ((a_ - 1) - (a_ + 1) * cos), (a_ + 1) - (a_ - 1) * cos - root]
    else:
        b = [a_ * ((a_ + 1) - (a_ - 1) * cos + root), 2 * a_ * ((a_ - 1) - (a_ + 1) * cos), a_ * ((a_ + 1) - (a_ - 1) * cos - root)]
        a = [(a_ + 1) + (a_ - 1) * cos + root, -2 * ((a_ - 1) + (a_ + 1) * cos), (a_ + 1) + (a_ - 1) * cos - root]
    return np.array([[b[0] / a[0], b[1] / a[0], b[2] / a[0], 1.0, a[1] / a[0], a[2] / a[0]]])


def eq(x: np.ndarray, *bands) -> np.ndarray:
    """Cascaded EQ. Each band: ("peak", f, dB, q), ("low", f, dB) or ("high", f, dB) shelves,
    ("hp", f) / ("lp", f) 2nd-order Butterworth cuts."""
    sections = []
    for band in bands:
        kind = band[0]
        if kind == "peak":
            sections.append(biquad_peak(band[1], band[2], band[3]))
        elif kind in ("low", "high"):
            sections.append(biquad_shelf(band[1], band[2], kind == "high"))
        elif kind == "hp":
            sections.append(signal.butter(2, min(band[1] / (SR / 2), 0.99), "high", output="sos"))
        elif kind == "lp":
            sections.append(signal.butter(2, min(band[1] / (SR / 2), 0.99), "low", output="sos"))
    if not sections:
        return x
    return signal.sosfilt(np.vstack(sections), x, axis=-1)


def formant(x: np.ndarray, peaks) -> np.ndarray:
    """A body or a voice: the dry sound plus resonant peaks [(freq, dB, q), ...]."""
    return eq(x, *[("peak", f, g, q) for f, g, q in peaks])


def tv_lowpass(x: np.ndarray, cutoff: np.ndarray, q: float = 0.707, block: int = 128) -> np.ndarray:
    """Resonant low-pass whose cutoff follows `cutoff` (Hz, one value per sample), block by block."""
    n = x.shape[-1]
    out = np.zeros_like(x)
    zi = None
    for start in range(0, n, block):
        end = min(n, start + block)
        fc = float(np.clip(cutoff[min(start + block // 2, n - 1)], 30, SR * 0.45))
        w0 = 2 * np.pi * fc / SR
        alpha = np.sin(w0) / (2 * q)
        cos = np.cos(w0)
        a0 = 1 + alpha
        sos = np.array([[(1 - cos) / 2 / a0, (1 - cos) / a0, (1 - cos) / 2 / a0, 1.0, -2 * cos / a0, (1 - alpha) / a0]])
        if zi is None:
            zi = np.zeros((1, 2)) if x.ndim == 1 else np.zeros((1, x.shape[0], 2))
        if x.ndim == 1:
            out[start:end], zi = signal.sosfilt(sos, x[start:end], zi=zi)
        else:
            out[:, start:end], zi = signal.sosfilt(sos, x[:, start:end], axis=-1, zi=zi)
    return out


def drive(x: np.ndarray, amount: float) -> np.ndarray:
    return np.tanh(x * amount) / np.tanh(amount)


def bend(x: np.ndarray, semitones: np.ndarray) -> np.ndarray:
    """Re-pitches a rendered note over time (a string bend, a slide, a pitch fall)."""
    rate = 2 ** (np.asarray(semitones, dtype=np.float64) / 12)
    if rate.ndim == 0:
        rate = np.full(x.shape[-1], float(rate))
    pos = np.cumsum(rate) - rate[0]
    pos = pos[pos < x.shape[-1] - 1]
    return np.interp(pos, np.arange(x.shape[-1]), x)


def _vibrato(t: np.ndarray, depth: float, rate: float = 5.5, delay: float = 0.2, rise: float = 0.25) -> np.ndarray:
    """Pitch offset in semitones: no vibrato for `delay` seconds, then it fades in."""
    return depth * np.clip((t - delay) / max(rise, 1e-3), 0, 1) * np.sin(2 * np.pi * rate * t)


def normalize(x: np.ndarray, peak: float = 1.0) -> np.ndarray:
    top = np.max(np.abs(x))
    return x * (peak / top) if top > 0 else x


# ---------------------------------------------------------------- plucked strings (Karplus-Strong)

@lru_cache(maxsize=None)
def ks(midi: float, length: float, bright: float = 0.5, decay: float = 1.5, pick: float = 0.18,
       soft: float = 0.0, variant: int = 0) -> np.ndarray:
    """A plucked string. `bright` 0..1 is how slowly the high harmonics die (0 = nylon/felt,
    1 = steel), `decay` the fundamental's time to fall 60 dB, `pick` where along the string it is
    plucked (near the bridge = thinner), `soft` 0..1 rounds the pluck itself (a finger vs a pick)."""
    f = s.midi_hz(midi)
    period = SR / f
    stretch = 0.5 - 0.42 * bright  # the loop's averaging weight: 0.5 is darkest
    delay = int(np.floor(period - stretch - 0.2))
    frac = period - delay - stretch
    c = (1 - frac) / (1 + frac)  # all-pass coefficient for the fractional part (keeps it in tune)
    w = 2 * np.pi * f / SR
    loss = abs((1 - stretch) + stretch * np.exp(-1j * w))
    rho = min(0.99995, 10 ** (-3 / (decay * f)) / loss)
    n = s.samples(length)
    rng = _rng("ks", midi, variant)
    burst = rng.uniform(-1, 1, int(np.ceil(period)) + 2)
    burst -= burst.mean()
    if soft > 0:
        burst = s.lowpass(burst, max(300.0, 9000 * (1 - soft) + f * 2), order=1)
    k = max(1, int(round(pick * period)))
    burst = burst - np.concatenate([np.zeros(k), burst[:-k]])
    x = np.zeros(n)
    x[: min(n, len(burst))] = burst[: min(n, len(burst))]
    a = np.zeros(delay + 3)
    a[0], a[1] = 1.0, c
    a[delay] += -rho * (1 - stretch) * c
    a[delay + 1] += -rho * ((1 - stretch) + stretch * c)
    a[delay + 2] += -rho * stretch
    y = signal.lfilter([1.0, c], a, x)
    y = s.highpass(y, 25)
    return _frozen(normalize(y))


def _gate(x: np.ndarray, gate: float, release: float) -> np.ndarray:
    """Damps a ringing note `gate` seconds in (a palm mute, a staccato, a lifted finger)."""
    n = x.shape[-1]
    g = s.samples(gate)
    if g >= n:
        return x
    out = x.copy()
    r = max(1, s.samples(release))
    tail = np.exp(-np.arange(n - g) / (r / 4.6))
    out[..., g:] *= tail
    return out


@lru_cache(maxsize=None)
def acoustic_guitar(midi: float, length: float, variant: int = 0) -> np.ndarray:
    tone = ks(midi, length + 0.3, bright=0.55, decay=2.2, pick=0.16, soft=0.2, variant=variant)
    tone = formant(tone, [(105, 4, 1.2), (210, 3, 1.4), (420, 2, 1.6), (2600, -3, 1.0)])
    return _frozen(normalize(_gate(tone, length, 0.12)))


@lru_cache(maxsize=None)
def nylon(midi: float, length: float, variant: int = 0) -> np.ndarray:
    """Ukulele / nylon guitar: soft and round."""
    tone = ks(midi, length + 0.3, bright=0.25, decay=1.2, pick=0.22, soft=0.55, variant=variant)
    tone = formant(tone, [(240, 4, 1.3), (480, 2, 1.5)])
    return _frozen(normalize(_gate(tone, length, 0.1)))


@lru_cache(maxsize=None)
def banjo(midi: float, length: float, variant: int = 0) -> np.ndarray:
    """Bright, plinky and short, with the drum head's nasal ring."""
    tone = ks(midi, min(length, 0.9) + 0.25, bright=0.8, decay=0.75, pick=0.1, soft=0.05, variant=variant)
    tone = formant(tone, [(620, 6, 2.0), (1350, 4, 2.5), (3800, -4, 1.0)])
    tone = eq(tone, ("hp", 160), ("lp", 7000))
    return _frozen(normalize(_gate(tone, length, 0.08)))


@lru_cache(maxsize=None)
def oud(midi: float, length: float, slide: float = 0.0, variant: int = 0) -> np.ndarray:
    """Fretless lute: a woody pluck; `slide` semitones it slides up into the note from below."""
    tone = ks(midi, length + 0.4, bright=0.45, decay=1.6, pick=0.14, soft=0.15, variant=variant)
    tone = formant(tone, [(180, 5, 1.0), (420, 3, 1.4), (1100, 2, 2.0), (3200, -5, 1.0)])
    if slide:
        n = tone.shape[-1]
        t = _t(n)
        tone = bend(tone, -slide * np.exp(-t / 0.05))
    return _frozen(normalize(_gate(tone, length, 0.12)))


@lru_cache(maxsize=None)
def koto(midi: float, length: float, press: float = 0.0, variant: int = 0) -> np.ndarray:
    """Zither pluck; `press` bends the note up that many semitones after the attack (or down if negative)."""
    tone = ks(midi, length + 0.6, bright=0.7, decay=2.0, pick=0.12, soft=0.1, variant=variant)
    tone = formant(tone, [(300, 3, 1.0), (900, 3, 1.5), (4000, -4, 1.0)])
    if press:
        t = _t(tone.shape[-1])
        tone = bend(tone, press * np.clip((t - 0.12) / 0.15, 0, 1))
    return _frozen(normalize(_gate(tone, length + 0.2, 0.2)))


@lru_cache(maxsize=None)
def harp(midi: float, length: float, variant: int = 0) -> np.ndarray:
    tone = ks(midi, length + 1.0, bright=0.4, decay=2.6, pick=0.4, soft=0.45, variant=variant)
    return _frozen(normalize(eq(tone, ("peak", 250, 2, 1.0), ("lp", 6000))))


@lru_cache(maxsize=None)
def pizz(midi: float, length: float = 0.3, variant: int = 0) -> np.ndarray:
    """Pizzicato string section: a dark, quick pluck with a little room in it."""
    voices = []
    for v, cents in enumerate((-6, 4, 0)):
        tone = ks(midi + cents / 100, 0.6, bright=0.2, decay=0.45, pick=0.3, soft=0.6, variant=variant * 3 + v)
        voices.append(np.concatenate([np.zeros(s.samples(0.004 * v)), tone])[: s.samples(0.6)])
    tone = sum(voices) / 3
    tone = formant(tone, [(280, 4, 1.0), (520, 3, 1.4), (1200, 2, 1.2)])
    return _frozen(normalize(_gate(tone, max(length, 0.18), 0.1)))


@lru_cache(maxsize=None)
def upright(midi: float, length: float, variant: int = 0) -> np.ndarray:
    """Upright bass: a round pluck with a woody thump, plenty of 2nd/3rd harmonic so small speakers hear it."""
    tone = ks(midi, length + 0.4, bright=0.3, decay=1.4, pick=0.2, soft=0.45, variant=variant)
    n = tone.shape[-1]
    t = _t(n)
    thump = np.sin(2 * np.pi * s.midi_hz(midi) * t) * np.exp(-t / 0.09)
    tone = tone * 0.8 + thump * 0.5
    tone = formant(tone, [(s.midi_hz(midi) * 2, 3, 1.0), (700, 2, 1.0)])
    return _frozen(normalize(_gate(tone, length, 0.07)))


@lru_cache(maxsize=None)
def bass_guitar(midi: float, length: float, bright: float = 0.5, variant: int = 0) -> np.ndarray:
    """Picked electric bass."""
    tone = ks(midi, length + 0.3, bright=0.35 + 0.3 * bright, decay=2.0, pick=0.15, soft=0.2, variant=variant)
    n = tone.shape[-1]
    t = _t(n)
    sub = np.sin(2 * np.pi * s.midi_hz(midi) * t) * np.exp(-t / 0.6) * 0.4
    tone = drive(tone * 0.9 + sub, 1.6)
    tone = eq(tone, ("lp", 1800 + 1800 * bright), ("peak", 800, 2, 1.0))
    return _frozen(normalize(_gate(tone, length, 0.05)))


@lru_cache(maxsize=None)
def electric_guitar(midi: float, length: float, mute: bool = False, variant: int = 0) -> np.ndarray:
    """Clean single-coil electric (surf, funk): bright and twangy."""
    tone = ks(midi, length + 0.5, bright=0.75, decay=0.35 if mute else 2.4, pick=0.13, soft=0.05, variant=variant)
    tone = formant(tone, [(1900, 4, 1.4), (160, 2, 1.0)])
    tone = eq(tone, ("hp", 90), ("lp", 6500))
    tone = drive(tone * 1.4, 1.3)
    return _frozen(normalize(_gate(tone, length, 0.04 if mute else 0.08)))


@lru_cache(maxsize=None)
def power_chord(root: float, length: float, mute: bool = False, variant: int = 0) -> np.ndarray:
    """Overdriven root-fifth-octave chord through a speaker cabinet (pop-punk crunch, not fizz)."""
    parts = []
    for i, interval in enumerate((0, 7, 12)):
        parts.append(ks(root + interval + (i - 1) * 0.04, length + 0.3, bright=0.6, decay=0.3 if mute else 2.0,
                        pick=0.12, soft=0.1, variant=variant * 3 + i))
    tone = sum(parts)
    tone = drive(tone * (2.0 if mute else 3.2), 3.0)
    tone = eq(tone, ("hp", 110), ("peak", 420, -3, 1.0), ("peak", 1500, 2, 1.2), ("lp", 3600), ("lp", 5200))
    return _frozen(normalize(_gate(tone, length, 0.05 if mute else 0.1)))


# ---------------------------------------------------------------- bowed, blown and sung

def _voice(midi: float, length: float, wave: str, attack: float, decay: float, sustain: float, release: float,
           vibrato: float, vib_rate: float, vib_delay: float, detune: tuple = (0.0,), scoop: float = 0.0,
           scoop_time: float = 0.05, width: float = 0.5, glide_from: float | None = None, glide_time: float = 0.08) -> np.ndarray:
    n = s.samples(length + release)
    t = _t(n)
    pitch = midi + _vibrato(t, vibrato, vib_rate, vib_delay)
    if scoop:
        pitch = pitch - scoop * np.exp(-t / scoop_time)
    if glide_from is not None:
        pitch = pitch + (glide_from - midi) * np.exp(-t / glide_time)
    out = np.zeros(n)
    for d in detune:
        freq = s.midi_hz(pitch + d)
        if wave == "saw":
            out += s.saw(freq, n, start=(d * 7.3) % 1.0)
        elif wave == "square":
            out += s.square(freq, n, width)
        elif wave == "sine":
            out += s.sine(freq, n)
        elif wave == "tri":
            phase, _ = s.phase_of(freq, n)
            out += 2 * np.abs(2 * phase - 1) - 1
    out /= len(detune)
    return out * env(n, attack, decay, sustain, release, gate=length)


@lru_cache(maxsize=None)
def fiddle(midi: float, length: float, glide_from: float | None = None, accent: float = 1.0) -> np.ndarray:
    """A country fiddle: bowed saw with vibrato, a wooden body and a little bow hiss."""
    tone = _voice(midi, length, "saw", 0.035, 0.3, 0.85, 0.09, vibrato=0.16, vib_rate=5.8, vib_delay=0.12,
                  detune=(-0.03, 0.03), scoop=0.25, scoop_time=0.03, glide_from=glide_from, glide_time=0.05)
    tone = formant(tone, [(290, 5, 1.6), (480, 4, 2.0), (1050, 3, 2.2), (2700, 3, 2.5), (5200, -8, 0.8)])
    n = tone.shape[-1]
    hiss = s.bandpass(_rng("bow", midi, length).uniform(-1, 1, n), 2500, 7000) * env(n, 0.02, 0.1, 0.25, 0.08, gate=length) * 0.05
    out = eq(tone + hiss, ("hp", 180), ("lp", 7500))
    return _frozen(normalize(out, 0.8 + 0.2 * accent))


@lru_cache(maxsize=None)
def erhu(midi: float, length: float, glide_from: float | None = None) -> np.ndarray:
    """A two-string fiddle: a singing, nasal bowed tone with wide vibrato and slides."""
    tone = _voice(midi, length, "saw", 0.06, 0.4, 0.9, 0.12, vibrato=0.28, vib_rate=6.2, vib_delay=0.1,
                  detune=(-0.02, 0.02), scoop=0.5, scoop_time=0.06, glide_from=glide_from, glide_time=0.09)
    tone = formant(tone, [(650, 6, 1.8), (1400, 5, 2.2), (3000, 2, 2.5), (5000, -8, 0.8)])
    return _frozen(normalize(eq(tone, ("hp", 250), ("lp", 6500))))


@lru_cache(maxsize=None)
def bee(midi: float, length: float) -> np.ndarray:
    """A cartoon bee: a buzzy kazoo-like reed that wobbles fast."""
    n = s.samples(length + 0.05)
    t = _t(n)
    pitch = midi + 0.25 * np.sin(2 * np.pi * 13 * t)
    tone = s.saw(s.midi_hz(pitch), n) + 0.5 * s.square(s.midi_hz(pitch), n, 0.3)
    tone = formant(tone, [(900, 8, 2.5), (2300, 5, 3.0)])
    tone = eq(tone, ("hp", 400), ("lp", 3800))
    return _frozen(normalize(tone * env(n, 0.01, 0.1, 0.85, 0.04, gate=length)))


@lru_cache(maxsize=None)
def whistle(midi: float, length: float) -> np.ndarray:
    n = s.samples(length + 0.12)
    t = _t(n)
    vib = midi + _vibrato(t, 0.08, 5.2, 0.15, 0.2)
    tone = s.sine(s.midi_hz(vib), n) + 0.12 * s.sine(s.midi_hz(vib + 12), n)
    breath = s.bandpass(_rng("whistle", midi).uniform(-1, 1, n), 2000, 6000) * 0.05
    return _frozen(normalize((tone + breath) * env(n, 0.04, 0.1, 0.85, 0.1, gate=length)))


@lru_cache(maxsize=None)
def combo_organ(midi: float, length: float) -> np.ndarray:
    """A 60s combo organ (surf and garage bands): a reedy pulse with vibrato."""
    n = s.samples(length + 0.05)
    t = _t(n)
    pitch = midi + _vibrato(t, 0.1, 6.5, 0.0, 0.01)
    tone = s.square(s.midi_hz(pitch), n, 0.32) * 0.7 + s.square(s.midi_hz(pitch + 12), n, 0.5) * 0.35
    tone = eq(tone, ("lp", 3000), ("lp", 4200), ("peak", 1200, 3, 1.0), ("hp", 200))
    return _frozen(normalize(tone * env(n, 0.006, 0.2, 0.92, 0.04, gate=length)))


@lru_cache(maxsize=None)
def lute(midi: float, length: float, variant: int = 0) -> np.ndarray:
    """Renaissance lute: a gentle, bright double-course pluck."""
    a = ks(midi, length + 0.4, bright=0.6, decay=1.4, pick=0.2, soft=0.25, variant=variant)
    b = ks(midi + 0.05, length + 0.4, bright=0.6, decay=1.3, pick=0.22, soft=0.25, variant=variant + 50)
    tone = formant(np.asarray(a) + np.asarray(b) * 0.7, [(220, 4, 1.2), (500, 3, 1.4), (3500, -3, 1.0)])
    return _frozen(normalize(_gate(tone, length + 0.1, 0.12)))


@lru_cache(maxsize=None)
def flute(midi: float, length: float, breath: float = 0.07, vibrato: float = 0.12, buzz: float = 0.0,
          fall: float = 0.0, glide_from: float | None = None) -> np.ndarray:
    """Flutes: concert flute, a fife (high, less vibrato), a bamboo dizi (`buzz` adds its membrane)
    or a breathy ney (more `breath`). `fall` drops the pitch at the end of the note (a shakuhachi sigh)."""
    n = s.samples(length + 0.12)
    t = _t(n)
    pitch = midi + _vibrato(t, vibrato, 5.2, 0.18, 0.3)
    if glide_from is not None:
        pitch = pitch + (glide_from - midi) * np.exp(-t / 0.06)
    if fall:
        pitch = pitch - fall * np.clip((t - length * 0.7) / max(length * 0.3, 0.05), 0, 1) ** 2
    freq = s.midi_hz(pitch)
    tone = s.sine(freq, n) + 0.22 * s.sine(freq * 2, n) + 0.07 * s.sine(freq * 3, n)
    if buzz:
        rasp = s.saw(freq, n)
        tone = tone + buzz * eq(rasp, ("peak", 2400, 8, 2.5), ("hp", 1200), ("lp", 5000)) * 0.35
    air = s.bandpass(_rng("air", midi, length).uniform(-1, 1, n), max(400, s.midi_hz(midi) * 1.5), min(9000, s.midi_hz(midi) * 5))
    e = env(n, 0.04, 0.25, 0.85, 0.1, gate=length)
    chiff = np.exp(-t / 0.03) * 0.6
    return _frozen(normalize((tone + air * (breath + chiff * breath * 3)) * e))


@lru_cache(maxsize=None)
def clarinet(midi: float, length: float, glide_from: float | None = None) -> np.ndarray:
    tone = _voice(midi, length, "square", 0.03, 0.4, 0.9, 0.08, vibrato=0.05, vib_rate=5.0, vib_delay=0.3,
                  width=0.5, glide_from=glide_from)
    tone = eq(tone, ("lp", 2400), ("lp", 3600), ("peak", 1500, 3, 1.5), ("hp", 140))
    return _frozen(normalize(tone))


@lru_cache(maxsize=None)
def bassoon(midi: float, length: float) -> np.ndarray:
    """A double reed in the low register: reedy, a bit comic, clear on small speakers."""
    tone = _voice(midi, length, "square", 0.025, 0.25, 0.8, 0.06, vibrato=0.04, vib_rate=5.2, vib_delay=0.25, width=0.28)
    tone = formant(tone, [(480, 7, 1.8), (1150, 4, 2.0)])
    tone = eq(tone, ("lp", 1900), ("lp", 2600), ("hp", 70))
    return _frozen(normalize(tone))


@lru_cache(maxsize=None)
def brass(midi: float, length: float, bright: float = 1.0, section: int = 3, vibrato: float = 0.08, fall: float = 0.0) -> np.ndarray:
    """Trumpets (or horns with low `bright`): a lip scoop, the brassy filter bloom, vibrato on long notes."""
    n = s.samples(length + 0.15)
    t = _t(n)
    detunes = (0.0,) if section == 1 else tuple(np.linspace(-0.07, 0.07, section))
    out = np.zeros(n)
    for i, d in enumerate(detunes):
        pitch = midi + d - 0.35 * np.exp(-t / 0.025) + _vibrato(t, vibrato, 5.3, 0.25, 0.3)
        if fall:
            pitch = pitch - fall * np.clip((t - length) / 0.12, 0, 1) ** 1.5
        out += s.saw(s.midi_hz(pitch), n, start=i * 0.37)
    out /= len(detunes)
    e = env(n, 0.03, 0.25, 0.8, 0.12, gate=length)
    peak = 900 + 2600 * bright
    cutoff = 400 + (peak - 400) * np.clip(e * (1.1 - 0.25 * np.clip(t / 0.4, 0, 1)), 0, 1.2) + s.midi_hz(midi) * 1.5
    tone = tv_lowpass(out * e, cutoff, q=0.9)
    tone = eq(tone, ("peak", 1200, 2.5, 1.0), ("hp", 120))
    return _frozen(normalize(tone))


@lru_cache(maxsize=None)
def tuba(midi: float, length: float) -> np.ndarray:
    """Oom-pah tuba: round, short, with enough upper harmonics for phone speakers."""
    n = s.samples(length + 0.1)
    t = _t(n)
    pitch = midi - 0.25 * np.exp(-t / 0.03)
    freq = s.midi_hz(pitch)
    tone = s.saw(freq, n) * 0.6 + s.sine(freq, n) * 0.6
    e = env(n, 0.02, 0.15, 0.7, 0.07, gate=length)
    tone = tv_lowpass(tone * e, 250 + 1300 * e, q=0.8)
    return _frozen(normalize(eq(tone, ("peak", 380, 3, 1.0))))


@lru_cache(maxsize=None)
def strings(notes: tuple, length: float, attack: float = 0.25, bright: float = 0.5, release: float = 0.5) -> np.ndarray:
    """A string section pad (stereo): detuned saws with slow attack, vibrato and a dark top."""
    n = s.samples(length + release)
    t = _t(n)
    out = np.zeros((2, n))
    for k, midi in enumerate(notes):
        for v, (d, pan_pos) in enumerate(((-0.08, -0.6), (0.0, 0.0), (0.08, 0.6))):
            pitch = midi + d + _vibrato(t + k * 0.13 + v * 0.07, 0.1, 5.0 + v * 0.3, 0.0, 0.01)
            out += s.pan(s.saw(s.midi_hz(pitch), n, start=(k * 3 + v) * 0.21), pan_pos)
    out /= 3 * max(1, len(notes)) ** 0.7
    out = eq(out, ("lp", 1400 + 2600 * bright), ("peak", 350, 2, 1.0), ("hp", 90))
    return _frozen(out * env(n, attack, 0.5, 0.9, release, gate=length))


@lru_cache(maxsize=None)
def spiccato(midi: float, length: float = 0.15) -> np.ndarray:
    """Short bouncing string notes for ostinatos."""
    tone = _voice(midi, length, "saw", 0.008, 0.06, 0.4, 0.06, vibrato=0.0, vib_rate=5, vib_delay=1, detune=(-0.05, 0.05))
    tone = formant(tone, [(300, 4, 1.2), (900, 2, 1.5), (2500, 2, 2.0)])
    return _frozen(normalize(eq(tone, ("lp", 4200), ("hp", 120))))


@lru_cache(maxsize=None)
def choir(notes: tuple, length: float, vowel: str = "ah", attack: float = 0.35) -> np.ndarray:
    """An 'aah' / 'ooh' choir pad (stereo): sawtooth voices through vocal formants."""
    formants = {"ah": [(750, 12, 4), (1150, 9, 5), (2800, 5, 6)], "oo": [(350, 12, 4), (800, 8, 5), (2400, 2, 6)],
                "eh": [(550, 11, 4), (1800, 9, 5), (2600, 5, 6)]}[vowel]
    n = s.samples(length + 0.6)
    t = _t(n)
    out = np.zeros((2, n))
    for k, midi in enumerate(notes):
        for v, (d, pan_pos) in enumerate(((-0.1, -0.5), (0.06, 0.5), (0.0, 0.0))):
            pitch = midi + d + _vibrato(t + v * 0.11 + k * 0.05, 0.12, 4.6 + v * 0.4, 0.15, 0.4)
            out += s.pan(s.saw(s.midi_hz(pitch), n, start=(k + v) * 0.3), pan_pos)
    out /= 3 * max(1, len(notes)) ** 0.7
    out = formant(out, formants)
    out = eq(out, ("lp", 3500), ("hp", 150))
    return _frozen(normalize(out * env(n, attack, 0.5, 0.9, 0.6, gate=length), 0.8))


@lru_cache(maxsize=None)
def organ(midi: float, length: float, drawbars: tuple = (8, 8, 6, 0, 3, 0, 0, 0, 2), leslie: float = 6.5, click: float = 0.5) -> np.ndarray:
    """Tonewheel organ: drawbars 16', 5 1/3', 8', 4', 2 2/3', 2', 1 3/5', 1 1/3', 1' (0..8), a rotary
    speaker's shimmer at `leslie` Hz (0 = off) and a key click. Stereo."""
    ratios = (0.5, 1.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0)
    n = s.samples(length + 0.08)
    t = _t(n)
    f = s.midi_hz(midi)
    tone = np.zeros(n)
    for ratio, bar in zip(ratios, drawbars):
        if bar and f * ratio < 9000:
            tone += (bar / 8) * np.sin(2 * np.pi * f * ratio * t + ratio)
    tone /= max(1.0, sum(drawbars) / 8) ** 0.8
    e = env(n, 0.005, 0.1, 1.0, 0.05, gate=length)
    clickn = s.bandpass(_rng("click", midi).uniform(-1, 1, n), 1500, 5000) * np.exp(-t / 0.004) * click * 0.3
    mono = tone * e + clickn
    if leslie:
        am_l = 1 - 0.18 * (1 + np.sin(2 * np.pi * leslie * t)) / 2
        am_r = 1 - 0.18 * (1 + np.sin(2 * np.pi * leslie * t + 1.9)) / 2
        return _frozen(np.vstack([mono * am_l, mono * am_r]))
    return _frozen(s.pan(mono))


@lru_cache(maxsize=None)
def calliope(midi: float, length: float) -> np.ndarray:
    """A carnival steam organ: two slightly out-of-tune whistle pipes with a wide, wobbly vibrato."""
    n = s.samples(length + 0.1)
    t = _t(n)
    out = np.zeros(n)
    for d, w in ((-0.08, 1.0), (0.1, 0.8), (12.03, 0.25)):
        pitch = midi + d + _vibrato(t, 0.22, 6.3, 0.05, 0.1)
        freq = s.midi_hz(pitch)
        out += w * (np.sin(2 * np.pi * np.cumsum(freq) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(freq) / SR))
    air = s.bandpass(_rng("steam", midi).uniform(-1, 1, n), 1500, 6000) * 0.08
    e = env(n, 0.02, 0.2, 0.9, 0.06, gate=length)
    return _frozen(normalize(eq((out / 2 + air) * e, ("lp", 6000), ("hp", 150))))


@lru_cache(maxsize=None)
def accordion(notes: tuple, length: float) -> np.ndarray:
    """Musette accordion chord (two reeds a few cents apart beat against each other). Stereo."""
    n = s.samples(length + 0.08)
    out = np.zeros(n)
    for midi in notes:
        for d in (-0.06, 0.06):
            out += s.square(s.midi_hz(midi + d), n, 0.42)
    out /= 2 * max(1, len(notes)) ** 0.7
    out = eq(out, ("lp", 2600), ("peak", 900, 3, 1.2), ("hp", 150))
    stereo = np.vstack([out, np.roll(out, 9)])
    return _frozen(normalize(stereo * env(n, 0.03, 0.3, 0.85, 0.06, gate=length)))


# ---------------------------------------------------------------- keys, mallets, bells

@lru_cache(maxsize=None)
def fm(midi: float, length: float, ratio: float, index: float, decay: float, mod_decay: float | None = None,
       attack: float = 0.002, ratio2: float = 0.0, index2: float = 0.0, decay2: float = 0.05) -> np.ndarray:
    """Two-operator FM with an optional second, fast-decaying modulator (a tine, a mallet's click)."""
    n = s.samples(length + decay * 2)
    t = _t(n)
    f = s.midi_hz(midi)
    mod = index * np.exp(-t / (mod_decay or decay * 0.3)) * np.sin(2 * np.pi * f * ratio * t)
    if ratio2:
        mod = mod + index2 * np.exp(-t / decay2) * np.sin(2 * np.pi * f * ratio2 * t)
    tone = np.sin(2 * np.pi * f * t + mod)
    amp = np.exp(-t / decay) * np.clip(t / attack, 0, 1)
    if length < n / SR:
        amp *= np.where(t < length + decay, 1, np.exp(-(t - length - decay) / 0.05))
    return _frozen(tone * amp)


def marimba(midi: float, length: float = 0.3) -> np.ndarray:
    return fm(midi, min(length, 0.4), 4.0, 2.2, 0.35, mod_decay=0.03)


def xylophone(midi: float, length: float = 0.2) -> np.ndarray:
    return fm(midi, min(length, 0.25), 3.0, 1.8, 0.18, mod_decay=0.02)


def glock(midi: float, length: float = 0.4) -> np.ndarray:
    return fm(midi, min(length, 0.6), 3.5, 1.1, 0.7, mod_decay=0.08)


def music_box(midi: float, length: float = 0.3) -> np.ndarray:
    return fm(midi, min(length, 0.5), 5.4, 0.9, 0.55, mod_decay=0.05, ratio2=13.1, index2=0.6, decay2=0.01)


def kalimba(midi: float, length: float = 0.4) -> np.ndarray:
    return fm(midi, min(length, 0.6), 5.6, 1.0, 0.45, mod_decay=0.04, ratio2=1.0, index2=0.4, decay2=0.03)


def celesta(midi: float, length: float = 0.4) -> np.ndarray:
    return fm(midi, min(length, 0.8), 4.0, 0.7, 0.9, mod_decay=0.1)


@lru_cache(maxsize=None)
def vibes(midi: float, length: float = 0.8, motor: float = 5.0) -> np.ndarray:
    """Vibraphone with its motor's tremolo. Stereo (the tremolo moves a little across)."""
    tone = np.asarray(fm(midi, length, 4.0, 0.6, 1.4, mod_decay=0.05)).copy()
    t = _t(tone.shape[-1])
    tremolo = 1 - 0.35 * (1 + np.sin(2 * np.pi * motor * t)) / 2
    left = tone * tremolo
    right = tone * (1 - 0.35 * (1 + np.sin(2 * np.pi * motor * t + 1.2)) / 2)
    return _frozen(np.vstack([left, right]))


@lru_cache(maxsize=None)
def epiano(midi: float, length: float = 0.8) -> np.ndarray:
    """Electric piano: a bell-like tine over a warm body, with a gentle stereo tremolo."""
    tone = np.asarray(fm(midi, length, 1.0, 1.6, 1.3, mod_decay=0.4, ratio2=14.0, index2=0.5, decay2=0.008)).copy()
    tone = _gate(tone, length + 0.05, 0.25)
    t = _t(tone.shape[-1])
    pan_lfo = 0.25 * np.sin(2 * np.pi * 4.2 * t)
    return _frozen(np.vstack([tone * (0.75 - pan_lfo), tone * (0.75 + pan_lfo)]))


@lru_cache(maxsize=None)
def toy_piano(midi: float, length: float = 0.3) -> np.ndarray:
    tone = np.asarray(fm(midi, min(length, 0.5), 2.76, 1.2, 0.5, mod_decay=0.05, ratio2=5.4, index2=0.5, decay2=0.02)).copy()
    return _frozen(normalize(eq(tone, ("hp", 300))))


@lru_cache(maxsize=None)
def steel_pan(midi: float, length: float = 0.3) -> np.ndarray:
    """Steel drum: a rounded FM tone with a short bloom and an octave shimmer."""
    body = np.asarray(fm(midi, length, 2.0, 1.6, 0.4, mod_decay=0.12)).copy()
    shimmer = fm(midi + 12.03, length, 3.0, 0.6, 0.2, mod_decay=0.05)
    body[: len(shimmer)] += np.asarray(shimmer)[: len(body)] * 0.25
    return _frozen(normalize(body))


@lru_cache(maxsize=None)
def clav(midi: float, length: float = 0.15) -> np.ndarray:
    """Funky clavinet: a thin pulse plucked through a snapping filter."""
    n = s.samples(length + 0.08)
    t = _t(n)
    tone = s.square(s.midi_hz(midi), n, 0.22) + 0.3 * s.saw(s.midi_hz(midi), n)
    e = env(n, 0.002, 0.12, 0.35, 0.03, gate=length)
    tone = tv_lowpass(tone * e, 700 + 3800 * np.exp(-t / 0.05), q=1.6)
    return _frozen(normalize(eq(tone, ("hp", 220), ("peak", 1100, 3, 1.2))))


@lru_cache(maxsize=None)
def synth_pluck(midi: float, length: float = 0.2, bright: float = 3500, wave: str = "saw") -> np.ndarray:
    n = s.samples(length + 0.15)
    t = _t(n)
    f = s.midi_hz(midi)
    tone = s.saw(f, n) if wave == "saw" else s.square(f, n, 0.3)
    e = env(n, 0.002, max(0.05, length * 0.5), 0.0, 0.05)
    return _frozen(normalize(tv_lowpass(tone * e, 300 + bright * np.exp(-t / max(0.04, length * 0.4)) + f, q=1.0)))


@lru_cache(maxsize=None)
def slap_bass(midi: float, length: float, pop: bool = False) -> np.ndarray:
    """Slap bass: a thumb thud with a bright snap (or a popped string an octave up)."""
    n = s.samples(length + 0.08)
    t = _t(n)
    f = s.midi_hz(midi + (12 if pop else 0))
    pitch_env = f * (1 + 0.03 * np.exp(-t / 0.01))
    tone = s.saw(pitch_env, n) * 0.6 + s.sine(pitch_env, n) * 0.7
    e = env(n, 0.002, 0.25, 0.5, 0.04, gate=length)
    tone = tv_lowpass(tone * e, 500 + (3600 if pop else 2400) * np.exp(-t / 0.04), q=1.2)
    snap = s.bandpass(_rng("snap", midi).uniform(-1, 1, n), 1500, 5000) * np.exp(-t / 0.006) * (0.5 if pop else 0.3)
    return _frozen(normalize(drive(tone + snap, 1.4)))


@lru_cache(maxsize=None)
def synth_bass(midi: float, length: float, cutoff: float = 900, env_amt: float = 1600, sub: float = 0.6, q: float = 1.0) -> np.ndarray:
    """Subtractive bass with a filter pluck, and enough mid harmonics to read on a phone."""
    n = s.samples(length + 0.06)
    t = _t(n)
    f = s.midi_hz(midi)
    tone = s.saw(f, n) * 0.6 + s.square(f, n, 0.5) * 0.25
    e = env(n, 0.003, 0.18, 0.7, 0.04, gate=length)
    tone = tv_lowpass(tone * e, cutoff + env_amt * np.exp(-t / 0.06), q=q)
    low = s.sine(f, n) * sub * e
    return _frozen(normalize(drive(tone + low, 1.3)))


# ---------------------------------------------------------------- drums & percussion

@lru_cache(maxsize=None)
def taiko(pitch: float = 62.0, length: float = 1.2, hard: float = 1.0, variant: int = 0) -> np.ndarray:
    """A big festival drum: a booming head that drops in pitch, its second mode, and the stick's slap."""
    n = s.samples(length)
    t = _t(n)
    f = pitch * (1 + 0.55 * np.exp(-t / 0.035))
    head = s.sine(f, n) * np.exp(-t / (0.32 * length))
    mode2 = s.sine(f * 1.59, n) * np.exp(-t / 0.12) * 0.35
    mode3 = s.sine(f * 2.14, n) * np.exp(-t / 0.07) * 0.18
    slap = s.bandpass(_rng("taiko", pitch, variant).uniform(-1, 1, n), 250, 1800) * np.exp(-t / 0.018) * 0.7 * hard
    return _frozen(normalize(drive((head + mode2 + mode3 + slap) * (0.8 + 0.4 * hard), 1.5)))


@lru_cache(maxsize=None)
def tom(pitch: float = 140.0, length: float = 0.5, variant: int = 0) -> np.ndarray:
    n = s.samples(length)
    t = _t(n)
    f = pitch * (1 + 0.35 * np.exp(-t / 0.03))
    head = s.sine(f, n) * np.exp(-t / (0.35 * length)) + 0.3 * s.sine(f * 1.5, n) * np.exp(-t / 0.06)
    stick = s.bandpass(_rng("tom", pitch, variant).uniform(-1, 1, n), 500, 4000) * np.exp(-t / 0.012) * 0.45
    return _frozen(normalize(drive(head + stick, 1.3)))


@lru_cache(maxsize=None)
def rim_click(pitch: float = 1800.0) -> np.ndarray:
    """Taiko 'ka' / rim click / side stick."""
    n = s.samples(0.08)
    t = _t(n)
    tone = s.sine(np.full(n, pitch), n) * np.exp(-t / 0.012) + 0.6 * s.sine(np.full(n, pitch * 2.3), n) * np.exp(-t / 0.006)
    click = s.bandpass(_rng("rim", pitch).uniform(-1, 1, n), 2000, 7000) * np.exp(-t / 0.004)
    return _frozen(normalize(tone + click * 0.6))


@lru_cache(maxsize=None)
def woodblock(pitch: float = 1000.0, length: float = 0.12) -> np.ndarray:
    n = s.samples(length)
    t = _t(n)
    tone = s.sine(np.full(n, pitch), n) * np.exp(-t / 0.03) + 0.35 * s.sine(np.full(n, pitch * 2.71), n) * np.exp(-t / 0.01)
    return _frozen(normalize(tone))


@lru_cache(maxsize=None)
def log_drum(pitch: float = 330.0, length: float = 0.3) -> np.ndarray:
    """A hollow wooden slit drum (tiki): a quick downward 'bonk'."""
    n = s.samples(length)
    t = _t(n)
    f = pitch * (1 + 0.25 * np.exp(-t / 0.015))
    tone = s.sine(f, n) * np.exp(-t / 0.09) + 0.4 * s.sine(f * 2.02, n) * np.exp(-t / 0.03)
    knock = s.bandpass(_rng("log", pitch).uniform(-1, 1, n), 600, 3000) * np.exp(-t / 0.005) * 0.4
    return _frozen(normalize(tone + knock))


@lru_cache(maxsize=None)
def bongo(pitch: float = 420.0, slap: bool = False) -> np.ndarray:
    n = s.samples(0.25)
    t = _t(n)
    tone = s.sine(pitch * (1 + 0.3 * np.exp(-t / 0.008)), n) * np.exp(-t / (0.04 if slap else 0.08))
    skin = s.bandpass(_rng("bongo", pitch, slap).uniform(-1, 1, n), 1500, 6000) * np.exp(-t / 0.005) * (0.8 if slap else 0.3)
    return _frozen(normalize(tone + skin))


@lru_cache(maxsize=None)
def conga(pitch: float = 220.0, slap: bool = False) -> np.ndarray:
    n = s.samples(0.3)
    t = _t(n)
    tone = s.sine(pitch * (1 + 0.4 * np.exp(-t / 0.01)), n) * np.exp(-t / (0.05 if slap else 0.1))
    skin = s.bandpass(_rng("conga", pitch, slap).uniform(-1, 1, n), 1200, 5000) * np.exp(-t / 0.006) * (0.7 if slap else 0.25)
    return _frozen(normalize(tone + skin))


@lru_cache(maxsize=None)
def doum(pitch: float = 92.0) -> np.ndarray:
    """Darbuka 'doum': the deep middle of the head."""
    n = s.samples(0.45)
    t = _t(n)
    tone = s.sine(pitch * (1 + 0.45 * np.exp(-t / 0.02)), n) * np.exp(-t / 0.16)
    ring = 0.25 * s.sine(np.full(n, pitch * 2.6), n) * np.exp(-t / 0.05)
    slap = s.bandpass(_rng("doum", pitch).uniform(-1, 1, n), 300, 2500) * np.exp(-t / 0.01) * 0.3
    return _frozen(normalize(drive(tone + ring + slap, 1.3)))


@lru_cache(maxsize=None)
def tek(bright: float = 1.0, variant: int = 0) -> np.ndarray:
    """Darbuka 'tek' (bright = 1) or the softer 'ka' (bright < 1): the crisp rim of the drum."""
    n = s.samples(0.12)
    t = _t(n)
    crack = s.bandpass(_rng("tek", bright, variant).uniform(-1, 1, n), 1800, 4500 + 3000 * bright) * np.exp(-t / (0.008 + 0.006 * (1 - bright)))
    shell = s.sine(np.full(n, 720.0), n) * np.exp(-t / 0.035) * 0.5 + s.sine(np.full(n, 1270.0), n) * np.exp(-t / 0.02) * 0.3
    return _frozen(normalize(crack + shell * (0.6 + 0.4 * bright)))


@lru_cache(maxsize=None)
def jingles(length: float = 0.18, bright: float = 1.0, variant: int = 0) -> np.ndarray:
    """Tambourine / riq jingles: a few small cymbals shaken together."""
    n = s.samples(length)
    t = _t(n)
    rng = _rng("jingle", length, bright, variant)
    out = np.zeros(n)
    for _ in range(5):
        start = int(rng.uniform(0, 0.012) * SR)
        m = n - start
        tt = _t(m)
        partials = sum(np.sin(2 * np.pi * rng.uniform(4200, 8200) * tt + rng.uniform(0, 6)) for _ in range(3))
        out[start:] += partials * np.exp(-tt / (0.05 * length / 0.18))
    hiss = s.bandpass(rng.uniform(-1, 1, n), 5000, 11000) * np.exp(-t / 0.03)
    out = eq(out / 15 + hiss * 0.4 * bright, ("lp", 10000), ("hp", 3000))
    return _frozen(normalize(out))


@lru_cache(maxsize=None)
def sleigh(length: float = 0.25, variant: int = 0) -> np.ndarray:
    """A shake of sleigh bells: a cluster of tiny bells, kept gentle (no ice-pick highs)."""
    n = s.samples(length)
    rng = _rng("sleigh", length, variant)
    out = np.zeros(n)
    for _ in range(12):
        start = int(rng.uniform(0, 0.035) * SR)
        m = n - start
        tt = _t(m)
        f = rng.uniform(4300, 7400)
        bell = np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(2 * np.pi * f * 1.62 * tt)
        out[start:] += bell * np.exp(-tt / rng.uniform(0.03, 0.08))
    out = eq(out, ("lp", 9000), ("hp", 3800), ("peak", 3200, -4, 1.0))
    return _frozen(normalize(out))


@lru_cache(maxsize=None)
def cowbell(length: float = 0.3) -> np.ndarray:
    n = s.samples(length)
    t = _t(n)
    tone = s.square(np.full(n, 562.0), n, 0.5) + 0.8 * s.square(np.full(n, 845.0), n, 0.5)
    tone = s.bandpass(tone, 500, 2500) * np.exp(-t / 0.08)
    return _frozen(normalize(tone))


@lru_cache(maxsize=None)
def ride(length: float = 1.2, bell: float = 0.3) -> np.ndarray:
    n = s.samples(length)
    t = _t(n)
    metal = sum(s.square(np.full(n, f), n) for f in (3110, 3790, 4510, 5530, 6370)) / 5
    wash = s.highpass(metal * 0.4 + _rng("ride", bell).uniform(-1, 1, n) * 0.6, 4500) * np.exp(-t / 0.35)
    ping = (np.sin(2 * np.pi * 2350 * t) + 0.5 * np.sin(2 * np.pi * 3720 * t)) * np.exp(-t / 0.25) * bell
    return _frozen(normalize(eq(wash * 0.6 + ping, ("lp", 11000))))


@lru_cache(maxsize=None)
def splash(length: float = 0.9) -> np.ndarray:
    n = s.samples(length)
    t = _t(n)
    return _frozen(normalize(eq(_rng("splash", length).uniform(-1, 1, n), ("hp", 4500), ("lp", 11000)) * np.exp(-t / 0.18)))


@lru_cache(maxsize=None)
def snare2(tone: float = 200.0, snappy: float = 1.0, length: float = 0.28, variant: int = 0) -> np.ndarray:
    """A fuller snare: two head modes plus the wires (snappy 0..1)."""
    n = s.samples(length)
    t = _t(n)
    head = s.sine(tone * (1 + 0.2 * np.exp(-t / 0.01)), n) * np.exp(-t / 0.06) + 0.5 * s.sine(np.full(n, tone * 1.7), n) * np.exp(-t / 0.035)
    wires = eq(_rng("snare", tone, variant).uniform(-1, 1, n), ("hp", 1800), ("lp", 9000), ("peak", 4500, 3, 1.0)) * np.exp(-t / 0.1)
    return _frozen(normalize(drive(head * 0.8 + wires * snappy * 0.9, 1.4)))


@lru_cache(maxsize=None)
def brush(length: float = 0.25, swish: bool = False) -> np.ndarray:
    """Jazz brushes: a tap, or a swish (a slow sweep across the head)."""
    n = s.samples(length)
    t = _t(n)
    noise_ = _rng("brush", length, swish).uniform(-1, 1, n)
    if swish:
        e = np.sin(np.pi * np.clip(t / length, 0, 1)) ** 1.5
        return _frozen(normalize(eq(noise_, ("hp", 2500), ("lp", 7000)) * e) * 0.6)
    return _frozen(normalize(eq(noise_, ("hp", 1500), ("lp", 7500)) * np.exp(-t / 0.04)))


@lru_cache(maxsize=None)
def washboard(length: float = 0.06) -> np.ndarray:
    """One scrape of a thimble on a washboard: a burst of fast metal clicks."""
    n = s.samples(length)
    out = np.zeros(n)
    step = s.samples(0.006)
    rng = _rng("wash", length)
    for i in range(0, n - 40, step):
        m = n - i
        out[i:] += rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / (SR * 0.0012))
    return _frozen(normalize(eq(out, ("hp", 2000), ("lp", 8500))))


@lru_cache(maxsize=None)
def timpani(midi: float, length: float = 1.6, hard: float = 0.8) -> np.ndarray:
    n = s.samples(length)
    t = _t(n)
    f = s.midi_hz(midi)
    tone = np.zeros(n)
    for ratio, amp, dec in ((1.0, 1.0, 0.9), (1.5, 0.5, 0.5), (1.98, 0.3, 0.35), (2.44, 0.18, 0.25)):
        tone += amp * np.sin(2 * np.pi * f * ratio * (1 + 0.01 * np.exp(-t / 0.05)) * t) * np.exp(-t / (dec * length / 1.6))
    mallet = s.bandpass(_rng("timp", midi).uniform(-1, 1, n), 200, 2000) * np.exp(-t / 0.01) * 0.3 * hard
    return _frozen(normalize(tone + mallet))


@lru_cache(maxsize=None)
def gong(length: float = 4.0, pitch: float = 110.0) -> np.ndarray:
    """A temple gong: inharmonic partials that bloom after the hit, then a long shimmer."""
    n = s.samples(length)
    t = _t(n)
    out = np.zeros(n)
    rng = _rng("gong", length, pitch)
    for ratio, amp in ((1.0, 1.0), (1.41, 0.6), (2.03, 0.5), (2.76, 0.35), (3.51, 0.25), (4.69, 0.15)):
        bloom = np.clip(t / (0.05 + 0.1 * ratio), 0, 1)
        out += amp * bloom * np.sin(2 * np.pi * pitch * ratio * t * (1 + 0.004 * np.sin(2 * np.pi * 0.7 * t + rng.uniform(0, 6)))) * np.exp(-t / (length * 0.35 / ratio ** 0.3))
    hit = s.lowpass(rng.uniform(-1, 1, n), 2500) * np.exp(-t / 0.05) * 0.4
    return _frozen(normalize(eq(out + hit, ("lp", 6000))))


@lru_cache(maxsize=None)
def finger_snap() -> np.ndarray:
    n = s.samples(0.12)
    t = _t(n)
    body = s.bandpass(_rng("snap").uniform(-1, 1, n), 1500, 4500) * np.exp(-t / 0.012)
    return _frozen(normalize(body + 0.4 * np.sin(2 * np.pi * 2200 * t) * np.exp(-t / 0.01)))


# ---------------------------------------------------------------- effects & toys

@lru_cache(maxsize=None)
def slide_whistle(start: float, end: float, length: float) -> np.ndarray:
    n = s.samples(length + 0.05)
    t = _t(n)
    pitch = start + (end - start) * np.clip(t / length, 0, 1) ** 0.8 + _vibrato(t, 0.15, 7, 0.0, 0.05)
    tone = s.sine(s.midi_hz(pitch), n) + 0.08 * s.sine(s.midi_hz(pitch + 12), n)
    air = s.bandpass(_rng("slide", start, end).uniform(-1, 1, n), 1500, 6000) * 0.04
    return _frozen(normalize((tone + air) * env(n, 0.02, 0.2, 0.9, 0.05, gate=length)))


@lru_cache(maxsize=None)
def jaw_harp(midi: float, length: float = 0.35) -> np.ndarray:
    """'Boing-oing': a buzzy reed whose mouth formant sweeps up and back."""
    n = s.samples(length + 0.05)
    t = _t(n)
    reed = s.square(s.midi_hz(midi), n, 0.12)
    centre = 500 + 1300 * np.sin(np.pi * np.clip(t / length, 0, 1)) ** 2
    tone = tv_lowpass(reed, centre, q=4.0) - tv_lowpass(reed, centre * 0.5, q=0.7) * 0.6
    return _frozen(normalize(eq(tone, ("hp", 200), ("lp", 4000)) * env(n, 0.005, 0.2, 0.7, 0.05, gate=length)))


@lru_cache(maxsize=None)
def bloop(pitch: float = 120.0, rise: float = 2.0, length: float = 0.18) -> np.ndarray:
    """A lava bubble / water bloop: a sine that swoops up."""
    n = s.samples(length)
    t = _t(n)
    f = pitch * rise ** (t / length)
    return _frozen(normalize(s.sine(f, n) * np.sin(np.pi * np.clip(t / length, 0, 1)) ** 0.7))


@lru_cache(maxsize=None)
def clank(pitch: float = 420.0, length: float = 0.4) -> np.ndarray:
    """A machine's metal clank: inharmonic partials over a low thud."""
    n = s.samples(length)
    t = _t(n)
    metal = sum(a * np.sin(2 * np.pi * pitch * r * t) * np.exp(-t / d) for r, a, d in ((1.0, 1.0, 0.12), (1.47, 0.7, 0.09), (2.31, 0.5, 0.06), (3.12, 0.3, 0.04)))
    thud = s.sine(80 * (1 + np.exp(-t / 0.01)), n) * np.exp(-t / 0.05)
    return _frozen(normalize(eq(metal * 0.7 + thud, ("lp", 7000))))


@lru_cache(maxsize=None)
def ratchet(length: float = 0.25, clicks: int = 8) -> np.ndarray:
    n = s.samples(length)
    out = np.zeros(n)
    for i in range(clicks):
        start = int(i * n / clicks)
        m = n - start
        out[start:] += _rng("ratchet", i).uniform(-1, 1, m) * np.exp(-np.arange(m) / (SR * 0.002))
    return _frozen(normalize(eq(out, ("hp", 1500), ("lp", 7000), ("peak", 3000, 4, 2.0))))


@lru_cache(maxsize=None)
def steam(length: float = 0.5) -> np.ndarray:
    n = s.samples(length)
    t = _t(n)
    e = np.clip(t / 0.03, 0, 1) * np.exp(-t / (length * 0.4))
    return _frozen(normalize(eq(_rng("steam", length).uniform(-1, 1, n), ("hp", 3000), ("lp", 8000)) * e))


@lru_cache(maxsize=None)
def blip(midi: float, length: float = 0.07) -> np.ndarray:
    """A robot's beep: a soft square blip."""
    n = s.samples(length + 0.02)
    tone = s.square(np.full(n, s.midi_hz(midi)), n, 0.5)
    return _frozen(normalize(eq(tone * env(n, 0.002, 0.04, 0.6, 0.015, gate=length), ("lp", 3800), ("hp", 300))))


@lru_cache(maxsize=None)
def whoosh(length: float = 1.0, up: bool = True) -> np.ndarray:
    """A filtered-noise swoosh (sand swirling, wind, a sled carving)."""
    n = s.samples(length)
    t = np.linspace(0, 1, n)
    base = _rng("whoosh", length, up).uniform(-1, 1, n)
    cut = 400 * (12 ** (t if up else 1 - t))
    shape = np.sin(np.pi * t) ** 2
    return _frozen(normalize(tv_lowpass(base, cut, q=2.0) * shape))


@lru_cache(maxsize=None)
def waves(length: float) -> np.ndarray:
    """Gentle surf: slow swells of filtered noise (stereo)."""
    n = s.samples(length)
    t = _t(n)
    rng = _rng("waves", length)
    out = np.zeros((2, n))
    for ch in range(2):
        swell = 0.5 + 0.5 * np.sin(2 * np.pi * t / 5.5 + ch * 1.3) ** 3
        out[ch] = eq(rng.uniform(-1, 1, n), ("lp", 1800), ("hp", 200)) * swell
    return _frozen(normalize(out))


@lru_cache(maxsize=None)
def crackle(length: float) -> np.ndarray:
    """Fire crackle: sparse little pops."""
    n = s.samples(length)
    rng = _rng("crackle", length)
    out = np.zeros(n)
    for _ in range(int(length * 9)):
        start = int(rng.uniform(0, n - 400))
        m = min(400, n - start)
        out[start:start + m] += rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / 30) * rng.uniform(0.2, 1)
    return _frozen(normalize(eq(out, ("hp", 800), ("lp", 6000))))


@lru_cache(maxsize=None)
def orchestra_hit(notes: tuple, length: float = 0.5) -> np.ndarray:
    """Brass, strings and a timpani all at once: the game-show 'ta-da!' stab. Stereo."""
    stack = np.zeros((2, s.samples(length + 0.6)))
    for midi in notes:
        b = s.pan(np.asarray(brass(midi, length * 0.6, bright=1.1, section=2)))
        stack[:, : b.shape[1]] += b[:, : stack.shape[1]]
    st = np.asarray(strings(tuple(notes), length * 0.5, attack=0.005, bright=0.8, release=0.3))
    stack[:, : st.shape[1]] += st[:, : stack.shape[1]] * 0.8
    tp = np.asarray(timpani(min(notes) - 12, 1.0))
    stack[:, : tp.shape[0]] += s.pan(tp)[:, : stack.shape[1]] * 0.5
    return _frozen(normalize(stack))


# --- batch C voices

@lru_cache(maxsize=None)
def snow_crunch(length: float = 0.14, variant: int = 0) -> np.ndarray:
    """A boot or a shovel biting into packed snow: a quick cluster of soft, papery grains."""
    n = s.samples(length)
    rng = _rng("crunch", length, variant)
    out = np.zeros(n)
    for _ in range(14):
        start = int(rng.uniform(0, 0.6) * n)
        m = min(n - start, s.samples(0.012))
        grain = rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / (SR * 0.002)) * rng.uniform(0.3, 1.0)
        out[start:start + m] += grain
    t = _t(n)
    out *= np.exp(-t / (length * 0.45))
    return _frozen(normalize(eq(out, ("hp", 700), ("peak", 1800, 4, 1.0), ("lp", 5500))))


@lru_cache(maxsize=None)
def plunge(length: float = 0.6) -> np.ndarray:
    """Someone dropping into icy water: a short splash and a cartoon 'bloop' falling away."""
    n = s.samples(length)
    t = _t(n)
    splash_ = eq(_rng("plunge", length).uniform(-1, 1, n), ("hp", 500), ("lp", 4000)) * np.clip(t / 0.005, 0, 1) * np.exp(-t / 0.08)
    f = 700 * 0.35 ** np.clip(t / 0.25, 0, 1)
    drop = s.sine(f, n) * np.sin(np.pi * np.clip(t / 0.3, 0, 1)) * 0.8
    return _frozen(normalize(splash_ * 0.7 + drop))


@lru_cache(maxsize=None)
def chip(midi: float, length: float, duty: float = 0.25, vibrato: float = 0.0, slide: float = 0.0) -> np.ndarray:
    """An 8-bit console's pulse channel: a pulse wave with a hard on-off envelope, optional
    delayed vibrato and a slide into the note, softened just enough for small speakers."""
    n = s.samples(length + 0.03)
    t = _t(n)
    pitch = midi + _vibrato(t, vibrato, 6.0, 0.15, 0.1)
    if slide:
        pitch = pitch - slide * np.exp(-t / 0.03)
    tone = s.square(s.midi_hz(pitch), n, duty)
    e = env(n, 0.003, 0.25, 0.75, 0.02, gate=length)
    return _frozen(normalize(eq(tone * e, ("lp", 6000), ("hp", 120))))


@lru_cache(maxsize=None)
def chip_tri(midi: float, length: float) -> np.ndarray:
    """The console's triangle channel, used for the bass: a stepped triangle (its 4-bit staircase
    adds upper harmonics) doubled by a quiet narrow pulse, whose bright 2nd-5th harmonics are what
    a phone's speaker actually plays."""
    n = s.samples(length + 0.02)
    phase, _ = s.phase_of(s.midi_hz(midi), n)
    tri = 2 * np.abs(2 * phase - 1) - 1
    tri = np.round(tri * 7.5) / 7.5
    tone = tri + 0.65 * s.square(s.midi_hz(midi), n, 0.25)
    e = env(n, 0.002, 0.3, 0.85, 0.015, gate=length)
    return _frozen(normalize(eq(tone * e, ("lp", 4000))))


@lru_cache(maxsize=None)
def chip_noise(length: float = 0.08, tone: float = 1.0, variant: int = 0) -> np.ndarray:
    """The console's noise channel: a sample-and-hold noise (a snare at tone ~1, a hat at 2)."""
    n = s.samples(length)
    rng = _rng("chipnoise", length, tone, variant)
    hold = max(1, int(6 / tone))
    raw = np.repeat(rng.choice((-1.0, 1.0), n // hold + 1), hold)[:n]
    t = _t(n)
    return _frozen(normalize(eq(raw * np.exp(-t / (length * 0.3)), ("hp", 400 * tone), ("lp", 9000))))


@lru_cache(maxsize=None)
def piano(midi: float, length: float = 0.8, bright: float = 0.6) -> np.ndarray:
    """An acoustic piano: struck, slightly stretched partials that die faster the higher they are,
    a felt hammer's thump and two strings beating a little against each other. Stereo."""
    n = s.samples(length + 0.6)
    t = _t(n)
    f = s.midi_hz(midi)
    decay = 2.2 * (261.6 / f) ** 0.45
    out = np.zeros(n)
    for k in range(1, 13):
        fk = f * k * (1 + 0.0004 * k * k)
        if fk > 12000:
            break
        amp = (1 / k ** (1.4 - 0.5 * bright)) * (1 if k != 7 else 0.3)
        for d in (-0.6, 0.6):
            out += amp * 0.5 * np.sin(2 * np.pi * fk * (1 + d / 1200) * t + k) * np.exp(-t * k ** 0.6 / decay)
    hammer = s.lowpass(_rng("hammer", midi).uniform(-1, 1, n), 1200 + 2500 * bright) * np.exp(-t / 0.008) * 0.25
    tone = (out + hammer) * np.clip(t / 0.002, 0, 1)
    tone = tone * np.where(t < length, 1.0, np.exp(-(t - length) / 0.09))
    tone = normalize(eq(tone, ("hp", 60)))
    pan_pos = float(np.clip((midi - 64) / 30, -0.5, 0.5))
    return _frozen(s.pan(tone, pan_pos))
