"""Rumble on the Rug: the round song for BigBadVacuum (see songkit.py for the rules every song keeps).

Owner: "make it but make it feel super sick and epic" (for Big Bad Vacuum, the whole lobby against a
giant robot vacuum in a kid's living room at night)."""

from functools import lru_cache

from score import Note

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def faded(x, seconds=0.02):
    """A short fade at the very end, so a tail that's cut off doesn't click."""
    x = np.array(x, dtype=float)
    k = min(x.shape[-1], s.samples(seconds))
    x[..., -k:] *= np.linspace(1.0, 0.0, k)
    return x


def _t(n):
    return np.arange(n) / s.SR


def _noise(n, *key):
    return ins._rng("bigbadvacuum", *key).uniform(-1, 1, n)


def harmony(notes, first, parts, spb=16):
    """The twin guitar: for every note of the tune, the nearest chord tone at least a minor third below
    it (in the chord under that note), so the two leads ring together and never rub."""
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


# ---------------------------------------------------------------- the band

@lru_cache(maxsize=None)
def hero_lead(m, sec):
    """The heroic lead guitar: one string picked twice a hair apart (a fat, singing tone) and pushed hard
    into the amp, a bend up into every note, wide finger vibrato on the held ones and a cocked wah's
    vocal honk, through a speaker cabinet."""
    ring = sec + 0.35
    a = np.asarray(ins.ks(m, ring, bright=0.8, decay=5.0, pick=0.14, soft=0.05))
    b = np.asarray(ins.ks(m + 0.07, ring, bright=0.76, decay=5.0, pick=0.18, soft=0.05, variant=7))
    x = a + 0.7 * b
    t = _t(x.shape[-1])
    pitch = -0.7 * np.exp(-t / 0.035)
    if sec > 0.3:
        pitch = pitch + 0.3 * np.clip((t - 0.17) / 0.25, 0, 1) * np.sin(2 * np.pi * 6.0 * t)
    x = ins.drive(ins.bend(x, pitch) * 6.0, 4.5)
    x = ins.eq(x, ("hp", 260), ("peak", 950, 5.0, 2.0), ("peak", 2300, 1.5, 1.4), ("lp", 4600), ("lp", 6200))
    return faded(ins.normalize(ins._gate(x, sec + 0.03, 0.09)))


@lru_cache(maxsize=None)
def chip(m, sec):
    """The vacuum's robot brain: a thin 8-bit pulse wave (12.5% duty, like an old game console's) with a
    hard edge and a quick fall, for its arpeggios; the fizz is filtered off for phones."""
    n = s.samples(sec + 0.04)
    tone = s.square(s.midi_hz(m), n, 0.125)
    e = ins.env(n, 0.002, max(0.04, sec * 0.6), 0.35, 0.02, gate=sec)
    return faded(ins.normalize(ins.eq(tone * e, ("hp", 250), ("lp", 5200), ("lp", 7000))))


@lru_cache(maxsize=None)
def metal_kick():
    """A tight double-bass-drum kick: a short punch at 60-200 Hz (where a phone can play it) with the
    beater's click on top, short enough for sixteenth-note rolls."""
    n = s.samples(0.22)
    t = _t(n)
    body = s.sine(62 + 170 * np.exp(-t / 0.022), n) * np.exp(-t / 0.075)
    click = ins.eq(_noise(n, "beater"), ("hp", 1800), ("lp", 7000)) * np.exp(-t / 0.0035) * 0.6
    knock = s.sine(np.full(n, 1250.0), n) * np.exp(-t / 0.008) * 0.2
    return faded(ins.normalize(np.tanh((body + click + knock) * 2.0)))


@lru_cache(maxsize=None)
def china(length=1.2):
    """A trashy china cymbal for the big hits: a clangy, honking crash."""
    n = s.samples(length)
    t = _t(n)
    metal = sum(s.square(np.full(n, f), n, 0.5) for f in (420.0, 573.0, 811.0, 1187.0, 1630.0, 2311.0)) / 6
    x = ins.eq(metal * 0.6 + _noise(n, "china", length) * 0.7, ("hp", 900), ("peak", 3200, 6, 1.0), ("lp", 9500))
    return faded(ins.normalize(x * np.exp(-t / 0.35) * np.clip(t / 0.002, 0, 1)))


@lru_cache(maxsize=None)
def brick(variant=0):
    """Two plastic toy bricks knocked together: a hollow, bright clack (the lobby's ammo)."""
    n = s.samples(0.12)
    t = _t(n)
    f = 1900 * (1 + 0.06 * variant)
    tone = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t / d) for r, a, d in ((1.0, 1.0, 0.018), (1.73, 0.6, 0.01), (2.61, 0.35, 0.006)))
    tok = np.sin(2 * np.pi * 720 * t) * np.exp(-t / 0.012) * 0.5
    click = ins.eq(_noise(n, "brick", variant), ("hp", 2500)) * np.exp(-t / 0.002) * 0.5
    return faded(ins.normalize(tone + tok + click))


# ---------------------------------------------------------------- the vacuum

@lru_cache(maxsize=None)
def siren(length, low, high, cycle):
    """The vacuum's alarm: a wailing siren (a pulse through a horn's honk) sweeping from `low` up to
    `high` and back every `cycle` seconds, in tune with the band."""
    n = s.samples(length)
    t = _t(n)
    pitch = low + (high - low) * (0.5 - 0.5 * np.cos(2 * np.pi * t / cycle))
    f = s.midi_hz(pitch)
    tone = s.square(f, n, 0.3) * 0.6 + s.saw(f, n) * 0.4
    tone = ins.eq(ins.formant(tone, [(1100, 8, 2.0), (2400, 4, 2.5)]), ("hp", 400), ("lp", 4200))
    e = np.clip(t / 0.15, 0, 1) * np.clip((length - t) / 0.2, 0, 1)
    return faded(ins.normalize(tone * e))


@lru_cache(maxsize=None)
def motor(length, start, end):
    """The vacuum's motor spinning up: a turbine whine gliding from `start` to `end` Hz over the rush of
    air through it, louder as it goes."""
    n = s.samples(length)
    t = _t(n)
    x = t / length
    f = start * (end / start) ** (x ** 1.4)
    whine = ins.eq(s.saw(f, n) * 0.5 + s.sine(f * 2, n) * 0.3 + s.sine(f * 3.01, n) * 0.15, ("hp", 200), ("lp", 5000))
    air = ins.eq(ins.tv_lowpass(_noise(n, "air", length), 300 + 5000 * x ** 1.5, q=1.5), ("hp", 200))
    return faded(ins.normalize((whine * 0.6 + air * 0.8) * (0.15 + 0.85 * x ** 1.8)), 0.05)


@lru_cache(maxsize=None)
def suck(length):
    """The vacuum breathing in: a rush of air rising in pitch and getting louder, cut off with a gulp."""
    n = s.samples(length)
    t = _t(n)
    x = t / length
    air = ins.eq(ins.tv_lowpass(_noise(n, "suck", length), 250 + 7000 * x ** 2, q=2.5), ("hp", 150))
    whistle = s.sine(s.midi_hz(60 + 30 * x ** 1.5), n) * 0.15
    return faded(ins.normalize((air + whistle) * x ** 2.2), 0.015)


@lru_cache(maxsize=None)
def falling(length):
    """The boss dropping from the ceiling: a cartoon bomb-drop whistle sliding down, louder as it nears."""
    n = s.samples(length)
    t = _t(n)
    x = t / length
    f = s.midi_hz(100 - 28 * x ** 1.3 + ins._vibrato(t, 0.1, 7.0, 0.0, 0.1))
    tone = s.sine(f, n) + 0.1 * s.sine(f * 2, n)
    return faded(ins.normalize(tone * (0.3 + 0.7 * x) * np.clip(t / 0.05, 0, 1)), 0.03)


@lru_cache(maxsize=None)
def slam():
    """The boss landing on the rug: a deep thump (with its octave, for phones), a crunch and toy bricks
    rattling across the floor."""
    n = s.samples(1.6)
    t = _t(n)
    boom = s.sine(55 + 90 * np.exp(-t / 0.04), n) * np.exp(-t / 0.35)
    octave = s.sine(110 + 160 * np.exp(-t / 0.03), n) * np.exp(-t / 0.18) * 0.6
    crunch = ins.eq(_noise(n, "slam"), ("hp", 200), ("lp", 3500)) * np.exp(-t / 0.06) * 0.6
    x = np.tanh((boom + octave + crunch) * 1.6)
    rng = ins._rng("rattle")
    for k in range(8):
        start = s.samples(rng.uniform(0.05, 0.7))
        clack = np.asarray(brick(k % 4))[: n - start]
        x[start:start + len(clack)] += clack * 0.25 * (1 - k / 10)
    return faded(ins.normalize(x))


@lru_cache(maxsize=None)
def hum(length):
    """The vacuum idling in the dark: a low buzzing drone on D whose filter breathes, swelling in."""
    n = s.samples(length)
    t = _t(n)
    f = s.midi_hz(38)
    tone = s.saw(f, n) * 0.5 + s.saw(f * 1.004, n) * 0.5 + s.sine(f * 2, n) * 0.3
    tone = ins.tv_lowpass(tone, 300 + 500 * (0.5 - 0.5 * np.cos(2 * np.pi * t / 1.6)), q=2.0)
    e = np.clip(t / (length * 0.6), 0, 1) ** 1.5 * np.clip((length - t) / 0.3, 0, 1)
    return faded(ins.normalize(ins.eq(tone, ("hp", 60)) * e))


@lru_cache(maxsize=None)
def wub(m, length, rate):
    """The vacuum's motor under the breakdown: a growling saw whose filter sucks open and shut `rate`
    times a second (wom-wom-wom), over a round sine."""
    n = s.samples(length + 0.05)
    t = _t(n)
    f = s.midi_hz(m)
    tone = s.saw(f, n) * 0.6 + s.square(f * 1.005, n, 0.5) * 0.3
    lfo = 0.5 - 0.5 * np.cos(2 * np.pi * rate * t)
    tone = ins.tv_lowpass(tone, 180 + 2200 * lfo ** 1.5, q=3.0)
    e = ins.env(n, 0.01, 0.3, 0.9, 0.05, gate=length)
    return faded(ins.normalize(ins.drive((tone + s.sine(f, n) * 0.5) * e * 1.5, 1.5)))


@lru_cache(maxsize=None)
def droop(m):
    """The lullaby's last note as the toy box's battery runs down: it rings, then sags a whole tone."""
    x = np.asarray(ins.fm(m, 1.2, 4.0, 0.7, 1.2, mod_decay=0.1))
    t = _t(x.shape[-1])
    return faded(ins.bend(x, -2.0 * np.clip((t - 0.25) / 1.2, 0, 1) ** 1.6))


# ---------------------------------------------------------------- the song

def big_bad_vacuum():
    """Rumble on the Rug (152 bpm, D minor, up to E minor and out in G major): toy-box metal for the
    whole lobby against the Big Bad Vacuum. A celesta plays a lullaby in the dark living room until
    the vacuum's red eye beeps on, its motor hums and the lullaby sags like a toy whose battery is
    dying; the band creeps in, the siren wails and the vacuum takes a breath into GO. The drop is the
    boss's entrance: the band hammers its motif (D, E flat, D, then the tritone) in stop time with
    brass and a choir, a bomb-drop whistle follows it down from the ceiling, the biggest hit lands
    with it (3.6 s after GO) and holds through its roar, and a fill starts the fight (5.5 s). Then
    palm-muted guitars gallop over a double kick with an 8-bit arpeggio (the robot's brain) and toy
    bricks clacking on the hits (6-19 s); the heroic twin-lead theme, the lullaby grown up, with a toy
    piano on top (19-32 s); and an anthem chorus in F with choir and brass (32-44 s). The suction
    break (44-57 s) is a half-time breakdown on a wom-wom motor bass under the boss's motif, the toys
    playing the riff on a toy piano and xylophone until the vacuum sucks them up, and a climb back in.
    Everything goes up a step to E minor for the angrier boss (57 s): the riff, the theme, and the
    anthem in G as the finale (76-88 s), whose last hit lands as the fight's clock runs out (87.5 s).
    A victory lullaby on the toy piano, then the vacuum reboots: its eye, its motif, its siren and its
    breath lead back into the drop."""
    tr = Track(bpm=152, bars=73)
    parts = plan(tr, [
        ("intro", 9, "Dm | Dm | Bb | C | Dm | Bb | Gm | A | A"),
        ("reveal", 4, "Dm | Dm | Bb | A"),
        ("riff", 8, "Dm | Dm | Dm | Bb A | Dm | Dm | Dm | Bb A"),
        ("hero", 8, "Dm | Bb | C | Dm | Dm | Bb | Gm | A"),
        ("chorus", 8, "Bb | C | Dm | Dm | Bb | C | F | A"),
        ("suction", 8, "Dm | Dm | Dm | Dm | Bb | C | D | B"),
        ("riff2", 4, "Em | Em | Em | C B"),
        ("hero2", 8, "Em | C | D | Em | Em | C | Am | B"),
        ("finale", 8, "C | D | Em | Em | C | D | C D | D"),
        ("outro", 8, "G | C | G | G | Bb | C | A | A"),
    ])
    part = {p.name: p for p in parts}

    lullaby = melody("r:12 A4:4 | D5:4 F5:4 A5:8 | Bb5:6 A5:2 F5:4 D5:4 | C5:4 E5:4 G5:8 | F5:6 E5:2 D5:8 | A5:4 C6:4 r:8")
    victory = melody("E5:4 G5:4 C6:8 | D6:6 C6:2 B5:4 G5:4 | A5:4 B5:4 G5:8")
    boss = melody("D4:6 Eb4:2 D4:8 | Ab4:6 G4:2 F4:4 E4:4")
    stir_intro = melody("D4:6 Eb4:2 D4:8 | D4:6 Eb4:2 D4:4 Bb3:4")
    stir_outro = melody("D4:6 Eb4:2 D4:8 | E4:6 F4:2 E4:8")
    rising = melody("C#4:6 D4:2 E4:8 | A3:4 C#4:4 E4:4 A4:4")
    hero = melody("""D5:2 D5:1 F5:1 A5:8 G5:2 F5:2 | Bb5:6 A5:2 F5:4 D5:4 | C5:2 C5:1 E5:1 G5:8 F5:2 E5:2 | F5:6 E5:2 D5:8 |
                     A5:2 A5:1 C6:1 D6:8 C6:2 A5:2 | D6:6 C6:2 Bb5:4 F5:4 | G5:2 G5:1 A5:1 Bb5:4 D6:4 C6:2 Bb5:2 |
                     A5:2 A5:1 C#6:1 E6:8 C#6:2 A5:2""")
    anthem = melody("""D5:2 F5:2 Bb5:8 A5:2 Bb5:2 | C6:6 Bb5:2 A5:4 G5:4 | F5:4 A5:4 D6:8 | D6:6 C6:2 A5:8 |
                       D5:2 F5:2 Bb5:8 A5:2 Bb5:2 | C6:6 D6:2 E6:4 C6:4 | F6:8 E6:4 C6:4 | C#6:4 E6:12""")
    finale = melody("""E5:2 G5:2 C6:8 B5:2 C6:2 | D6:6 C6:2 B5:4 A5:4 | G5:4 B5:4 E6:8 | E6:6 D6:2 B5:8 |
                       E5:2 G5:2 C6:8 B5:2 C6:2 | D6:6 E6:2 F#6:4 D6:4 | E6:6 D6:2 F#6:6 E6:2 | D6:4 E6:4 F#6:8 | G6:16""")
    # the riff: power-chord roots; a soft note (') is palm-muted, an accented one (!) rings open
    riff_a = melody("""D2:2' D2:1' D2:1' D2:2' D2:1' D2:1' D2:2' D2:1' D2:1' F2:2! G2:2! |
                       D2:2' D2:1' D2:1' D2:2' D2:1' D2:1' Ab2:2! G2:2! F2:2! E2:2! |
                       D2:2' D2:1' D2:1' D2:2' D2:1' D2:1' D2:2' D2:1' D2:1' F2:2! G2:2! |
                       Bb2:2' Bb2:1' Bb2:1' Bb2:4! A2:2' A2:1' A2:1' A2:4!""")

    kick = metal_kick()
    snares = [ins.snare2(215.0, 1.0, 0.24, v) for v in range(4)]
    toms = [ins.tom(p, 0.45, v) for v, p in enumerate((210.0, 160.0, 120.0, 88.0))]
    chat, ohat, crash, ride, chin = s.hat(False), s.hat(True), s.crash(2.0), ins.ride(1.2, 0.45), china()
    gong, jingle, toy_kick = ins.gong(4.0, 98.0), ins.jingles(0.12), ins.woodblock(520.0, 0.1)
    riser1, riser2 = s.riser(tr.bar), s.riser(tr.bar * 2)

    def sec(steps):
        return round(tr.step * steps, 4)  # rounded, so the instruments' note caches hit

    def horns(m, length):
        return ins.brass(m, length, bright=0.55, section=3, vibrato=0.03)

    def trumpets(m, length):
        return ins.brass(m, length, bright=1.0, section=3, vibrato=0.05)

    def beat(stem, bar, pattern, sounds, gain=1.0, pan=0.0):
        """One bar of a drum pattern (X accent, x hit, o ghost), taking turns through the sound's variants."""
        sounds = list(sounds) if isinstance(sounds, list) else [sounds]
        k = 0
        for step, ch in enumerate(pattern):
            vel = {"X": 1.0, "x": 0.8, "o": 0.45}.get(ch)
            if vel:
                tr.add(stem, bar, step, sounds[k % len(sounds)], gain * vel, pan)
                k += 1

    def fill(bar, start=8, gain=1.0):
        """Snare sixteenths, then down the toms, into the next section."""
        for k in range(start, 16):
            if k < 12:
                tr.add("snare", bar, k, snares[k % 4], gain * (0.5 + 0.045 * k))
            else:
                tr.add("toms", bar, k, toms[k - 12], gain * 0.95, (-0.4, -0.15, 0.15, 0.4)[k - 12])

    def crash_at(bar, step=0, gain=1.0, pan=-0.3):
        tr.add("cymbals", bar, step, crash, gain, pan)

    def chord_hit(bar, step, root, steps, mute=False, gain=1.0, octave=False):
        """Both rhythm guitars (hard left and right) on one power chord; `octave` adds a third guitar an
        octave up for the big hits."""
        for side, pan in ((0, -0.8), (1, 0.8)):
            tr.add("rhythm", bar, step + 0.06 * side, ins.power_chord(root, sec(steps), mute, side), gain, pan)
        if octave:
            tr.add("rhythm", bar, step + 0.1, ins.power_chord(root + 12, sec(steps), False, 2), gain * 0.5)

    def bass(bar, step, m, steps, gain=1.0):
        tr.add("bass", bar, step, ins.bass_guitar(m, sec(steps * 0.95), 0.6, int(step) % 3), gain)

    def gallop(bar, step, length, root, gain=1.0, octave=False):
        """The gallop (an eighth and two sixteenths on every beat), palm-muted, with the chord ringing
        out on its first beat; the bass gallops with it."""
        for k in range(int(step), int(step + length), 4):
            first = k == int(step)
            chord_hit(bar, k, root, 2, not first, gain * (1.0 if first else 0.82), octave and first)
            chord_hit(bar, k + 2, root, 0.9, True, gain * 0.68)
            chord_hit(bar, k + 3, root, 0.9, True, gain * 0.74)
            bass(bar, k, root, 2)
            bass(bar, k + 2, root, 1, 0.8)
            bass(bar, k + 3, root, 1, 0.85)

    def ring(bar, step, length, root, gain=1.0):
        """Big open chords for the anthem, struck every half bar, with the octave guitar; the bass in eighths."""
        for k in range(int(step), int(step + length), 8):
            chord_hit(bar, k, root, min(8, step + length - k), False, gain, True)
        for k in range(int(step), int(step + length), 2):
            bass(bar, k, root, 2, 1.0 if k % 4 == 0 else 0.85)

    def stab(bar, step, notes, steps=1.5, gain=1.0, bright=1.0):
        """The brass section on one short chord."""
        for k, m in enumerate(notes):
            tr.add("brass", bar, step, ins.brass(m, sec(steps), bright, 3, 0.0), gain / len(notes) ** 0.5, (k - 1) * 0.25)

    def riff(first, notes, big=False):
        """The riff on the guitars, the bass and the kick drum together; the open hits get a toy brick's
        clack and, when it's `big`, brass and choir stabs and the octave guitar."""
        for n in notes:
            bar, st = first + int(n.step // 16), n.step % 16
            mute = n.vel < 0.7
            chord_hit(bar, st, n.midi, n.length * (0.9 if mute else 1.0), mute, 0.82 if mute else 1.0, big and not mute)
            bass(bar, st, n.midi, n.length, 0.85 if mute else 1.0)
            tr.add("kick", bar, st, kick, 0.75 if mute else 1.0)
            if not mute:
                tr.add("perc", bar, st, brick(int(st) % 4), 0.7, 0.3 if int(st) % 4 else -0.3)
                if big:
                    stab(bar, st, (n.midi + 24, n.midi + 31, n.midi + 36), n.length * 0.75)
                    tr.add("choir", bar, st, ins.choir((n.midi + 19, n.midi + 24), sec(1.2), "ah", 0.01), 0.8)

    def arp(bar, step, length, c, gain=1.0, low=74, shape=(0, 1, 2, 3)):
        """The robot brain's 8-bit arpeggio in sixteenths, bouncing left and right."""
        tones = voicing(c, low, low + 17, size=4)
        for k in range(int(length)):
            m = tones[shape[k % len(shape)]]
            tr.add("chip", bar, step + k, chip(m, sec(0.85)), gain * (1.0 if k % 4 == 0 else 0.72), 0.4 if k % 2 else -0.4)

    def pad(bar, step, length, c, gain=1.0, vowel="ah"):
        tr.add("choir", bar, step, ins.choir(tuple(voicing(c, 55, 72, size=4)), sec(length), vowel, 0.25), gain)

    def strings_pad(bar, step, length, c, gain=1.0):
        tr.add("pad", bar, step, ins.strings(tuple(voicing(c, 50, 67, size=4)), sec(length), 0.2, 0.55), gain)

    def sing(first, notes, under, gain=1.0):
        """The choir on a tune: every note with its harmony under it, an octave down."""
        for n, h in zip(notes, under):
            tr.add("choir", first, n.step, ins.choir((h.midi - 12, n.midi - 12), sec(n.length), "ah", 0.05), gain * n.vel)

    def eye(bar, step, gain=1.0):
        """The vacuum's red eye blinking on: 'bee-boo'."""
        tr.add("fx", bar, step, ins.blip(93, 0.06), 0.6 * gain, 0.2)
        tr.add("fx", bar, step + 2, ins.blip(86, 0.12), 0.6 * gain, 0.2)

    def timp(bar, step, m, gain=1.0, hard=0.8):
        tr.add("timp", bar, step, ins.timpani(m, 1.4, hard), gain)

    def big_hit(bar, step, notes, root):
        """Everybody at once: the band, the orchestra, a gong and the vacuum's thump."""
        tr.add("kick", bar, step, kick)
        tr.add("snare", bar, step, snares[0])
        crash_at(bar, step, 1.0, -0.3)
        crash_at(bar, step + 0.1, 0.8, 0.3)
        tr.add("cymbals", bar, step, chin, 0.8, 0.1)
        tr.add("fx", bar, step, slam(), 0.9)
        tr.add("fx", bar, step, gong, 0.6)
        tr.add("orch", bar, step, ins.orchestra_hit(tuple(notes), 0.6), 1.0)
        timp(bar, step, 41 + (root - 41) % 12, 1.0, 1.0)

    def climb(bar):
        """Two bars on A into the drop: the siren wails, the band winds up and the vacuum takes a breath
        (the intro's last two bars and the outro's, so the loop carries straight on)."""
        a = part["intro"].changes[-1][3]
        tr.add("fx", bar, 0, siren(sec(32), 81, 86, sec(16)), 0.7, -0.2)
        tr.add("fx", bar, 0, riser2, 0.45)
        tr.play("brass", bar, rising, horns, 0.7)
        tr.add("choir", bar, 0, ins.choir((57, 61, 64, 69), sec(32), "ah", sec(26)), 0.8)
        for k in range(0, 16, 2):
            chord_hit(bar, k, 45, 1.8, True, 0.5 + 0.02 * k)
            bass(bar, k, 45, 2, 0.75)
        for k in range(12):
            chord_hit(bar + 1, k, 45, 0.9, True, 0.62 + 0.025 * k)
            bass(bar + 1, k, 45, 1, 0.8)
        chord_hit(bar + 1, 12, 45, 4, False, 1.0, True)
        bass(bar + 1, 12, 45, 4)
        arp(bar, 0, 16, a, 0.45, 69)
        arp(bar + 1, 0, 16, a, 0.65, 69, (0, 1, 2, 3, 1, 2, 3, 2))
        beat("kick", bar, "X...X...X...X...", kick, 0.85)
        beat("snare", bar, "....o...o.o.x.xx", snares, 0.8)
        beat("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.6, 0.25)
        beat("kick", bar + 1, "XxxxXxxxXxxxXxxx", kick, 0.85)
        fill(bar + 1, 4)
        for k in range(16):
            tr.add("timp", bar + 1, k, ins.timpani(45, 0.5, round(0.4 + 0.04 * k, 2)), 0.3 + 0.04 * k)
        tr.add("fx", bar + 1, 0, suck(sec(16)), 0.9)

    # ------------------------------------------------ the intro: a lullaby, then the vacuum wakes up
    for bar, step, length, c in part["intro"].changes:
        if bar <= 5:
            tr.add("pad", bar, step, ins.strings(tuple(voicing(c, 50, 65, size=3)), sec(length), 0.5, 0.25, 0.8), 0.45 + 0.1 * min(bar, 4))
    tr.add("music", 0, 4, ins.glock(93, 0.5), 0.35, 0.3)  # the night-light's twinkle
    tr.add("music", 0, 8, ins.glock(86, 0.5), 0.3, -0.3)
    tr.play("music", 0, lullaby, ins.celesta, 1.0, 0.1)
    tr.play("toy", 0, shift(lullaby, 12), ins.toy_piano, 0.35, -0.25)
    tr.add("music", 5, 8, droop(86), 1.0, 0.1)  # ...and it sags: the toy box's battery is running down
    eye(3, 8)
    tr.add("fx", 3, 8, hum(sec(88)), 0.7)
    eye(5, 12, 1.2)
    # Bb, Gm: a low chord rings, the boss's motif on the horns, the drums and guitars creep in
    chord_hit(5, 0, 46, 16, False, 0.35)
    bass(5, 0, 46, 16, 0.4)
    timp(5, 0, 46, 0.6, 0.5)
    tr.play("brass", 5, stir_intro, horns, 0.55)
    tr.add("choir", 5, 0, ins.choir((50, 53, 58), sec(32), "oo", 0.6), 0.5)
    tr.add("fx", 5, 0, motor(sec(64), 120.0, 900.0), 0.5)
    for k in range(0, 16, 2):
        chord_hit(6, k, 43, 1.8, True, 0.3 + 0.025 * k)
        bass(6, k, 43, 2, 0.5 + 0.02 * k)
    beat("toms", 6, "X...x...X...x...", toms[3], 0.6)
    beat("kick", 6, "X.......X.......", kick, 0.7)
    timp(6, 0, 43, 0.6, 0.6)
    arp(6, 0, 16, part["intro"].changes[6][3], 0.3)
    climb(7)

    # ------------------------------------------------ GO: the boss's entrance
    for n in boss:  # the band hammers the motif in stop time
        bar, st = 9 + int(n.step // 16), n.step % 16
        chord_hit(bar, st, n.midi - 24, n.length, False, 1.0, True)
        bass(bar, st, n.midi - 24, n.length)
        tr.add("kick", bar, st, kick)
        tr.add("choir", 9, n.step, ins.choir((n.midi - 12, n.midi), sec(n.length), "ah", 0.03), 0.9)
    tr.play("brass", 9, boss, trumpets, 0.8)
    tr.play("brass", 9, shift(boss, -12), horns, 0.9)
    big_hit(9, 0, (62, 65, 69, 74), 38)
    for bar in (9, 10):
        beat("snare", bar, "........X.......", snares)
        beat("hats", bar, "..x...x...x...x.", ohat, 0.45, 0.25)
    eye(9, 12, 0.9)
    tr.add("cymbals", 10, 0, chin, 0.7, -0.2)
    tr.add("fx", 10, 0, falling(sec(20)), 0.8, 0.15)  # ...it falls from the ceiling...
    # ...and lands (3.6 s after GO), and roars
    chord_hit(11, 4, 46, 12, False, 1.0, True)
    bass(11, 4, 46, 12)
    big_hit(11, 4, (58, 62, 65, 70), 46)
    tr.add("choir", 11, 4, ins.choir((53, 58, 62, 65), sec(12), "ah", 0.02), 1.0)
    for m in (62, 65, 70):
        tr.add("brass", 11, 4, ins.brass(m, sec(11), 1.0, 3, 0.06, 3.0), 0.6)
    # the fill into the fight, which starts halfway through this bar
    for k in range(12):
        chord_hit(12, k, 45, 0.9, True, 0.6 + 0.03 * k)
        bass(12, k, 45, 1, 0.7 + 0.02 * k)
    chord_hit(12, 12, 45, 4, False, 1.0, True)
    bass(12, 12, 45, 4)
    beat("kick", 12, "XxxxXxxxXxxxXxxx", kick, 0.85)
    fill(12, 8)
    tr.play("brass", 12, melody("A3:4 C#4:4 E4:4 A4:4"), trumpets, 0.8)
    for k, m in enumerate((69, 73, 76, 81, 73, 76, 81, 85, 76, 81, 85, 88, 81, 85, 88, 93)):
        tr.add("chip", 12, k, chip(m, sec(0.85)), 0.5 + 0.03 * k, 0.4 if k % 2 else -0.4)
    tr.add("fx", 12, 0, riser1, 0.45)

    # ------------------------------------------------ the fight: the riff
    riff(13, riff_a)
    riff(17, riff_a, big=True)
    for bar, step, length, c in part["riff"].changes:
        arp(bar, step, length, c, 0.55 if bar < 17 else 0.7)
    for bar in part["riff"].bars_range():
        local = bar - 13
        beat("snare", bar, "....X.......X...", snares)
        beat("hats", bar, "x.x.x.x.x.x.x.x." if local < 4 else "x.X.x.X.x.X.x.X.", chat if local < 4 else [chat, ohat], 0.6, 0.25)
        if local in (0, 4):
            crash_at(bar)
            tr.add("cymbals", bar, 0, chin, 0.6, 0.3)
        if local == 7:
            fill(bar, 12)

    # ------------------------------------------------ the heroes' theme (the lullaby, grown up)
    tr.play("lead", 21, hero, hero_lead)
    tr.play("lead2", 21, [n for n in harmony(hero, 21, parts) if n.step >= 64], hero_lead, pan=0.35)
    tr.play("toy", 21, shift(hero, 12), ins.toy_piano, 0.5, -0.3)
    for bar, step, length, c in part["hero"].changes:
        gallop(bar, step, length, bass_note(c, 36))
        if bar >= 25:
            pad(bar, step, length, c, 0.55, "oo")
    for bar in part["hero"].bars_range():
        local = bar - 21
        beat("kick", bar, "XxxxXxxxXxxxXxxx", kick, 0.75)
        beat("snare", bar, "....X.......X...", snares)
        beat("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.6, 0.25)
        if local in (0, 4):
            crash_at(bar, 0, 1.0, 0.3 if local else -0.3)
        if local == 7:
            fill(bar, 12)

    # ------------------------------------------------ the anthem
    under = harmony(anthem, 29, parts)
    tr.play("lead", 29, anthem, hero_lead)
    tr.play("lead2", 29, under, hero_lead, 0.7, 0.35)
    sing(29, anthem, under)
    tr.play("brass", 29, shift(anthem, -12), trumpets, 0.75)
    tr.play("toy", 29, shift(anthem, 12), ins.glock, 0.35, 0.3)
    for bar, step, length, c in part["chorus"].changes:
        root = bass_note(c, 36)
        if bar < 36:
            ring(bar, step, length, root)
            strings_pad(bar, step, length, c, 0.6)
        else:  # the last bar rings out while the vacuum breathes in
            chord_hit(bar, 0, root, 16, False, 1.0, True)
            bass(bar, 0, root, 16)
        timp(bar, step, 41 + (root - 41) % 12, 0.8)
    for bar in part["chorus"].bars_range():
        local = bar - 29
        if local < 7:
            beat("kick", bar, "XxxxXxxxXxxxXxxx", kick, 0.8)
            beat("snare", bar, "....X.......X...", snares)
            beat("cymbals", bar, "x...x...x...x...", ride, 0.8, -0.2)
        else:
            tr.add("kick", bar, 0, kick)
            for k in range(4, 16):
                tr.add("snare", bar, k, snares[k % 4], 0.25 + 0.05 * k)
        if local % 2 == 0:
            crash_at(bar, 0, 1.0, 0.3 if local % 4 else -0.3)
        if local in (0, 4):
            tr.add("orch", bar, 0, ins.orchestra_hit(tuple(voicing(part["chorus"].at(bar)[0][2], 58, 74)), 0.6), 0.9)
    tr.add("fx", 36, 0, suck(sec(16)), 0.9)

    # ------------------------------------------------ the suction break
    # half time: the guitars and the kick chug against the motor's wom-wom, under the boss's motif
    tr.play("brass", 37, boss, trumpets, 0.75)
    tr.play("brass", 37, shift(boss, -12), horns, 0.9)
    for n in boss:
        tr.add("choir", 37, n.step, ins.choir((n.midi - 12, n.midi), sec(n.length), "ah", 0.03), 0.8)
    for bar, pattern in ((37, "X..x..x.X..x.x.."), (38, "X..x..x.X...X.X.")):
        for k, ch in enumerate(pattern):
            if ch != ".":
                chord_hit(bar, k, 38, 2 if ch == "X" else 0.9, ch == "x", 1.0 if ch == "X" else 0.85)
                tr.add("kick", bar, k, kick, 1.0 if ch == "X" else 0.85)
        beat("snare", bar, "........X.......", snares)
        beat("hats", bar, "x...x...x...x...", ohat, 0.6, 0.25)
        tr.add("cymbals", bar, 0, chin, 0.8, -0.2)
    tr.add("wub", 37, 0, wub(38, sec(32), round(1 / tr.beat, 4)), 1.0)
    tr.add("fx", 37, 0, siren(sec(32), 81, 86, sec(16)), 0.55, 0.3)
    # the toys play the riff (a toy piano, a xylophone and the robot's chip), until the vacuum sucks them up
    for n in riff_a:
        if n.step >= 32:
            continue
        bar, st = 39 + int(n.step // 16), n.step % 16
        accent = n.vel > 0.7
        tr.add("toy", bar, st, ins.toy_piano(n.midi + 36, sec(n.length)), 1.0 if accent else 0.75, -0.25)
        tr.add("toy", bar, st, ins.xylophone(n.midi + 48, sec(n.length)), 0.55 if accent else 0.4, 0.3)
        tr.add("chip", bar, st, chip(n.midi + 36, sec(n.length * 0.8)), 0.6)
    for bar in (39, 40):
        beat("perc", bar, "....X.......X...", [brick(0), brick(2)])
        beat("perc", bar, "x.x.x.x.x.x.x.x.", jingle, 0.4, 0.3)
        beat("perc", bar, "X.......X.......", toy_kick, 0.8, -0.1)
    tr.add("wub", 39, 0, wub(38, sec(16), round(2 / tr.beat, 4)), 0.45)
    tr.add("fx", 40, 0, suck(sec(16)), 1.0)
    # ...and the band climbs back in: Bb, C, D, then B (E minor's dominant)
    for bar, step, length, c in part["suction"].changes:
        if bar < 41:
            continue
        root, local = bass_note(c, 36), bar - 41
        voices = tuple(voicing(c, 55, 72, size=4))
        if local < 2:
            for k in range(0, 16, 2):
                chord_hit(bar, k, root, 1.8, False, 0.75 + 0.1 * local + 0.01 * k, k == 0)
                bass(bar, k, root, 2, 0.9)
        elif local == 2:
            for k in range(16):
                chord_hit(bar, k, root, 0.9, True, 0.6 + 0.025 * k)
                bass(bar, k, root, 1, 0.75 + 0.015 * k)
        else:
            for k in (0, 4, 8):
                chord_hit(bar, k, root, 3.5, False, 1.0, True)
                bass(bar, k, root, 3.5)
                stab(bar, k, voices[1:], 2.5)
                tr.add("choir", bar, k, ins.choir(voices, sec(2.5), "ah", 0.01), 0.9)
                timp(bar, k, root, 0.9, 0.9)
        if local < 3:
            tr.add("choir", bar, 0, ins.choir(voices, sec(16), "ah", 0.2), 0.7 + 0.1 * local)
            for m in voices[1:]:
                tr.add("brass", bar, 0, ins.brass(m, sec(15), 0.6 + 0.15 * local, 3, 0.05), 0.35 + 0.1 * local)
            arp(bar, 0, 16, c, 0.5 + 0.1 * local, 74, (0, 1, 2, 3, 3, 2, 1, 0))
    crash_at(41)
    beat("kick", 41, "X...X...X...X...", kick, 0.9)
    beat("snare", 41, "x.x.x.x.x.x.x.x.", snares, 0.5)
    crash_at(42, 0, 0.8, 0.3)
    beat("kick", 42, "X.X.X.X.X.X.X.X.", kick, 0.9)
    beat("snare", 42, "x.x.x.x.x.x.x.x.", snares, 0.65)
    crash_at(43, 0, 0.8)
    beat("kick", 43, "XxxxXxxxXxxxXxxx", kick, 0.85)
    for k in range(16):
        tr.add("snare", 43, k, snares[k % 4], 0.35 + 0.04 * k)
        tr.add("timp", 43, k, ins.timpani(50, 0.5, round(0.4 + 0.04 * k, 2)), 0.25 + 0.04 * k)
    for k in (0, 4, 8):
        tr.add("kick", 44, k, kick)
        tr.add("snare", 44, k, snares[k // 4])
        crash_at(44, k, 0.9, (-0.3, 0.3, 0.0)[k // 4])
    fill(44, 12)
    tr.add("fx", 41, 0, motor(sec(64), 140.0, 1600.0), 0.55)
    tr.add("fx", 43, 0, riser2, 0.5)
    tr.add("fx", 44, 8, suck(sec(8)), 0.8)

    # ------------------------------------------------ up a step: the angrier boss
    riff(45, shift(riff_a, 2), big=True)
    for bar, step, length, c in part["riff2"].changes:
        arp(bar, step, length, c, 0.75, 76)
    for bar in part["riff2"].bars_range():
        local = bar - 45
        beat("snare", bar, "....X.......X...", snares)
        beat("hats", bar, "x.X.x.X.x.X.x.X.", [chat, ohat], 0.6, 0.25)
        if local in (0, 2):
            crash_at(bar, 0, 1.0, 0.3 if local else -0.3)
            tr.add("cymbals", bar, 0, chin, 0.6, -0.1)
        if local == 3:
            fill(bar, 12)

    hero_up = shift(hero, 2)
    tr.play("lead", 49, hero_up, hero_lead)
    tr.play("lead2", 49, harmony(hero_up, 49, parts), hero_lead, pan=0.35)
    tr.play("toy", 49, shift(hero_up, 12), ins.toy_piano, 0.5, -0.3)
    for bar, step, length, c in part["hero2"].changes:
        gallop(bar, step, length, bass_note(c, 36), 1.0, True)
        pad(bar, step, length, c, 0.7)
        strings_pad(bar, step, length, c, 0.5)
    for bar in part["hero2"].bars_range():
        local = bar - 49
        beat("kick", bar, "XxxxXxxxXxxxXxxx", kick, 0.8)
        beat("snare", bar, "....X.......X...", snares)
        beat("cymbals", bar, "x...x...x...x...", ride, 0.75, -0.2)
        beat("hats", bar, "..x...x...x...x.", ohat, 0.4, 0.3)
        if local in (0, 4):
            crash_at(bar, 0, 1.0, 0.3 if local else -0.3)
        if local == 7:
            fill(bar, 12)

    # ------------------------------------------------ the finale: the anthem in G
    under = harmony(finale, 57, parts)
    tr.play("lead", 57, finale, hero_lead)
    tr.play("lead2", 57, under, hero_lead, 0.75, 0.35)
    sing(57, finale, under)
    tr.play("brass", 57, shift(finale, -12), trumpets, 0.8)
    tr.play("toy", 57, shift(finale, 12), ins.glock, 0.35, 0.3)
    for bar, step, length, c in part["finale"].changes:
        root = bass_note(c, 36)
        strings_pad(bar, step, length, c, 0.6)
        if bar < 64:
            ring(bar, step, length, root)
            arp(bar, step, length, c, 0.45, 76)
            timp(bar, step, 41 + (root - 41) % 12, 0.8)
        else:  # stop time on D-E-F sharp, then the fill into G
            voices = tuple(voicing(c, 62, 74, size=3))
            for k in (0, 4, 8):
                chord_hit(bar, k, root, 3.5, False, 1.0, True)
                bass(bar, k, root, 3.5)
                stab(bar, k, voices, 2.5)
                tr.add("choir", bar, k, ins.choir(voices, sec(2.5), "ah", 0.01), 0.9)
                tr.add("kick", bar, k, kick)
                tr.add("snare", bar, k, snares[k // 4])
                crash_at(bar, k, 0.9, (-0.3, 0.3, 0.0)[k // 4])
                timp(bar, k, 50, 0.9, 1.0)
            tr.add("snare", bar, 10, snares[2], 0.7)
            tr.add("snare", bar, 11, snares[3], 0.8)
            fill(bar, 12)
    for bar in range(57, 64):
        local = bar - 57
        beat("kick", bar, "XxxxXxxxXxxxXxxx", kick, 0.8)
        beat("snare", bar, "....X.......X...", snares)
        beat("cymbals", bar, "x...x...x...x...", ride, 0.75, -0.2)
        crash_at(bar, 0, 1.0 if local % 2 == 0 else 0.75, 0.3 if local % 2 else -0.3)
        if local % 2 == 1:
            tr.add("cymbals", bar, 8, chin, 0.55, 0.2)
        if local in (0, 4):
            tr.add("orch", bar, 0, ins.orchestra_hit(tuple(voicing(part["finale"].at(bar)[0][2], 60, 76)), 0.6), 0.9)
    tr.add("fx", 63, 0, riser1, 0.4)

    # ------------------------------------------------ the last hit, as the fight's clock runs out
    chord_hit(65, 0, 43, 16, False, 1.0, True)
    bass(65, 0, 43, 16)
    big_hit(65, 0, (55, 59, 62, 67), 43)
    tr.add("choir", 65, 0, ins.choir((55, 59, 62, 67), sec(30), "ah", 0.02), 1.0)
    for m in (59, 62, 67):
        tr.add("brass", 65, 0, ins.brass(m, sec(24), 0.9, 3, 0.06), 0.5)
    for k in range(8, 16):
        tr.add("timp", 65, k, ins.timpani(43, 0.5, round(0.5 + 0.03 * k, 2)), 0.6 - 0.03 * (k - 8))
    # the victory lullaby on the toy piano
    tr.play("music", 66, victory, ins.celesta, 1.0, 0.1)
    tr.play("toy", 66, shift(victory, 12), ins.toy_piano, 0.6, -0.25)
    tr.play("toy", 66, shift(victory, 24), ins.glock, 0.25, 0.3)
    for bar, step, length, c in part["outro"].changes:
        if not 66 <= bar <= 68:
            continue
        root = bass_note(c, 36)
        chord_hit(bar, 0, root, 16, False, 0.55)
        bass(bar, 0, root, 8, 0.6)
        bass(bar, 8, root, 8, 0.5)
        pad(bar, 0, 16, c, 0.55)
        for m in voicing(c, 55, 67, size=3):
            tr.add("brass", bar, 0, horns(m, sec(15)), 0.3)
        timp(bar, 0, 41 + (root - 41) % 12, 0.5, 0.5)
        beat("kick", bar, "X.......X.......", kick, 0.7)
        beat("snare", bar, "........X.......", snares, 0.7)
        beat("cymbals", bar, "x...x...x...x...", ride, 0.6, -0.2)
    # ...but the vacuum reboots: its eye, its hum, its motif, and back round into the drop
    eye(69, 0, 1.2)
    tr.add("fx", 69, 0, hum(sec(64)), 0.7)
    tr.add("fx", 69, 0, motor(sec(64), 120.0, 900.0), 0.5)
    chord_hit(69, 0, 46, 16, False, 0.35)
    bass(69, 0, 46, 16, 0.4)
    timp(69, 0, 46, 0.6, 0.5)
    tr.play("brass", 69, stir_outro, horns, 0.55)
    tr.add("choir", 69, 0, ins.choir((50, 53, 58), sec(16), "oo", 0.6), 0.5)
    tr.add("choir", 70, 0, ins.choir((52, 55, 60), sec(16), "oo", 0.3), 0.5)
    for k in range(0, 16, 2):
        chord_hit(70, k, 36, 1.8, True, 0.3 + 0.025 * k)
        bass(70, k, 36, 2, 0.5 + 0.02 * k)
    beat("toms", 70, "X...x...X...x...", toms[3], 0.6)
    beat("kick", 70, "X.......X.......", kick, 0.7)
    timp(70, 0, 48, 0.6, 0.6)
    arp(70, 0, 16, part["outro"].changes[5][3], 0.3)
    climb(71)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.15, delay=0.12),
        "lead2": Bus(-11, reverb=0.15),
        "rhythm": Bus(-8, eq=(("hp", 80), ("peak", 2200, -2.5, 1.0))),
        "bass": Bus(-11),
        "kick": Bus(-10, drive=1.3),
        "snare": Bus(-12, reverb=0.1),
        "toms": Bus(-14, reverb=0.1),
        "cymbals": Bus(-19, eq=(("lp", 9500),)),
        "hats": Bus(-22, eq=(("lp", 9500),)),
        "timp": Bus(-14, reverb=0.25),
        "choir": Bus(-11, reverb=0.35),
        "brass": Bus(-12, reverb=0.2),
        "orch": Bus(-12, reverb=0.3),
        "pad": Bus(-17, reverb=0.3),
        "chip": Bus(-17, delay=0.15),
        "toy": Bus(-16, reverb=0.25, delay=0.1),
        "music": Bus(-9, reverb=0.4, delay=0.15),
        "perc": Bus(-19, reverb=0.1),
        "wub": Bus(-10),
        "fx": Bus(-14, reverb=0.3),
    }, reverb_decay=1.6, reverb_tone=5500, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("BigBadVacuum", "Rumble on the Rug", 152, 9, 73, big_bad_vacuum)
