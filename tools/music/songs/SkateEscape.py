"""Canyon Grind: the round song for SkateEscape (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from score import Note

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def harmony(notes, first, parts, spb=16):
    """A second voice under the tune: for every note, the nearest chord tone at least a minor third
    below it (in the chord playing under that note), so the twin line never rubs against the band."""
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
def lead_guitar(m, sec):
    """A singing overdriven lead: a bright pick pushed hard into the amp (so it sustains), a little
    scoop into every note and finger vibrato on the held ones, through a speaker cabinet."""
    pluck = np.asarray(ins.ks(m, sec + 0.3, bright=0.85, decay=4.5, pick=0.13, soft=0.05))
    t = np.arange(pluck.shape[-1]) / s.SR
    pitch = -0.3 * np.exp(-t / 0.018)
    if sec > 0.28:
        pitch = pitch + 0.24 * np.clip((t - 0.16) / 0.22, 0, 1) * np.sin(2 * np.pi * 5.8 * t)
    tone = ins.drive(ins.bend(pluck, pitch) * 5.0, 4.0)
    tone = ins.eq(tone, ("hp", 240), ("peak", 800, 2.0, 0.8), ("peak", 2300, 3.0, 1.5), ("lp", 4600), ("lp", 6200))
    return ins.normalize(ins._gate(tone, sec + 0.02, 0.08))


@lru_cache(maxsize=None)
def gang(m, sec, vowel="oh"):
    """The skaters shouting along ("whoa-oh!", or "hey!" with vowel "eh"): five rough voices, a little
    out of time and tune with each other, scooping up into the note."""
    n = s.samples(sec + 0.2)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(int(m * 100 + sec * 1000))
    out = np.zeros((2, n))
    for k, (detune, pos) in enumerate(((-0.14, -0.7), (0.11, 0.7), (0.0, 0.0), (-0.06, -0.35), (0.07, 0.35))):
        late = int(rng.uniform(0, 0.025) * s.SR)
        pitch = m + detune - 0.8 * np.exp(-t / 0.05) + 0.12 * np.sin(2 * np.pi * (5.0 + 0.4 * k) * t + k)
        voice = s.saw(s.midi_hz(pitch), n, start=0.21 * k) * 0.7 + s.square(s.midi_hz(pitch), n, 0.4) * 0.3
        out += s.pan(np.concatenate([np.zeros(late), voice[: n - late]]), pos)
    peaks = {"oh": [(480, 12, 4), (820, 9, 5), (2500, 4, 6)], "eh": [(550, 11, 4), (1800, 9, 5), (2600, 5, 6)]}[vowel]
    out = ins.eq(ins.formant(out, peaks), ("hp", 180), ("lp", 3800))
    out = ins.drive(out / np.max(np.abs(out)) * 2.0, 1.6)
    return ins.normalize(out * ins.env(n, 0.03, 0.3, 0.8, 0.12, gate=sec))


@lru_cache(maxsize=None)
def punk_kick():
    """A tight kick that punches at 60-200 Hz, where a phone can play it, rather than booming below."""
    n = s.samples(0.28)
    t = np.arange(n) / s.SR
    body = s.sine(58 + 150 * np.exp(-t / 0.028), n) * np.exp(-t / 0.11)
    click = ins.eq(np.random.default_rng(4).uniform(-1, 1, n), ("hp", 1500), ("lp", 6000)) * np.exp(-t / 0.004) * 0.5
    return ins.normalize(np.tanh((body + click) * 1.8))


@lru_cache(maxsize=None)
def crumble(length=1.8, seed=3):
    """The bridge giving way behind the pack: a low rumble with planks cracking in it."""
    rng = np.random.default_rng(seed)
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rumble = ins.eq(rng.uniform(-1, 1, n), ("hp", 75), ("lp", 320)) * np.clip(t / 0.08, 0, 1) * np.exp(-t / (length * 0.45))
    cracks = np.zeros(n)
    for _ in range(9):
        start = int(rng.uniform(0, 0.7) * n)
        size = min(n - start, s.samples(0.08))
        burst = ins.eq(rng.uniform(-1, 1, size), ("hp", 500), ("lp", 3000)) * np.exp(-np.arange(size) / (s.SR * 0.012))
        cracks[start:start + size] += burst * rng.uniform(0.4, 1.0)
    return ins.normalize(rumble * 1.2 + cracks)


@lru_cache(maxsize=None)
def lava(length):
    """The lava river far below: a slow dark swell of noise."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(29)
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / 3.1) * np.sin(2 * np.pi * t / 1.7 + 1.0)
    return ins.normalize(ins.eq(rng.uniform(-1, 1, n), ("hp", 90), ("lp", 420)) * swell * np.clip(t / 2.5, 0, 1))


def skate_escape():
    """Canyon Grind (175 bpm, E minor): skate punk on a crumbling bridge over a lava canyon. Two
    power-chord guitars, a picked bass, a singing lead guitar and a gang shouting "whoa-oh" over the
    skate beat. The verse rides a 3-3-2 hook, the chorus opens out in G major, and the climax goes up
    to A major while the collapse chases the pack to the finish line: its last bar, a band-wide stop,
    lands just after the collapse reaches the line (42 s after GO). Then a half-time breakdown and a
    guitar solo that lands back on the drop."""
    tr = Track(bpm=175, bars=54)
    parts = plan(tr, [
        ("intro", 10, "Em | Em | C | D | Em | Em | G | D | C | B"),
        ("A1", 8, "Em | Em | C | D | Em | Em | C | D"),
        ("A2", 8, "Em | Em | C | D | Em | Em | C | D"),
        ("chorus", 8, "G | D | Em | C | G | D | C | D"),
        ("climax", 8, "A | E | F#m | D | A | E | D | E"),
        ("break", 4, "Em | C | Em | D"),
        ("solo", 8, "C | D | Em | Em | C | D | B | B"),
    ])
    verse = melody("""E5:3 E5:3 G5:2 ~:2 A5:2 B5:4 | A5:3 G5:3 E5:2 ~:4 r:4 | E5:3 E5:3 G5:2 ~:2 A5:2 C6:4 | B5:3 A5:3 F#5:2 ~:4 r:2 D5:2 |
                      E5:3 E5:3 G5:2 ~:2 A5:2 B5:4 | D6:3 B5:3 A5:2 ~:2 G5:2 A5:4 | G5:3 E5:3 C5:2 ~:2 E5:2 G5:4 | F#5:3 G5:3 A5:2 ~:8""")
    chorus = melody("""B5:6 A5:2 G5:4 D5:4 | A5:6 G5:2 F#5:4 D5:4 | G5:6 F#5:2 E5:4 B4:4 | C5:4 E5:4 G5:4 A5:4 |
                       B5:6 A5:2 G5:4 D5:4 | D6:6 C6:2 B5:4 A5:4 | G5:4 A5:4 B5:4 C6:4 | D6:12 r:4""")
    climax = melody("""C#6:6 B5:2 A5:4 E5:4 | B5:6 A5:2 G#5:4 E5:4 | A5:6 G#5:2 F#5:4 C#5:4 | D5:4 F#5:4 A5:4 B5:4 |
                       C#6:6 B5:2 A5:4 E5:4 | E6:6 D6:2 C#6:4 B5:4 | A5:4 B5:4 C#6:4 D6:4 | E6:3 E6:3 E6:2 ~:8""")
    tease = melody("B5:6 A5:2 G5:4 D5:4 | A5:6 G5:2 F#5:8")
    breakdown = melody("r:16 | r:16 | E5:3 E5:3 G5:2 ~:2 A5:2 B5:4 | D6:3 B5:3 A5:2 ~:8")
    solo = melody("""G5:2 A5:2 B5:2 C6:2 E6:4 D6:2 C6:2 | D6:4 A5:2 F#5:2 A5:2 D6:2 F#6:4 | E6:6 D6:2 B5:2 G5:2 E5:4 |
                     G5:1 A5:1 B5:1 D6:1 E6:1 D6:1 B5:1 A5:1 G5:1 A5:1 B5:1 D6:1 E6:4 | C6:4 E6:4 G6:4 E6:4 |
                     F#6:4 D6:4 A5:4 F#5:4 | D#6:6 B5:2 F#5:4 A5:4 | B5:1 A5:1 G5:1 F#5:1 E5:1 F#5:1 G5:1 A5:1 B5:4 D#5:4""")

    kick = punk_kick()
    snares = [ins.snare2(205.0, 1.0, 0.22, v) for v in range(4)]
    chat, ohat, crash = s.hat(False), s.hat(True), s.crash(1.8)
    ride = ins.ride(1.0, 0.45)
    toms = [ins.tom(p, 0.35, v) for v, p in enumerate((175.0, 130.0, 95.0))]
    sides = ((0, -0.75), (1, 0.75))  # two rhythm guitars, hard left and right

    def hits(stem, bar, pattern, sounds, gain=1.0, pan=0.0):
        for k, (step, vel) in enumerate((i, {"X": 1.0, "x": 0.8, "o": 0.45}[ch]) for i, ch in enumerate(pattern) if ch != "."):
            tr.add(stem, bar, step, sounds[k % len(sounds)], gain * vel, pan)

    def fill(bar, start=8, gain=1.0):
        """Snare 16ths, then down the toms, into the next section."""
        for k in range(start, 16):
            if k < 12:
                tr.add("snare", bar, k, snares[k % 4], gain * (0.55 + 0.04 * k))
            else:
                tr.add("toms", bar, k, toms[{12: 0, 13: 0, 14: 1, 15: 2}[k]], gain * 0.95)

    def chug(bar, steps, root, mute, gain=1.0, octave=False):
        for k in steps:
            accent = gain * (1.0 if k % 4 == 0 else 0.82)
            for side, pan in sides:
                tr.add("rhythm", bar, k + 0.07 * side, ins.power_chord(root, tr.step * 1.8, mute, side), accent, pan)
            if octave:  # a third guitar an octave up, for the big parts
                tr.add("rhythm", bar, k + 0.12, ins.power_chord(root + 12, tr.step * 1.8, False, 4), accent * 0.55, 0.1)

    def band_hits(bar, root, low, hold=True):
        """The whole band on the 3-3-2 (and a held chord after it)."""
        for k in (0, 3, 6):
            for side, pan in sides:
                tr.add("rhythm", bar, k + 0.07 * side, ins.power_chord(root, tr.step * 2.6, False, side), 1.0, pan)
            tr.add("bass", bar, k, ins.bass_guitar(low, tr.step * 2.6, 0.6), 1.0)
        tr.kick("kick", bar, "X..X..X.........", kick)
        hits("snare", bar, "X..X..X.........", snares)
        tr.add("cymbal", bar, 0, crash, 1.0, 0.3)
        tr.add("cymbal", bar, 6, crash, 0.8, -0.3)
        if hold:
            for side, pan in sides:
                tr.add("rhythm", bar, 8 + 0.07 * side, ins.power_chord(root, tr.step * 8, False, side + 2), 0.75, pan)
            tr.add("bass", bar, 8, ins.bass_guitar(low, tr.step * 7.5, 0.6), 0.8)

    def hey(bar, step, low=52):
        """The gang shouts HEY! (on B3 and, under it, the chord's E3 or F#3)."""
        tr.add("gang", bar, step, gang(59, 0.16, "eh"), 1.0)
        tr.add("gang", bar, step, gang(low, 0.16, "eh"), 0.8)

    # the canyon before the start: lava far below, wind across the bridge, a fire crackling
    tr.add("fx", 0, 0, lava(tr.bar * 8), 0.7)
    tr.add("fx", 0, 0, ins.crackle(tr.bar * 4), 0.3)
    for bar, up in ((1, True), (5, False)):
        tr.add("fx", bar, 4, ins.whoosh(tr.bar * 1.6, up), 0.5, -0.4 if up else 0.4)
    for bar, step, pitch in ((0, 6, 70.0), (1, 11, 60.0), (2, 3, 80.0), (3, 9, 65.0)):
        tr.add("fx", bar, step, ins.bloop(pitch, 1.8, 0.25), 0.35, -0.3)

    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 40)  # the power chord's root, E2..D#3
            low = bass_note(c, 36)  # the bass guitar, C2..B2
            beats = range(int(step), int(step + length), 2)
            if name == "intro":
                if local < 8:  # a clean guitar picks the chords, ringing out over the canyon
                    ring = [root, root + 7, root + 12, root + 12 + c.intervals[1], root + 19]
                    for k, idx in enumerate((0, 1, 2, 3, 4, 3, 2, 1)):
                        tr.add("clean", bar, k * 2, ins.electric_guitar(ring[idx], tr.step * 4, False, k), 0.28 + 0.1 * local, 0.25)
                if 4 <= local < 8:  # the band creeps in under it
                    chug(bar, beats, root, True, 0.25 + 0.12 * (local - 4))
                    for k in beats:
                        tr.add("bass", bar, k, ins.bass_guitar(low, tr.step * 1.8, 0.5, k % 3), 0.35 + 0.15 * (local - 4))
                elif local == 8:
                    band_hits(bar, root, low, hold=False)
                    chug(bar, range(8, 16, 2), root, True, 0.75)
                    for k in range(8, 16, 2):
                        tr.add("bass", bar, k, ins.bass_guitar(low, tr.step * 1.8, 0.5, k % 3), 0.8)
                elif local == 9:
                    band_hits(bar, root, low)
            elif name == "climax" and local == part.bars - 1:
                band_hits(bar, root, low)  # the finish line
                hey(bar, 6)
            elif name == "break":
                riff = [0, 0, 12, 0, 7, 0, 12, 7] if local % 2 == 0 else [0, 0, 12, 0, 7, 12, 7, 0]
                for k, off in enumerate(riff):
                    tr.add("bass", bar, k * 2, ins.bass_guitar(low + off, tr.step * 1.8, 0.7, k % 3), 1.0 if k % 2 == 0 else 0.85)
                if local >= 2:  # the guitars come back chugging the 3-3-2
                    for k in (0, 3, 6, 8, 11, 14):
                        big = k in (0, 8)
                        for side, pan in sides:
                            tr.add("rhythm", bar, k + 0.07 * side, ins.power_chord(root, tr.step * (2.6 if big else 1.6), not big, side), 1.0 if big else 0.75, pan)
            else:
                chug(bar, beats, root, name == "A1", octave=name in ("chorus", "climax"))
                for k in beats:  # the bass drives 8ths on the root (an octave pop in the climax)
                    off = 12 if name == "climax" and k % 8 == 6 else 0
                    tr.add("bass", bar, k, ins.bass_guitar(low + off, tr.step * 1.8, 0.55, k % 3), 1.0 if k % 4 == 0 else 0.85)

        for bar in part.bars_range():
            local = bar - part.first
            last = local == part.bars - 1
            if name == "intro":
                if 4 <= local < 8:
                    hits("toms", bar, "X...x...X...x...", [toms[2]], 0.3 + 0.12 * (local - 4))
                    hits("hats", bar, "x.x.x.x.x.x.x.x." if local >= 6 else "x...x...x...x...", [chat], 0.5 + 0.1 * (local - 4))
                if local == 7:
                    fill(bar, 12, 0.7)
                if local == 8:
                    hits("hats", bar, "........x.x.x.x.", [chat], 0.8)
                    tr.kick("kick", bar, "........X...X...", kick, 0.8)
                if local == 9:
                    for k in range(8, 16):
                        tr.add("snare", bar, k, snares[k % 4], 0.35 + 0.08 * (k - 8))
                    tr.add("riser", bar - 1, 0, s.riser(tr.bar * 2), 1.0)
                    hey(bar, 14, 54)
                continue
            if name == "break":
                # half time, then the kick doubles the guitars' 3-3-2 chugs
                tr.kick("kick", bar, "X.........X....." if local < 2 else ("X..X..X.X..X..X." if local == 2 else "X..X..X........."), kick)
                hits("snare", bar, "........X.......", snares)
                hits("hats", bar, "x...x...x...x...", [ohat], 0.7)
                if local == 0:
                    tr.add("fx", bar, 0, crumble(), 1.0)
                if local == 3:
                    fill(bar, 8, 0.9)
                continue
            if name == "climax" and last:
                fill(bar, 12)
                continue
            if local == 0:
                tr.add("cymbal", bar, 0, crash, 1.0, -0.3)
            if name == "chorus":
                # the big two-beat: kick on every beat, snare on 2 and 4, a ride in 8ths, crash every two bars
                tr.kick("kick", bar, "X...X...X...X...", kick)
                hits("snare", bar, "....X.......X...", snares)
                hits("cymbal", bar, "x.x.x.x.x.x.x.x.", [ride], 0.8, -0.2)
                if local % 2 == 0 and local:
                    tr.add("cymbal", bar, 0, crash, 0.9, 0.3)
            else:
                # the skate beat: kick on every beat, snare on every off-beat
                tr.kick("kick", bar, "X...X...X...X...", kick)
                hits("snare", bar, "..X...X...X...X." if not last else "..X...X.........", snares)
                if name == "climax":
                    hits("cymbal", bar, "x...x...x...x...", [crash], 0.55, -0.3)
                elif name == "solo":
                    hits("cymbal", bar, "x.x.x.x.x.x.x.x.", [ride], 0.75, -0.2)
                else:
                    hits("hats", bar, "x.x.x.x.x.x.x.x." if name == "A1" else "X.x.X.x.X.x.X.x.", [chat], 0.7, 0.25)
                    if name == "A2":
                        hits("hats", bar, "..x...x...x...x.", [ohat], 0.5, -0.25)
            if last:
                fill(bar)
                if name == "solo":
                    tr.add("riser", bar - 1, 0, s.riser(tr.bar * 2), 0.9)
            if name == "climax" and local == 0:
                tr.add("fx", bar, 0, crumble(2.4, 5), 0.8)

    tr.play("lead", 6, tease, lead_guitar, 0.75)
    tr.play("lead", 10, verse, lead_guitar)
    tr.play("lead", 18, verse, lead_guitar)
    tr.play("lead2", 18, harmony(verse, 18, parts), lead_guitar, pan=0.3)
    tr.play("lead", 26, chorus, lead_guitar)
    tr.play("lead", 34, climax, lead_guitar)
    tr.play("lead2", 34, harmony(climax, 34, parts), lead_guitar, pan=0.3)
    for first, tune in ((26, chorus), (34, climax)):
        for n in tune:  # the gang sings the chorus, an octave and two below
            tr.add("gang", first, n.step, gang(n.midi - 12, n.length * tr.step), n.vel)
            tr.add("gang", first, n.step, gang(n.midi - 24, n.length * tr.step), n.vel * 0.8)
    tr.play("lead", 42, breakdown, lead_guitar, 0.85)
    tr.play("lead", 46, solo, lead_guitar)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.12, delay=0.1),
        "lead2": Bus(-12, reverb=0.12),
        "gang": Bus(-10, reverb=0.22),
        "rhythm": Bus(-8, eq=(("peak", 2000, -3, 1.0),)),
        "clean": Bus(-12, spring=0.35, delay=0.12),
        "bass": Bus(-10),
        "kick": Bus(-10, drive=1.3),
        "snare": Bus(-12, reverb=0.08),
        "toms": Bus(-14, reverb=0.08),
        "hats": Bus(-21, eq=(("lp", 9000),)),
        "cymbal": Bus(-18, eq=(("lp", 9000),)),
        "fx": Bus(-15, reverb=0.3),
        "riser": Bus(-17, eq=(("lp", 8000),)),
    }, reverb_decay=1.3, reverb_tone=5000, delay_time=tr.beat * 0.75, delay_feedback=0.28)
    return finish(tr, mix), tr


SONG = Song("SkateEscape", "Canyon Grind", 175, 10, 54, skate_escape)
