"""Shark Surf Panic: the round song for SharkBait (see songkit.py for the rules every song keeps)."""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)

from score import Note  # noqa: E402 (a note of a melody line, for the twin guitar below)


def pick_slide(length: float = 0.9) -> np.ndarray:
    """The surf guitarist's pick scraped down the low strings: a ratcheting roar that falls away."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    noise = np.random.default_rng(17).uniform(-1, 1, n)
    windings = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * np.cumsum(140 - 90 * t / length) / s.SR))
    tone = ins.tv_lowpass(noise * windings, 3400 * (0.07 ** (t / length)) + 180, q=4.0)
    e = np.clip(t / 0.015, 0, 1) * (1 - t / length) ** 1.4
    return ins.normalize(ins.eq(tone * e, ("hp", 140), ("lp", 5000)))


def sonar(length: float = 1.4) -> np.ndarray:
    """A sonar ping from the deep: something big is down there."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    f = 1180 * (1 - 0.03 * t / length)
    tone = s.sine(f, n) * np.exp(-t / 0.35) * np.clip(t / 0.004, 0, 1)
    return ins.normalize(tone + 0.25 * s.sine(f * 2.01, n) * np.exp(-t / 0.12))


def under(notes, bar0, parts):
    """A twin guitar under the lead: the nearest chord tone at least a minor third below each note."""
    changes = [(b * 16 + st, ln, c) for p in parts for b, st, ln, c in p.changes]
    out = []
    for n in notes:
        pos = bar0 * 16 + n.step
        c = next(c for start, ln, c in changes if start <= pos < start + ln)
        m = n.midi - 3
        while m % 12 not in c.tones():
            m -= 1
        out.append(Note(n.step, m, n.length, n.vel * 0.85))
    return out


def shark_surf_panic():
    """Shark Surf Panic (160 bpm, E minor): surf rock in the tropical cove. A twangy lead guitar drenched
    in spring reverb, tremolo-picking its long notes; a combo organ that takes the sunny middle tune;
    a pounding tom beat; and a low, lurking shark riff on the bass strings. COIN RUSH (45 s after GO)
    lands on bar 30 after GO: up to F sharp minor, double-time drums and glittering coins."""
    tr = Track(bpm=160, bars=51)
    parts = plan(tr, [
        ("intro", 9, "Em | Em | Em | Em | Em | C | B7 | Em | B7"),
        ("A1", 8, "Em | D | C | B7 | Em | D | C | B7"),
        ("shark", 4, "Em | Em | Em | Em"),
        ("A2", 8, "Em | D | C | B7 | Em | D | C | B7"),
        ("B", 8, "C | D | G | Em | C | D | Bm | B7"),
        ("build", 2, "D | C#7"),
        ("rush", 8, "F#m | E | D | C#7 | F#m | E | D | C#7"),
        ("final", 4, "F#m | D | C | B7"),
    ])
    surf = melody("""E4:2 E4:2 G4:2 B4:10 | A4:2 A4:2 F#4:2 D5:10 | G4:2 G4:2 E4:2 C5:6 B4:2 A4:2 | B4:4 A4:2 F#4:2 D#4:8 |
                     E4:2 E4:2 G4:2 B4:6 C5:2 B4:2 | A4:2 A4:2 D5:2 F#5:10 | E5:2 D5:2 C5:2 G4:4 A4:2 B4:2 C5:2 | B4:12 r:4""")
    sunny = melody("""E5:3 G5:3 C6:2 B5:4 G5:4 | F#5:3 A5:3 D6:2 C6:4 A5:4 | B5:6 A5:2 G5:4 D5:4 | E5:12 r:4 |
                      E5:3 G5:3 C6:2 B5:4 G5:4 | F#5:3 A5:3 D6:2 E6:4 D6:4 | D6:6 B5:2 F#5:4 D5:4 | D#5:4 F#5:4 A5:4 B5:4""")
    riff = melody("""E2:3 E2:1 G2:2 E2:2 A2:2 Bb2:2 A2:2 G2:2 | E2:3 E2:1 G2:2 E2:2 D3:2 C#3:2 C3:2 B2:2 |
                     E2:3 E2:1 G2:2 E2:2 A2:2 Bb2:2 A2:2 G2:2 | E2:3 E2:1 G2:2 E2:2 Bb2:4 B2:4""")
    climb = melody("D5:4 D#5:4 E5:4 F5:4 | F#5:4 G5:4 G#5:8")
    falls = melody("F#4:4 A4:4 C#5:8 | D5:6 C#5:2 A4:8 | C5:6 B4:2 G4:8 | F#4:4 A4:4 B4:4 D#5:4")
    answers = melody("r:16 | r:16 | r:16 | r:8 B4:2 D5:2 E5:4 | r:16 | r:16 | r:16 | r:8 F#4:2 A4:2 B4:4")

    def guitar(m, sec, k=0):
        return ins.electric_guitar(m, sec, variant=k % 3)

    def surf_line(stem, bar, notes, gain=1.0, pan=0.0, trem_from=6):
        """Staccato picking, and tremolo picking (down-up 16ths, each pick damping the last) on long notes."""
        for n in notes:
            if n.length >= trem_from:
                k = 0
                while k < n.length - 1e-6:
                    tr.add(stem, bar, n.step + k, guitar(n.midi, tr.step * 1.25, k), gain * n.vel * (0.95 if k % 2 == 0 else 0.72), pan)
                    k += 1
            else:
                tr.add(stem, bar, n.step, guitar(n.midi, n.length * tr.step * 0.8), gain * n.vel, pan)

    def organ(m, sec):
        return ins.combo_organ(m, sec)

    kick, snare = s.kick(0.9, 0.35), ins.snare2(200.0, 1.0)
    ride, chat, ohat = ins.ride(0.9, 0.35), s.hat(False), s.hat(True)
    tamb = ins.jingles(0.14)
    toms = [ins.tom(p, 0.45) for p in (95.0, 130.0, 175.0)]
    rim = ins.rim_click(1700.0)

    # the cove before the round: surf, a sonar ping, and something on the low strings
    tr.add("fx", 0, 0, ins.waves(tr.bar * 7), 1.0)
    tr.add("ping", 0, 8, sonar(), 1.0)
    tr.add("ping", 2, 8, sonar(), 0.8)
    tr.add("fx", 8, 4, pick_slide(tr.beat * 3), 1.0, -0.1)
    rng = np.random.default_rng(41)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 28) + 12  # E2 .. D#3: the bass strings, an octave up from the deep
            notes = voicing(c, 52, 67, prev, size=4)
            prev = notes
            seconds = length * tr.step
            # bass: driving 8ths (root, fifth, octave); in the shark section it doubles the riff instead
            if name in ("A1", "A2", "B", "rush", "final") or (name == "intro" and local >= 7):
                line = ((0, 0), (2, 0), (4, 7), (6, 0), (8, 0), (10, 0), (12, 7), (14, 12))
                if name == "B":
                    line = ((0, 0), (3, 0), (6, 7), (8, 0), (10, 12), (12, 7), (14, 0))
                for st, off in line:
                    if step <= st < step + length:
                        tr.add("bass", bar, st, ins.bass_guitar(root + off, tr.step * 1.7, bright=0.6), (1.0 if st % 4 == 0 else 0.8) * (0.7 if name == "intro" else 1.0))
            elif name == "build":
                for st in range(0, 16, 2):
                    tr.add("bass", bar, st, ins.bass_guitar(root, tr.step * 1.6, bright=0.6), 0.75 + 0.02 * st)
            # rhythm guitar: the surf "chank" on 2 and 4 (spring-soaked); 8th strums in the rush
            if name in ("A1", "A2", "final"):
                for st in (4, 12):
                    if step <= st < step + length:
                        strum(tr, "rhythm", bar, st, notes, ins.electric_guitar, tr.step * 2.5, 1.0, spread=0.008, pan=-0.35)
            elif name == "rush":
                for st in range(0, 16, 2):
                    if step <= st < step + length:
                        strum(tr, "rhythm", bar, st, notes, ins.electric_guitar, tr.step * 1.4, 0.9 if st % 4 else 0.75, spread=0.006, down=st % 4 == 0, pan=-0.35)
            elif name == "B":
                for st in (2, 6, 10, 14):
                    if step <= st < step + length:
                        strum(tr, "rhythm", bar, st, notes, ins.electric_guitar, tr.step * 1.2, 0.8, spread=0.006, pan=-0.35)
            # combo organ: held chords in B (the organ leads it) and the rush, swells in the intro
            if name in ("A2", "rush") or (name == "intro" and local in (5, 6)):
                for v, m in enumerate(notes[1:]):
                    tr.add("organ", bar, step, organ(m + 12, seconds * 0.98), 0.8 if name != "intro" else 0.45, 0.3 - 0.2 * v)
            if name == "shark":
                tr.add("organ", bar, 0, organ(52, tr.bar * 0.98), 0.35, 0.3)
                tr.add("organ", bar, 0, organ(59, tr.bar * 0.98), 0.3, 0.1)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 1:  # the low E rumbling, swelling up
                    for k in range(16):
                        tr.add("lowgtr", bar, k, guitar(40, tr.step * 1.25, k), (0.18 + 0.08 * (local - 1)) * (1.0 if k % 2 == 0 else 0.75))
                if 3 <= local <= 6:
                    tr.play("bass", bar, [n for n in riff if n.step < 16] if local % 2 == 1 else shift([n for n in riff if 16 <= n.step < 32], steps=-16), lambda m, sec: ins.bass_guitar(m, sec, bright=0.6), 0.55 + 0.1 * (local - 3))
                if local >= 5:
                    tr.drum("toms", bar, "X.....X.....X...", toms[0], 0.45 + 0.1 * (local - 5))
                if local >= 6:
                    tr.drum("toms", bar, "....x.x.....x.x." if local < 8 else "....x.x...x.x.xx", toms[1], 0.5)
                if local >= 7:
                    tr.kick("kick", bar, "X.......X.......", kick, 0.75)
                    tr.drum("cymbal", bar, "x.x.x.x.x.x.x.x.", ride, 0.5, 0.3)
                if local == 8:
                    for k in range(8, 16):
                        tr.add("snare", bar, k, snare, 0.4 + 0.07 * (k - 8), 0.05)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.45)
                continue
            if name == "shark":
                tr.kick("kick", bar, "X.......X.......", kick, 0.8)
                tr.drum("toms", bar, "X.....X.....X...", toms[0], 0.9)
                tr.drum("toms", bar, "...x.......x..x." if local % 2 == 0 else "...x..x....x.xx.", toms[1], 0.6)
                tr.drum("perc", bar, "..x...x...x...x.", rim, 0.7, 0.3)
                if local == 1:
                    tr.add("fx", bar, 0, ins.whoosh(tr.bar * 1.5, up=False), 0.8, 0.5)
                if local == 3:
                    for k, st in enumerate(range(8, 16)):
                        tr.add("toms", bar, st, toms[2 - k // 3], 0.6 + 0.04 * k)
                continue
            if name == "build":
                tr.kick("kick", bar, "X...X...X...X...", kick, 0.9)
                for k in range(16):
                    tr.add("snare", bar, k, snare, 0.3 + 0.03 * (k + 16 * local), 0.05)
                if local == 0:
                    tr.add("fx", bar, 0, s.riser(tr.bar * 2), 0.5)
                    tr.add("fx", bar + 1, 4, pick_slide(tr.beat * 3), 1.0, 0.1)
                continue
            fast = name == "rush"
            tr.kick("kick", bar, "X.....x.X.......", kick, 1.0)
            tr.drum("snare", bar, "....X.......X..." if not fast else "....X..o.o..X..o", snare, 0.95, 0.05)
            tr.drum("perc", bar, "....x.......x..." if name != "B" else "x.x.x.x.x.x.x.x.", tamb, 0.8, 0.35)
            if name in ("A1", "final"):
                tr.drum("cymbal", bar, "x.x.x.x.x.x.x.x.", ride, 0.7, 0.3)
            elif name == "B":
                tr.drum("cymbal", bar, "x.x.x.x.x.x.x.x.", ride, 0.6, 0.3)
                tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.4, -0.3)
            else:  # A2 and the rush: the pounding surf tom beat
                tr.drum("toms", bar, "X.x.X.xxX.x.X.xx", toms[0], 0.55)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x." if not fast else "xxxxxxxxxxxxxxxx", chat, 0.6, -0.3)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.6, 0.25)
            if fast and local == 4:
                tr.add("cymbal", bar, 0, s.crash(), 1.3, -0.25)
            if local == part.bars - 1 and name in ("A1", "A2", "rush"):
                for k, st in enumerate((12, 13, 14, 15)):
                    tr.add("toms", bar, st, toms[2 - k // 2], 0.75)
            # COIN RUSH: coins glitter up out of the water
            if fast:
                chord_tones = [m + 24 for m in voicing(part.at(bar)[0][2], 57, 69, size=3)]
                for k, m in enumerate(chord_tones + [chord_tones[0] + 12]):
                    tr.add("coins", bar, 12 + k, ins.glock(m, 0.25), 0.6 + 0.12 * k, 0.4 - 0.25 * k)
                if local % 2 == 1:
                    for k in range(3):
                        tr.add("coins", bar, 4 + k * 0.5, ins.glock(chord_tones[1 + k % 2] + 12, 0.15), 0.4 + 0.2 * rng.random(), -0.4)

    # the tunes
    tr.play("bass", 17, riff, lambda m, sec: ins.bass_guitar(m, sec, bright=0.7), 1.0)
    surf_line("lowgtr", 17, shift(riff, 12), 0.9, pan=0.2, trem_from=99)
    surf_line("lead", 9, surf)
    surf_line("lead", 21, surf)
    surf_line("twin", 21, under(surf, 21, parts), 0.8, pan=-0.25)
    tr.play("organlead", 29, sunny, organ, 1.0)
    surf_line("lead", 29, answers, 0.85, pan=0.15)
    surf_line("lead", 37, climb, trem_from=4)
    surf_line("lead", 39, shift(surf, 2))
    surf_line("twin", 39, under(shift(surf, 2), 39, parts), 0.8, pan=-0.25)
    tr.play("organlead", 39, shift(surf, 14), organ, 0.55)
    surf_line("lead", 47, falls, trem_from=8)

    mix = Mix(buses={
        "lead": Bus(-5, spring=0.32, delay=0.05, eq=(("high", 3000, -4), ("peak", 3600, -2.5, 0.9), ("lp", 7000))),
        "twin": Bus(-12, spring=0.35, eq=(("high", 3000, -4), ("lp", 6500))),
        "lowgtr": Bus(-11, spring=0.4, eq=(("lp", 4000),)),
        "rhythm": Bus(-13, spring=0.5, pump=0.1, eq=(("high", 2500, -4), ("lp", 5000))),
        "organ": Bus(-15, reverb=0.15, pump=0.15),
        "organlead": Bus(-7, reverb=0.15, spring=0.15),
        "bass": Bus(-8, pump=0.2, eq=(("lp", 2600),)),
        "kick": Bus(-10, drive=1.4),
        "snare": Bus(-12, reverb=0.15),
        "toms": Bus(-11, drive=1.3, reverb=0.12),
        "cymbal": Bus(-18),
        "hats": Bus(-19),
        "perc": Bus(-19),
        "coins": Bus(-16, reverb=0.25, delay=0.15),
        "ping": Bus(-17, reverb=0.5, delay=0.3),
        "fx": Bus(-17, reverb=0.25),
    }, reverb_decay=1.8, reverb_tone=5500, delay_time=tr.beat * 0.75, delay_feedback=0.3, pump_release=0.15)
    return finish(tr, mix), tr


SONG = Song("SharkBait", "Shark Surf Panic", 160, 9, 51, shark_surf_panic)
