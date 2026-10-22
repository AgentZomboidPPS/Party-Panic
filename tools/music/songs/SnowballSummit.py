"""Avalanche Polka: the round song for SnowballSummit (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from score import Note
from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


# ---------------------------------------------------------------- the summit's own sounds

def _vibrato(t, depth, rate, delay, rise):
    return depth * np.clip((t - delay) / rise, 0, 1) * np.sin(2 * np.pi * rate * t)


@lru_cache(maxsize=None)
def alphorn(m, sec):
    """An alphorn far across the valley: one dark horn that blooms slowly, with a breathy lip."""
    tone = np.array(ins.brass(m, sec, bright=0.1, section=1, vibrato=0.04))
    n = tone.shape[-1]
    t = np.arange(n) / s.SR
    tone *= np.clip(t / 0.16, 0, 1) ** 1.5
    breath = s.bandpass(np.random.default_rng(int(m) * 31).uniform(-1, 1, n), 400, 2600)
    tone += breath * ins.env(n, 0.1, 0.3, 0.3, 0.15, gate=sec) * 0.03
    return ins.normalize(ins.eq(tone, ("peak", 420, 3, 1.0), ("lp", 2600)))


@lru_cache(maxsize=None)
def yodel(m, sec, glide_from=None):
    """The whistled yodel: a whistle with a little voice in it. A leap flips into its note: a quick
    slide from the last note, a catch in the breath and a small overshoot (the yodel's break)."""
    n = s.samples(sec + 0.12)
    t = np.arange(n) / s.SR
    pitch = m + _vibrato(t, 0.12, 5.6, 0.14, 0.18)
    catch = np.ones(n)
    if glide_from is not None:
        jump = m - glide_from
        pitch = pitch - jump * np.exp(-t / 0.012) + np.sign(jump) * 0.45 * (t / 0.04) * np.exp(1 - t / 0.04)
        catch = 1 - 0.45 * np.exp(-((t - 0.012) / 0.009) ** 2)
    phase = 2 * np.pi * np.cumsum(s.midi_hz(pitch)) / s.SR
    tone = np.sin(phase) + 0.16 * np.sin(2 * phase) + 0.05 * np.sin(3 * phase)
    breath = s.bandpass(np.random.default_rng(int(m) * 17).uniform(-1, 1, n), 1800, 6000) * 0.035
    return ins.normalize((tone * catch + breath) * ins.env(n, 0.025, 0.12, 0.85, 0.08, gate=sec))


@lru_cache(maxsize=None)
def alp_bell(pitch, length=1.3, variant=0):
    """A Swiss cowbell: a clangy, beating bell with a tin clapper."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(int(pitch) * 10 + variant)
    tone = np.zeros(n)
    for ratio, amp, dec in ((1.0, 1.0, 0.5), (1.007, 0.5, 0.42), (2.32, 0.42, 0.22), (3.08, 0.28, 0.14), (4.53, 0.14, 0.07)):
        tone += amp * np.sin(2 * np.pi * pitch * ratio * t + rng.uniform(0, 6)) * np.exp(-t / (dec * length / 1.3))
    clapper = s.bandpass(rng.uniform(-1, 1, n), 900, 4500) * np.exp(-t / 0.005) * 0.35
    return ins.normalize(ins.eq(tone + clapper, ("hp", 250), ("lp", 7000)))


@lru_cache(maxsize=None)
def hey(pitch=57.0, length=0.3, seed=0):
    """The band's shout: seven voices yelling 'Hey!' together, each a shouted fall. Stereo."""
    n = s.samples(length + 0.1)
    rng = np.random.default_rng(seed)
    out = np.zeros((2, n))
    for _ in range(7):
        start = s.samples(rng.uniform(0.0, 0.03))
        m = n - start
        t = np.arange(m) / s.SR
        contour = pitch + rng.uniform(-2.0, 5.0) + 2.0 * np.exp(-t / 0.04) - 3.0 * np.clip(t / length, 0, 1) ** 2
        f = s.midi_hz(contour)
        src = s.saw(f, m, start=rng.random()) + 0.25 * s.square(f, m, 0.35)
        e = np.clip(t / 0.01, 0, 1) * np.exp(-t / (length * 0.5))
        h = s.bandpass(rng.uniform(-1, 1, m), 900, 3500) * np.exp(-t / 0.03) * 0.5
        voice = ins.formant(src * e, [(620, 12, 4), (1750, 10, 5), (2600, 6, 6)]) + h
        out[:, start:] += s.pan(voice, rng.uniform(-0.6, 0.6))
    return ins.normalize(ins.eq(out, ("hp", 180), ("lp", 4200)))


@lru_cache(maxsize=None)
def wind(length):
    """Mountain wind: resonant noise whose whistle wanders, in gusts. Stereo."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(7)
    out = np.zeros((2, n))
    for ch in range(2):
        centre = 600 + 280 * np.sin(2 * np.pi * t / 3.3 + 1.7 * ch) + 150 * np.sin(2 * np.pi * t / 1.4 + ch)
        gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / 4.1 + 2.2 * ch) ** 2
        out[ch] = ins.eq(ins.tv_lowpass(rng.uniform(-1, 1, n), centre, q=3.5), ("hp", 220)) * gust
    out *= np.sin(np.pi * np.clip(t / length, 0, 1)) ** 0.8
    return ins.normalize(out)


@lru_cache(maxsize=None)
def rumble(length):
    """A snowball rolling closer and growing: a low, wobbling rumble that brightens as it comes."""
    n = s.samples(length)
    t = np.linspace(0, 1, n)
    x = ins.tv_lowpass(np.random.default_rng(42).uniform(-1, 1, n), 180 * 9 ** t, q=1.4)
    wobble = 1 - 0.4 * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(2.5 + 9 * t) / s.SR))
    return ins.normalize(ins.eq(x, ("hp", 70)) * wobble * t ** 1.5)


def swell(x, attack):
    """A copy of a sound that fades in over `attack` seconds (bellows drawing breath)."""
    y = np.array(x)
    return y * np.clip(np.arange(y.shape[-1]) / s.samples(attack), 0, 1) ** 2


def segment(notes, first_bar, bars, spb=16):
    """The notes of bars [first_bar, first_bar + bars) of a phrase, from the start of first_bar."""
    lo, hi = first_bar * spb, (first_bar + bars) * spb
    return shift([n for n in notes if lo <= n.step < hi], 0, -lo)


def sparkle(notes, ceiling=96):
    """A glockenspiel doubling an octave up, staying put where that would pass C7 (too shrill)."""
    return [Note(n.step, n.midi + (12 if n.midi + 12 <= ceiling else 0), n.length, n.vel) for n in notes]


def yodel_line(tr, stem, bar, notes, gain=1.0, pan=0.0):
    """Plays a whistled yodel: a leap of a fourth or more straight after a note flips into it."""
    last = None
    for n in notes:
        glide = None
        if last is not None and abs(n.midi - last.midi) >= 5 and n.step - (last.step + last.length) < 0.5:
            glide = last.midi
        top = 0.85 if n.midi > 86 else 1.0  # the highest notes a touch softer: phones
        tr.add(stem, bar, n.step, yodel(n.midi, max(0.05, n.length * tr.step * 0.92), glide), gain * n.vel * top, pan)
        last = n


# ---------------------------------------------------------------- the song

def snowball_summit():
    """Avalanche Polka (128 bpm, F major): an alpine oom-pah band on the frozen summit. An alphorn
    calls across the valley and echoes back, then tuba, accordion and a clarinet strike up the polka;
    a whistled yodel takes over, the trio swings up to B flat, and the finale goes up again to C with
    cowbells, clarinet runs and shouts as the summit thins out. A stop-time clarinet cadenza leads
    back to the top."""
    tr = Track(bpm=128, bars=42)
    parts = plan(tr, [
        ("intro", 8, "F | F | F | F | Bb | F | Gm7 C7 | C7"),
        ("A", 8, "F | C7 | F Gm7 | C7 F | F | C7 | F Bb | C7 F"),
        ("yodel", 8, "F | C7 | C7 | F | Bb | F | C7 | F F7"),
        ("trio", 8, "Bb | Eb | F7 | Bb | Gm | Eb | C7 F7 | G7"),
        ("finale", 8, "C | G7 | C Dm7 | G7 C | C | G7 | C F | G7 C"),
        ("tag", 2, "C | C7"),
    ])
    call = melody("r:4 C4:4 F4:4 A4:4 | C5:10 A4:2 G4:2 F4:2 | r:4 F4:4 A4:4 C5:4 | F5:6 C5:2 A4:4 Bb4:2 G4:2 | F4:16")
    theme = melody("""A4:1 Bb4:1 C5:2 F5:2 A5:2 G5:1 A5:1 G5:2 F5:2 C5:2 | Bb4:1 C5:1 E5:2 G5:2 Bb5:2 A5:1 Bb5:1 A5:2 G5:2 E5:2 |
                      F5:1 G5:1 A5:2 C6:2 A5:2 G5:1 A5:1 G5:2 F5:2 D5:2 | E5:2 G5:2 C6:2 Bb5:2 A5:4 F5:2 r:2 |
                      A4:1 Bb4:1 C5:2 F5:2 A5:2 G5:1 A5:1 G5:2 F5:2 C5:2 | Bb4:1 C5:1 E5:2 G5:2 Bb5:2 A5:1 Bb5:1 A5:2 G5:2 E5:2 |
                      F5:1 G5:1 A5:2 C6:2 F6:2 D6:1 F6:1 D6:2 C6:2 Bb5:2 | Bb5:2 G5:2 E5:2 G5:2 F5:4 r:4""")
    yodel_tune = melody("""C5:2 A5:2 F5:1 C6:3 A5:2 F5:2 C5:2 A5:2 | Bb4:2 G5:2 E5:1 C6:3 Bb5:2 G5:2 E5:2 G5:2 |
                           C5:1 E5:1 G5:1 Bb5:1 C6:4 Bb5:1 G5:1 E5:2 C6:4 | A5:6 F5:2 C6:4 F5:4 |
                           D5:2 Bb5:2 F5:1 D6:3 Bb5:2 F5:2 D5:2 Bb5:2 | C5:2 A5:2 F5:1 C6:3 A5:2 F6:2 C6:2 A5:2 |
                           G5:2 C6:2 Bb5:2 E5:2 G5:2 C5:2 E5:2 G5:2 | F5:4 A5:2 C6:2 Eb6:4 C6:2 A5:2""")
    counter = melody("""A4:6 Bb4:2 C5:8 | Bb4:6 A4:2 G4:8 | E4:6 F4:2 G4:8 | A4:6 G4:2 F4:8 |
                        F4:6 E4:2 D4:8 | A4:6 Bb4:2 C5:8 | Bb4:6 A4:2 G4:8 | A4:8 Eb5:8""")
    trio_tune = melody("""D5:6 Eb5:2 F5:4 Bb5:4 | G5:6 F5:2 Eb5:4 G5:4 | F5:6 Eb5:2 C5:4 A4:4 | Bb4:8 D5:4 F5:4 |
                          G5:6 A5:2 Bb5:4 D6:4 | C6:6 Bb5:2 G5:4 Eb5:4 | E5:4 G5:4 F5:4 A5:4 | G5:2 F5:2 D5:2 B4:2 G4:4 r:4""")
    trio_clarinet = melody("""G4:2 Bb4:2 D5:2 Bb4:2 G4:2 Bb4:2 D5:2 Bb4:2 | G4:2 Bb4:2 Eb5:2 Bb4:2 G4:2 Bb4:2 Eb5:2 Bb4:2 |
                              G4:2 Bb4:2 C5:2 E5:2 A4:2 C5:2 Eb5:2 F5:2 |
                              G5:1 F5:1 D5:1 B4:1 G4:1 B4:1 D5:1 F5:1 G5:1 A5:1 B5:1 C6:1 D6:1 E6:1 F6:1 G6:1""")
    runs = melody("""C5:1 E5:1 G5:1 C6:1 E6:1 C6:1 G5:1 E5:1 D5:1 E5:1 F5:1 G5:1 A5:1 G5:1 F5:1 E5:1 |
                     D5:1 F5:1 G5:1 B5:1 D6:1 B5:1 G5:1 F5:1 G5:1 F5:1 E5:1 D5:1 B4:1 C5:1 D5:1 B4:1 |
                     C5:1 E5:1 G5:1 E5:1 C6:1 G5:1 E5:1 G5:1 A5:1 C6:1 F6:1 C6:1 A5:1 F5:1 C5:1 F5:1 |
                     G5:1 F5:1 D5:1 B4:1 G4:1 B4:1 D5:1 F5:1 E5:4 C5:4""")
    lead_in = melody("C5:1 D5:1 E5:1 F5:1 G5:1 A5:1 Bb5:1 C6:1 Bb5:1 A5:1 G5:1 E5:1 C5:2 G4:2")
    cadenza = melody("""r:4 C5:1 D5:1 E5:1 F5:1 G5:1 A5:1 B5:1 C6:1 D6:1 E6:1 F6:1 G6:1 |
                        C6:1 Bb5:1 G5:1 E5:1 Bb5:1 G5:1 E5:1 C5:1 G5:1 E5:1 C5:1 Bb4:1 G4:2 r:2""")

    kick = s.kick(0.7, 0.3)
    snare = ins.snare2(230.0, 0.55, 0.16)
    roll = ins.snare2(230.0, 0.8, 0.12, variant=1)
    chick = s.hat(False)
    clap = s.clap(0.25)
    block = ins.woodblock(900.0)
    toms = [ins.tom(p, 0.35) for p in (180.0, 140.0, 105.0)]
    bells = [alp_bell(p, 1.3, v) for v, p in enumerate((523.0, 587.0, 698.0, 784.0))]
    rng = np.random.default_rng(11)

    def chord_at(bar, step):
        for part in parts:
            for b, st, length, c in part.changes:
                if b == bar and st <= step < st + length:
                    return c
        raise ValueError(f"no chord at {bar}:{step}")

    def harmony_below(notes, bar):
        """Each melody note with the nearest chord tone a third to a sixth under it (an accordion's thirds)."""
        out = []
        for n in notes:
            c = chord_at(bar + int(n.step // tr.spb), n.step % tr.spb)
            tones = c.tones()
            low = next(m for m in range(n.midi - 3, n.midi - 10, -1) if m % 12 in tones)
            out.append((n, low))
        return out

    # ------------------------------------------------ the intro: an alphorn across the valley
    tr.add("fx", 0, 0, wind(tr.bar * 6), 0.45)
    tr.play("alphorn", 0, segment(call, 0, 2), alphorn, 0.55)  # the first call, far away
    tr.play("alphorn", 2, segment(call, 2, 3), alphorn, 0.72)  # the answer, nearer
    for bar in range(1, 5):  # snowflakes
        for k in range(3):
            m = (77, 79, 81, 84, 86, 89)[rng.integers(6)]
            tr.add("glock", bar, int(rng.integers(0, 16)), ins.glock(m, 0.5), 0.25 + 0.15 * rng.random(), rng.uniform(-0.6, 0.6))
    for bar, step, bell, gain in ((2, 6, 0, 0.35), (3, 2, 2, 0.3), (3, 11, 1, 0.35), (4, 9, 3, 0.4), (5, 4, 0, 0.45)):
        tr.add("bells", bar, step, bells[bell], gain, 0.5 if bell % 2 else -0.5)
    tr.play("glock", 5, shift(segment(theme, 0, 1), 12), ins.glock, 0.6)
    tr.add("fx", 6, 0, rumble(tr.bar * 2), 0.9)
    tr.add("fx", 7, 0, s.riser(tr.bar), 0.4)
    tr.play("clarinet", 7, lead_in, ins.clarinet, 0.6, legato=0.9)

    # ------------------------------------------------ the band: tuba and accordion oom-pah
    walks = {  # bass walks into the next phrase: (bar, step) -> note
        (27, 8): 46, (27, 12): 45,  # trio: Bb A down to the G minor
        (31, 8): 45, (31, 12): 47,  # trio: G A B up to the finale's C
        (35, 12): 47,               # finale: B into the repeat
    }
    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 40)
            fifth = root - 5 if root - 5 >= 38 else root + 7
            notes = tuple(voicing(c, 53, 66, prev, size=3))
            prev = list(notes)
            quarters = int(round(length / 4))
            if name == "intro":
                if local in (4, 5):  # the accordion breathes in under the alphorn's last note
                    tr.add("pah", bar, step, swell(ins.accordion(notes, length * tr.step), 1.2), 0.5)
                if local >= 6:
                    for k in range(quarters):
                        st = step + 4 * k
                        level = 0.45 + 0.25 * (local - 6) + 0.04 * k
                        tr.add("tuba", bar, st, ins.tuba(root if k % 2 == 0 else fifth, tr.step * 2.5), level)
                        tr.add("pah", bar, st + 2, ins.accordion(notes, tr.step * 1.3), level * 0.9)
                continue
            if name == "tag":
                if local == 0:  # the big hit, then the band stops for the clarinet
                    tr.add("tuba", bar, 0, ins.tuba(48, tr.step * 3), 1.0)
                    tr.add("pah", bar, 0, ins.accordion(tuple(voicing(c, 55, 72)), tr.step * 3.5), 1.0)
                    for m in (84, 88, 91):
                        tr.add("glock", bar, 0, ins.glock(m, 0.6), 0.5)
                else:  # walk down to the F of the drop, the oom-pah back in
                    for k, m in enumerate((48, 46, 45, 43)):
                        tr.add("tuba", bar, 4 * k, ins.tuba(m, tr.step * 2.6), 0.9)
                        tr.add("pah", bar, 4 * k + 2, ins.accordion(notes, tr.step * 1.3), 0.5 + 0.12 * k)
                continue
            shake = name == "finale" and local >= 6
            for k in range(quarters):
                st = step + 4 * k
                bass = walks.get((bar, st), root if k % 2 == 0 else fifth)
                tr.add("tuba", bar, st, ins.tuba(bass, tr.step * 2.6), 1.0 if k % 2 == 0 else 0.85)
                if shake:  # the bellows shake: the chord re-pumped every sixteenth
                    for j in range(4):
                        tr.add("pah", bar, st + j, ins.accordion(notes, tr.step * 0.8), 0.75 if j % 2 else 0.5)
                else:
                    tr.add("pah", bar, st + 2, ins.accordion(notes, tr.step * 1.3), 0.8)
                    if name in ("trio", "finale") and k % 2 == 1:  # a lighter second pah: the band leans in
                        tr.add("pah", bar, st + 3, ins.accordion(notes, tr.step * 0.8), 0.4)

        # ------------------------------------------------ drums, cowbells and shouts
        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local == 6:
                    tr.drum("perc", bar, "x...x...x...x...", block, 0.55)
                if local == 7:
                    tr.drum("perc", bar, "x...x...x...x...", block, 0.7)
                    tr.drum("kick", bar, "x...x...x...x...", kick, 0.7)
                    for k in range(16):
                        tr.add("snare", bar, k, roll, 0.08 + 0.028 * k)
                    for k in range(8, 15):
                        tr.add("snare", bar, k + 0.5, roll, 0.05 + 0.025 * k)
                continue
            if name == "tag":
                if local == 0:
                    tr.add("kick", bar, 0, kick, 1.0)
                    tr.add("cymbal", bar, 0, s.crash(), 1.0, 0.2)
                    tr.add("shout", bar, 0, hey(57.0, 0.35, 5), 1.0)
                    tr.add("bells", bar, 0, bells[3], 0.8, 0.3)
                else:
                    tr.drum("kick", bar, "x...x...x...x...", kick, 0.8)
                    for k in range(8, 16):
                        tr.add("snare", bar, k, roll, 0.15 + 0.045 * (k - 8))
                        if k < 15:
                            tr.add("snare", bar, k + 0.5, roll, 0.12 + 0.04 * (k - 8))
                continue
            big = name in ("trio", "finale")
            tr.drum("kick", bar, "X...x...X...x...", kick, 1.0)
            tr.drum("snare", bar, "..x...x...x...x.", snare, 0.85 if big else 0.75)
            tr.drum("hats", bar, "..x...x...x...x.", chick, 0.8)
            if name != "A":
                tr.drum("claps", bar, "....x.......x...", clap, 0.8 if big else 0.6)
            if name == "A" and local >= 4:
                tr.drum("perc", bar, "x...x...x...x...", block, 0.5)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.0, 0.2)
            # cowbells: a few in the yodel, every bar in the trio, every beat in the finale
            if name == "yodel" and local % 2 == 0:
                tr.add("bells", bar, 0, bells[local // 2 % 4], 0.5, -0.4)
            elif name == "trio":
                tr.add("bells", bar, 0, bells[local % 4], 0.6, -0.4)
                tr.add("bells", bar, 8, bells[(local + 2) % 4], 0.45, 0.4)
            elif name == "finale":
                for k in range(4):
                    tr.add("bells", bar, 4 * k, bells[(k + local) % 4], 0.6 if k % 2 == 0 else 0.45, -0.4 if k % 2 == 0 else 0.4)
                if local == 4:
                    tr.add("cymbal", bar, 0, s.crash(), 0.9, -0.2)
            # fills at the ends of phrases
            if local % 4 == 3 and name in ("yodel", "trio", "finale"):
                if name == "finale" or local == 7:
                    for k, step in enumerate((12, 13, 14, 15)):
                        tr.add("toms", bar, step, toms[min(2, k // 2 + (1 if k == 3 else 0))], 0.8)
                else:
                    for k in range(12, 16):
                        tr.add("snare", bar, k, roll, 0.35 + 0.1 * (k - 12))
        if name == "A":
            tr.add("shout", part.first, 0, hey(57.0, 0.3, 1), 1.0)
            tr.add("shout", part.first + 7, 12, hey(58.0, 0.3, 2), 0.9)
        elif name == "trio":
            tr.add("shout", part.first + 7, 12, hey(59.0, 0.3, 3), 0.95)
            tr.add("fx", part.first - 1, 8, ins.whoosh(tr.bar * 0.5, True), 0.5)
        elif name == "finale":
            tr.add("shout", part.first + 7, 12, hey(60.0, 0.32, 4), 1.0)
            tr.add("fx", part.first - 1, 8, ins.whoosh(tr.bar * 0.5, True), 0.6)

    # ------------------------------------------------ the tunes
    tr.play("clarinet", 8, theme, ins.clarinet, 1.0, legato=0.85)
    tr.play("glock", 12, sparkle(segment(theme, 4, 4)), ins.glock, 0.4)
    yodel_line(tr, "whistle", 16, yodel_tune, 1.0)
    tr.play("clar2", 16, counter, ins.clarinet, 0.8)
    for n, low in harmony_below(trio_tune, 24):  # the trio on the accordion, in thirds and sixths
        tr.add("melody", 24, n.step, ins.accordion((low, n.midi), n.length * tr.step * 0.9), n.vel)
    tr.play("glock", 28, sparkle(segment(trio_tune, 4, 4)), ins.glock, 0.45)
    yodel_line(tr, "whistle", 27, melody("r:12 C6:1 F6:3"), 0.8)  # a yodel's 'hoo-ee' between phrases
    tr.play("clar2", 24, shift(segment(trio_tune, 0, 4), -12), ins.clarinet, 0.85, legato=0.95)  # the whole band on the tune
    tr.play("clar2", 28, trio_clarinet, ins.clarinet, 0.9, legato=0.85)
    yodel_line(tr, "whistle", 32, shift(theme, 7), 1.0)
    tr.play("glock", 32, shift(theme, 7), ins.glock, 0.35)
    tr.play("clarinet", 32, shift(segment(theme, 0, 4), -5), ins.clarinet, 0.7, legato=0.85)
    tr.play("clar2", 36, runs, ins.clarinet, 1.0, legato=0.9)
    tr.play("clarinet", 40, cadenza, ins.clarinet, 0.75, legato=0.9)

    mix = Mix(buses={
        "clarinet": Bus(-7, reverb=0.18),
        "clar2": Bus(-11, reverb=0.18),
        "whistle": Bus(-6, reverb=0.2, delay=0.1),
        "melody": Bus(-6, reverb=0.15),
        "alphorn": Bus(-12, reverb=0.35, delay=0.4),
        "pah": Bus(-12, reverb=0.12),
        "tuba": Bus(-9, reverb=0.05),
        "glock": Bus(-15, reverb=0.3, delay=0.12),
        "bells": Bus(-17, reverb=0.3),
        "kick": Bus(-15, drive=1.3),
        "snare": Bus(-15, reverb=0.1),
        "hats": Bus(-21),
        "claps": Bus(-17, reverb=0.15),
        "toms": Bus(-15, reverb=0.12),
        "perc": Bus(-18, reverb=0.1),
        "cymbal": Bus(-19, reverb=0.1),
        "shout": Bus(-13, reverb=0.2),
        "fx": Bus(-16, reverb=0.3),
    }, reverb_decay=1.8, reverb_tone=5500, delay_time=tr.beat * 1.5, delay_feedback=0.35)
    return finish(tr, mix), tr


SONG = Song("SnowballSummit", "Avalanche Polka", 128, 8, 42, snowball_summit)
