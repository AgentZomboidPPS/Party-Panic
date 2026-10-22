"""Sandlot Smash: the round song for Struggle (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from score import Note
from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


# ---------------------------------------------------------------- the sandlot's own sounds

@lru_cache(maxsize=None)
def riff_organ(m, sec):
    """The riff organ: a tonewheel organ, first drawbars out, its rotary speaker on fast and driven
    hard into the amp so it growls."""
    x = np.array(ins.organ(m, sec, drawbars=(8, 8, 8, 6, 0, 0, 0, 0, 3), leslie=6.8, click=0.8))
    x = ins.drive(x * 1.6, 2.2)
    return ins.normalize(ins.eq(x, ("hp", 120), ("peak", 900, 2, 1.0), ("lp", 5000)))


@lru_cache(maxsize=None)
def ballpark_organ(m, sec):
    """The stadium organ for the big tunes: nearly every drawbar out and a slow chorale swirl."""
    x = np.array(ins.organ(m, sec, drawbars=(6, 4, 8, 8, 6, 6, 4, 0, 4), leslie=1.3, click=0.4))
    return ins.normalize(ins.eq(x, ("hp", 150), ("peak", 1600, 2, 1.0), ("lp", 6000)))


@lru_cache(maxsize=None)
def organ_chord(notes, sec, leslie=1.0):
    """Held organ chords under the tunes: a mellow 16'+8'+4' registration."""
    out = sum(np.asarray(ins.organ(m, sec, drawbars=(6, 0, 8, 4, 0, 0, 0, 0, 0), leslie=leslie, click=0.2)) for m in notes)
    return ins.normalize(ins.eq(out / len(notes) ** 0.7, ("hp", 110), ("lp", 4200)))


@lru_cache(maxsize=None)
def crowd_voice(m, sec):
    """The crowd singing: men and women an octave apart, two loose layers that never quite line up."""
    a = np.asarray(ins.choir((m - 12, m), sec, "ah", attack=0.05))
    b = np.asarray(ins.choir((m - 11.88, m + 0.1), sec, "eh", attack=0.09))
    out = np.zeros((2, max(a.shape[1], b.shape[1]) + s.samples(0.02)))
    out[:, : a.shape[1]] += a
    out[:, s.samples(0.02): s.samples(0.02) + b.shape[1]] += b * 0.7
    return ins.normalize(ins.eq(out, ("hp", 160), ("lp", 4000)))


@lru_cache(maxsize=None)
def hey(pitch=55.0, length=0.32, seed=0, voices=12):
    """The crowd's 'HEY!': a dozen voices, men and women, each a shouted fall. Stereo."""
    n = s.samples(length + 0.12)
    rng = np.random.default_rng(seed)
    out = np.zeros((2, n))
    for v in range(voices):
        start = s.samples(rng.uniform(0.0, 0.035))
        m = n - start
        t = np.arange(m) / s.SR
        base = pitch + (12 if v % 3 == 0 else 0) + rng.uniform(-2.0, 4.0)
        contour = base + 2.0 * np.exp(-t / 0.04) - 3.0 * np.clip(t / length, 0, 1) ** 2
        f = s.midi_hz(contour)
        src = s.saw(f, m, start=rng.random()) + 0.25 * s.square(f, m, 0.35)
        e = np.clip(t / 0.01, 0, 1) * np.exp(-t / (length * 0.5))
        h = s.bandpass(rng.uniform(-1, 1, m), 900, 3500) * np.exp(-t / 0.03) * 0.5
        voice = ins.formant(src * e, [(620, 12, 4), (1750, 10, 5), (2600, 6, 6)]) + h
        out[:, start:] += s.pan(voice, rng.uniform(-0.7, 0.7))
    return ins.normalize(ins.eq(out, ("hp", 180), ("lp", 4200)))


@lru_cache(maxsize=None)
def crowd(length, cheer=0.0, seed=0):
    """A crowd on the bleachers (stereo): a murmur of many voices; `cheer` swells it into a roar with
    a few whoops."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(500 + seed)
    out = np.zeros((2, n))
    for ch in range(2):
        for _ in range(6):  # bands of babble, each fluttering at its own syllable rate
            lo = rng.uniform(250, 600)
            band = s.bandpass(rng.uniform(-1, 1, n), lo, lo * rng.uniform(2.2, 3.4))
            out[ch] += band * (0.65 + 0.35 * np.sin(2 * np.pi * rng.uniform(2.5, 6.0) * t + rng.uniform(0, 6)))
    if cheer:
        rise = np.clip(t / (length * 0.35), 0, 1) ** 1.5 * np.exp(-np.clip(t - length * 0.35, 0, None) / (length * 0.4))
        roar = np.vstack([s.bandpass(rng.uniform(-1, 1, n), 400, 3000) for _ in range(2)])
        out = out * (1 - 0.5 * rise) + roar * rise * 3.0 * cheer
        for _ in range(int(4 * cheer)):  # whoops
            at = rng.uniform(0.15, 0.6) * length
            k = s.samples(at)
            m = min(n - k, s.samples(0.5))
            tt = np.arange(m) / s.SR
            whoop = np.sin(2 * np.pi * np.cumsum(s.midi_hz(76 + rng.uniform(-3, 3) + 7 * np.clip(tt / 0.25, 0, 1))) / s.SR)
            out[:, k:k + m] += s.pan(whoop * np.sin(np.pi * tt / (m / s.SR)) * 0.08, rng.uniform(-0.8, 0.8))
    return ins.normalize(ins.eq(out, ("hp", 200), ("lp", 4500)))


@lru_cache(maxsize=None)
def stomp(variant=0):
    """The crowd stomping on wooden bleachers: a hollow boom and the planks' knock, many feet at once."""
    n = s.samples(0.5)
    rng = np.random.default_rng(300 + variant)
    out = np.zeros(n)
    for _ in range(9):
        start = s.samples(rng.uniform(0, 0.028))
        m = n - start
        t = np.arange(m) / s.SR
        f = 95 * (1 + 0.6 * np.exp(-t / 0.02)) * rng.uniform(0.9, 1.1)
        boom = np.sin(2 * np.pi * np.cumsum(f) / s.SR) * np.exp(-t / 0.09)
        plank = s.bandpass(rng.uniform(-1, 1, m), 180, 1400) * np.exp(-t / 0.03) * 0.8
        out[start:] += (boom + plank) * rng.uniform(0.6, 1.0)
    out = ins.formant(out, [(210, 6, 1.5), (520, 3, 1.5)])
    return ins.normalize(ins.eq(out, ("hp", 60), ("lp", 3500)))


@lru_cache(maxsize=None)
def crowd_clap(variant=0):
    """A crowd clapping together, never quite together. Stereo."""
    n = s.samples(0.3)
    rng = np.random.default_rng(400 + variant)
    out = np.zeros((2, n))
    for ch in range(2):
        for _ in range(9):
            start = s.samples(rng.uniform(0, 0.03))
            m = n - start
            burst = s.bandpass(rng.uniform(-1, 1, m), rng.uniform(700, 1100), rng.uniform(2200, 3500))
            out[ch, start:] += burst * np.exp(-np.arange(m) / (s.SR * rng.uniform(0.008, 0.016))) * rng.uniform(0.5, 1.0)
    return ins.normalize(ins.eq(out, ("hp", 400), ("lp", 7000)))


def crowd_line(tr, stem, bar, notes, gain=1.0, rng=None):
    """The crowd sings a line: each note a little late or early, like a stand full of people."""
    rng = rng or np.random.default_rng(int(bar))
    for n in notes:
        late = rng.uniform(0.0, 0.25)  # in steps
        tr.add(stem, bar, n.step + late, crowd_voice(n.midi, max(0.1, n.length * tr.step * 0.9)), gain * n.vel)


# ---------------------------------------------------------------- the song

def struggle():
    """Sandlot Smash (120 bpm, A minor): a stadium organ rock anthem for a foam-bat brawl on a sunset
    sandlot. A growling organ riff, rock drums, bleacher stomps and claps; the crowd chants
    'whoa-oh' and the organ answers; a sing-along chorus in C on the ballpark organ; a climbing charge
    with the crowd's HEY!s, then the last chorus a step up in D with everybody singing."""
    tr = Track(bpm=120, bars=44)
    parts = plan(tr, [
        ("intro", 8, "Am | Am | F | G | Am | Am | F | E7"),
        ("riff", 8, "Am | Am | Am | Am | F | G | Am | E7"),
        ("chant", 8, "Am | F | C | G | Am | F | G | E7"),
        ("chorus", 8, "C | G | Am | F | C | G | F G | C"),
        ("charge", 4, "F | G | A | A"),
        ("final", 8, "D | A | Bm | G | D | A | G A | D E7"),
    ])
    riff = melody("""A4:2 r:1 A4:1 C5:2 D5:2 Eb5:1 E5:2 r:1 G5:2 E5:2 | D5:2 C5:2 A4:2 G4:2 A4:6 r:2 |
                     A4:2 r:1 A4:1 C5:2 D5:2 Eb5:1 E5:2 r:1 A5:2 G5:2 | E5:2 D5:2 C5:2 D5:2 E5:6 r:2 |
                     F5:2 r:1 F5:1 E5:2 C5:2 A4:2 C5:2 F5:4 | G5:2 r:1 G5:1 F5:2 D5:2 B4:2 D5:2 G5:4 |
                     A5:2 G5:2 E5:2 D5:2 C5:2 A4:2 C5:2 D5:2 | E5:4 G#4:2 B4:2 D5:4 E5:2 r:2""")
    chant = melody("""A4:4 C5:4 E5:6 D5:2 | C5:4 A4:4 C5:8 | G4:4 C5:4 E5:6 D5:2 | D5:4 B4:4 G4:8 |
                      A4:4 C5:4 E5:6 G5:2 | A5:6 G5:2 F5:4 E5:4 | D5:4 E5:2 D5:2 B4:4 G4:4 | G#4:4 B4:4 E5:8""")
    answers = melody("""r:16 | r:10 A5:1 C6:1 A5:1 F5:1 C5:2 | r:16 | r:10 B5:1 D6:1 B5:1 G5:1 D5:2 |
                        r:16 | r:16 | r:16 | r:8 E5:1 G#5:1 B5:1 D6:1 E6:2 D6:1 B5:1""")
    tune = melody("""E5:4 E5:2 F5:2 G5:4 E5:4 | D5:4 D5:2 E5:2 F5:4 D5:4 | C5:4 C5:2 D5:2 E5:4 A5:4 | G5:6 F5:2 E5:4 C5:4 |
                     E5:4 E5:2 F5:2 G5:4 C6:4 | B5:4 B5:2 A5:2 G5:4 D5:4 | A5:4 G5:2 F5:2 G5:4 F5:2 D5:2 | E5:4 D5:2 E5:2 C5:8""")
    charge = melody("""A4:2 C5:2 F5:3 E5:1 F5:2 A5:2 G5:2 F5:2 | B4:2 D5:2 G5:3 F#5:1 G5:2 B5:2 A5:2 G5:2 |
                       C#5:2 E5:2 A5:3 G#5:1 A5:2 C#6:2 B5:2 A5:2 | E6:12 r:4""")
    home = melody("F#5:4 E5:2 F#5:2 D5:4 B4:2 G#4:2")  # the last bar: down to the riff's A
    final = [n for n in shift(tune, 2) if n.step < 7 * 16] + shift(home, 0, 7 * 16)

    kick = s.kick(1.0, 0.4)
    snare = ins.snare2(190.0, 1.0, 0.3)
    roll = ins.snare2(200.0, 0.9, 0.14, variant=2)
    chat, ohat = s.hat(False), s.hat(True)
    ride = ins.ride(1.0, 0.35)
    toms = [ins.tom(p, 0.4) for p in (190.0, 140.0, 100.0)]
    stomps = [stomp(v) for v in range(3)]
    claps = [crowd_clap(v) for v in range(3)]
    rng = np.random.default_rng(21)

    # ---- the intro: the crowd fills the bleachers while the organist warms up
    tr.add("crowd", 0, 0, crowd(tr.bar * 8, 0.0, 1), 0.5)
    tr.add("crowd", 6, 0, crowd(tr.bar * 3, 1.0, 2), 0.8)  # the roar as the bats come out
    for k, m in enumerate((60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84)):  # a palm glissando up
        tr.add("melody", 3, 12 + k * 4 / 15, ballpark_organ(m, 0.06), 0.12 + 0.012 * k)
    tr.play("organ", 4, [n for n in riff if n.step < 32], riff_organ, 0.5)  # the riff, teased
    tr.add("fx", 6, 0, s.riser(tr.bar * 2), 0.5)
    for k, m in enumerate((64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84, 86, 88)):
        tr.add("melody", 7, 12 + k * 4 / 15, ballpark_organ(m, 0.06), 0.22 + 0.015 * k)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 40)
            seconds = length * tr.step * (0.6 if name == "final" and bar == part.first + 7 and step == 8 else 1.0)
            notes = voicing(c, 55, 67, prev, size=3)
            prev = notes
            five = root + 7 if root + 7 <= 52 else root - 5
            # ---- the organ chords
            if name == "intro" and local < 4:
                tr.add("chords", bar, step, organ_chord(tuple(notes), seconds, 0.8), 0.45 + 0.1 * local)
            elif name == "intro" or name in ("chant", "chorus", "final"):
                tr.add("chords", bar, step, organ_chord(tuple(notes), seconds, 1.0 if name != "final" else 6.0), 0.8 if name == "intro" else 1.0)
            elif name == "charge":  # the organ pumps the chord on every beat, harder each bar
                for k in range(4):
                    tr.add("chords", bar, step + 4 * k, organ_chord(tuple(n + 12 for n in notes), tr.step * 2.5, 6.0), 0.6 + 0.12 * local + 0.03 * k)
            # ---- bass
            if name == "intro":
                if local >= 6:
                    for k in range(8):
                        tr.add("bass", bar, 2 * k, ins.bass_guitar(root, tr.step * 1.8), 0.6 + 0.15 * (local - 6))
            elif name == "chant":
                for st, m, vel in ((0, root, 1.0), (6, root, 0.8), (8, root, 0.9), (14, five, 0.7)):
                    tr.add("bass", bar, st, ins.bass_guitar(m, tr.step * 1.8), vel)
            elif name != "riff":  # chorus, charge, final: driving eighths
                count = int(length // 2)
                for k in range(count):
                    m = five if name == "final" and k % 4 == 3 else root
                    level = 0.6 + 0.15 * local if name == "charge" else 1.0
                    tr.add("bass", bar, step + 2 * k, ins.bass_guitar(m, tr.step * 1.7), level * (1.0 if k % 2 == 0 else 0.85))
            # ---- guitar: power chords under the organ
            pc = root + 12  # an octave over the bass
            if name == "riff":
                for k in range(8):
                    tr.add("guitar", bar, step + 2 * k, ins.power_chord(pc, tr.step * 1.5, mute=k not in (0, 4), variant=k), 1.0 if k in (0, 4) else 0.55)
            elif name == "chant":
                tr.add("guitar", bar, step, ins.power_chord(pc, seconds * 0.9), 0.8)
            elif name in ("chorus", "final"):
                for k in range(int(length // 2)):
                    tr.add("guitar", bar, step + 2 * k, ins.power_chord(pc, tr.step * 1.6, mute=k % 2 == 1, variant=k), 0.9 if k % 2 == 0 else 0.6)
            elif name == "charge" and local >= 2:
                for k in range(4):
                    tr.add("guitar", bar, step + 4 * k, ins.power_chord(pc, tr.step * 3), 0.7 + 0.15 * (local - 2))

        # ---- drums, stomps and claps
        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if 2 <= local < 4:
                    tr.drum("stomp", bar, "X.......X.......", stomps[local % 3], 0.4 + 0.1 * (local - 2))
                if local >= 4:
                    tr.drum("stomp", bar, "X.......X.......", stomps[local % 3], 0.6 + 0.08 * (local - 4))
                    tr.drum("claps", bar, "....X.......X...", claps[local % 3], 0.55 + 0.1 * (local - 4))
                if local >= 6:
                    tr.kick("kick", bar, "X.....x.X.......", kick, 0.7)
                    tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.5)
                    tr.drum("snare", bar, "....X.......X...", snare, 0.7)
                if local == 7:
                    for k in range(8, 16):
                        tr.add("snare", bar, k, roll, 0.25 + 0.06 * (k - 8))
                    for k, st in enumerate((12, 13, 14, 15)):
                        tr.add("toms", bar, st, toms[min(2, k // 2 + (1 if k == 3 else 0))], 0.8)
                continue
            if name == "charge":  # the band drops out to the crowd's stomps, then comes back bar by bar
                tr.drum("stomp", bar, "X...X...X...X...", stomps[local % 3], 0.9)
                tr.drum("claps", bar, "....X.......X...", claps[local % 3], 0.8)
                if local >= 2:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.85)
                    tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.5)
                if local == 2:
                    tr.drum("toms", bar, "......x.......x.", toms[2], 0.6)
                if local < 3:
                    tr.add("shout", bar, 12, hey(55.0 + 2 * local, 0.3, 10 + local), 0.8 + 0.1 * local)
                    if local == 2:
                        tr.drum("snare", bar, "....X.......X...", snare, 0.8)
                else:
                    for k in range(16):
                        tr.add("snare", bar, k, roll, 0.2 + 0.05 * k)
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.6)
                    tr.add("crowd", bar, 0, crowd(tr.bar * 2.5, 0.8, 3), 0.7)
                continue
            if name == "riff":
                tr.kick("kick", bar, "X.....x.X.x.....", kick, 1.0)
                tr.drum("snare", bar, "....X.......X...", snare, 1.0)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.7)
                tr.drum("claps", bar, "....X.......X...", claps[local % 3], 0.6)
            elif name == "chant":  # the bleacher stomp
                tr.kick("kick", bar, "X.....x.X.......", kick, 1.0)
                tr.drum("stomp", bar, "X.....x.X.......", stomps[local % 3], 0.9)
                tr.drum("snare", bar, "....X.......X...", snare, 0.9)
                tr.drum("claps", bar, "....X.......X...", claps[local % 3], 1.0)
                tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.5)
            else:  # chorus and final: four on the floor, ride and claps
                tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
                tr.drum("snare", bar, "....X.......X...", snare, 1.0)
                tr.drum("claps", bar, "....X.......X...", claps[local % 3], 0.8)
                tr.drum("ride", bar, "x.x.x.x.x.x.x.x.", ride, 0.6)
                if name == "final":
                    tr.drum("stomp", bar, "X.......X.......", stomps[local % 3], 0.7)
            if local % 4 == 0 or (name == "final" and local % 2 == 0):
                tr.add("cymbal", bar, 0, s.crash(), 1.0 if local % 4 == 0 else 0.7, 0.2 if local % 8 else -0.2)
            if name == "final" and local == 7:  # back to the drop: a short fill
                for k, st in enumerate((8, 10, 12)):
                    tr.add("toms", bar, st, ins.tom((190.0, 140.0, 100.0)[k], 0.22), 0.85)
                tr.drum("snare", bar, "..............xx", roll, 0.7)
            elif local % 4 == 3:
                for k, st in enumerate((12, 13, 14, 15)):
                    tr.add("toms", bar, st, toms[min(2, k // 2 + (1 if k == 3 else 0))], 0.75)
        if name == "riff":
            tr.add("shout", part.first, 0, hey(55.0, 0.34, 1), 1.0)
            tr.add("crowd", part.first, 0, crowd(tr.bar * 2, 1.0, 4), 0.6)
            tr.add("shout", part.first + 7, 14, hey(57.0, 0.28, 2), 0.9)
        elif name == "final":
            tr.add("shout", part.first, 0, hey(57.0, 0.34, 3), 1.0)
            tr.add("crowd", part.first, 0, crowd(tr.bar * 3, 1.0, 5), 0.6)

    # ---- the tunes
    tr.play("organ", 8, riff, riff_organ, 1.0, legato=0.9)
    tr.play("organ", 8, shift(riff, -12), riff_organ, 0.6, legato=0.9)
    tr.play("bass", 8, shift(riff, -24), lambda m, sec: ins.bass_guitar(m, sec, bright=0.6), 1.0, legato=0.9)
    crowd_line(tr, "chant", 16, chant, 1.0, rng)
    tr.play("organ", 16, answers, riff_organ, 0.8, legato=0.9)
    tr.play("melody", 24, tune, ballpark_organ, 1.0, legato=0.95)
    crowd_line(tr, "singers", 24, tune, 0.8, rng)
    tr.play("melody", 32, charge, ballpark_organ, 1.0, legato=0.95)
    tr.play("melody", 36, final, ballpark_organ, 1.0, legato=0.95)
    sung = [n for n in final if n.step < 7 * 16 + 8] + [Note(7 * 16 + 8, 74, 2, 0.85)]  # they stop on the D
    crowd_line(tr, "singers", 36, sung, 1.0, rng)

    mix = Mix(buses={
        "organ": Bus(-6, reverb=0.12),
        "melody": Bus(-6, reverb=0.18),
        "chords": Bus(-13, reverb=0.2, pump=0.1),
        "chant": Bus(-6.5, reverb=0.22),
        "singers": Bus(-11, reverb=0.22),
        "crowd": Bus(-18, reverb=0.2),
        "shout": Bus(-12, reverb=0.2),
        "guitar": Bus(-14, reverb=0.08),
        "bass": Bus(-9),
        "kick": Bus(-10.5, drive=1.4),
        "snare": Bus(-11, reverb=0.15),
        "stomp": Bus(-12, reverb=0.15),
        "claps": Bus(-14, reverb=0.15),
        "hats": Bus(-19),
        "ride": Bus(-20),
        "toms": Bus(-14, reverb=0.12),
        "cymbal": Bus(-18),
        "fx": Bus(-16, reverb=0.3),
    }, reverb_decay=1.9, reverb_tone=5000, delay_time=tr.beat * 0.75, delay_feedback=0.3, pump_release=0.18)
    return finish(tr, mix), tr


SONG = Song("Struggle", "Sandlot Smash", 120, 8, 44, struggle)
