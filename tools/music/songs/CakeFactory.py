"""Conveyor Belt Boogie: the round song for CakeFactory (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)

NAMES = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


def blues(key: int, nxt: int) -> str:
    """Twelve bars of blues in `key` (a pitch class); the last bar is the dominant of the next chorus's key."""
    i, iv, v, x = NAMES[key % 12], NAMES[(key + 5) % 12], NAMES[(key + 7) % 12], NAMES[(nxt + 7) % 12]
    return f"{i}7 | {iv}7 | {i}7 | {i}7 | {iv}7 | {iv}7 | {i}7 | {i}7 | {v}7 | {iv}7 | {i}7 | {x}7"


@lru_cache(maxsize=None)
def piano(m: float, sec: float) -> np.ndarray:
    """A honky-tonk upright piano: two slightly detuned struck strings, the hammer's knock, a wooden body."""
    decay = max(0.9, 3.4 - (m - 40) * 0.05)
    a = np.asarray(ins.ks(m - 0.05, sec + 0.5, bright=0.38, decay=decay, pick=0.22, soft=0.62, variant=1))
    b = np.asarray(ins.ks(m + 0.06, sec + 0.5, bright=0.38, decay=decay * 0.9, pick=0.25, soft=0.62, variant=2))
    n = a.shape[-1]
    t = np.arange(n) / s.SR
    f = s.midi_hz(m)
    fund = np.sin(2 * np.pi * f * t) * np.exp(-t / (0.25 + decay * 0.12)) * 0.55
    hammer = s.lowpass(ins._rng("hammer", m).uniform(-1, 1, n), 2500) * np.exp(-t / 0.004) * 0.25
    tone = ins.formant(a + 0.8 * b + fund + hammer, [(f * 2, 2, 1.0), (500, 2, 1.0), (2500, -2, 1.0)])
    return ins.normalize(ins._gate(ins.eq(tone, ("hp", 60), ("lp", 6000)), sec, 0.12))


@lru_cache(maxsize=None)
def whistle(root: int, length: float = 0.8) -> np.ndarray:
    """The factory's steam whistle: three breathy pipes that scoop up into a major chord."""
    n = s.samples(length + 0.25)
    t = np.arange(n) / s.SR
    out = np.zeros(n)
    for k, (m, a) in enumerate(((root, 1.0), (root + 4, 0.8), (root + 7, 0.75))):
        f = s.midi_hz(m - 0.7 * np.exp(-t / 0.06) + 0.06 * np.sin(2 * np.pi * (5.5 + k) * t))
        phase = 2 * np.pi * np.cumsum(f) / s.SR
        out += a * (np.sin(phase) + 0.15 * np.sin(2 * phase))
    breath = s.bandpass(ins._rng("whistle", root).uniform(-1, 1, n), 1200, 5000) * 0.12
    e = ins.env(n, 0.04, 0.2, 0.9, 0.2, gate=length)
    return ins.normalize(ins.eq((out / 3 + breath) * e, ("hp", 300), ("lp", 7000)))


@lru_cache(maxsize=None)
def tick(pitch: float = 2600.0) -> np.ndarray:
    """One link of the belt's chain clicking over its sprocket."""
    n = s.samples(0.05)
    t = np.arange(n) / s.SR
    tone = np.sin(2 * np.pi * pitch * t) * np.exp(-t / 0.006) + 0.5 * np.sin(2 * np.pi * pitch * 1.7 * t) * np.exp(-t / 0.004)
    click = s.bandpass(ins._rng("tick", pitch).uniform(-1, 1, n), 2000, 6000) * np.exp(-t / 0.002)
    return ins.normalize(tone + 0.5 * click)


@lru_cache(maxsize=None)
def hat() -> np.ndarray:
    n = s.samples(0.1)
    t = np.arange(n) / s.SR
    noise = ins.eq(ins._rng("hat").uniform(-1, 1, n), ("hp", 3500), ("lp", 8500), ("peak", 6000, 4, 1.5))
    return ins.normalize(noise * np.exp(-t / 0.025))


@lru_cache(maxsize=None)
def kick() -> np.ndarray:
    """A round kick tuned near 62 Hz (a phone still hears it), with the beater's tick."""
    n = s.samples(0.32)
    t = np.arange(n) / s.SR
    f = 62 + 120 * np.exp(-t / 0.025)
    body = np.sin(2 * np.pi * np.cumsum(f) / s.SR) * np.exp(-t / 0.09)
    beater = s.bandpass(ins._rng("kick").uniform(-1, 1, n), 1500, 5000) * np.exp(-t / 0.004) * 0.35
    return ins.normalize(np.tanh((body + beater) * 1.6))


def play_struck(tr, stem, bar, notes, voice, gain=1.0, pan=0.0, humanize=0.0):
    """Plays tines and mallets: a note struck again stops the one still ringing (as a music box's tooth
    does), so fast repeated notes don't pile up in phase."""
    rng = np.random.default_rng(int(bar * 1000 + len(notes)))
    for i, n in enumerate(notes):
        sound = np.asarray(voice(n.midi, max(0.03, n.length * tr.step)))
        again = next((o.step for o in notes[i + 1:] if o.midi == n.midi), None)
        if again is not None:
            sound = ins._gate(sound, (again - n.step) * tr.step, 0.03)
        vel = n.vel * (1 + rng.uniform(-humanize, humanize)) if humanize else n.vel
        tr.add(stem, bar, n.step, sound, gain * vel, pan)


def stab(c) -> list:
    """The right hand's shuffle chord: the 3rd, 5th and 7th, packed into C4..B4."""
    return sorted(60 + ((c.root + i) - 60) % 12 for i in (4, 7, 10))


def cake_factory():
    """Conveyor Belt Boogie (168 bpm shuffle, D blues): the toy cake factory's line. A honky-tonk piano
    rolls a boogie-woogie bass under a music box tune, with the machines clanking on the backbeat, steam
    hissing and the belt's chain ticking along. Each 12-bar chorus lands on a FASTER! (the belts speed up
    every 17 seconds), and every time the whole band shifts up a gear: D, E, F sharp, then G for the last
    dash, when the factory whistle blows the end of the shift (55 s, the round's end)."""
    tr = Track(bpm=168, bars=50, spb=12)
    D, E, FS, G = 2, 4, 6, 7
    parts = plan(tr, [
        ("intro", 10, "D7 | D7 | D7 | D7 | D7 | D7 | G7 | G7 | D7 | A7"),
        ("belt1", 12, blues(D, E)),
        ("belt2", 12, blues(E, FS)),
        ("belt3", 12, blues(FS, G)),
        ("dash", 4, "G7 | C7 | G7 | A7"),
    ])
    tune_a = melody("""D5:2 F#5:1 A5:3 B5:2 A5:1 F#5:3 | F5:2 D5:1 B4:3 D5:6 | D5:2 F#5:1 A5:3 B5:2 A5:1 D6:3 |
                       C6:2 A5:1 F#5:3 D5:3 E5:2 F5:1 | G5:2 B5:1 D6:3 E6:2 D6:1 B5:3 | Bb5:2 B5:1 G5:3 F5:6 |
                       D5:2 F#5:1 A5:3 B5:2 A5:1 F#5:3 | F5:2 F#5:1 D5:3 r:6 | E5:2 A5:1 C#6:3 E6:2 C#6:1 A5:3 |
                       D6:2 B5:1 G5:3 F5:2 D5:1 B4:3 | A5:2 F#5:1 D5:3 F5:2 F#5:1 A5:3 | r:12""", 12)
    tune_b = melody("""A5:1 A5:1 A5:1 F#5:3 A5:1 A5:1 A5:1 D6:3 | B5:2 G5:1 F5:3 D5:6 | A5:1 A5:1 A5:1 F#5:3 A5:1 A5:1 A5:1 D6:3 |
                       C6:3 A5:3 F#5:3 D5:3 | B5:1 B5:1 B5:1 G5:3 B5:1 B5:1 B5:1 E6:3 | D6:2 B5:1 Bb5:3 G5:6 |
                       A5:1 A5:1 A5:1 F#5:3 A5:1 A5:1 A5:1 D6:3 | C6:2 A5:1 F#5:3 r:6 | C#6:3 E6:3 C#6:3 A5:3 |
                       B5:3 D6:3 B5:3 G5:3 | F#5:2 A5:1 D6:3 C6:2 A5:1 F#5:3 | r:12""", 12)
    dash = melody("G5:2 B5:1 D6:3 E6:2 D6:1 B5:3 | E6:2 C6:1 G5:3 Bb5:2 G5:1 E5:3 | G5:2 B5:1 D6:3 G6:6 | r:12", 12)
    chime = melody("A5:3 F#5:3 D5:3 F#5:3 | A5:6 B5:3 A5:3 | F#5:3 A5:3 D6:6 | C6:6 A5:6", 12)
    shift_up = [n for n in tune_a if 12 * 4 <= n.step < 12 * 6]  # its G7 bars, for the intro

    bd, sn, hh, tk = kick(), ins.snare2(220.0, 0.8, 0.2), hat(), tick()
    tamb = ins.jingles(0.16)
    crash = ins.eq(s.crash(2.0), ("lp", 9000))
    press, press_lo = ins.clank(520.0, 0.35), ins.clank(380.0, 0.45)

    def boogie(bar, c, gain, octave=False):
        """The left hand: root, 3rd, 5th, 6th, 7th and back down, in swung 8ths; the bass doubles the beats."""
        root = bass_note(c, 38)
        for st, iv, ln in ((0, 0, 2), (2, 4, 1), (3, 7, 2), (5, 9, 1), (6, 10, 2), (8, 9, 1), (9, 7, 2), (11, 4, 1)):
            g = gain * (1.0 if st % 3 == 0 else 0.78)
            tr.add("piano", bar, st, piano(root + iv, tr.step * ln * 0.95), g)
            if octave:
                tr.add("piano", bar, st, piano(root + iv + 12, tr.step * ln * 0.95), g * 0.45)
        for st, iv in ((0, 0), (3, 7), (6, 10), (9, 7)):
            tr.add("bass", bar, st, ins.upright(root + iv, tr.step * 2.6, variant=st % 2), gain)

    def gear(bar, c, nxt):
        """A gear change: the band hits the new key's dominant, the right hand runs up its arpeggio and
        the bass walks into the new root (`nxt`)."""
        root = bass_note(c, 38)
        for st, g in ((0, 1.0), (5, 0.9)):
            tr.add("piano", bar, st, piano(root, tr.step * 1.8), g)
            tr.add("piano", bar, st, piano(root + 12, tr.step * 1.8), g * 0.6)
            tr.add("bass", bar, st, ins.upright(root, tr.step * 1.8), g)
            strum(tr, "rh", bar, st, stab(c), piano, tr.step * 1.6, 1.0, spread=0.004)
        top = 59 + (c.root - 59) % 12
        for k, iv in enumerate((0, 4, 7, 10, 12, 16)):
            tr.add("rh", bar, 6 + k, piano(top + iv, tr.step * 1.2), 0.7 + 0.06 * k)
        fifth = root + 7 if root + 7 <= 50 else root - 5
        tr.add("bass", bar, 6, ins.upright(fifth, tr.step * 2.6), 0.8)
        tr.add("bass", bar, 9, ins.upright(nxt - 1, tr.step * 2.6), 0.85)

    # ---- the intro: the machines wake, the music box chimes, the belt starts, then the first gear
    tr.add("clank", 0, 0, press_lo, 0.3)
    tr.add("steam", 0, 6, ins.steam(0.6), 0.28)
    tr.add("clank", 1, 0, press, 0.32)
    tr.add("clank", 1, 6, press_lo, 0.36)
    tr.add("steam", 1, 9, ins.steam(0.4), 0.32)
    play_struck(tr, "lead", 0, chime, ins.music_box, 0.42)
    play_struck(tr, "toy", 0, shift(chime, -12), ins.celesta, 0.3)
    play_struck(tr, "lead", 6, shift(shift_up, 0, -12 * 4), ins.music_box, 0.5)
    for bar in range(2, 10):
        local = bar
        c = parts[0].at(bar)[0][2]
        tr.drum("belt", bar, "x.xx.xx.xx.x", tk, 0.3 + 0.05 * min(bar - 2, 6))
        if bar < 4:
            tr.drum("kick", bar, "x.....x.....", bd, 0.3 + 0.1 * (bar - 2))
        if 4 <= bar < 8:
            boogie(bar, c, 0.5 + 0.08 * (bar - 4))
            tr.drum("kick", bar, "x.....x.....", bd, 0.55 + 0.05 * (bar - 4))
            if bar % 2 == 1:
                tr.add("clank", bar, 9, press, 0.6)
        if bar == 8:
            for st, g in ((0, 1.0), (5, 0.9)):
                tr.add("piano", bar, st, piano(38, tr.step * 1.8), g)
                tr.add("piano", bar, st, piano(50, tr.step * 1.8), g * 0.6)
                tr.add("bass", bar, st, ins.upright(38, tr.step * 1.8), g)
                strum(tr, "rh", bar, st, stab(c), piano, tr.step * 1.6, 0.9, spread=0.004)
            tr.drum("kick", bar, "x....x......", bd, 0.9)
            tr.drum("snare", bar, "x....x......", sn, 0.7)
            tr.add("clank", bar, 9, press, 0.8)
        if bar == 9:
            gear(bar, c, 38)
            tr.drum("kick", bar, "x....x......", bd, 1.0)
            for k in range(6, 12):
                tr.add("snare", bar, k, sn, 0.35 + 0.1 * (k - 6))
            tr.add("belt", bar, 6, ins.ratchet(0.7, 14), 0.7)
            tr.add("steam", bar, 6, ins.steam(0.6), 0.8)
            tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.35)

    # ---- the belts: three choruses, each a gear up, and the last dash
    keys = {"belt1": 0, "belt2": 2, "belt3": 4}
    next_root = {"belt1": 40, "belt2": 42, "belt3": 43, "dash": 38}  # E, F#, G, then D again
    for part in parts[1:]:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            last = local == part.bars - 1
            if last:
                gear(bar, c, next_root[name])
                continue
            boogie(bar, c, 1.0 if name != "belt1" else 0.85, octave=name == "dash")
            chord = stab(c)
            if name == "belt2":
                for st in (2, 8):
                    strum(tr, "rh", bar, st, chord, piano, tr.step * 1.2, 0.8, spread=0.004)
            elif name == "belt3":
                for st in (2, 5, 8, 11):
                    strum(tr, "rh", bar, st, chord, piano, tr.step * 1.0, 0.85 if st in (2, 8) else 0.65, spread=0.004)
            elif name == "dash":
                for st in (0, 3, 6, 9):
                    strum(tr, "rh", bar, st, chord + [chord[0] + 12], piano, tr.step * 2.2, 1.0 if st in (3, 9) else 0.85, spread=0.006)

        for bar in part.bars_range():
            local = bar - part.first
            if local == part.bars - 1:  # the gear change
                tr.drum("kick", bar, "x....x......", bd, 1.0)
                tr.drum("snare", bar, "x....x......", sn, 0.8)
                tr.add("clank", bar, 0, press, 0.9)
                tr.add("steam", bar, 6, ins.steam(0.6), 0.9)
                for k in range(6, 12):
                    tr.add("snare", bar, k, sn, 0.35 + 0.1 * (k - 6))
                tr.add("belt", bar, 6, ins.ratchet(0.7, 14), 0.8)
                tr.add("fx", bar, 0, s.riser(tr.bar), 0.3)
                continue
            four = name in ("belt3", "dash")
            tr.drum("kick", bar, "x..x..x..x.." if four else "x.....x.....", bd, 1.0 if not four else 0.9)
            tr.drum("snare", bar, "...x.....x..", sn, 0.85)
            tr.drum("belt", bar, "x.xx.xx.xx.x", tk, 0.6)
            if name != "belt1":
                tr.drum("hat", bar, "x.xx.xx.xx.x", hh, 0.75)
            if name != "belt1" or local % 2 == 1:
                tr.add("clank", bar, 9, press, 0.8)
            if name == "belt3" and local % 2 == 0:
                tr.add("clank", bar, 3, press_lo, 0.55)
            if four:
                tr.drum("tamb", bar, "...x.....x..", tamb, 0.8)
                tr.add("belt", bar, 11, ins.ratchet(0.1, 3), 0.6)
            steam_every = 4 if name == "belt1" else 2
            if local % steam_every == steam_every - 1:
                tr.add("steam", bar, 11, ins.steam(0.3), 0.75)
            if local in (0, 8) and name != "dash" or (name == "dash" and local == 0):
                tr.add("cymbal", bar, 0, crash, 1.0, 0.2)

    # ---- the tunes
    tr.add("fx", 10, 0, whistle(74, 0.7), 1.0, -0.2)  # GO: the shift starts
    play_struck(tr, "lead", 10, tune_a, ins.music_box, 0.9, humanize=0.08)
    play_struck(tr, "toy", 10, shift(tune_a, -12), ins.celesta, 0.5)
    play_struck(tr, "lead", 22, shift(tune_b, keys["belt2"]), ins.music_box, 0.85, humanize=0.08)
    play_struck(tr, "toy", 22, shift(tune_b, keys["belt2"] - 12), ins.toy_piano, 1.0)
    play_struck(tr, "lead", 34, shift(tune_a, keys["belt3"]), ins.music_box, 1.0, humanize=0.08)
    play_struck(tr, "toy", 34, shift(tune_a, keys["belt3"] - 12), ins.toy_piano, 0.9)
    play_struck(tr, "sparkle", 34, shift(tune_a, keys["belt3"]), ins.glock, 0.6)
    play_struck(tr, "lead", 46, dash, ins.music_box, 1.0)
    play_struck(tr, "toy", 46, shift(dash, -12), ins.toy_piano, 1.0)
    play_struck(tr, "sparkle", 46, dash, ins.glock, 0.7)
    tr.add("fx", 48, 6, whistle(79, 1.2), 1.0, 0.2)  # 55 s: the end of the shift

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.2, delay=0.08),
        "toy": Bus(-12, reverb=0.18),
        "sparkle": Bus(-17, reverb=0.25),
        "piano": Bus(-8, reverb=0.08),
        "rh": Bus(-14, reverb=0.12),
        "bass": Bus(-13),
        "kick": Bus(-12, drive=1.3),
        "snare": Bus(-14, reverb=0.12),
        "hat": Bus(-21),
        "belt": Bus(-19, eq=(("lp", 8000),)),
        "tamb": Bus(-21, eq=(("lp", 8500),)),
        "clank": Bus(-14, reverb=0.15),
        "steam": Bus(-19, eq=(("lp", 7500),)),
        "cymbal": Bus(-19),
        "fx": Bus(-12, reverb=0.25),
    }, reverb_decay=1.2, reverb_tone=6000, delay_time=tr.beat * 2 / 3, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("CakeFactory", "Conveyor Belt Boogie", 168, 10, 50, cake_factory)
