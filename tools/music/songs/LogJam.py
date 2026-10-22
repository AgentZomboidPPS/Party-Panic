"""Timber Tumble: the round song for LogJam (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def _sealed(x: np.ndarray) -> np.ndarray:
    x.setflags(write=False)  # cached notes are shared: nobody changes them in place
    return x


def _faded(x: np.ndarray, seconds: float = 0.008) -> np.ndarray:
    """Brings a one-shot's last few milliseconds down to silence, so it never ends on a click."""
    k = min(x.shape[-1], s.samples(seconds))
    x[..., -k:] *= np.linspace(1, 0, k)
    return x


@lru_cache(maxsize=None)
def bass_marimba(midi: float, length: float) -> np.ndarray:
    """A bass marimba: a round wooden boom, the bar's ring two octaves up and the resonator's octave
    (so a phone still hears the note), struck with a felt mallet."""
    n = s.samples(min(length, 0.6) + 0.45)
    t = np.arange(n) / s.SR
    f = s.midi_hz(midi)
    rng = np.random.default_rng(int(midi))
    body = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.4)
    octave = 0.5 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t / 0.22)
    ring = 0.3 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t / 0.1)
    felt = s.bandpass(rng.uniform(-1, 1, n), 120, 900) * np.exp(-t / 0.008) * 0.35
    tone = ins.drive(body + octave + ring + felt, 1.2)
    return _sealed(ins.normalize(tone * ins.env(n, 0.002, 1.0, 1.0, 0.12, gate=min(length, 0.6) + 0.3)))


@lru_cache(maxsize=None)
def musical_saw(midi: float, length: float, glide_from: float | None = None, glide: float = 0.09) -> np.ndarray:
    """A musical saw, bowed: an eerie singing near-sine with a slow, wide wobble, sliding in from the
    note before."""
    n = s.samples(length + 0.25)
    t = np.arange(n) / s.SR
    pitch = midi + 0.3 * np.clip((t - 0.08) / 0.3, 0, 1) * np.sin(2 * np.pi * 5.3 * t)
    if glide_from is not None:
        pitch = pitch + (glide_from - midi) * np.exp(-t / glide)
    phase = 2 * np.pi * np.cumsum(s.midi_hz(pitch)) / s.SR
    tone = np.sin(phase) + 0.14 * np.sin(2 * phase) + 0.05 * np.sin(3 * phase)
    bow = s.bandpass(np.random.default_rng(int(midi) + 7).uniform(-1, 1, n), 1500, 4500) * 0.02
    return _sealed(ins.normalize((tone + bow) * ins.env(n, 0.09, 0.4, 0.9, 0.2, gate=length)))


@lru_cache(maxsize=None)
def stomp(variant: int = 0) -> np.ndarray:
    """A lumberjack's boot on the mill's plank floor: a low thud and the board's knock."""
    n = s.samples(0.3)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(90 + variant)
    thud = s.sine(58 + 80 * np.exp(-t / 0.018), n) * np.exp(-t / 0.085)
    board = np.sin(2 * np.pi * 172 * t) * np.exp(-t / 0.05) * 0.5 + np.sin(2 * np.pi * 315 * t) * np.exp(-t / 0.03) * 0.3
    knock = s.bandpass(rng.uniform(-1, 1, n), 200, 1800) * np.exp(-t / 0.012) * 0.6
    return _sealed(_faded(ins.normalize(ins.drive(thud + board + knock, 1.4))))


@lru_cache(maxsize=None)
def claps() -> np.ndarray:
    """The whole crew clapping: a few hands a hair apart."""
    n = s.samples(0.3)
    out = np.zeros(n)
    rng = np.random.default_rng(5)
    for k, (delay, low, high) in enumerate(((0.0, 900, 2600), (0.007, 1100, 3200), (0.013, 800, 2200))):
        start = s.samples(delay)
        m = n - start
        tt = np.arange(m) / s.SR
        burst = s.bandpass(rng.uniform(-1, 1, m), low, high)
        e = np.zeros(m)
        for offset, gain in ((0.0, 0.7), (0.009, 0.6), (0.018, 1.0)):
            o = s.samples(offset)
            e[o:] += gain * np.exp(-tt[: m - o] / (0.012 if gain < 1 else 0.07))
        out[start:] += burst * e
    return _sealed(_faded(ins.normalize(out)))


@lru_cache(maxsize=None)
def chop(variant: int = 0) -> np.ndarray:
    """An axe biting into a log: the blade's crack, the wood's knock, a low thud and a few splinters."""
    n = s.samples(0.35)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(120 + variant)
    crack = s.bandpass(rng.uniform(-1, 1, n), 1200, 5000) * np.exp(-t / 0.006)
    knock = s.sine(430 * (1 + 0.3 * np.exp(-t / 0.01)), n) * np.exp(-t / 0.045)
    thud = s.sine(95 * (1 + 0.5 * np.exp(-t / 0.01)), n) * np.exp(-t / 0.07)
    splinters = np.zeros(n)
    for _ in range(6):
        start = int(rng.uniform(0.006, 0.05) * s.SR)
        m = min(250, n - start)
        splinters[start:start + m] += rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / 30) * rng.uniform(0.3, 1)
    splinters = s.bandpass(splinters, 1500, 6000)
    return _sealed(ins.normalize(ins.drive(crack * 0.9 + knock * 0.7 + thud * 0.8 + splinters * 0.4, 1.3)))


@lru_cache(maxsize=None)
def sawing(length: float, pull: bool) -> np.ndarray:
    """One stroke of a two-man crosscut saw: the teeth rasping through the log, faster in the middle of
    the stroke, a little higher on the pull."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(140 + pull)
    speed = np.sin(np.pi * np.clip(t / length, 0, 1))
    phase = np.cumsum((150 if pull else 115) * (0.35 + 0.65 * speed)) / s.SR
    teeth = np.maximum(0, np.cos(2 * np.pi * phase)) ** 8
    rasp = s.bandpass(rng.uniform(-1, 1, n), 900 if pull else 700, 4200 if pull else 3400) * (0.25 + teeth)
    return _sealed(ins.normalize(rasp * speed ** 0.6))


@lru_cache(maxsize=None)
def woodpecker(hits: int = 14) -> np.ndarray:
    """A woodpecker's drumroll on a hollow trunk."""
    tap = np.asarray(ins.woodblock(1150.0, 0.1))
    n = s.samples(hits / 21 + 0.1)
    out = np.zeros(n)
    for i in range(hits):
        start = s.samples(i / 21)
        m = min(len(tap), n - start)
        out[start:start + m] += tap[:m] * (1.0 - 0.5 * i / hits)
    return _sealed(ins.normalize(out))


@lru_cache(maxsize=None)
def chirp(variant: int = 0) -> np.ndarray:
    """A small bird: two quick upward whistles."""
    n = s.samples(0.2)
    t = np.arange(n) / s.SR
    out = np.zeros(n)
    base = (2600, 3000, 2300)[variant % 3]
    for start in (0.0, 0.09):
        m = s.samples(0.06)
        a = s.samples(start)
        tt = np.arange(m) / s.SR
        out[a:a + m] += np.sin(2 * np.pi * np.cumsum(base * (1 + 0.45 * tt / 0.06)) / s.SR) * np.sin(np.pi * tt / 0.06)
    return _sealed(ins.normalize(out))


@lru_cache(maxsize=None)
def creak(length: float = 0.9) -> np.ndarray:
    """A trunk giving way: a slow wooden creak, stick-slip pulses through the wood's resonances."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    phase = np.cumsum(28 + 30 * t / length) / s.SR
    pulses = np.maximum(0, np.cos(2 * np.pi * phase)) ** 30
    tone = ins.formant(pulses, [(320, 14, 6), (760, 12, 6), (1450, 8, 5)])
    tone = ins.eq(tone, ("hp", 150), ("lp", 4000))
    return _sealed(ins.normalize(tone * np.clip(t / 0.1, 0, 1) * np.clip((length - t) / 0.08, 0, 1)))


@lru_cache(maxsize=None)
def timber() -> np.ndarray:
    """The tree lands: a deep boom, the ground's thud and the branches crashing round it."""
    n = s.samples(1.6)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(160)
    boom = s.sine(48 + 70 * np.exp(-t / 0.06), n) * np.exp(-t / 0.35)
    thud = s.bandpass(rng.uniform(-1, 1, n), 80, 700) * np.exp(-t / 0.08)
    branches = np.zeros(n)
    for _ in range(40):
        start = int(rng.uniform(0.0, 0.5) ** 2 * s.SR)
        m = min(600, n - start)
        branches[start:start + m] += rng.uniform(-1, 1, m) * np.exp(-np.arange(m) / 70) * rng.uniform(0.2, 1)
    branches = s.bandpass(branches, 600, 5000)
    return _sealed(ins.normalize(ins.drive(boom + thud * 0.7 + branches * 0.5, 1.3)))


def log_jam():
    """Timber Tumble (132 bpm, G major with a folky flat seventh): the lumber yard's stomp. A woodpecker
    and birds at dawn, then boots on the plank floor, the crew's claps, log drums and woodblocks, a
    marimba with a chop-chop-TIM-ber hook and a bass marimba; a musical saw sings the middle part in
    E minor, a two-man saw rasps the break, and the last stretch ends on a 'TIM-BERRR!' and a falling
    tree before the chop-chop back round."""
    tr = Track(bpm=132, bars=30)
    parts = plan(tr, [
        ("intro", 8, "G | G | G | F | C | G | C | D"),
        ("A", 8, "G | F | C | G | G | F | C D | G"),
        ("B", 8, "Em | C | G | D | Em | C | Am | D"),
        ("saw", 2, "C | D"),
        ("finale", 4, "G | F | C D | G"),
    ])
    hook = melody("""D5:2 D5:2 G5:4 D5:4 B4:2 D5:2 | C5:2 C5:2 F5:4 C5:4 A4:2 C5:2 | E5:2 E5:2 G5:2 E5:2 C5:2 E5:2 G5:2 A5:2 | B5:4 A5:2 G5:2 D5:8 |
                     D5:2 D5:2 G5:4 D5:4 B4:2 D5:2 | C5:2 C5:2 F5:4 A5:4 C6:4 | B5:2 A5:2 G5:2 E5:2 F#5:2 G5:2 A5:2 F#5:2 | G5:4 r:2 D5:1 D5:1 G4:4! r:4""")
    sawtune = melody("B5:8 A5:4 G5:4 | E5:12 G5:4 | D5:8 B4:4 D5:4 | A5:16 | B5:8 C6:4 B5:4 | G5:12 E5:4 | A5:6 B5:2 C6:4 A5:4 | D6:12 r:4")
    last = melody("D5:2 D5:2 G5:4 D5:4 B4:2 D5:2 | C5:2 C5:2 F5:4 A5:4 C6:4 | B5:2 A5:2 G5:2 E5:2 F#5:2 G5:2 A5:2 B5:2 | D6:8 G5:4! r:4")
    countersaw = melody("B5:16 | A5:16 | G5:8 A5:8")

    def mallets(bar, notes, voice, gain=1.0, stem="lead", pan=0.0, roll_from=6, rate=0.5):
        """Plays notes on a mallet instrument; notes `roll_from` steps or longer are rolled."""
        for n in notes:
            if n.length >= roll_from:
                k = 0.0
                while k < n.length - 1e-6:
                    tr.add(stem, bar, n.step + k, voice(n.midi, 0.12), gain * n.vel * (0.9 if int(k / rate) % 2 == 0 else 0.7), pan)
                    k += rate
            else:
                tr.add(stem, bar, n.step, voice(n.midi, min(0.4, n.length * tr.step)), gain * n.vel, pan)

    def saw_line(bar, notes, gain=1.0, glide=0.09):
        """The musical saw slides from each note into the next when they touch."""
        before = None
        for n in notes:
            touching = before is not None and abs(before.step + before.length - n.step) < 1e-6
            tr.add("saw", bar, n.step, musical_saw(n.midi, n.length * tr.step, before.midi if touching else None, glide), gain * n.vel)
            before = n

    knock = {p: ins.log_drum(p, 0.45) for p in (147.0, 196.0, 220.0, 262.0, 294.0, 330.0)}
    tik, tok = ins.woodblock(1650.0, 0.12), ins.woodblock(1150.0, 0.13)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 38)
            fifth = root + 7 if root + 7 <= 50 else root - 5
            notes = voicing(c, 55, 69, prev)
            prev = notes
            if name == "intro":
                if local >= 5:
                    g = 0.6 + 0.12 * (local - 5)
                    for k, m in ((0, root), (6, root), (8, fifth), (14, root + 12)):
                        tr.add("bass", bar, k, bass_marimba(m, 0.4), g if k % 8 == 0 else g * 0.8)
                continue
            if name == "finale" and local == 3:  # TIM-BERRR: held for the call, then down with the tree
                tr.add("bass", bar, 0, bass_marimba(root, 0.6), 0.8)
                tr.add("bass", bar, 8, bass_marimba(root, 0.6), 1.0)
                tr.add("bass", bar, 12, bass_marimba(fifth, 0.3), 0.8)
                tr.add("bass", bar, 14, bass_marimba(root + 12, 0.3), 0.8)
            elif name == "A" or name == "finale":
                pattern = ((0, root, 1.0), (3, root, 0.7), (6, fifth, 0.85), (8, root, 1.0), (11, root, 0.7), (14, fifth, 0.85))
                for k, m, g in pattern:
                    if k < length:
                        tr.add("bass", bar, step + k, bass_marimba(m, 0.3), g)
                for k in range(0, int(length), 4):  # the log drums answer the stomp
                    tr.add("logs", bar, step + k + 2, knock[(196.0, 220.0, 262.0, 294.0)[(k // 4 + local) % 4]], 0.8, -0.3)
                if local % 2 == 1 and length == 16:
                    tr.add("logs", bar, 13, knock[330.0], 0.7, 0.3)
            elif name == "B":
                tr.add("bass", bar, 0, bass_marimba(root, 0.5), 1.0)
                tr.add("bass", bar, 10, bass_marimba(root, 0.3), 0.75)
                tr.add("bass", bar, 12, bass_marimba(fifth, 0.3), 0.8)
                ring = notes + [notes[0] + 12, notes[1] + 12]
                for k in range(16):  # the marimba's running sixteenths under the saw
                    idx = (0, 2, 1, 3, 2, 4, 3, 2)[k % 8]
                    tr.add("ostinato", bar, k, ins.marimba(ring[idx] + 12, 0.15), 1.0 if k % 4 == 0 else 0.7, 0.3 if k % 2 else -0.1)
                for k, p in ((0, 147.0), (3, 196.0), (6, 220.0), (10, 196.0), (12, 262.0), (14, 220.0)):
                    tr.add("logs", bar, k, knock[p], 0.85 if k % 4 == 0 else 0.65, -0.3)
            elif name == "saw":
                for k in range(0, 16, 4):
                    tr.add("bass", bar, k, bass_marimba(root, 0.3), 1.0)
                    tr.add("bass", bar, k + 2, bass_marimba(root + 12, 0.2), 0.6)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local in (0, 1):
                    tr.add("fx", bar, 4 if local == 0 else 9, woodpecker(14), 0.32 + 0.08 * local, 0.4)
                    tr.add("fx", bar, 10 if local == 0 else 2, chirp(local), 0.26, -0.5)
                    tr.add("fx", bar, 12 if local == 0 else 5, chirp(local + 1), 0.22, -0.6)
                    tr.add("logs", bar, 0, knock[147.0], 0.28 + 0.12 * local)
                    tr.add("logs", bar, 8, knock[196.0], 0.25 + 0.12 * local)
                if 2 <= local < 5:
                    tr.drum("logs", bar, "x.....x.x.......", knock[196.0], 0.5 + 0.05 * local, -0.3)
                    tr.drum("logs", bar, "....x.......x...", knock[147.0], 0.5, 0.2)
                    tr.drum("blocks", bar, "..x...x...x...x.", tik, 0.35 + 0.08 * (local - 2), 0.3)
                if local == 4:
                    tr.add("fx", bar, 0, woodpecker(10), 0.35, 0.5)
                if local >= 5:
                    tr.drum("stomp", bar, "X.......X......." if local == 5 else "X...X...X...X...", stomp(local % 2), 0.65 + 0.12 * (local - 5))
                    tr.drum("blocks", bar, "x.x.x.x.x.x.x.x.", tik, 0.45, 0.3)
                    tr.drum("logs", bar, "x.....x.x.....x.", knock[196.0], 0.6, -0.3)
                if local >= 6:
                    tr.drum("clap", bar, "....X.......X...", claps(), 0.6 + 0.15 * (local - 6))
                if local == 6:
                    tr.drum("chop", bar, "X...X...X...X...", chop(0), 0.45)
                if local == 7:
                    for k, g in zip(range(0, 14, 2), (0.45, 0.5, 0.55, 0.6, 0.7, 0.8, 0.9)):
                        tr.add("chop", bar, k, chop(k % 3), g)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.25)
                continue
            if name == "finale" and local == 3:  # the band stops for the call and lands with the tree
                tr.drum("stomp", bar, "X.......X...X.X.", stomp(1), 1.0)
                tr.drum("clap", bar, "........X.......", claps(), 1.0)
                tr.drum("blocks", bar, "........x.x.x.x.", tok, 0.6, -0.3)
            elif name in ("A", "finale"):
                big = name == "finale"
                tr.drum("stomp", bar, "X...X...X...X...", stomp(local % 2), 1.0)
                tr.drum("clap", bar, "....X.......X..." if not big else "....X.......X..x", claps(), 1.0)
                tr.drum("blocks", bar, "x.x.x.x.x.x.x.x.", tok, 0.6, -0.3)
                tr.drum("blocks", bar, ".x.x.x.x.x.x.x.x" if big or local >= 4 else "..x...x...x...x.", tik, 0.5, 0.3)
                if name == "A" and local == 7:  # the hook's own 'chop-chop CHOP!'
                    for k, g in ((6, 0.6), (7, 0.7), (8, 1.0)):
                        tr.add("chop", bar, k, chop(k % 3), g, 0.15)
                elif local % 2 == 1:
                    tr.add("chop", bar, 14, chop(local % 3), 0.9, 0.15)
                if local == 0:
                    tr.add("chop", bar, 0, chop(2), 1.0)
            elif name == "B":
                tr.drum("stomp", bar, "X.......X.......", stomp(local % 2), 0.95)
                tr.drum("clap", bar, "........X.......", claps(), 0.9)
                tr.drum("blocks", bar, "x.xx.xx.x.xx.xx.", tik, 0.45, 0.3)
                if local == 0:
                    tr.add("chop", bar, 0, chop(1), 0.9)
                if local == 7:
                    for k in (8, 10, 12, 14):
                        tr.add("chop", bar, k, chop(k % 3), 0.6 + 0.05 * k / 2)
            elif name == "saw":  # a two-man saw: slow strokes, then faster
                strokes = range(0, 16, 4) if local == 0 else range(0, 16, 2)
                for i, k in enumerate(strokes):
                    tr.add("fx", bar, k, sawing(tr.step * (4 if local == 0 else 2) * 0.95, i % 2 == 1), 0.8 + 0.05 * i if local else 0.85, 0.3 if i % 2 else -0.3)
                tr.drum("stomp", bar, "X...X...X...X...", stomp(local % 2), 1.0)
                tr.drum("clap", bar, "....X.......X..." if local == 0 else "....X.......X.X.", claps(), 1.0)
                tr.drum("logs", bar, "x..x..x...x.x..." if local == 0 else "x.x.x.x.xxxxxxxx", knock[262.0 if local else 220.0], 0.7, -0.3)
                if local == 1:
                    for k in range(8, 16):
                        tr.add("blocks", bar, k, tik, 0.4 + 0.06 * (k - 8), 0.3)

    # the dawn: the marimba tries the tune, the saw yawns
    mallets(2, melody("D5:2 D5:2 G5:4 D5:4 B4:2 D5:2 | C5:2 C5:2 F5:4 C5:4 A4:2 C5:2"), ins.marimba, 0.55)
    saw_line(4, melody("E5:8 G5:8 | B5:12 r:4"), 0.6, glide=0.15)
    mallets(7, melody("A4:2 A4:2 D5:2 D5:2 F#5:2 F#5:2 A5:2 r:2"), ins.marimba, 0.8)
    mallets(8, hook, ins.marimba)
    mallets(8, [n for n in shift(hook, 12) if n.step >= 64 and n.length <= 2], ins.xylophone, 0.35, stem="xylo", pan=0.3)  # second half
    saw_line(16, sawtune)
    mallets(24, melody("G4:2 G4:2 C5:2 C5:2 E5:2 E5:2 G5:2 G5:2 | A4:2 A4:2 D5:2 D5:2 F#5:2 F#5:2 A5:1 G5:1 E5:1 C#5:1"), ins.marimba, 0.85)
    mallets(26, last, ins.marimba)
    mallets(26, shift(last, 12), ins.xylophone, 0.5, stem="xylo", pan=0.3)
    saw_line(26, countersaw, 0.55)
    saw_line(29, melody("D6:4 G5:8 r:4"), 1.0, glide=0.35)  # TIM-BERRR!
    tr.add("fx", 29, 0, creak(0.9), 0.7, 0.2)
    tr.add("fx", 29, 6, ins.whoosh(0.35, up=False), 0.6, -0.2)
    tr.add("timber", 29, 8, timber(), 1.0)
    tr.add("chop", 29, 12, chop(0), 0.8)
    tr.add("chop", 29, 14, chop(1), 0.9)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.15, delay=0.06),
        "saw": Bus(-7, reverb=0.3, delay=0.1),
        "xylo": Bus(-13, reverb=0.15),
        "ostinato": Bus(-13, reverb=0.15),
        "bass": Bus(-8),
        "logs": Bus(-12, reverb=0.12),
        "stomp": Bus(-9, reverb=0.08),
        "clap": Bus(-13, reverb=0.15),
        "blocks": Bus(-17, reverb=0.08),
        "chop": Bus(-12, reverb=0.1),
        "timber": Bus(-11, reverb=0.25),
        "fx": Bus(-14, reverb=0.25, eq=(("lp", 6500),)),
    }, reverb_decay=1.5, reverb_tone=5000, delay_time=tr.beat * 0.75, delay_feedback=0.28)
    return finish(tr, mix), tr


SONG = Song("LogJam", "Timber Tumble", 132, 8, 30, log_jam)
