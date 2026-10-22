"""Giddy-Up Gallop: the round song for RockinRaceway (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from score import Note

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def faded(x, seconds=0.03):
    """A short fade at the very end, so a tail that's cut off doesn't click."""
    x = np.array(x, dtype=float)
    k = min(x.shape[-1], s.samples(seconds))
    x[..., -k:] *= np.linspace(1.0, 0.0, k)
    return x


def harmony(notes, first, parts, spb=16):
    """A second voice under the tune: for every note, the nearest chord tone at least a minor third
    below it (in the chord playing under that note), so the second line never rubs against the band."""
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


@lru_cache(maxsize=None)
def harmonica(m, sec):
    """A cowboy's harmonica: a buzzy free reed in cupped hands, bending up into each note, with a
    throat tremolo on the held ones and a little breath."""
    n = s.samples(sec + 0.1)
    t = np.arange(n) / s.SR
    f = s.midi_hz(m - 0.45 * np.exp(-t / 0.035))
    reed = 0.55 * s.saw(f, n) + 0.45 * s.square(f, n, 0.3)
    reed = ins.eq(ins.formant(reed, [(1150, 7, 1.8), (2400, 5, 2.2), (3500, 2, 2.5)]), ("hp", 300), ("lp", 4800), ("lp", 6000))
    tremolo = np.ones(n)
    if sec > 0.3:
        tremolo -= 0.2 * np.clip((t - 0.18) / 0.15, 0, 1) * (0.5 + 0.5 * np.sin(2 * np.pi * 5.6 * t))
    breath = ins.eq(np.random.default_rng(int(m)).uniform(-1, 1, n), ("hp", 1200), ("lp", 5000)) * 0.05
    return ins.normalize((reed * tremolo + breath) * ins.env(n, 0.018, 0.15, 0.8, 0.05, gate=sec))


@lru_cache(maxsize=None)
def steel(m, sec, slide=0.0):
    """A lap steel guitar: a bright string stopped with a steel bar, so it slides into its note from
    `slide` semitones away (from the note before) and wavers with the bar's vibrato."""
    pluck = np.asarray(ins.ks(m, sec + 0.5, bright=0.7, decay=3.5, pick=0.2, soft=0.15))
    t = np.arange(pluck.shape[-1]) / s.SR
    pitch = slide * np.exp(-t / 0.06) + 0.15 * np.clip((t - 0.12) / 0.2, 0, 1) * np.sin(2 * np.pi * 5.2 * t)
    tone = ins.bend(pluck, pitch)
    tone = tone * np.clip(np.arange(tone.shape[-1]) / s.SR / 0.04, 0, 1)
    tone = ins.drive(ins.eq(tone, ("hp", 200), ("peak", 1200, 3, 1.0), ("lp", 5000)) * 1.5, 1.3)
    return ins.normalize(ins._gate(tone, sec + 0.05, 0.12))


@lru_cache(maxsize=None)
def bugle(m, sec):
    """A lone bugle at the starting post: one bright brass voice, no valves."""
    return ins.brass(m, sec, bright=0.85, section=1, vibrato=0.04)


@lru_cache(maxsize=None)
def trumpets(m, sec):
    return ins.brass(m, sec, bright=1.0, section=3)


@lru_cache(maxsize=None)
def chunk(m, sec):
    """One string of the rhythm guitar's galloping strum: a steel-string acoustic, palm-damped."""
    return ins.acoustic_guitar(m, sec, 1)


@lru_cache(maxsize=None)
def hoof(pitch, variant=0):
    """A hobby horse's hoof: two coconut shells knocked together (a hollow 'clop' and its click)."""
    n = s.samples(0.1)
    t = np.arange(n) / s.SR
    shell = np.sin(2 * np.pi * pitch * t) * np.exp(-t / 0.018) + 0.45 * np.sin(2 * np.pi * pitch * 2.37 * t) * np.exp(-t / 0.008)
    knock = ins.eq(np.random.default_rng(variant + 11).uniform(-1, 1, n), ("hp", 900), ("lp", 4500)) * np.exp(-t / 0.004) * 0.5
    return ins.normalize(shell + knock)


@lru_cache(maxsize=None)
def bass_drum():
    """A bass drum with a felt beater: a round boom at 65-130 Hz, where a phone can still play it."""
    n = s.samples(0.3)
    t = np.arange(n) / s.SR
    body = s.sine(64 + 70 * np.exp(-t / 0.03), n) * np.exp(-t / 0.12)
    felt = ins.eq(np.random.default_rng(6).uniform(-1, 1, n), ("hp", 200), ("lp", 1500)) * np.exp(-t / 0.01) * 0.3
    return faded(ins.normalize(np.tanh((body + felt) * 1.5)))


@lru_cache(maxsize=None)
def whip():
    """A whip crack: a short swish up into a sharp snap (the snap lands 0.06 s in)."""
    n = s.samples(0.3)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(23)
    swish = ins.eq(rng.uniform(-1, 1, n), ("hp", 1500), ("lp", 5000)) * np.clip(t / 0.06, 0, 1) ** 2 * (t < 0.06)
    snap = ins.eq(rng.uniform(-1, 1, n), ("hp", 900), ("lp", 5000), ("lp", 6500)) * np.exp(-np.clip(t - 0.06, 0, None) / 0.014) * (t >= 0.06)
    return ins.normalize(swish * 0.25 + snap)


@lru_cache(maxsize=None)
def crowd(length, cheer=False):
    """The grandstand: a murmur of voices, or (cheer) a roar that swells up and dies away."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(31 if cheer else 17)
    out = np.zeros((2, n))
    for ch in range(2):
        babble = np.zeros(n)
        for vowel in ((620, 1100), (450, 1700), (750, 1250)):
            flutter = ins.eq(rng.uniform(0, 1, n), ("lp", 9.0)) ** 2  # each voice group comes and goes
            babble += ins.formant(ins.eq(rng.uniform(-1, 1, n), ("hp", 250), ("lp", 3200), ("lp", 4000)),
                                  [(vowel[0], 10, 3), (vowel[1], 8, 3)]) * flutter
        out[ch] = babble
    shape = np.clip(t / 0.4, 0, 1) * np.exp(-np.clip(t - length * 0.35, 0, None) / (length * 0.3)) if cheer else np.clip(t / 1.5, 0, 1)
    return faded(ins.normalize(out * shape), 0.5 if cheer else 1.5)


def rockin_raceway():
    """Giddy-Up Gallop (142 bpm, D major): a cartoon gallop round the fairground oval. A lone bugle
    calls the riders to the post, then coconut-shell hooves, a galloping strum and a gallop snare set
    off, and a harmonica takes the tune over an upright bass. The back straight is a lap steel guitar
    sliding through a fairground tune with a glockenspiel; xylophone flicks hop the hurdles. The
    climax kicks up to E major with trumpets and the grandstand roaring for the final straight and
    the finish (about 27-47 s after GO, the first rider home and the finish clock), then a trotting
    lap of honour that breaks back into the gallop at the drop."""
    tr = Track(bpm=142, bars=44)
    parts = plan(tr, [
        ("intro", 8, "D | D | D | D | D | D | A7 | A7"),
        ("A", 8, "D | A7 | D | G | D | Bm | E7 A7 | D"),
        ("B", 8, "G | C | G | D7 | G | E7 | Am | B7"),
        ("climax", 8, "E | B7 | E | A | E | C#m | F#7 B7 | E"),
        ("finish", 4, "E | A | B7 | E"),
        ("lap", 8, "G | D | G | D | Em | A7 | D | A7"),
    ])
    call = melody("r:4 D4:3 D4:1 F#4:3 A4:1 D5:4 | D5:3 D5:1 F#5:3 D5:1 A5:8 | A5:3 F#5:1 D5:3 F#5:1 A5:3 F#5:1 D5:4 | A4:3 D5:1 F#5:3 A4:1 D5:8")
    tune = melody("""D5:1 E5:1 F#5:2 A5:2 F#5:2 B5:1 A5:1 F#5:2 D5:4 | C#5:1 D5:1 E5:2 G5:2 E5:2 A5:1 G5:1 E5:2 C#5:4 |
                     D5:1 E5:1 F#5:2 A5:2 D6:2 C#6:1 B5:1 A5:2 F#5:4 | G5:2 B5:2 A5:2 G5:2 F#5:2 E5:2 D5:4 |
                     A5:3 F#5:1 A5:3 F#5:1 D6:4 A5:4 | B5:3 F#5:1 B5:3 F#5:1 D6:4 B5:4 |
                     G#5:2 B5:2 E6:2 D6:2 C#6:2 A5:2 G5:2 E5:2 | F#5:2 E5:1 D5:1 A4:2 D5:2 F#5:4 r:4""")
    fair = melody("""D5:2 G5:2 B5:2 D6:2 ~:4 B5:2 G5:2 | E5:2 G5:2 C6:2 E6:2 ~:4 C6:2 G5:2 | D5:2 G5:2 B5:2 D6:2 C6:2 B5:2 A5:2 G5:2 |
                     F#5:4 A5:4 C6:4 D6:4 | D6:4 B5:2 G5:2 D5:4 G5:4 | E5:2 G#5:2 B5:2 D6:2 ~:4 B5:2 G#5:2 |
                     A5:4 C6:4 E6:4 C6:4 | B5:4 A5:4 F#5:4 D#5:4""")
    ending = melody("""E5:1 F#5:1 G#5:2 B5:2 G#5:2 C#6:1 B5:1 G#5:2 E5:4 | A5:1 B5:1 C#6:2 E6:2 C#6:2 F#6:1 E6:1 C#6:2 A5:4 |
                       B5:2 B5:1 B5:1 B5:2 B5:2 C#6:2 D#6:2 F#6:4 | E6:4 B5:2 G#5:2 E5:4 r:4""")
    lap = melody("""G5:3 A5:1 B5:4 D6:4 B5:4 | A5:3 F#5:1 D5:4 A5:8 | G5:3 A5:1 B5:4 E6:4 D6:4 | F#6:3 E6:1 D6:4 A5:8 |
                    G5:3 F#5:1 E5:4 B5:4 G5:4 | A5:3 G5:1 E5:4 C#6:4 A5:4 | D6:3 C#6:1 D6:2 A5:2 F#5:4 D5:4 | G5:4 E5:4 C#5:4 A4:4""")
    descant = melody("G#4:8 B4:8 | A4:8 B4:8 | B4:8 E5:8 | C#5:8 E5:8 | B4:8 G#4:8 | C#5:8 E5:8 | E5:8 D#5:8 | E5:12 r:4")

    kick = bass_drum()
    snares = [ins.snare2(230.0, 0.7, 0.18, v) for v in range(4)]
    clip, clop = [hoof(720.0, v) for v in range(3)], [hoof(560.0, v + 3) for v in range(3)]
    crash, tamb = s.crash(1.6), ins.jingles(0.16, 0.8)
    toms = [ins.tom(p, 0.35, v) for v, p in enumerate((190.0, 140.0, 100.0))]

    def hits(stem, bar, pattern, sounds, gain=1.0, pan=0.0):
        for k, (step, vel) in enumerate((i, {"X": 1.0, "x": 0.8, "o": 0.45}[ch]) for i, ch in enumerate(pattern) if ch != "."):
            tr.add(stem, bar, step, sounds[k % len(sounds)], gain * vel, pan)

    def hooves(bar, pattern, gain):
        """Two hooves, left and right, on the gallop's 'DUM-da-da'."""
        for k, (step, vel) in enumerate((i, {"X": 1.0, "x": 0.8, "o": 0.45}[ch]) for i, ch in enumerate(pattern) if ch != "."):
            sound = clop[k % 3] if k % 2 == 0 else clip[k % 3]
            tr.add("hooves", bar, step, sound, gain * vel, -0.3 if k % 2 == 0 else 0.3)

    def gallop_strum(bar, beats, notes, gain):
        """The rhythm guitar galloping with the hooves: down, up-down on every beat, damped short."""
        for k in beats:
            for off, vel, down in ((0, 1.0, True), (2, 0.65, False), (3, 0.8, True)):
                strum(tr, "guitar", bar, k + off, notes, chunk, tr.step * 0.9, gain * vel, spread=0.005, down=down, pan=0.25)

    def flick(bar, step, notes, up=True, gain=0.8):
        """A xylophone flick: a hop over a hurdle (up), a spin-out (down)."""
        run = [m + 12 for m in notes] + [notes[0] + 24]
        for k, m in enumerate(run if up else list(reversed(run)) + [notes[0]]):
            tr.add("xylo", bar, step + k * 0.5, ins.xylophone(m, 0.12), gain * (0.7 + 0.08 * k), -0.3 if up else 0.3)

    def glissando(bar, notes):
        """The xylophone runs up into the drop (and stops short of ringing on past the loop point)."""
        for k, m in enumerate([n + 12 for n in notes] + [n + 24 for n in notes]):
            tr.add("xylo", bar, 9.5 + k, ins.xylophone(m, 0.1), 0.4 + 0.06 * k, 0.2)

    def play_steel(first, notes, gain=1.0):
        """The steel guitar slides from each note into the next one when they're close and joined."""
        before = None
        for n in notes:
            joined = before is not None and before.step + before.length >= n.step - 0.01
            slide = float(before.midi - n.midi) if joined and abs(before.midi - n.midi) <= 5 else -1.0
            tr.add("steel", first, n.step, steel(n.midi, n.length * tr.step, slide), gain * n.vel)
            before = n

    # the crowd in the grandstand, all the way through the intro
    tr.add("crowd", 0, 0, crowd(tr.bar * 8), 1.0)
    for k in range(4):  # the bugle call drifts over from the starting post, nearer every bar
        tr.play("bugle", 0, [n for n in call if k * 16 <= n.step < (k + 1) * 16], bugle, 0.5 + 0.17 * k)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 38)  # D2..C#3
            fifth = root + 7 if root + 7 <= 50 else root - 5
            notes = voicing(c, 55, 67, prev)
            prev = notes
            beats = range(int(step), int(step + length), 4)
            if name == "intro":
                if local in (4, 5):  # the band strikes up as the riders come in
                    for k in (0, 8):
                        tr.add("bass", bar, k, ins.upright(root if k == 0 else fifth, tr.step * 6), 0.7 + 0.15 * (local - 4))
                        strum(tr, "guitar", bar, k, notes, lambda m, sec: ins.acoustic_guitar(m, sec, 2), tr.step * 6, 0.65 + 0.15 * (local - 4), spread=0.015, pan=0.25)
                elif local >= 6:
                    for k in beats:
                        tr.add("bass", bar, k, ins.upright(root if k % 8 == 0 else fifth, tr.step * 3), 0.85)
                    gallop_strum(bar, beats, notes, 0.55 + 0.2 * (local - 6))
                if local == part.bars - 1 and step == 0:
                    glissando(bar, notes)
                continue
            if name == "finish" and local == 3:  # ta... DA!
                for k in (0, 8):
                    tr.add("bass", bar, k, ins.upright(root, tr.step * 6), 1.0)
                    strum(tr, "guitar", bar, k, notes, lambda m, sec: ins.acoustic_guitar(m, sec, 3), tr.step * 6, 1.0, spread=0.01, pan=-0.2)
                continue
            if name == "lap" and local < 5:
                # a trot: the bass on 1 and 3, the guitar chopping every beat
                for k in (step, step + 8) if length >= 16 else (step,):
                    tr.add("bass", bar, k, ins.upright(root if k == step else fifth, tr.step * 6), 1.0)
                for k in beats:
                    strum(tr, "guitar", bar, k, notes, lambda m, sec: ins.acoustic_guitar(m, sec, 2), tr.step * 2.5, 0.8 if k % 8 == 0 else 0.65, spread=0.012, pan=0.25)
                continue
            # the gallop: the bass on every beat (root, fifth), the guitar galloping along
            for k in beats:
                tr.add("bass", bar, k, ins.upright(root if (k - step) % 8 == 0 else fifth, tr.step * 3), 1.0 if k % 8 == 0 else 0.85)
            gallop_strum(bar, beats, notes, 0.8 if name == "B" else 1.0)
            if name == "B":  # fairground sparkle: the glockenspiel rolls the chord
                for k, m in enumerate(notes + [notes[0] + 12]):
                    tr.add("glock", bar, step + 12 + k * 0.5, ins.glock(m + 24, 0.3), 0.5, 0.35)
                if local in (2, 6) and step == 0:  # a hop over a hurdle
                    flick(bar, 12, notes)
                if local == 5 and step == 0:  # somebody ran out of carrots: a spin-out
                    flick(bar, 10, notes, up=False, gain=0.7)
            if name in ("climax", "finish") and local % 2 == 0 and step == 0:
                strum(tr, "guitar", bar, 0, notes, lambda m, sec: ins.acoustic_guitar(m, sec, 3), tr.step * 4, 0.9, spread=0.01, pan=-0.2)
            if name == "lap" and local == part.bars - 1 and step == 0:
                glissando(bar, notes)

        for bar in part.bars_range():
            local = bar - part.first
            last = local == part.bars - 1
            if name == "intro":
                if local >= 4:  # the riders gallop in from far away
                    hooves(bar, "X.xxX.xxX.xxX.xx", 0.5 + 0.13 * (local - 4))
                    if local < 7:
                        hits("snare", bar, "o.ooo.ooo.ooo.oo", snares, 0.25 + 0.1 * (local - 4))
                if local >= 6:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.6 + 0.2 * (local - 6))
                if local == 3:
                    for k in range(0, 16, 2):
                        tr.add("snare", bar, 8 + k / 2, snares[k % 4], 0.1 + 0.02 * k)
                if local == 7:
                    for k in range(16):
                        tr.add("snare", bar, k, snares[k % 4], 0.3 + 0.04 * k)
                continue
            if name == "finish" and local == 3:
                tr.kick("kick", bar, "X.......X.......", kick)
                hits("snare", bar, "X.......X.......", snares)
                for k in (0, 8):
                    tr.add("crash", bar, k, crash, 1.0, -0.25 if k else 0.25)
                tr.add("crash", bar, 7.4, whip(), 0.9, 0.3)
                tr.add("crowd", bar - 2, 0, crowd(tr.bar * 6, True), 1.0)
                continue
            if local == 0:
                tr.add("crash", bar, 0, crash, 1.0, -0.25)
                tr.add("crash", bar, -0.6, whip(), 0.9, 0.3)
            if name == "lap" and local < 5:
                hooves(bar, "X...x...X...x...", 0.7)  # trotting
                tr.kick("kick", bar, "X.......X.......", kick, 0.7)
                hits("snare", bar, "....x.......x...", snares, 0.6)
                continue
            if name == "lap" and local == 5:
                hooves(bar, "X.x.X.x.X.x.X.x.", 0.75)  # picking up speed again
                tr.kick("kick", bar, "X...X...X...X...", kick, 0.8)
                hits("snare", bar, "....x.......x.x.", snares, 0.7)
                continue
            hooves(bar, "X.xxX.xxX.xxX.xx", 1.0 if name != "B" else 0.8)
            tr.kick("kick", bar, "X...X...X...X...", kick)
            hits("snare", bar, "o.ooX.ooo.ooX.oo" if name != "B" else "....X.......X.o.", snares)
            if name in ("climax", "finish"):
                hits("crash", bar, "....x.......x...", [tamb], 0.8, 0.4)
            if last and name in ("A", "B", "climax", "lap"):
                for k in range(8, 16):
                    if k >= 12:
                        tr.add("toms", bar, k, toms[(k - 12) // 2 + (k == 15)], 0.9)
                    else:
                        tr.add("snare", bar, k, snares[k % 4], 0.5 + 0.06 * (k - 8))
            if name == "finish" and local == 2:  # a roll up to the finish line
                for k in range(16):
                    tr.add("snare", bar, k, snares[k % 4], 0.35 + 0.04 * k)
            if name == "climax" and local == 0:
                tr.add("crowd", bar, 0, crowd(tr.bar * 6, True), 0.7)

    tr.play("lead", 8, tune, harmonica)
    play_steel(16, fair)
    tr.play("glock", 16, shift(fair, 12), ins.glock, 0.5, pan=-0.25)
    climax = shift(tune, 2)
    tr.play("lead", 24, climax, harmonica)
    tr.play("lead2", 24, harmony(climax, 24, parts), harmonica, pan=-0.3)
    tr.play("xylo", 24, shift(climax, 12), ins.xylophone, 0.6, pan=0.3)
    tr.play("brass", 24, descant, trumpets, 0.8, pan=0.2)
    tr.play("lead", 32, ending, harmonica)
    tr.play("lead2", 32, harmony(ending, 32, parts), harmonica, pan=-0.3)
    tr.play("brass", 32, shift(ending, -12), trumpets, 0.9, pan=0.2)
    tr.play("lead", 36, lap, harmonica, 0.9)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.15),
        "lead2": Bus(-13, reverb=0.15),
        "steel": Bus(-5, reverb=0.2, delay=0.1),
        "glock": Bus(-15, reverb=0.25),
        "xylo": Bus(-15, reverb=0.2),
        "bugle": Bus(-15, reverb=0.5, delay=0.15),
        "brass": Bus(-10, reverb=0.2),
        "bass": Bus(-9),
        "guitar": Bus(-12, reverb=0.1),
        "hooves": Bus(-13, reverb=0.08),
        "kick": Bus(-12),
        "snare": Bus(-14, reverb=0.1, eq=(("lp", 8500),)),
        "toms": Bus(-15, reverb=0.1),
        "crash": Bus(-18, eq=(("lp", 9000),)),
        "crowd": Bus(-21, reverb=0.2),
    }, reverb_decay=1.5, reverb_tone=5500, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("RockinRaceway", "Giddy-Up Gallop", 142, 8, 44, rockin_raceway)
