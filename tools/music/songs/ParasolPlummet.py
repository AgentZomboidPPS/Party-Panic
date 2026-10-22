"""Breezy Does It: the round song for ParasolPlummet (see songkit.py for the rules every song keeps)."""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def breezy_does_it():
    """Breezy Does It (120 bpm with a light swing, B-flat major): drifting down a sunny sky under an
    umbrella. A ukulele's island strum and a whistled tune over an upright bass, a shaker, finger snaps
    and a woodblock clave, an airy "oo" choir and glockenspiel coins; a drift that floats down a chord
    at a time, a slide-whistle DIVE, then up to C major for the COIN RUSH (the last 7 seconds, from
    28 s) with coins raining, whose F7 leads back into the drop."""
    tr = Track(bpm=120, bars=25, swing=0.25)
    parts = plan(tr, [
        ("intro", 7, "Bb | Bb | Eb | F | Bb | Gm | F"),
        ("A", 8, "Bb | Gm | Eb | F | Bb | Gm | Cm F | Bb"),
        ("drift", 4, "Ebmaj7 | Dm7 | Cm7 | F7"),
        ("dive", 2, "Dm7 | G7"),
        ("rush", 4, "C | Am | F | G F7"),
    ])
    tune = melody("""F5:4 D5:2 F5:2 Bb5:6 A5:2 | G5:4 F5:2 D5:2 Bb4:8 | Eb5:2 G5:2 Bb5:4 C6:2 Bb5:2 G5:4 | A5:6 G5:2 F5:8 |
                     F5:4 D5:2 F5:2 Bb5:6 C6:2 | D6:4 C6:2 Bb5:2 G5:8 | Eb5:4 G5:4 F5:2 G5:2 A5:2 C6:2 | Bb5:12 r:4""")
    drift = melody("""G4:2 Bb4:2 D5:4 C5:2 Bb4:2 G4:4 | F4:2 A4:2 C5:4 Bb4:2 A4:2 F4:4 |
                      Eb4:2 G4:2 Bb4:4 A4:2 G4:2 Eb4:4 | F4:2 A4:2 C5:2 Eb5:2 F5:4 r:4""")
    pickup = melody("r:16 | D5:2 F5:2 G5:2 B5:2 D6:4 r:4")
    rush = melody("G5:4 E5:2 G5:2 C6:6 B5:2 | A5:4 G5:2 E5:2 C5:8 | F5:2 A5:2 C6:4 D6:2 C6:2 A5:4 | B5:6 A5:2 G5:8")

    def whistle(m, sec):
        return ins.whistle(m, sec)

    def uke(m, sec):
        return ins.nylon(m, sec)

    shaker, snap, clap = s.shaker(), ins.finger_snap(), s.clap()
    kick = s.kick(0.6, 0.3)
    clave = ins.woodblock(1250.0)

    def chord_at(bar, step):
        for st, _, c in reversed(parts_at[bar]):
            if step >= st:
                return c
        return parts_at[bar][0][2]

    parts_at = {}
    for part in parts:
        for bar in part.bars_range():
            parts_at[bar] = part.at(bar)

    # The intro: wind, wind chimes and an airy choir; the ukulele and a soft whistle, then the band.
    tr.add("fx", 0, 0, ins.whoosh(tr.bar * 2.5, True), 0.3, -0.3)
    rng = np.random.default_rng(3)
    for bar in range(4):
        for k in sorted(rng.choice(16, size=5 if bar < 2 else 3, replace=False)):
            tr.add("chimes", bar, k, ins.celesta(int(rng.choice([82, 84, 86, 89, 91, 94])), 0.8), 0.45 + 0.1 * min(bar, 2), float(rng.uniform(-0.6, 0.6)))
    tr.play("lead", 4, [n for n in tune if n.step < 32], whistle, 0.55, transpose=12)
    tr.add("fx", 6, 8, ins.slide_whistle(91, 70, tr.bar * 0.45), 0.5, 0.2)  # the umbrella opens: wheee

    def bass_root(c):
        root = bass_note(c, 34)  # A#1 .. A2, played an octave up where it's low
        return root + 12 if root < 38 else root

    flat = [change for part in parts for change in part.changes]
    following = {(b, st): flat[(i + 1) % len(flat)][3] for i, (b, st, ln, c) in enumerate(flat)}

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            approach = bass_root(following[(bar, step)]) - 1  # a half step under the next chord's root
            step = int(round(step))
            span = int(length)
            root = bass_root(c)
            notes = voicing(c, 60, 72, prev)
            prev = notes
            seconds = length * tr.step
            fifth = root + 7 if root + 7 <= 50 else root - 5
            # the sky: an airy choir
            if name in ("intro", "drift", "rush") or (name == "A" and local >= 4):
                gain = (0.45 + 0.07 * local) if name == "intro" else (0.7 if name == "A" else 1.0)
                tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "oo" if name != "rush" else "ah", attack=0.4), gain)
            # the upright bass
            if name == "intro" and local < 4:
                continue
            if name == "rush":
                for k in range(0, span, 2):
                    tr.add("bass", bar, step + k, ins.upright(root + (12 if (k // 2) % 2 else 0), tr.step * 1.8, variant=k % 3), 1.0 if k % 4 == 0 else 0.8)
            else:
                walk = ((0, root, 1.0), (6, root, 0.6), (8, fifth, 0.85), (14, approach, 0.6)) if span == 16 else ((0, root, 1.0), (6, approach, 0.6))
                for k, m, g in walk:
                    if k < span and not (name == "intro" and local < 5 and k > 0):
                        tr.add("bass", bar, step + k, ins.upright(m, tr.step * (3.5 if k in (0, 8) else 1.5), variant=k % 3), g)

        for bar in part.bars_range():
            local = bar - part.first
            # the ukulele's island strum: down, down-up, up-down-up
            if name == "intro" and local < 2:
                pass
            else:
                pattern = ((0, True, 1.0), (4, True, 0.8), (6, False, 0.6), (10, False, 0.6), (12, True, 0.85), (14, False, 0.6))
                if name == "intro" and local < 4:
                    pattern = ((0, True, 0.8), (8, True, 0.7))
                if name == "rush" or (name == "intro" and local == 6):
                    pattern = tuple((k, k % 4 == 0, 1.0 if k % 4 == 0 else 0.6) for k in range(0, 16, 2))
                gain = 0.5 + 0.1 * local if name == "intro" else 1.0
                for k, down, g in pattern:
                    cc = chord_at(bar, k)
                    strum(tr, "uke", bar, k, voicing(cc, 60, 72), uke, tr.step * 2.2, g * gain, spread=0.014, down=down, pan=-0.25)
            if name == "intro":
                if local >= 4:
                    tr.drum("perc", bar, "xoxoxoxoxoxoxoxo", shaker, 0.5 + 0.15 * (local - 4), 0.35)
                    tr.drum("snaps", bar, "....X.......X...", snap, 0.6 + 0.1 * (local - 4), 0.2)
                if local >= 5:
                    tr.kick("kick", bar, "X.......X.......", kick, 0.6)
                if local == 6:
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.25)
                    for k in range(8, 16):
                        tr.add("claps", bar, k, clap, 0.3 + 0.06 * (k - 8))
                continue
            tr.drum("perc", bar, "xoxoxoxoxoxoxoxo" if name != "rush" else "xxxxxxxxxxxxxxxx", shaker, 0.9, 0.35)
            tr.drum("snaps", bar, "....X.......X...", snap, 0.9, 0.2)
            if name in ("A", "rush"):
                tr.drum("clave", bar, "X..X..X...X.X...", clave, 0.8, -0.35)
            if name == "rush":
                tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
                tr.drum("claps", bar, "....X.......X..x", clap, 1.0, -0.05)
            elif name == "dive":
                tr.kick("kick", bar, "X.......X.......", kick, 0.9)
                if local == 1:
                    for k in range(16):
                        tr.add("claps", bar, k, clap, 0.25 + 0.045 * k)
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.3)
            else:
                tr.kick("kick", bar, "X.......X......." if name == "A" else "X.........X.....", kick, 1.0)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(1.6), 0.9, 0.2)
            # coins: a ding-ding-ding as the whistle breathes in the drift, rain in the rush
            if name == "drift":
                cc = chord_at(bar, 12)
                for k, m in enumerate(voicing(cc, 79, 93, size=3)):
                    tr.add("coins", bar, 12 + k, ins.glock(m, 0.4), 0.8, 0.3)
            if name == "rush":
                for half in (0, 8):
                    cc = chord_at(bar, half)
                    rain = sorted(voicing(cc, 77, 96, size=5), reverse=True)
                    for k, m in enumerate(rain):
                        tr.add("coins", bar, half + k * 0.5 + 1, ins.glock(m, 0.35), 0.75 - 0.08 * k, 0.4 - 0.15 * k)

    tr.play("lead", 7, tune, whistle, transpose=12)
    tr.play("lead2", 7, [n for n in tune if n.step >= 4 * 16], lambda m, sec: ins.marimba(m, sec), 0.7)
    tr.play("lead", 15, drift, whistle, transpose=12)
    tr.add("fx", 19, 0, ins.slide_whistle(96, 67, tr.bar * 0.9), 0.7, -0.2)  # the DIVE
    tr.play("lead", 19, pickup, whistle, transpose=12)
    tr.play("lead", 21, rush, whistle, transpose=12)
    tr.play("lead2", 21, rush, lambda m, sec: ins.marimba(m, sec), 0.8)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.25, delay=0.12),
        "lead2": Bus(-14, reverb=0.2),
        "uke": Bus(-9, reverb=0.15),
        "bass": Bus(-10),
        "choir": Bus(-15, reverb=0.4),
        "coins": Bus(-14, reverb=0.3, delay=0.15),
        "chimes": Bus(-15, reverb=0.4),
        "perc": Bus(-18, eq=(("lp", 8500),)),
        "snaps": Bus(-15, reverb=0.15),
        "clave": Bus(-19, reverb=0.15),
        "kick": Bus(-13, drive=1.2, eq=(("hp", 50), ("peak", 110, 3, 1.2))),
        "claps": Bus(-15, reverb=0.15),
        "cymbal": Bus(-22, eq=(("lp", 9000),)),
        "fx": Bus(-14, reverb=0.3),
    }, reverb_decay=1.7, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("ParasolPlummet", "Breezy Does It", 120, 7, 25, breezy_does_it)
