"""A tiny synthesizer, sequencer and mixer used to render Party Panic's original soundtrack.

Everything here is generated from math (oscillators, filtered noise, FM), so the resulting audio
is original and free of licensing concerns. Rendering needs numpy and scipy; encoding uses ffmpeg.
"""

from __future__ import annotations

import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
RNG = np.random.default_rng(1234)


# ---------------------------------------------------------------- basics

def seconds(n: int) -> float:
    return n / SR


def samples(duration: float) -> int:
    return max(1, int(round(duration * SR)))


def midi_hz(note: float) -> float:
    return 440.0 * 2 ** ((note - 69) / 12)


NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
              "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def note(name: str) -> int:
    """'F#4' -> 66"""
    letters = name[:-1]
    octave = int(name[-1])
    return 12 * (octave + 1) + NOTE_INDEX[letters]


def db(value: float) -> float:
    return 10 ** (value / 20)


# ---------------------------------------------------------------- oscillators

def _poly_blep(phase: np.ndarray, step: np.ndarray) -> np.ndarray:
    out = np.zeros_like(phase)
    low = phase < step
    t = phase[low] / step[low]
    out[low] = t + t - t * t - 1
    high = phase > 1 - step
    t = (phase[high] - 1) / step[high]
    out[high] = t * t + t + t + 1
    return out


def phase_of(freq: np.ndarray | float, n: int, start: float = 0.0) -> tuple[np.ndarray, np.ndarray]:
    freq_arr = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    step = freq_arr / SR
    phase = (start + np.cumsum(step) - step[0]) % 1.0
    return phase, step


def saw(freq, n: int, start: float = 0.0) -> np.ndarray:
    """Band-limited sawtooth (polyBLEP) - bright without harsh aliasing."""
    phase, step = phase_of(freq, n, start)
    return 2 * phase - 1 - _poly_blep(phase, step)


def square(freq, n: int, width: float = 0.5, start: float = 0.0) -> np.ndarray:
    phase, step = phase_of(freq, n, start)
    out = np.where(phase < width, 1.0, -1.0)
    out += _poly_blep(phase, step)
    out -= _poly_blep((phase + 1 - width) % 1.0, step)
    return out


def sine(freq, n: int, start: float = 0.0) -> np.ndarray:
    phase, _ = phase_of(freq, n, start)
    return np.sin(2 * np.pi * phase)


def noise(n: int) -> np.ndarray:
    return RNG.uniform(-1, 1, n)


# ---------------------------------------------------------------- envelopes & filters

def adsr(n: int, attack: float, decay: float, sustain: float, release: float, gate: float | None = None) -> np.ndarray:
    """Envelope of n samples. The note is held for `gate` seconds, then released."""
    env = np.zeros(n)
    a = samples(attack)
    d = samples(decay)
    g = n - samples(release) if gate is None else min(n, samples(gate))
    g = max(1, g)
    idx = np.arange(n)
    env = np.where(idx < a, idx / max(a, 1), 0)
    decay_part = (idx >= a) & (idx < a + d)
    env = np.where(decay_part, 1 - (1 - sustain) * (idx - a) / max(d, 1), env)
    env = np.where((idx >= a + d) & (idx < g), sustain, env)
    level_at_gate = env[g - 1] if g - 1 < n else sustain
    rel = idx >= g
    r = max(samples(release), 1)
    env = np.where(rel, level_at_gate * np.clip(1 - (idx - g) / r, 0, 1), env)
    return env


def exp_decay(n: int, time: float) -> np.ndarray:
    return np.exp(-np.arange(n) / (time * SR))


def _sos(kind: str, cutoff, order: int = 2):
    nyq = SR / 2
    if isinstance(cutoff, (tuple, list)):
        wn = [min(c / nyq, 0.99) for c in cutoff]
    else:
        wn = min(cutoff / nyq, 0.99)
    return signal.butter(order, wn, btype=kind, output="sos")


def lowpass(x: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("low", cutoff, order), x, axis=-1)


def highpass(x: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("high", cutoff, order), x, axis=-1)


def bandpass(x: np.ndarray, low: float, high: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("band", (low, high), order), x, axis=-1)


def sweep_lowpass(x: np.ndarray, start: float, end: float, blocks: int = 64) -> np.ndarray:
    """Low-pass whose cutoff glides exponentially from start to end (block-wise, smooth enough)."""
    out = np.zeros_like(x)
    edges = np.linspace(0, x.shape[-1], blocks + 1).astype(int)
    zi = None
    for i in range(blocks):
        cutoff = start * (end / start) ** (i / max(blocks - 1, 1))
        sos = _sos("low", cutoff, 2)
        if zi is None:
            zi = np.zeros((sos.shape[0], 2)) if x.ndim == 1 else np.zeros((sos.shape[0], x.shape[0], 2))
        seg = x[..., edges[i]:edges[i + 1]]
        if x.ndim == 1:
            y, zi = signal.sosfilt(sos, seg, zi=zi)
        else:
            y, zi = signal.sosfilt(sos, seg, axis=-1, zi=zi)
        out[..., edges[i]:edges[i + 1]] = y
    return out


def soft_clip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def pan(mono: np.ndarray, position: float = 0.0) -> np.ndarray:
    """Equal-power pan; position -1 (left) .. 1 (right)."""
    angle = (position + 1) * np.pi / 4
    return np.vstack([mono * np.cos(angle), mono * np.sin(angle)])


# ---------------------------------------------------------------- instruments (mono unless noted)

def kick(punch: float = 1.0, length: float = 0.45) -> np.ndarray:
    n = samples(length)
    t = np.arange(n) / SR
    freq = 45 + 120 * np.exp(-t / 0.035) * punch
    body = sine(freq, n) * exp_decay(n, 0.16)
    click = highpass(noise(n), 2500) * exp_decay(n, 0.004) * 0.5
    return soft_clip((body + click) * 1.4, 1.6)


def clap(length: float = 0.35) -> np.ndarray:
    n = samples(length)
    out = np.zeros(n)
    burst = bandpass(noise(n), 900, 2600)
    for offset, gain in ((0.0, 0.8), (0.011, 0.7), (0.022, 1.0)):
        start = samples(offset)
        env = exp_decay(n - start, 0.012 if gain < 1 else 0.11)
        out[start:] += burst[: n - start] * env * gain
    return out * 1.2


def snare(length: float = 0.3) -> np.ndarray:
    n = samples(length)
    tone = sine(np.full(n, 190.0), n) * exp_decay(n, 0.05)
    rattle = bandpass(noise(n), 1800, 9000) * exp_decay(n, 0.09)
    return (tone * 0.7 + rattle) * 0.9


def hat(open_: bool = False) -> np.ndarray:
    n = samples(0.3 if open_ else 0.06)
    metal = sum(square(f, n) for f in (2860, 3370, 4120, 5280, 6620, 8100)) / 6
    body = highpass(metal * 0.5 + noise(n) * 0.5, 7000)
    return body * exp_decay(n, 0.09 if open_ else 0.014)


def shaker() -> np.ndarray:
    n = samples(0.08)
    return bandpass(noise(n), 5000, 12000) * adsr(n, 0.01, 0.05, 0.0, 0.02)


def crash(length: float = 2.2) -> np.ndarray:
    n = samples(length)
    return highpass(noise(n), 5000) * exp_decay(n, 0.7) * 0.6


def supersaw(notes: list[float], duration: float, cutoff: float = 6000, voices: int = 7,
             detune: float = 0.18, attack: float = 0.01, release: float = 0.25, sustain: float = 0.85,
             decay: float = 0.2) -> np.ndarray:
    """Stereo detuned saw stack - the big, bright 'party' chord sound."""
    n = samples(duration + release)
    out = np.zeros((2, n))
    for midi in notes:
        for v in range(voices):
            spread = (v - (voices - 1) / 2) / ((voices - 1) / 2)
            freq = midi_hz(midi + spread * detune)
            wave_ = saw(freq, n, start=RNG.random())
            out += pan(wave_, spread * 0.8)
    out /= voices * max(len(notes), 1) ** 0.6
    out = lowpass(out, cutoff)
    env = adsr(n, attack, decay, sustain, release, gate=duration)
    return out * env


def pluck(midi: float, duration: float, brightness: float = 4500, wave_: str = "saw") -> np.ndarray:
    n = samples(duration + 0.25)
    freq = midi_hz(midi)
    osc = saw(freq, n) if wave_ == "saw" else square(freq, n, 0.35)
    env = exp_decay(n, max(0.06, duration * 0.6))
    filtered = sweep_lowpass(osc * env, brightness, max(400, brightness * 0.15), blocks=16)
    return filtered


def fm_bell(midi: float, duration: float, ratio: float = 3.5, index: float = 2.2, decay: float = 0.9) -> np.ndarray:
    """FM bell / marimba. Low ratio + short decay = woody marimba; higher = glassy bell."""
    n = samples(duration + decay)
    t = np.arange(n) / SR
    freq = midi_hz(midi)
    mod_env = index * np.exp(-t / (decay * 0.25))
    modulator = np.sin(2 * np.pi * freq * ratio * t) * mod_env
    carrier = np.sin(2 * np.pi * freq * t + modulator)
    amp = np.exp(-t / (decay * 0.5)) * np.clip(t / 0.002, 0, 1)
    return carrier * amp


def bass(midi: float, duration: float, cutoff: float = 900, sub: float = 0.6) -> np.ndarray:
    n = samples(duration + 0.06)
    freq = midi_hz(midi)
    body = saw(freq, n) * 0.6 + square(freq, n, 0.5) * 0.3
    body = sweep_lowpass(body, cutoff * 2.2, cutoff, blocks=8)
    low = sine(freq, n) * sub
    env = adsr(n, 0.004, 0.08, 0.75, 0.05, gate=duration)
    return soft_clip((body + low) * env, 1.3)


def lead(midi: float, duration: float, cutoff: float = 5200, vibrato: float = 0.12) -> np.ndarray:
    """Stereo lead: two detuned saws with delayed vibrato."""
    n = samples(duration + 0.18)
    t = np.arange(n) / SR
    depth = vibrato * np.clip((t - 0.18) / 0.25, 0, 1)
    cents = depth * np.sin(2 * np.pi * 5.5 * t)
    left = saw(midi_hz(midi - 0.07) * 2 ** (cents / 12), n)
    right = saw(midi_hz(midi + 0.07) * 2 ** (cents / 12), n)
    stereo = np.vstack([left, right]) * 0.5 + square(midi_hz(midi - 12), n, 0.5) * 0.18
    stereo = lowpass(stereo, cutoff)
    return stereo * adsr(n, 0.008, 0.12, 0.8, 0.16, gate=duration)


def riser(duration: float) -> np.ndarray:
    n = samples(duration)
    t = np.linspace(0, 1, n)
    swept = sweep_lowpass(noise(n), 300, 12000, blocks=48)
    tone = sine(200 * 2 ** (t * 4), n) * 0.25
    return (swept * 0.8 + tone) * t ** 2


def downlifter(duration: float) -> np.ndarray:
    n = samples(duration)
    t = np.linspace(0, 1, n)
    return sweep_lowpass(noise(n), 9000, 200, blocks=32) * (1 - t) ** 2


def impact() -> np.ndarray:
    n = samples(1.5)
    t = np.arange(n) / SR
    boom = sine(30 + 60 * np.exp(-t / 0.08), n) * exp_decay(n, 0.5)
    hiss = lowpass(noise(n), 3000) * exp_decay(n, 0.25) * 0.4
    return boom + hiss


# ---------------------------------------------------------------- timeline & effects

class Timeline:
    """A stereo buffer you drop sounds onto by time (seconds)."""

    def __init__(self, duration: float, wrap: bool = False):
        self.buffer = np.zeros((2, samples(duration)))
        self.wrap = wrap  # loop-friendly buffers wrap tails around to the start

    @property
    def length(self) -> int:
        return self.buffer.shape[1]

    def add(self, time: float, sound: np.ndarray, gain: float = 1.0, position: float = 0.0, wrap: bool | None = None):
        wrap = self.wrap if wrap is None else wrap
        stereo = sound if sound.ndim == 2 else pan(sound, position)
        start = samples(time) if time > 0 else 0
        end = start + stereo.shape[1]
        if end <= self.length:
            self.buffer[:, start:end] += stereo * gain
            return
        fit = self.length - start
        if fit > 0:
            self.buffer[:, start:] += stereo[:, :fit] * gain
        if wrap:
            # Loop-friendly: the tail wraps around to the start of the buffer.
            tail = stereo[:, max(fit, 0):] * gain
            self.buffer[:, : tail.shape[1]] += tail[:, : self.length]

    def mix(self, other: "Timeline", gain: float = 1.0):
        self.buffer += other.buffer * gain


def reverb(stereo: np.ndarray, decay: float = 1.6, mix: float = 0.25, tone: float = 6000, wrap: bool = False) -> np.ndarray:
    """Convolution reverb with a synthetic, decorrelated stereo impulse response."""
    n = samples(decay * 1.6)
    t = np.arange(n) / SR
    env = np.exp(-t * 6.9 / decay)
    ir = np.vstack([lowpass(noise(n), tone) * env, lowpass(noise(n), tone) * env])
    ir[:, : samples(0.012)] = 0  # short pre-delay
    ir /= np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))
    wet = np.vstack([signal.oaconvolve(stereo[i], ir[i]) for i in range(2)])
    length = stereo.shape[1]
    if wrap:
        tail = wet[:, length:]
        wet = wet[:, :length].copy()
        wet[:, : min(tail.shape[1], length)] += tail[:, :length]
    else:
        wet = wet[:, :length]
    return stereo * (1 - mix * 0.5) + wet * mix


def ping_pong(stereo: np.ndarray, delay: float, feedback: float = 0.4, mix: float = 0.3, taps: int = 6, wrap: bool = False) -> np.ndarray:
    out = stereo.copy()
    d = samples(delay)
    mono = stereo.mean(axis=0)
    length = stereo.shape[1]
    for tap in range(1, taps + 1):
        gain = mix * feedback ** (tap - 1)
        channel = tap % 2
        shifted = np.zeros(length)
        offset = d * tap
        if offset < length:
            shifted[offset:] = mono[: length - offset]
            if wrap:
                shifted[:offset] = mono[length - offset:]
        out[channel] += lowpass(shifted, 5000) * gain
    return out


def sidechain(length: int, kick_times: list[float], depth: float = 0.7, release: float = 0.22) -> np.ndarray:
    """Gain curve that ducks on every kick and recovers - the classic dance 'pump'."""
    gain = np.ones(length)
    r = samples(release)
    curve = 1 - depth * (1 - np.clip(np.arange(r) / r, 0, 1)) ** 2
    for time in kick_times:
        start = samples(time)
        end = min(length, start + r)
        if start < length:
            gain[start:end] = np.minimum(gain[start:end], curve[: end - start])
    return gain


def master(stereo: np.ndarray, target_rms_db: float = -14.0, ceiling_db: float = -1.0) -> np.ndarray:
    out = highpass(stereo, 28, order=2)
    rms = np.sqrt(np.mean(out ** 2)) + 1e-9
    out *= db(target_rms_db) / rms
    out = soft_clip(out, 1.15)  # gentle saturation / limiting
    peak = np.max(np.abs(out)) + 1e-9
    return out * min(1.0, db(ceiling_db) / peak)


def fade(stereo: np.ndarray, fade_in: float = 0.0, fade_out: float = 0.0) -> np.ndarray:
    out = stereo.copy()
    if fade_in > 0:
        n = samples(fade_in)
        out[:, :n] *= np.linspace(0, 1, n)
    if fade_out > 0:
        n = samples(fade_out)
        out[:, -n:] *= np.linspace(1, 0, n)
    return out


# ---------------------------------------------------------------- output

def write_wav(path: Path, stereo: np.ndarray):
    data = np.clip(stereo.T, -1, 1)
    pcm = (data * 32767).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())


def encode(wav_path: Path, out_path: Path, codec: str):
    args = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path)]
    if codec == "ogg":
        args += ["-c:a", "libvorbis", "-q:a", "6"]
    elif codec == "mp3":
        args += ["-c:a", "libmp3lame", "-b:a", "192k"]
    subprocess.run(args + [str(out_path)], check=True)
