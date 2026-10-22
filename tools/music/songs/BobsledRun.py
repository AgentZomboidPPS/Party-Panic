"""Ice Chute Rush: the round song for BobsledRun (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def faded(x, seconds=0.03):
    """A short fade at the very end, so a tail that's cut off doesn't click."""
    x = np.array(x, dtype=float)
    k = min(x.shape[-1], s.samples(seconds))
    x[..., -k:] *= np.linspace(1.0, 0.0, k)
    return x


@lru_cache(maxsize=None)
def trumpets(m, sec):
    return ins.brass(m, sec, bright=1.0, section=3)


@lru_cache(maxsize=None)
def horns(m, sec):
    return ins.brass(m, sec, bright=0.45, section=4, vibrato=0.05)


@lru_cache(maxsize=None)
def low_brass(m, sec):
    """Trombones and a tuba holding the bass: dark, no vibrato."""
    return ins.brass(m, sec, bright=0.35, section=3, vibrato=0.0)


@lru_cache(maxsize=None)
def violins(m, sec):
    return ins.strings((m, m + 12), sec, attack=0.08, bright=0.6, release=0.3)


@lru_cache(maxsize=None)
def bass_drum():
    """A concert bass drum: a round boom at 60-130 Hz, where a phone can still play it."""
    n = s.samples(0.45)
    t = np.arange(n) / s.SR
    body = s.sine(62 + 60 * np.exp(-t / 0.035), n) * np.exp(-t / 0.18)
    felt = ins.eq(np.random.default_rng(8).uniform(-1, 1, n), ("hp", 150), ("lp", 1200)) * np.exp(-t / 0.012) * 0.3
    return faded(ins.normalize(np.tanh((body + felt) * 1.4)))


@lru_cache(maxsize=None)
def wind(length):
    """The wind at the top of the run: a hollow, slowly swelling howl."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(41)
    out = np.zeros((2, n))
    for ch in range(2):
        centre = 700 + 350 * np.sin(2 * np.pi * t / (3.7 + ch) + ch)
        out[ch] = ins.tv_lowpass(rng.uniform(-1, 1, n), centre, q=3.0) - ins.tv_lowpass(rng.uniform(-1, 1, n), centre * 0.5, q=0.7) * 0.5
    return faded(ins.normalize(ins.eq(out, ("hp", 250), ("lp", 3000)) * np.clip(t / 2.0, 0, 1)), 1.5)


def bobsled_run():
    """Ice Chute Rush (156 bpm, C major): heroic brass and sleigh bells down the ice. Trumpets carry
    the theme over driving spiccato strings, timpani and a concert bass drum; the curves are a
    swaying tune the horns (left) and strings (right) trade like a crew leaning together, with the
    sled's whoosh through every bend; the climax lifts the theme to D major with a choir for the home
    stretch (21-34 s after GO: the first sleds come home at about 29 s) and the fanfare finish lands
    as the 8 s finish clock runs out (34-40 s). A calmer coda in C climbs down B flat, A flat, G7 and
    back into the drop."""
    tr = Track(bpm=156, bars=45)
    parts = plan(tr, [
        ("intro", 9, "C | C | Am | Am | F | F | G | G | G"),
        ("A", 8, "C | Bb/C | C | F/A | C | Bb | Ab Bb | C"),
        ("B", 6, "Am | F | C | G | G | A7"),
        ("climax", 8, "D | C/D | D | G/B | D | C | Bb C | D"),
        ("final", 4, "Bb | C | D | D"),
        ("coda", 10, "F | C/E | Dm | C | F | C/E | Dm7 | Bb | Ab | G7"),
    ])
    theme = melody("""G4:3 C5:1 E5:4 G5:6 E5:2 | F5:3 D5:1 Bb4:4 D5:8 | G4:3 C5:1 E5:4 G5:4 C6:4 | A5:4 G5:2 F5:2 C5:8 |
                      E5:3 F5:1 G5:4 C6:6 B5:2 | Bb5:4 A5:2 F5:2 D5:8 | C6:4 Ab5:4 D6:4 Bb5:4 | C6:12 r:4""")
    counter = melody("E4:8 G4:8 | F4:16 | E4:8 C4:8 | C4:8 F4:8 | G4:16 | F4:8 D4:8 | Eb4:8 F4:8 | E4:12 r:4")
    lean_left = melody("E5:8 A5:8 | A5:4 G5:4 F5:8 | r:16 | r:16 | B5:4 C6:4 D6:4 B5:4 | C#6:8 E6:8")
    lean_right = melody("r:16 | r:16 | G5:8 C6:8 | B5:4 A5:4 G5:8 | B5:4 C6:4 D6:4 B5:4 | C#6:8 E6:8")
    fanfare = melody("Bb4:3 D5:1 F5:4 Bb5:8 | C5:3 E5:1 G5:4 C6:8 | D5:3 F#5:1 A5:4 D6:4 C#6:2 D6:2 | D6:12 r:4")
    coda = melody("""A4:8 C5:8 | G4:8 C5:4 E5:4 | F5:8 E5:4 D5:4 | E5:16 | A5:8 G5:4 F5:4 | E5:8 G5:8 | F5:4 E5:4 D5:4 C5:4 |
                     D5:8 F5:8 | Eb5:8 C5:8 | B4:4 D5:4 F5:4 G5:4""")
    head = melody("G4:3 C5:1 E5:4 G5:8 | r:16")

    kick = bass_drum()
    snares = [ins.snare2(190.0, 1.0, 0.26, v) for v in range(4)]
    bells = [ins.sleigh(0.22, v) for v in range(4)]
    crash = s.crash(2.2)
    toms = [ins.tom(p, 0.45, v) for v, p in enumerate((150.0, 110.0, 85.0))]

    def hits(stem, bar, pattern, sounds, gain=1.0, pan=0.0):
        for k, (step, vel) in enumerate((i, {"X": 1.0, "x": 0.8, "o": 0.45}[ch]) for i, ch in enumerate(pattern) if ch != "."):
            tr.add(stem, bar, step, sounds[k % len(sounds)], gain * vel, pan)

    def roll(stem, bar, start, end, sound_at, gain_from, gain_to, rate=1.0):
        """A roll (timpani or snare) from `start` to `end` steps, swelling."""
        k = start
        while k < end - 1e-6:
            frac = (k - start) / max(end - start, 1e-6)
            tr.add(stem, bar, k, sound_at(int(k / rate)), gain_from + (gain_to - gain_from) * frac)
            k += rate

    # the top of the run: wind, the crew's bells, ice glinting
    tr.add("fx", 0, 0, wind(tr.bar * 9), 0.8)
    for bar in range(0, 4):
        for k, step in enumerate((0, 3, 6, 10)):
            tr.add("bells", bar, step, bells[k % 4], 0.25 + 0.08 * bar, -0.2 + 0.13 * k)
    tr.play("horns", 2, head, horns, 0.4)
    tr.play("brass", 6, shift(head, 7), trumpets, 0.8)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 36)  # C2..B2
            notes = voicing(c, 60, 72, prev)
            prev = notes
            seconds = length * tr.step
            eighths = range(int(step), int(step + length), 2)
            if name == "intro":
                if local < 4:  # ice glinting: a celesta rolls the chord
                    for k, m in enumerate(notes + [notes[0] + 12, notes[1] + 12]):
                        tr.add("ice", bar, 2 + k * 1.5, ins.celesta(m + 12, 0.6), 0.3 + 0.1 * local, -0.4 + 0.2 * k)
                    tr.add("pad", bar, 0, ins.strings((root + 24, root + 31), seconds, attack=0.9, bright=0.25), 0.4 + 0.2 * local)
                elif local < 8:
                    tr.add("pad", bar, 0, ins.strings(tuple(notes), seconds, attack=0.4, bright=0.35), 0.9)
                    for k in eighths:
                        tr.add("ostinato", bar, k, ins.spiccato(notes[(0, 1, 2, 1)[(k // 2) % 4]], tr.step * 1.5), 0.35 + 0.12 * (local - 4), 0.3)
                        tr.add("bass", bar, k, ins.spiccato(root + 12, tr.step * 1.5), 0.4 + 0.12 * (local - 4))
                else:  # the push: the brass hits the start, 1-2-3
                    for k in (0, 4, 8):
                        strum(tr, "brass", bar, k, [n + 12 for n in notes], lambda m, sec: ins.brass(m, sec, bright=1.0, section=2), tr.step * 2.5, 1.0, spread=0.0)
                        tr.add("lowbrass", bar, k, low_brass(root + 12, tr.step * 2.5), 1.0)
                    tr.add("lowbrass", bar, 12, low_brass(root + 12, tr.step * 4), 0.8)
                continue
            if name == "final" and local == 3:  # ta-da
                strum(tr, "brass", bar, 0, [n + 12 for n in notes], lambda m, sec: ins.brass(m, sec, bright=1.0, section=3), tr.step * 10, 1.0, spread=0.0)
                tr.add("lowbrass", bar, 0, low_brass(root + 12, tr.step * 10), 1.0)
                tr.add("lowbrass", bar, 0, low_brass(root, tr.step * 10), 0.8)
                tr.add("pad", bar, 0, ins.strings(tuple(notes), tr.step * 12, attack=0.02, bright=0.7), 1.0)
                tr.add("choir", bar, 0, ins.choir(tuple(notes), tr.step * 12, "ah", attack=0.05), 1.0)
                continue
            calm = name == "coda" and local < 4
            # strings: the driving ostinato (8ths, a 16th pickup on the last beat) and the bass in octaves
            if not calm:
                ring = notes + [notes[0] + 12]
                for k in eighths:
                    idx = (0, 1, 2, 1, 3, 1, 2, 1)[(k // 2) % 8]
                    tr.add("ostinato", bar, k, ins.spiccato(ring[idx], tr.step * 1.5), 1.0 if k % 4 == 0 else 0.8, 0.3)
                    tr.add("bass", bar, k, ins.spiccato(root + (12 if k % 4 == 0 else 24 if k % 8 == 6 else 12), tr.step * 1.5), 1.0 if k % 4 == 0 else 0.75)
                    if k % 16 == 14:
                        tr.add("ostinato", bar, k + 1, ins.spiccato(ring[2], tr.step * 0.9), 0.7, 0.3)
            tr.add("lowbrass", bar, step, low_brass(root + 12, seconds * 0.95), 0.9 if name != "coda" else 0.6)
            if name in ("B", "climax", "final") or calm:
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.15 if not calm else 0.5, bright=0.5), 1.0)
            if name in ("climax", "final"):
                tr.add("choir", bar, step, ins.choir(tuple(notes), seconds, "ah", attack=0.12), 1.0)
            if name == "B":  # ice crystals: the glockenspiel rolls up each chord
                for k, m in enumerate(notes + [notes[0] + 12]):
                    tr.add("ice", bar, step + 8 + k, ins.glock(m + 24, 0.3), 0.55, 0.35 if local % 4 < 2 else -0.35)
            if calm:
                for k, m in enumerate(notes + [notes[0] + 12, notes[1] + 12]):
                    tr.add("ice", bar, step + 2 + k * 2, ins.celesta(m + 12, 0.6), 0.7, -0.3 + 0.15 * k)

        for bar in part.bars_range():
            local = bar - part.first
            last = local == part.bars - 1
            troot = bass_note(part.at(bar)[0][2], 36)  # the timpani follow the bass: the root, then the fifth
            tfifth = troot + 7 if troot + 7 <= 47 else troot - 5
            if name == "intro":
                if 4 <= local < 8:
                    tr.add("timp", bar, 0, ins.timpani(troot, 1.0, 0.6), 0.5 + 0.1 * (local - 4))
                    tr.add("timp", bar, 8, ins.timpani(tfifth, 1.0, 0.6), 0.45 + 0.1 * (local - 4))
                    hits("bells", bar, "x.x.x.x.x.x.x.x.", bells, 0.4 + 0.08 * (local - 4), 0.2)
                if local in (6, 7):
                    roll("snare", bar, 8 if local == 6 else 0, 16, lambda k: snares[k % 4], 0.15 + 0.1 * (local - 6), 0.35 + 0.2 * (local - 6))
                if local == 4:
                    tr.add("fx", bar, 0, ins.whoosh(tr.bar * 1.5, True), 0.6, -0.5)
                if local == 8:
                    for k in (0, 4, 8):
                        tr.add("timp", bar, k, ins.timpani(43, 1.0, 1.0), 1.0)
                        tr.add("drums", bar, k, snares[k // 4], 0.9)
                    tr.kick("kick", bar, "X...X...X.......", kick)
                    roll("timp", bar, 12, 16, lambda k: ins.timpani(43, 0.5, 0.8), 0.5, 1.0, 0.5)
                    roll("snare", bar, 12, 16, lambda k: snares[k % 4], 0.5, 1.0, 0.5)
                    tr.add("riser", bar - 1, 0, s.riser(tr.bar * 2), 1.0)
                    tr.add("fx", bar, 4, ins.whoosh(tr.bar * 0.75, True), 0.9, 0.4)
                continue
            if name == "final" and local == 3:
                tr.kick("kick", bar, "X...............", kick)
                tr.add("drums", bar, 0, crash, 1.0, 0.3)
                tr.add("timp", bar, 0, ins.timpani(38, 1.6, 1.0), 1.0)
                tr.add("timp", bar, 0, ins.timpani(50, 1.6, 1.0), 0.6)
                continue
            if local == 0 or (name in ("climax", "final") and local % 2 == 0):
                tr.add("drums", bar, 0, crash, 1.0 if local == 0 else 0.8, 0.3)
            calm = name == "coda" and local < 4
            if calm:
                hits("bells", bar, "x...x...x...x...", bells, 0.6, 0.2)
                tr.add("timp", bar, 0, ins.timpani(troot, 1.2, 0.4), 0.5)
                if local == 0:
                    tr.add("fx", bar, 0, ins.whoosh(tr.bar * 2.0, False), 0.6, 0.4)
                continue
            # the run: the bass drum on 1 and 3 (and the and-of-2), the snare on 2 and 4, timpani on the beat
            tr.kick("kick", bar, "X.....x.X......." if name != "B" else "X.....x.X.....x.", kick)
            hits("snare", bar, "....X.......X..." if not last else "....X.......X.xx", snares)
            tr.add("timp", bar, 0, ins.timpani(troot, 0.9, 0.8), 0.8)
            tr.add("timp", bar, 8, ins.timpani(tfifth, 0.9, 0.7), 0.6)
            hits("bells", bar, "X.x.X.x.X.x.X.x." if name in ("A", "coda") else "XxxxXxxxXxxxXxxx", bells, 0.8, 0.2)
            if name == "B":
                if local % 2 == 0:  # through a curve: whoosh (lean left, then right)
                    tr.add("fx", bar, 0, ins.whoosh(tr.bar * 1.6, True), 0.55, -0.6 if local % 4 == 0 else 0.6)
                hits("toms", bar, "..x...x...x..xx." if local % 2 else "..x...x...x...x.", toms, 0.6, -0.2)
            if last and name in ("A", "B", "climax", "coda"):
                top = 0.7 if name == "coda" else 0.9  # (the coda's tail rings round into the soft intro)
                roll("snare", bar, 8, 16, lambda k: snares[k % 4], 0.3, top, 0.5)
                if name in ("B", "coda"):
                    roll("timp", bar, 8, 16, lambda k: ins.timpani(43 if name == "coda" else 45, 0.5, 0.8), 0.3, top - 0.1, 0.5)
                if name == "coda":
                    tr.add("riser", bar - 1, 0, s.riser(tr.bar * 2), 0.9)
            if name == "final" and local == 2:
                roll("timp", bar, 0, 16, lambda k: ins.timpani(38, 0.5, 0.8), 0.4, 1.0, 0.5)

    tr.play("lead", 9, theme, trumpets)
    tr.play("horns", 9, [n for n in counter if n.step >= 4 * 16], horns, 0.8, pan=-0.3)
    tr.play("horns", 17, shift(lean_left, -12), horns, pan=-0.5)
    tr.play("strings", 17, lean_right, violins, pan=0.5)
    tr.play("lead", 17, [n for n in lean_left if n.step >= 4 * 16], trumpets, 0.55)
    tr.play("lead", 23, shift(theme, 2), trumpets)
    tr.play("horns", 23, shift(counter, 2), horns, pan=-0.3)
    tr.play("ice", 23, shift(theme, 14), ins.glock, 0.5, pan=0.3)
    tr.play("strings", 23, shift(theme, 14), violins, 0.6, pan=0.3)
    tr.play("lead", 31, fanfare, trumpets)
    tr.play("horns", 31, shift(fanfare, -12), horns, pan=-0.3)
    tr.play("horns", 35, coda, horns, pan=-0.2)
    tr.play("strings", 35, shift([n for n in coda if n.step >= 4 * 16], 12), violins, 0.8, pan=0.3)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.25),
        "horns": Bus(-9, reverb=0.3),
        "strings": Bus(-10, reverb=0.3),
        "brass": Bus(-10, reverb=0.25),
        "lowbrass": Bus(-13, reverb=0.2),
        "ostinato": Bus(-13, reverb=0.15),
        "bass": Bus(-11, reverb=0.1),
        "pad": Bus(-16, reverb=0.3),
        "choir": Bus(-13, reverb=0.3),
        "ice": Bus(-15, reverb=0.35, delay=0.2),
        "bells": Bus(-17, reverb=0.15, eq=(("lp", 8500),)),
        "timp": Bus(-12, reverb=0.1),
        "kick": Bus(-12),
        "snare": Bus(-15, reverb=0.08),
        "drums": Bus(-15, reverb=0.1, eq=(("lp", 9000),)),
        "toms": Bus(-16, reverb=0.15),
        "fx": Bus(-17, reverb=0.3),
        "riser": Bus(-18, eq=(("lp", 8000),)),
    }, reverb_decay=1.7, reverb_tone=5500, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("BobsledRun", "Ice Chute Rush", 156, 9, 45, bobsled_run)
