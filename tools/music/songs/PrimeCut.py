"""High Steaks: the round song for PrimeCut (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


@lru_cache(maxsize=None)
def kick() -> np.ndarray:
    """A deep, short kick tuned near 64 Hz (a phone still hears it)."""
    n = s.samples(0.32)
    t = np.arange(n) / s.SR
    f = 64 + 100 * np.exp(-t / 0.025)
    body = np.sin(2 * np.pi * np.cumsum(f) / s.SR) * np.exp(-t / 0.1)
    beater = s.bandpass(ins._rng("kick").uniform(-1, 1, n), 1200, 4500) * np.exp(-t / 0.004) * 0.3
    return ins.normalize(np.tanh((body + beater) * 1.5))


@lru_cache(maxsize=None)
def whip() -> np.ndarray:
    """A bullwhip: a short swish, then the crack."""
    n = s.samples(0.25)
    t = np.arange(n) / s.SR
    rng = ins._rng("whip")
    swish = ins.eq(rng.uniform(-1, 1, n), ("hp", 1500), ("lp", 6000)) * np.clip(t / 0.06, 0, 1) ** 2 * (t < 0.06) * 0.3
    k = s.samples(0.06)
    crack = np.zeros(n)
    tt = np.arange(n - k) / s.SR
    crack[k:] = ins.eq(rng.uniform(-1, 1, n - k), ("hp", 2000), ("lp", 7500), ("peak", 3500, 6, 1.5)) * np.exp(-tt / 0.012)
    crack[k:k + 30] += np.linspace(1, 0, 30) * 1.5
    return ins.normalize(swish + crack)


@lru_cache(maxsize=None)
def bell(pitch: float = 220.0, length: float = 4.0) -> np.ndarray:
    """The mission bell tolling noon: a church bell's hum, prime, minor third, fifth and nominal."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    out = np.zeros(n)
    for ratio, amp, decay in ((0.5, 0.6, 1.6), (1.0, 1.0, 1.2), (1.19, 0.55, 0.9), (1.5, 0.35, 0.7), (2.0, 0.6, 0.6), (2.52, 0.25, 0.4), (3.0, 0.15, 0.3)):
        out += amp * np.sin(2 * np.pi * pitch * ratio * t) * np.exp(-t / (decay * length / 2.5))
    strike = s.lowpass(ins._rng("bell", pitch).uniform(-1, 1, n), 3000) * np.exp(-t / 0.01) * 0.4
    return ins.normalize(ins.eq(out + strike, ("hp", 90), ("lp", 6000)))


@lru_cache(maxsize=None)
def sizzle(length: float) -> np.ndarray:
    """Steaks on the grill: a soft hiss with fat popping in it."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    hiss = ins.eq(ins._rng("sizzle", length).uniform(-1, 1, n), ("hp", 2500), ("lp", 7000)) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.37 * t) ** 2)
    return ins.normalize(hiss * 0.35 + np.asarray(ins.crackle(length)))


@lru_cache(maxsize=None)
def watch(pitch: float) -> np.ndarray:
    """A pocket watch ticking: a tiny metal tick."""
    n = s.samples(0.04)
    t = np.arange(n) / s.SR
    tone = np.sin(2 * np.pi * pitch * t) * np.exp(-t / 0.004) + 0.4 * np.sin(2 * np.pi * pitch * 1.83 * t) * np.exp(-t / 0.003)
    return ins.normalize(tone + s.bandpass(ins._rng("watch", pitch).uniform(-1, 1, n), 2500, 7000) * np.exp(-t / 0.0015) * 0.4)


def prime_cut():
    """High Steaks (120 bpm, A minor): a spaghetti-western showdown at the backyard grill. A lonesome
    whistle, a reverb-soaked baritone twang, nylon-string strums, mariachi trumpets in harmony, a choir,
    whip cracks and a ticking pocket watch. Every steak is eight bars, timed to the round: four bars of
    the tense theme while teams line their knives up, a crescendo through the 3-2-1, a hush for the CHOP and
    the verdict (a heartbeat), then the crown in F major (the key of the game's own victory jingle) and a
    turnaround into the next steak. The third steak is the biggest, and its winner's F-G-A finish lands on
    "WINS PRIME CUT!"."""
    tr = Track(bpm=120, bars=36)
    cycle = "Am | G | F | E | E7 | C7 | F | G E7"
    parts = plan(tr, [
        ("intro", 8, "Am | Am | Am | Am | Am | G | F | E7"),
        ("steak1", 8, cycle),
        ("steak2", 8, cycle),
        ("steak3", 8, "Am | G | F | E | E7 | C7 | F | G"),
        ("finale", 4, "A | A | Dm | E7"),
    ])
    theme = melody("""A4:2 E5:2 A5:4 ~:4 G5:2 E5:2 | D5:2 G5:2 B5:4 ~:4 A5:2 G5:2 | F5:2 A5:2 C6:4 B5:2 A5:2 G5:4 |
                      G#5:4 B5:4 E5:8 | D6:6 C6:2 B5:4 G#5:4""")
    second = melody("""r:2 C5:2 E5:4 ~:4 E5:2 C5:2 | B4:2 D5:2 G5:4 ~:4 F#5:2 D5:2 | C5:2 F5:2 A5:4 G5:2 F5:2 E5:4 |
                       E5:4 G#5:4 B4:8 | B5:6 A5:2 G#5:4 E5:4""")
    hail, hail2 = melody("r:4 C5:2 F5:2 A5:8"), melody("r:4 A4:2 C5:2 F5:8")
    ready, ready2 = melody("G5:2 B5:2 D6:4 B5:2 G#5:2 E5:4"), melody("D5:2 G5:2 B5:4 G#5:2 E5:2 B4:4")
    crown, crown2 = melody("r:4 C5:2 F5:2 A5:4 C6:4"), melody("r:4 A4:2 C5:2 F5:4 A5:4")
    winner, winner2 = melody("D5:2 G5:2 B5:4 D6:8"), melody("B4:2 D5:2 G5:4 B5:8")
    lonely = melody("A4:2 E5:2 A5:4 ~:4 G5:2 E5:2 | A5:12 r:4")
    sunset = melody("E5:2 A5:2 C#6:12")

    def whistle(m, sec):
        return ins.whistle(m, sec)

    def trumpet(m, sec):
        return ins.brass(m, sec, bright=1.0, section=1, vibrato=0.14)

    def twang(m, sec):
        return ins.electric_guitar(m, sec, variant=int(m) % 3)

    bd = kick()
    boom, tom_hi = ins.tom(98.0, 0.6), ins.tom(140.0, 0.45)
    clap, shake = s.clap(), s.shaker()
    tick, tock = watch(3300.0), watch(2700.0)
    crash = ins.eq(s.crash(2.4), ("lp", 9000))
    anvil = ins.clank(1150.0, 0.9)
    riff = ((0, 0, 3), (3, 0, 1), (4, 7, 4), (8, 12, 3), (11, 0, 1), (12, 7, 4))

    def rasgueado(bar, step, notes, gain):
        """A flamenco strum: four quick strokes, the last one up."""
        for k in range(4):  # (each finger its own pluck, so the strokes don't comb against each other)
            strum(tr, "nylon", bar, step + k * 0.5, notes, lambda m, sec, k=k: ins.nylon(m, sec, variant=k + 1), 0.25,
                  gain * (0.7 + 0.1 * k), spread=0.006, down=k < 3)

    # ---- the intro: noon at the grill
    tr.add("grill", 0, 0, sizzle(tr.bar * 6), 1.0)
    tr.add("bell", 0, 0, bell(220.0), 0.55, -0.3)
    tr.add("bell", 1, 0, bell(220.0), 0.5, -0.3)
    tr.add("strings", 0, 0, ins.strings((45, 52), tr.bar * 6, attack=3.0, bright=0.25), 0.4)
    tr.play("whistle", 2, lonely, whistle, 0.6)
    tr.play("trumpet", 4, [n for n in theme if n.step < 16 * 3], trumpet, 0.5)  # a call from across the yard

    prev = None
    for part in parts:
        name = part.name
        level = {"steak1": 1, "steak2": 2, "steak3": 3}.get(name, 0)
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 40)
            notes = voicing(c, 52, 67, prev)
            prev = notes
            seconds = length * tr.step
            if name == "intro":
                if local in (3, 4, 5):
                    for st, iv, ln in riff:
                        tr.add("twang", bar, st, twang(root + iv, tr.step * ln), 0.4 + 0.12 * (local - 3))
                if local == 6:
                    tr.add("twang", bar, 0, twang(root, tr.step * 8), 0.75)
                    tr.add("twang", bar, 8, twang(root + 12, tr.step * 8), 0.7)
                if local == 7:
                    for k in range(8):
                        tr.add("twang", bar, 2 * k, twang(root + (12 if k % 2 else 0), tr.step * 1.6), 0.5 + 0.04 * k)
                    rasgueado(bar, 0, notes, 0.6)
                    tr.add("choir", bar, 0, ins.choir(tuple(voicing(c, 55, 67)[:3]), tr.bar, "ah", attack=1.2), 0.6)
                if local >= 6:
                    for k in range(16):
                        for m in notes[-3:]:
                            tr.add("strings", bar, k, ins.spiccato(m + 12, tr.step * 1.2), (0.12 + 0.012 * (k + 16 * (local - 6))) * (1.0 if k % 2 == 0 else 0.8))
                continue
            if name == "finale":
                if local == 0:  # the final chord
                    rasgueado(bar, 0, notes, 1.0)
                    tr.add("strings", bar, 0, ins.strings(tuple(n + 12 for n in notes), tr.bar * 2, attack=0.05, bright=0.6), 1.0)
                    tr.add("choir", bar, 0, ins.choir(tuple(voicing(c, 57, 69)[:3]), tr.bar * 2, "ah", attack=0.1), 1.0)
                    tr.add("twang", bar, 0, twang(root, tr.bar * 1.5), 1.0)
                    tr.add("twang", bar, 0, twang(root + 12, tr.bar * 1.5), 0.7)
                elif local == 2:
                    for st, iv, ln in riff:
                        tr.add("twang", bar, st, twang(root + iv, tr.step * ln), 0.6)
                elif local == 3:
                    for k in range(8):
                        tr.add("twang", bar, 2 * k, twang(root + (12 if k % 2 else 0), tr.step * 1.6), 0.6 + 0.04 * k)
                    for k in range(16):
                        for m in notes[-3:]:
                            tr.add("strings", bar, k, ins.spiccato(m + 12, tr.step * 1.2), (0.25 + 0.03 * k) * (1.0 if k % 2 == 0 else 0.8))
                continue
            # the steaks
            if local < 4:  # line up the knife: the riff, the strums
                for st, iv, ln in riff:
                    tr.add("twang", bar, st, twang(root + iv, tr.step * ln), 0.8 + 0.05 * level)
                for st in (4, 12) if level < 2 else (4, 12, 14):
                    strum(tr, "nylon", bar, st, notes, ins.nylon, 0.22, 0.75 if st != 14 else 0.55, spread=0.008, down=st != 14)
                if local == 3:
                    rasgueado(bar, 12, notes, 0.7)
                if level == 3:
                    tr.add("strings", bar, 0, ins.strings(tuple(n + 12 for n in notes), seconds, attack=0.3, bright=0.45), 0.6)
                    tr.add("choir", bar, 0, ins.choir(tuple(voicing(c, 55, 67)[:3]), seconds, "ah", attack=0.25), 0.6)
            elif local == 4:  # 3-2-1: everything climbs
                for k in range(8):
                    tr.add("twang", bar, 2 * k, twang(root + (12 if k % 2 else 0), tr.step * 1.6), 0.7 + 0.04 * k)
                for k in range(16):
                    for m in notes[-3:]:
                        tr.add("strings", bar, k, ins.spiccato(m + 12, tr.step * 1.2), (0.3 + 0.03 * k) * (1.0 if k % 2 == 0 else 0.8))
                if level >= 2:
                    tr.add("choir", bar, 0, ins.choir(tuple(voicing(c, 55, 67)[:3]), seconds, "ah", attack=1.0), 0.7 + 0.15 * (level - 2))
            elif local == 5:  # CHOP, then the verdict: a hush, a held breath
                tr.add("twang", bar, 2, twang(root, tr.step * 12), 0.85)
                tr.add("strings", bar, 2, ins.strings((root, root + 7), tr.step * 14, attack=0.6, bright=0.2), 0.7)
                for k in range(2, 16):
                    for m in notes[-3:]:
                        tr.add("strings", bar, k, ins.spiccato(m, tr.step * 1.2), (0.22 + 0.01 * k) * (1.0 if k % 2 == 0 else 0.8))
            elif local == 6:  # the crown, in F
                rasgueado(bar, 0, notes, 0.9 + 0.05 * level)
                tr.add("strings", bar, 0, ins.strings(tuple(n + 12 for n in notes), seconds, attack=0.05, bright=0.6), 1.0)
                tr.add("twang", bar, 0, twang(root, tr.step * 8), 0.95)
                tr.add("twang", bar, 0, twang(root + 12, tr.step * 8), 0.65)
                tr.add("choir", bar, 0, ins.choir(tuple(voicing(c, 57, 69)[:3]), seconds, "ah", attack=0.1), 0.6 + 0.15 * (level - 1))
            elif local == 7:  # next steak (in the third: the winner's G)
                strum(tr, "nylon", bar, step, notes, ins.nylon, 0.4, 0.85, spread=0.01)
                tr.add("twang", bar, step, twang(root, seconds * 0.9), 0.85)
                if level == 3:
                    rasgueado(bar, 0, notes, 1.0)
                    tr.add("strings", bar, 0, ins.strings(tuple(n + 12 for n in notes), seconds, attack=0.05, bright=0.65), 1.0)
                    tr.add("choir", bar, 0, ins.choir(tuple(voicing(c, 55, 67)[:3]), seconds, "ah", attack=0.1), 1.0)

        # drums and the rest of the percussion
        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 2:
                    tr.drum("tick", bar, "x...x...x...x...", tick, 0.3 + 0.05 * local, 0.35)
                    tr.drum("tick", bar, "..x...x...x...x.", tock, 0.25 + 0.05 * local, 0.35)
                if local >= 4:
                    tr.drum("toms", bar, "x.......x.......", boom, 0.55 + 0.1 * (local - 4))
                    tr.drum("shaker", bar, "x.x.x.x.x.x.x.x.", shake, 0.45 + 0.1 * (local - 4))
                if local == 6:
                    tr.kick("kick", bar, "x.......x.......", bd, 0.7)
                if local >= 6:
                    for k in range(16):
                        tr.add("timp", bar, k, ins.timpani(40, 0.5, 0.5), 0.12 + 0.012 * (k + 16 * (local - 6)))
                if local == 7:
                    tr.drum("toms", bar, "........x.x.xxxx", tom_hi, 0.6)
                    tr.add("fx", bar, 14, whip(), 0.7, 0.3)
                continue
            if name == "finale":
                if local == 0:
                    tr.add("cymbal", bar, 0, crash, 1.0, 0.2)
                    tr.add("timp", bar, 0, ins.timpani(45, 2.0, 1.0), 1.0)
                    tr.add("fx", bar, 0, anvil, 0.7, -0.2)
                    tr.kick("kick", bar, "x...............", bd, 1.0)
                elif local >= 2:
                    tr.drum("tick", bar, "x...x...x...x...", tick, 0.45, 0.35)
                    tr.drum("tick", bar, "..x...x...x...x.", tock, 0.4, 0.35)
                    tr.drum("toms", bar, "x.......x.......", boom, 0.7)
                    tr.drum("shaker", bar, "x.x.x.x.x.x.x.x.", shake, 0.6)
                    if local == 3:
                        for k in range(16):
                            tr.add("timp", bar, k, ins.timpani(40, 0.5, 0.5), 0.15 + 0.03 * k)
                        tr.drum("toms", bar, "........x.x.xxxx", tom_hi, 0.75)
                        tr.add("fx", bar, 14, whip(), 0.8, 0.3)
                continue
            if local < 4:
                tr.drum("tick", bar, "x...x...x...x...", tick, 0.5, 0.35)
                tr.drum("tick", bar, "..x...x...x...x.", tock, 0.42, 0.35)
                tr.drum("shaker", bar, "x.x.x.x.x.x.x.x." if level == 1 else "x.xxx.xxx.xxx.xx", shake, 0.7)
                tr.drum("toms", bar, "x.......x......." if level < 3 else "x.....x.x.......", boom, 0.8)
                if level >= 2:
                    tr.kick("kick", bar, "x.......x.x.....", bd, 0.9)
                    tr.drum("clap", bar, "....x.......x...", clap, 0.8)
                if level == 3 and local in (1, 3):
                    tr.add("fx", bar, 12, whip(), 0.75, 0.3)
                if local == 0:
                    tr.add("cymbal", bar, 0, crash, 0.6 + 0.2 * level, 0.2)
                    tr.add("fx", bar, 0, anvil, 0.35 + 0.15 * level, -0.2)
                    if level == 3:
                        tr.add("timp", bar, 0, ins.timpani(45, 1.6, 1.0), 0.9)
            elif local == 4:  # 3-2-1
                tr.drum("tick", bar, "xxxxxxxxxxxxxxxx", tick, 0.5, 0.35)
                for k in range(16):
                    tr.add("timp", bar, k, ins.timpani(40, 0.5, 0.5), 0.15 + 0.035 * k)
                tr.drum("toms", bar, "x...x...x.x.xxxx", tom_hi if level < 3 else boom, 0.7)
                if level >= 2:
                    tr.kick("kick", bar, "x...x...x...x...", bd, 0.8)
            elif local == 5:  # the hush: the chop is the game's, then a heartbeat under the verdict
                tr.drum("kick", bar, "....x.x.....x.x.", bd, 0.8)
                tr.drum("tick", bar, "....x...x...x...", tick, 0.5, 0.35)
                for k in range(4, 16):
                    tr.add("timp", bar, k, ins.timpani(48, 0.5, 0.4), 0.1 + 0.008 * k)
            elif local == 6:  # the crown
                tr.add("cymbal", bar, 0, crash, 0.8 + 0.1 * level, -0.2)
                tr.add("timp", bar, 0, ins.timpani(41, 1.6, 1.0), 0.9)
                tr.kick("kick", bar, "x.......x.......", bd, 0.9)
                tr.drum("clap", bar, "....x.......x...", clap, 0.6 + 0.1 * level)
                tr.drum("shaker", bar, "x.x.x.x.x.x.x.x.", shake, 0.6)
            elif local == 7:
                tr.kick("kick", bar, "x.......x.......", bd, 0.9)
                tr.drum("shaker", bar, "x.x.x.x.x.x.x.x.", shake, 0.6)
                if level < 3:
                    tr.drum("toms", bar, "........x.x.xxxx", tom_hi, 0.7)
                else:  # the winner of the whole round
                    tr.add("cymbal", bar, 0, crash, 1.0, 0.2)
                    tr.add("timp", bar, 0, ins.timpani(43, 1.6, 1.0), 1.0)
                    tr.drum("clap", bar, "....x.......x...", clap, 0.9)
                    tr.drum("toms", bar, "........x.x.xxxx", boom, 0.8)

    # ---- the tunes
    for first, level in ((8, 1), (16, 2), (24, 3)):
        if level == 1:
            tr.play("whistle", first, theme, whistle, 1.0)
        elif level == 2:
            tr.play("trumpet", first, theme, trumpet, 1.0)
            tr.play("trumpet2", first, second, trumpet, 0.8)
        else:
            tr.play("whistle", first, theme, whistle, 1.0)
            tr.play("trumpet", first, theme, trumpet, 0.7)
            tr.play("trumpet2", first, second, trumpet, 0.75)
        if level < 3:
            tr.play("trumpet", first + 6, hail, trumpet, 0.85)
            tr.play("trumpet2", first + 6, hail2, trumpet, 0.7)
            tr.play("trumpet", first + 7, ready, trumpet, 0.85)
            tr.play("trumpet2", first + 7, ready2, trumpet, 0.7)
        else:
            tr.play("trumpet", first + 6, crown, trumpet, 1.0)
            tr.play("trumpet2", first + 6, crown2, trumpet, 0.85)
            tr.play("trumpet", first + 7, winner, trumpet, 1.0)
            tr.play("trumpet2", first + 7, winner2, trumpet, 0.85)
    tr.play("trumpet", 32, melody("C#6:16 | r:16"), trumpet, 1.0)
    tr.play("trumpet2", 32, melody("A5:16 | r:16"), trumpet, 0.85)
    tr.play("whistle", 33, sunset, whistle, 0.7)

    mix = Mix(buses={
        "whistle": Bus(-6, reverb=0.3, delay=0.12),
        "trumpet": Bus(-7, reverb=0.25, delay=0.05),
        "trumpet2": Bus(-12, reverb=0.25),
        "choir": Bus(-13, reverb=0.35),
        "strings": Bus(-14, reverb=0.3),
        "twang": Bus(-10, spring=0.3),
        "nylon": Bus(-14, reverb=0.15),
        "kick": Bus(-13),
        "toms": Bus(-13, reverb=0.15),
        "clap": Bus(-17, reverb=0.2),
        "shaker": Bus(-22, eq=(("lp", 8000),)),
        "tick": Bus(-19),
        "timp": Bus(-13, reverb=0.25),
        "cymbal": Bus(-19),
        "fx": Bus(-14, reverb=0.3),
        "bell": Bus(-17, reverb=0.4),
        "grill": Bus(-24, eq=(("lp", 7000),)),
    }, reverb_decay=2.2, reverb_tone=5000, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("PrimeCut", "High Steaks", 120, 8, 36, prime_cut)
