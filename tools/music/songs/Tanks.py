"""Toy Box Brigade: the round song for Tanks (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


@lru_cache(maxsize=None)
def toy_trumpet(m, sec):
    """A toy soldier's tin trumpet: a small, nasal, slightly buzzy brass voice (two players, a hair apart)."""
    x = np.asarray(ins.brass(m, sec, bright=0.8, section=2, vibrato=0.03))
    x = ins.eq(x, ("hp", 420), ("peak", 1700, 6, 1.4), ("peak", 3100, 3, 2.0), ("lp", 5200))
    return ins.normalize(ins.drive(x * 1.8, 1.6))


@lru_cache(maxsize=None)
def baritone(m, sec):
    """The baritone horn's counter-line: a warm, round low brass."""
    return ins.brass(m, sec, bright=0.35, section=2, vibrato=0.05)


@lru_cache(maxsize=None)
def wood_bass(m, sec):
    """A bass marimba, as wooden as the arena's blocks: a round thump with its octave and a hint of
    the bar's overtone, so a phone hears the line."""
    n = s.samples(min(sec, 0.6) + 0.45)
    t = np.arange(n) / s.SR
    f = s.midi_hz(m)
    tone = (np.sin(2 * np.pi * f * t) * np.exp(-t / 0.32) + 0.5 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.18)
            + 0.25 * np.sin(2 * np.pi * 4 * f * t) * np.exp(-t / 0.06))
    mallet = ins.eq(np.random.default_rng(int(m)).uniform(-1, 1, n), ("hp", 200), ("lp", 1500)) * np.exp(-t / 0.006) * 0.25
    return ins.normalize(ins._gate(tone + mallet, sec + 0.05, 0.08))


@lru_cache(maxsize=None)
def bass_drum():
    """The toy drummer's bass drum: a round boom at 70-120 Hz, where a phone can still play it."""
    n = s.samples(0.4)
    t = np.arange(n) / s.SR
    body = s.sine(70 + 50 * np.exp(-t / 0.03), n) * np.exp(-t / 0.15)
    felt = ins.eq(np.random.default_rng(12).uniform(-1, 1, n), ("hp", 150), ("lp", 1200)) * np.exp(-t / 0.01) * 0.3
    return ins.normalize(np.tanh((body + felt) * 1.4))


@lru_cache(maxsize=None)
def cannon(pitch=85.0):
    """A toy tank's cannon: a stubby boom with a puff of smoke."""
    n = s.samples(0.5)
    t = np.arange(n) / s.SR
    boom = s.sine(pitch * (1 + 0.9 * np.exp(-t / 0.02)), n) * np.exp(-t / 0.13)
    puff = ins.eq(np.random.default_rng(int(pitch)).uniform(-1, 1, n), ("hp", 300), ("lp", 2500)) * np.exp(-t / 0.07) * 0.5
    return ins.normalize(np.tanh((boom + puff) * 1.6))


@lru_cache(maxsize=None)
def ricochet(up=True):
    """A shell bouncing off a wooden block: a knock, then a bright 'ptchiu' bending away."""
    n = s.samples(0.3)
    t = np.arange(n) / s.SR
    ping = s.sine(1900 * 2 ** ((0.5 if up else -0.6) * np.clip(t / 0.2, 0, 1)), n) * np.exp(-t / 0.07)
    knock = ins.eq(np.random.default_rng(5 if up else 6).uniform(-1, 1, n), ("hp", 800), ("lp", 3500)) * np.exp(-t / 0.005) * 0.6
    return ins.normalize(ins.eq(ping * 0.8 + knock, ("lp", 5000)))


def tanks():
    """Toy Box Brigade (126 bpm, F major): a toy-soldier march for tanks battling among the building
    blocks. A military snare drives it (flams, drags and rolls) with a bass drum and toy cymbals; tin
    toy trumpets have the tune over toy-piano after-beats and a wooden bass marimba, a glockenspiel
    rings along like a bell lyre and a baritone horn plays the counter-line. In march form: tank
    treads rattle in under a distant drum, the first strain twice, a gentler trio in B flat for the
    baritone, a battle break in G minor (a "charge!" call, the drums answering, cannons, ricochets and
    a mine arming), then the trio grandioso for the last tanks standing and a stinger just before the
    bell (75 s after GO); a drum cadence marches back to the drop."""
    tr = Track(bpm=126, bars=48)
    parts = plan(tr, [
        ("intro", 8, "F | F | F | F | C7 | C7 | F C7 | C7"),
        ("A1", 8, "F | C7 | F | C7 | F | Bb | F/C C7 | F"),
        ("A2", 8, "F | C7 | F | C7 | F | Bb | F/C C7 | F"),
        ("trio", 8, "Bb | F7 | F7 | Bb | Bb7 | Eb | F7 | Bb"),
        ("battle", 4, "Gm | D7 | Gm | F7"),
        ("grandioso", 8, "Bb | F7 | F7 | Bb | Bb7 | Eb | F7 | Bb"),
        ("final", 4, "Gm7 | C7 | F | F"),
    ])
    strain = melody("""C5:2 C5:1 C5:1 F5:4 A5:3 G5:1 F5:4 | G5:2 G5:1 G5:1 Bb5:4 E5:3 F5:1 G5:4 |
                       A5:2 A5:1 A5:1 C6:4 Bb5:2 A5:2 G5:2 F5:2 | D6:3 C6:1 Bb5:2 A5:2 G5:4 r:4 |
                       C5:2 C5:1 C5:1 F5:4 A5:3 G5:1 F5:4 | D5:2 D5:1 D5:1 F5:4 Bb5:3 A5:1 Bb5:4 |
                       C6:4 A5:4 G5:4 E5:4 | F5:4 C5:2 C5:2 F5:4 r:4""")
    counter = melody("""A3:8 C4:8 | Bb3:8 G3:8 | F3:4 A3:4 C4:4 F4:4 | E4:8 C4:8 |
                        A3:8 C4:8 | D4:8 F4:8 | C4:8 Bb3:8 | A3:8 r:8""")
    trio = melody("""D5:4 F5:4 Bb5:8 | A5:4 G5:4 F5:8 | Eb5:4 F5:4 G5:4 A5:4 | Bb5:12 r:4 |
                     D6:4 C6:4 Bb5:4 Ab5:4 | G5:8 Eb5:8 | F5:4 G5:4 A5:4 C6:4 | Bb5:12 r:4""")
    trio_counter = melody("""F3:16 | Eb3:8 C3:8 | A3:8 F3:8 | Bb3:8 D4:8 | Ab3:16 | G3:8 Bb3:8 | A3:8 Eb4:8 | D4:12 r:4""")
    call = melody("C5:2 C5:1 C5:1 G5:4 E5:2 G5:2 C6:4 | C6:3 G5:1 E5:3 C5:1 G5:8")
    fanfare = melody("F5:2 F5:1 F5:1 A5:2 F5:2 C6:4 Bb5:2 G5:2 | E5:2 G5:2 Bb5:2 C6:2 E6:4 r:4")
    charge = melody("D5:2 D5:1 D5:1 G5:2 D5:2 Bb5:4 G5:4 | r:16 | D5:2 D5:1 D5:1 G5:2 Bb5:2 D6:4 C6:2 Bb5:2 | A5:2 A5:1 A5:1 F5:2 A5:2 C6:2 A5:2 F5:2 Eb5:2")
    answer = melody("r:16 | r:8 A3:2 D4:2 F#4:2 A4:2 | r:16 | A3:2 A3:1 A3:1 F3:2 A3:2 C4:2 A3:2 F3:2 Eb3:2")
    ending = melody("Bb5:4 A5:4 G5:4 F5:4 | E5:4 G5:4 Bb5:4 C6:4 | C6:2 C6:1 C6:1 F6:4 r:8 | r:16")

    kick = bass_drum()
    snares = [ins.snare2(240.0, 1.0, 0.2, v) for v in range(4)]
    tenor = [ins.snare2(165.0, 0.35, 0.3, v + 4) for v in range(2)]
    rim = ins.rim_click(1700.0)
    splash, crash = ins.splash(0.6), s.crash(1.8)
    treads = [ins.ratchet(0.2, 6), ins.ratchet(0.24, 7)]

    def hits(stem, bar, pattern, sounds, gain=1.0, pan=0.0):
        for k, (step, vel) in enumerate((i, {"X": 1.0, "x": 0.8, "o": 0.45}[ch]) for i, ch in enumerate(pattern) if ch != "."):
            tr.add(stem, bar, step, sounds[k % len(sounds)], gain * vel, pan)

    def snare(bar, pattern, gain=1.0, flams=()):
        """The military snare: accents, and a flam (a grace note just before) on the steps in `flams`."""
        hits("snare", bar, pattern, snares, gain)
        for step in flams:
            tr.add("snare", bar, step - 0.3, snares[3], gain * 0.45)

    def roll(bar, start, end, gain_from, gain_to):
        """A buzz roll in 32nds, swelling."""
        k = start
        while k < end - 1e-6:
            frac = (k - start) / max(end - start, 1e-6)
            tr.add("snare", bar, k, snares[int(k * 2) % 4], gain_from + (gain_to - gain_from) * frac)
            k += 0.5

    # toy tanks rattling in across the playroom floor, a drummer far off
    for bar in range(0, 6):
        for beat in range(4):
            tr.add("fx", bar, beat * 4 + (1 if beat % 2 else 0), treads[beat % 2], (0.25 + 0.1 * bar if bar < 4 else 0.5 - 0.2 * (bar - 4)), -0.6 + 0.2 * bar)
    for bar in range(0, 4):
        snare(bar, "x.x.x.xxx.x.x.xx" if bar < 2 else "x.xxX.x.x.xxX.x.", 0.3 + 0.12 * bar)
        if bar >= 2:
            tr.kick("kick", bar, "X.......X.......", kick, 0.4 + 0.15 * (bar - 2))
            hits("cymbal", bar, "....x.......x...", [splash], 0.4, 0.3)
    tr.play("lead", 4, call, toy_trumpet, 0.4)
    tr.play("lead", 6, fanfare, toy_trumpet, 0.55)
    tr.play("glock", 6, shift(fanfare, 12), ins.glock, 0.35, pan=-0.2)
    tr.play("euph", 6, shift(fanfare, -12), baritone, 0.4, pan=0.2)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 41)  # F2..E3
            fifth = root + 7 if root + 7 <= 52 else root - 5
            notes = voicing(c, 62, 74, prev)
            prev = notes
            beats = range(int(step), int(step + length), 4)
            if name == "intro" and local < 4:
                continue
            if name == "final" and local >= 2:
                if local == 2:  # the stinger: everyone on the motif, then a held chord
                    for k in (0, 2, 3, 4):
                        strum(tr, "piano", bar, k, notes, ins.toy_piano, tr.step * 1.5, 1.0 if k in (0, 4) else 0.7, spread=0.004)
                        tr.add("bass", bar, k, wood_bass(root, tr.step * (1.5 if k < 4 else 6)), 1.0)
                    tr.add("euph", bar, 4, baritone(root + 12, tr.step * 8), 0.9)
                continue
            level = {"trio": 0.75, "intro": 0.4 if local < 6 else 0.55}.get(name, 1.0)
            # the wooden bass on every beat (root, fifth), the toy piano's after-beats
            for k in beats:
                bass = root if (k - step) % 8 == 0 else fifth
                tr.add("bass", bar, k, wood_bass(bass, tr.step * 3), level * (1.0 if k % 8 == 0 else 0.85))
                strum(tr, "piano", bar, k + 2, notes, ins.toy_piano, tr.step * 1.2, 0.85 * level, spread=0.004, pan=0.2)
            if name == "grandioso":  # the baritones lean on the bass line for the big finish
                tr.add("euph2", bar, step, baritone(root, length * tr.step * 0.45), 0.8)
            if name in ("A1", "A2", "grandioso") and local in (3, 7):  # a toy xylophone run into the next phrase
                run = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24]
                for k, m in enumerate(run):
                    tr.add("xylo", bar, 12 + k, ins.xylophone(m, 0.15), 0.6 + 0.1 * k, -0.3)

        for bar in part.bars_range():
            local = bar - part.first
            last = local == part.bars - 1
            if name == "intro":
                if 4 <= local < 6:
                    snare(bar, "x.xxX.x.x.xxX.x.", 0.65, flams=(4, 12))
                    tr.kick("kick", bar, "X.......X.......", kick, 0.75)
                    hits("cymbal", bar, "....x.......x...", [splash], 0.5, 0.3)
                if local == 6:
                    snare(bar, "X.xxX.x.X.xxX.x.", 0.85, flams=(0, 8))
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.9)
                if local == 7:
                    snare(bar, "X.xxX.xxX.......", 0.9, flams=(0,))
                    roll(bar, 8, 16, 0.3, 0.95)
                    tr.kick("kick", bar, "X...X...X.......", kick)
                continue
            if local == 0 and name != "trio":
                tr.add("cymbal", bar, 0, crash, 1.0, -0.3)
                tr.add("fx", bar, 0, cannon(), 0.8, 0.4)
            if name == "trio":
                hits("snare", bar, "....x.......x...", [rim], 0.9)
                snare(bar, "o.o.....o.o.....", 0.5)
                tr.kick("kick", bar, "X.......X.......", kick, 0.7)
                if last:
                    roll(bar, 8, 16, 0.25, 0.8)
                continue
            if name == "battle":
                if local % 2 == 0:  # the charge: the snare drives under the call
                    snare(bar, "X.xxX.x.X.xxX.x.", 0.9, flams=(0, 8))
                    tr.kick("kick", bar, "X.......X.......", kick)
                    tr.add("fx", bar, 6, ricochet(local == 0), 0.6, 0.5 if local == 0 else -0.5)
                else:  # the drums answer, the cannons go off, a mine arms
                    snare(bar, "X.X.xxX.X.X.xxxx", 1.0, flams=(0, 2, 8, 10))
                    hits("tenor", bar, "X..X..X.X..X..X.", tenor, 0.9, -0.2)
                    tr.kick("kick", bar, "X..X..X.X.......", kick)
                    tr.add("fx", bar, 0, cannon(75.0), 1.0, -0.4)
                    tr.add("fx", bar, 6, cannon(95.0), 0.8, 0.4)
                    tr.add("fx", bar, 11, ricochet(False), 0.6, 0.3)
                    if local == 1:
                        for k in (8, 11, 13, 14, 15):
                            tr.add("fx", bar, k, ins.blip(93, 0.05), 0.5, 0.6)
                tr.add("cymbal", bar, 0, crash if local % 2 else splash, 0.7, 0.3)
                continue
            if name == "final":
                if local < 2:
                    snare(bar, "X.xxX.xxX.xxX.xx", 1.0, flams=(0, 4, 8, 12))
                    tr.kick("kick", bar, "X...X...X...X...", kick)
                    hits("cymbal", bar, "....x.......x...", [splash], 0.8, 0.3)
                    if local == 1:
                        roll(bar, 12, 16, 0.5, 1.0)
                elif local == 2:
                    snare(bar, "X.xxX...........", 1.0, flams=(0, 4))
                    tr.kick("kick", bar, "X...X...........", kick)
                    tr.add("cymbal", bar, 4, crash, 1.0, 0.3)
                    tr.add("fx", bar, 4, cannon(), 1.0, -0.3)
                else:  # the drum cadence that marches back to the top
                    snare(bar, "X.x.X.x.X.xxX.xx", 0.8, flams=(0, 8))
                    roll(bar, 14, 16, 0.6, 0.9)
                    tr.kick("kick", bar, "X.......X.......", kick, 0.8)
                continue
            # the march: the snare's accents off the beat (flams on 2 and 4), the bass drum on 1 and 3,
            # toy cymbals on 2 and 4 (every beat in the grandioso)
            big = name == "grandioso"
            snare(bar, "x.xxX.x.x.xxX.x." if not big else "X.xxX.xxX.xxX.xx", 0.85 if name == "A1" else 1.0, flams=(4, 12))
            tr.kick("kick", bar, "X.......X......." if not big else "X...X...X...X...", kick)
            hits("cymbal", bar, "....x.......x..." if not big else "x...x...x...x...", [splash], 0.7 if name == "A1" else 0.9, 0.3)
            if last or local == 3:
                roll(bar, 12, 16, 0.4, 0.9)
            if big and local % 2 == 0 and local:
                tr.add("cymbal", bar, 0, crash, 0.8, -0.3)
                tr.add("fx", bar, 0, cannon(100.0), 0.6, -0.4)
                tr.add("fx", bar, 10, ricochet(local % 4 == 0), 0.45, 0.5)

    tr.play("lead", 8, strain, toy_trumpet)
    tr.play("lead", 16, strain, toy_trumpet)
    tr.play("glock", 16, shift(strain, 12), ins.glock, 0.7, pan=-0.2)
    tr.play("euph", 16, counter, baritone, pan=0.2)
    tr.play("trio", 24, shift(trio, -12), baritone)
    tr.play("keys", 24, trio, ins.toy_piano)
    tr.play("glock", 24, shift(trio, 12), ins.glock, 0.6, pan=-0.2)
    tr.play("lead", 32, charge, toy_trumpet)
    tr.play("euph", 32, answer, baritone, pan=0.2)
    tr.play("lead", 36, trio, toy_trumpet)
    tr.play("glock", 36, shift(trio, 12), ins.glock, 0.8, pan=-0.2)
    tr.play("keys", 36, trio, ins.toy_piano, 0.5)
    tr.play("euph", 36, shift(trio_counter, 12), baritone, pan=0.2)
    tr.play("lead", 44, ending, toy_trumpet)
    tr.play("glock", 44, shift(ending, 12), ins.glock, 0.7, pan=-0.2)
    tr.play("euph", 44, shift(ending, -12), baritone, 0.8, pan=0.2)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.15),
        "trio": Bus(-6, reverb=0.2),
        "keys": Bus(-11, reverb=0.15),
        "glock": Bus(-13, reverb=0.2),
        "euph": Bus(-12, reverb=0.15),
        "euph2": Bus(-15, reverb=0.1),
        "piano": Bus(-13, reverb=0.1),
        "xylo": Bus(-15, reverb=0.15),
        "bass": Bus(-9),
        "snare": Bus(-11, reverb=0.1, eq=(("lp", 8000),)),
        "tenor": Bus(-14, reverb=0.1),
        "kick": Bus(-12),
        "cymbal": Bus(-19, eq=(("lp", 9000),)),
        "fx": Bus(-15, reverb=0.2, eq=(("lp", 7000),)),
    }, reverb_decay=1.4, reverb_tone=5500, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("Tanks", "Toy Box Brigade", 126, 8, 48, tanks)
