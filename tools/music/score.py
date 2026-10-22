"""Writing music down in code, and mixing it, for the mini-games' own round tracks (modes.py).

Owner: "put in the backlog custom music for each mini game".

Melodies, chords and drum patterns are short strings, so a song reads like a lead sheet:

    melody  "D5:4 F5:2 G5:2 A5:8 | ..."   notes as name+octave with a length in grid steps, "r" a rest,
            "~" ties onto the note before (across bar lines too). A trailing "!" accents a note, "'"
            plays it softly. Every bar ("|") must add up to exactly one bar, or rendering stops.
    chords  "Dm | Bb C | Gm7/F"           one bar per "|"; two chords in a bar split it in half, four in quarters.
    drums   "X...x...X...x..o"            one character per grid step: X accent, x hit, o ghost, . rest.

The grid has 16 steps a bar (16th notes) or 12 (triplet 8ths, for shuffles, jigs and swing).

Mixing: every stem wraps around (a note ringing past the loop point continues at its start), the
reverb and delays wrap too, and the master's filters and limiter run circularly, so a track loops
without a seam. The master aims at a loudness (LUFS, ITU-R BS.1770) with true peaks under -1 dBTP.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

import numpy as np
from scipy import ndimage, signal

import instruments as ins
import synth as s

SR = s.SR


# ---------------------------------------------------------------- notation

NOTE_RE = re.compile(r"^([A-G])([#b]?)(-?\d)$")
TOKEN_RE = re.compile(r"^([^:!']+?)(?::([\d.]+))?([!']?)$")


def midi(name: str) -> int:
    m = NOTE_RE.match(name)
    if not m:
        raise ValueError(f"not a note: {name!r}")
    return 12 * (int(m.group(3)) + 1) + s.NOTE_INDEX[m.group(1) + m.group(2)]


@dataclass
class Note:
    step: float  # from the start of the phrase, in grid steps
    midi: int
    length: float  # grid steps
    vel: float


def melody(text: str, spb: int = 16) -> list[Note]:
    notes: list[Note] = []
    pos = 0.0
    last = 4.0
    for index, bar in enumerate(text.split("|")):
        tokens = bar.split()
        start = pos
        for token in tokens:
            m = TOKEN_RE.match(token)
            if not m:
                raise ValueError(f"bad token {token!r} in bar {index + 1}: {bar!r}")
            name, length, mark = m.group(1), m.group(2), m.group(3)
            length = float(length) if length else last
            last = length
            if name == "~":
                if not notes:
                    raise ValueError("a tie needs a note before it")
                notes[-1].length += length
            elif name not in ("r", "-"):
                vel = 1.0 if mark == "!" else (0.6 if mark == "'" else 0.85)
                notes.append(Note(pos, midi(name), length, vel))
            pos += length
        if abs((pos - start) - spb) > 1e-6:
            raise ValueError(f"bar {index + 1} lasts {pos - start} steps, not {spb}: {bar.strip()!r}")
    return notes


def shift(notes: list[Note], semitones: int = 0, steps: float = 0.0) -> list[Note]:
    return [Note(n.step + steps, n.midi + semitones, n.length, n.vel) for n in notes]


def hits(pattern: str, spb: int = 16) -> list[tuple[float, float]]:
    """(step, velocity) for every hit; a pattern with "|" spans several bars."""
    out = []
    for index, bar in enumerate(pattern.split("|")):
        bar = bar.strip()
        if len(bar) != spb:
            raise ValueError(f"drum bar {index + 1} has {len(bar)} steps, not {spb}: {bar!r}")
        for step, ch in enumerate(bar):
            vel = {"X": 1.0, "x": 0.8, "o": 0.45}.get(ch)
            if vel:
                out.append((index * spb + step, vel))
    return out


CHORDS = {
    "": (0, 4, 7), "m": (0, 3, 7), "5": (0, 7), "dim": (0, 3, 6), "aug": (0, 4, 8), "sus2": (0, 2, 7),
    "sus4": (0, 5, 7), "6": (0, 4, 7, 9), "m6": (0, 3, 7, 9), "7": (0, 4, 7, 10), "maj7": (0, 4, 7, 11),
    "m7": (0, 3, 7, 10), "mmaj7": (0, 3, 7, 11), "dim7": (0, 3, 6, 9), "m7b5": (0, 3, 6, 10),
    "7sus4": (0, 5, 7, 10), "add9": (0, 4, 7, 14), "madd9": (0, 3, 7, 14), "9": (0, 4, 7, 10, 14),
    "maj9": (0, 4, 7, 11, 14), "m9": (0, 3, 7, 10, 14), "6/9": (0, 4, 7, 9, 14), "7b9": (0, 4, 7, 10, 13),
}
CHORD_RE = re.compile(r"^([A-G][#b]?)([^/]*)(?:/([A-G][#b]?))?$")


@dataclass
class Chord:
    root: int  # pitch class 0..11
    intervals: tuple
    bass: int  # pitch class of the bass note
    name: str

    def tones(self) -> list[int]:
        return sorted({(self.root + i) % 12 for i in self.intervals})


def chord(symbol: str) -> Chord:
    m = CHORD_RE.match(symbol)
    if not m or m.group(2) not in CHORDS:
        raise ValueError(f"unknown chord {symbol!r}")
    root = s.NOTE_INDEX[m.group(1)]
    bass = s.NOTE_INDEX[m.group(3)] if m.group(3) else root
    return Chord(root, CHORDS[m.group(2)], bass, symbol)


def chords(text: str, spb: int = 16) -> list[tuple[float, float, Chord]]:
    """(step, length, chord) for each chord in a progression, from its start."""
    out = []
    for index, bar in enumerate(text.split("|")):
        symbols = bar.split()
        if not symbols:
            raise ValueError(f"empty chord bar {index + 1}")
        each = spb / len(symbols)
        for k, symbol in enumerate(symbols):
            out.append((index * spb + k * each, each, chord(symbol)))
    return out


def voicing(c: Chord, low: int, high: int, previous: list[int] | None = None, size: int | None = None) -> list[int]:
    """Close voicing of a chord inside [low, high] that moves least from the previous one."""
    pcs = [(c.root + i) % 12 for i in c.intervals]
    size = size or len(pcs)
    best, best_score = None, None
    for base in range(low, high + 1):
        if base % 12 not in pcs:
            continue
        notes = [base]
        order = pcs[pcs.index(base % 12):] + pcs[: pcs.index(base % 12)]
        for pc in order[1:]:
            nxt = notes[-1] + ((pc - notes[-1]) % 12 or 12)
            notes.append(nxt)
        while len(notes) < size:
            notes.append(notes[len(notes) - len(pcs)] + 12)
        notes = notes[:size]
        if notes[-1] > high:
            continue
        if previous:
            score = sum(abs(a - b) for a, b in zip(sorted(notes), sorted(previous)))
        else:
            score = abs(np.mean(notes) - (low + high) / 2)
        if best_score is None or score < best_score:
            best, best_score = notes, score
    if best is None:
        raise ValueError(f"no voicing of {c.name} in {low}..{high}")
    return best


def bass_note(c: Chord, low: int = 28) -> int:
    """The chord's bass note in the octave starting at `low`."""
    return low + (c.bass - low) % 12


# ---------------------------------------------------------------- the track

class Track:
    """A loop of `bars` bars at `bpm` (4 beats a bar), on a grid of `spb` steps per bar. `swing`
    delays every off-beat 8th (spb 16) by that fraction of a 16th."""

    def __init__(self, bpm: float, bars: int, spb: int = 16, swing: float = 0.0):
        self.bpm = bpm
        self.spb = spb
        self.beat = 60 / bpm
        self.bar = self.beat * 4
        self.step = self.bar / spb
        self.bars = bars
        self.length = self.bar * bars
        self.swing = swing
        self.stems: dict[str, s.Timeline] = {}
        self.kicks: list[float] = []

    def t(self, bar: float, step: float = 0.0) -> float:
        when = bar * self.bar + step * self.step
        if self.swing and self.spb == 16 and abs((step % 4) - 2) < 1e-6:
            when += self.swing * self.step
        return when % self.length

    def stem(self, name: str) -> s.Timeline:
        if name not in self.stems:
            self.stems[name] = s.Timeline(self.length, wrap=True)
        return self.stems[name]

    def add(self, stem: str, bar: float, step: float, sound: np.ndarray, gain: float = 1.0, pan: float = 0.0):
        self.stem(stem).add(self.t(bar, step), np.asarray(sound), gain, pan)

    def play(self, stem: str, bar: float, notes: list[Note], voice, gain: float = 1.0, pan: float = 0.0,
             transpose: int = 0, legato: float = 1.0, humanize: float = 0.0):
        """Plays notes starting at `bar` with `voice(midi, seconds)`."""
        rng = np.random.default_rng(int(bar * 1000 + len(notes)))
        for n in notes:
            seconds = max(0.03, n.length * self.step * legato)
            vel = n.vel * (1 + rng.uniform(-humanize, humanize)) if humanize else n.vel
            self.add(stem, bar, n.step, voice(n.midi + transpose, seconds), gain * vel, pan)

    def drum(self, stem: str, bar: float, pattern: str, sound, gain: float = 1.0, pan: float = 0.0):
        for step, vel in hits(pattern, self.spb):
            self.add(stem, bar, step, sound, gain * vel, pan)

    def kick(self, stem: str, bar: float, pattern: str, sound, gain: float = 1.0):
        """Like drum(), and remembers each hit for the sidechain pump."""
        for step, vel in hits(pattern, self.spb):
            self.add(stem, bar, step, sound, gain * vel)
            self.kicks.append(self.t(bar, step))


# ---------------------------------------------------------------- mixing

def circular(fn, x: np.ndarray, pad: float = 1.0) -> np.ndarray:
    """Runs a filter as if the loop had been playing already: warm it up on the loop's own end."""
    p = min(x.shape[-1], s.samples(pad))
    y = fn(np.concatenate([x[..., -p:], x], axis=-1))
    return y[..., p:]


def reverb_wet(x: np.ndarray, decay: float = 1.6, tone: float = 5500, predelay: float = 0.015, seed: int = 7) -> np.ndarray:
    """Wet-only convolution reverb (decorrelated stereo), its tail wrapped round the loop."""
    n = s.samples(decay * 1.5)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    envelope = np.exp(-t * 6.9 / decay) * np.clip(t / 0.02, 0, 1)
    ir = np.vstack([s.lowpass(rng.uniform(-1, 1, n), tone) * envelope for _ in range(2)])
    ir[:, : s.samples(predelay)] = 0
    ir /= np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))
    length = x.shape[1]
    wet = np.vstack([signal.oaconvolve(x[i], ir[i]) for i in range(2)])
    out = wet[:, :length].copy()
    tail = wet[:, length:]
    while tail.shape[1] > 0:
        take = min(length, tail.shape[1])
        out[:, :take] += tail[:, :take]
        tail = tail[:, take:]
    return out


def spring_wet(x: np.ndarray, decay: float = 2.2) -> np.ndarray:
    """A guitar amp's spring reverb: a dark plate with a metallic 'drip' (comb resonances)."""
    wet = reverb_wet(x, decay=decay, tone=4200, predelay=0.02, seed=11)
    combs = np.zeros_like(wet)
    for delay_ms, fb in ((29.7, 0.72), (37.1, 0.7), (41.3, 0.68)):
        d = s.samples(delay_ms / 1000)
        a = np.zeros(d + 1)
        a[0], a[d] = 1.0, -fb
        combs += circular(lambda y, a=a: signal.lfilter([1.0], a, y, axis=-1), x, pad=1.5) * 0.12
    return wet + ins.eq(combs, ("hp", 600), ("lp", 4500))


def delay_wet(x: np.ndarray, time: float, feedback: float = 0.35, taps: int = 6, tone: float = 4500, ping_pong: bool = True) -> np.ndarray:
    length = x.shape[1]
    mono = x.mean(axis=0)
    out = np.zeros_like(x)
    d = s.samples(time)
    for tap in range(1, taps + 1):
        shifted = np.roll(mono, d * tap)
        gain = feedback ** (tap - 1)
        if ping_pong:
            out[tap % 2] += shifted * gain
        else:
            out += shifted * gain * 0.7
    return circular(lambda y: s.lowpass(y, tone), out[:, :length])


@dataclass
class Bus:
    level: float | None = None  # loudness relative to the whole mix (LU) while it plays; sets the gain
    pump: float = 0.0  # sidechain depth (0..1) from the track's kicks
    reverb: float = 0.0  # send level
    delay: float = 0.0
    spring: float = 0.0
    eq: tuple = ()
    width: float = 1.0  # 0 = mono, 1 = as is
    drive: float = 0.0  # gentle saturation (tames drum peaks)
    gain: float = 1.0  # used when no level is given


@dataclass
class Mix:
    buses: dict = field(default_factory=dict)
    reverb_decay: float = 1.6
    reverb_tone: float = 5500
    delay_time: float = 0.375
    delay_feedback: float = 0.35
    pump_release: float = 0.2
    target_lufs: float = -11.0


def bus_signals(track: Track, mix: Mix) -> dict[str, np.ndarray]:
    """Each stem after its bus processing (EQ, drive, width, pump), before its gain."""
    length = s.samples(track.length)
    pump = s.sidechain(length, sorted(set(track.kicks)), depth=1.0, release=mix.pump_release) if track.kicks else np.ones(length)
    out = {}
    for name, stem in track.stems.items():
        bus = mix.buses.get(name, Bus())
        x = stem.buffer[:, :length]
        if bus.eq:
            x = circular(lambda y, b=bus.eq: ins.eq(y, *b), x)
        if bus.drive:
            x = np.tanh(x * bus.drive) / bus.drive
        if bus.width != 1.0:
            mid = x.mean(axis=0)
            x = np.vstack([mid + (x[0] - mid) * bus.width, mid + (x[1] - mid) * bus.width])
        if bus.pump:
            x = x * (1 - bus.pump * (1 - pump))
        out[name] = x
    return out


def balance(signals: dict[str, np.ndarray], mix: Mix) -> dict[str, float]:
    """Bus gains that put every bus with a `level` that many LU from the whole (dry) mix."""
    base = {name: lufs(x) for name, x in signals.items() if np.any(x)}
    gains = {name: mix.buses.get(name, Bus()).gain for name in signals}
    for _ in range(6):
        total = lufs(sum(x * gains[name] for name, x in signals.items()))
        for name in base:
            level = mix.buses.get(name, Bus()).level
            if level is not None:
                gains[name] = 10 ** ((total + level - base[name]) / 20)
    return gains


def mixdown(track: Track, mix: Mix) -> np.ndarray:
    length = s.samples(track.length)
    dry = np.zeros((2, length))
    sends = {"reverb": np.zeros((2, length)), "delay": np.zeros((2, length)), "spring": np.zeros((2, length))}
    signals = bus_signals(track, mix)
    gains = balance(signals, mix)
    for name, x in signals.items():
        bus = mix.buses.get(name, Bus())
        x = x * gains[name]
        dry += x
        sends["reverb"] += x * bus.reverb
        sends["delay"] += x * bus.delay
        sends["spring"] += x * bus.spring
    out = dry
    if np.any(sends["reverb"]):
        out = out + reverb_wet(sends["reverb"], mix.reverb_decay, mix.reverb_tone)
    if np.any(sends["delay"]):
        out = out + delay_wet(sends["delay"], mix.delay_time, mix.delay_feedback)
    if np.any(sends["spring"]):
        out = out + spring_wet(sends["spring"])
    return out


# ---------------------------------------------------------------- loudness & master

def _k_weight(x: np.ndarray) -> np.ndarray:
    f0, g, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    k = np.tan(np.pi * f0 / SR)
    vh = 10 ** (g / 20)
    vb = vh ** 0.4996667741545416
    a0 = 1 + k / q + k * k
    y = signal.lfilter([(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0],
                       [1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0], x, axis=-1)
    f0, q = 38.13547087602444, 0.5003270373238773
    k = np.tan(np.pi * f0 / SR)
    a0 = 1 + k / q + k * k
    return signal.lfilter([1, -2, 1], [1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0], y, axis=-1)


def lufs(x: np.ndarray) -> float:
    """Integrated loudness (ITU-R BS.1770-4) of a loop, measured as it plays round."""
    y = circular(_k_weight, x, pad=0.5)
    power = (y ** 2).sum(axis=0)
    block, hop = int(0.4 * SR), int(0.1 * SR)
    csum = np.concatenate([[0], np.cumsum(np.concatenate([power, power[:block]]))])
    starts = np.arange(0, len(power), hop)
    ms = (csum[starts + block] - csum[starts]) / block
    level = -0.691 + 10 * np.log10(ms + 1e-12)
    ms = ms[level > -70]
    rel = -0.691 + 10 * np.log10(ms.mean() + 1e-12) - 10
    level = -0.691 + 10 * np.log10(ms + 1e-12)
    return float(-0.691 + 10 * np.log10(ms[level > rel].mean() + 1e-12))


def true_peak_db(x: np.ndarray) -> float:
    up = signal.resample_poly(np.concatenate([x[:, -64:], x, x[:, :64]], axis=1), 4, 1, axis=-1)
    return float(20 * np.log10(np.max(np.abs(up)) + 1e-12))


def limiter(x: np.ndarray, ceiling_db: float = -1.4, window: float = 0.005) -> np.ndarray:
    """Look-ahead brickwall limiter (stereo-linked, loop-aware): the gain ramps down over `window`
    before a peak and back up after it, never letting a sample past the ceiling."""
    ceiling = 10 ** (ceiling_db / 20)
    peak = np.max(np.abs(x), axis=0)
    need = np.minimum(1.0, ceiling / np.maximum(peak, 1e-9))
    size = 2 * s.samples(window) + 1
    gain = ndimage.minimum_filter1d(need, size, mode="wrap")
    gain = ndimage.uniform_filter1d(gain, size, mode="wrap")
    return x * gain


def master(x: np.ndarray, target_lufs: float = -11.0, ceiling_dbtp: float = -1.5) -> np.ndarray:
    x = circular(lambda y: ins.eq(y, ("hp", 32), ("hp", 32)), x)
    gain = 10 ** ((target_lufs - lufs(x)) / 20)
    ceiling = ceiling_dbtp - 0.5
    y = x
    for _ in range(8):
        y = limiter(x * gain, ceiling)
        level = lufs(y)
        peak = true_peak_db(y)
        if peak > ceiling_dbtp:
            ceiling -= peak - ceiling_dbtp + 0.05
            continue
        if abs(level - target_lufs) < 0.05:
            break
        gain *= 10 ** ((target_lufs - level) / 20)
    return y
