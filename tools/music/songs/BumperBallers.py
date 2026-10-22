"""Tiki Bumper Bash: the round song for BumperBallers (see songkit.py for the rules every song keeps)."""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)

from score import Note  # noqa: E402 (a note of a melody line, for the harmony below)

F_MAJOR = (5, 7, 9, 10, 0, 2, 4)  # pitch classes of the key, for the second pan's passing notes
G_MAJOR = (7, 9, 11, 0, 2, 4, 6)


def under(notes, bar0, parts, scale):
    """A second pan under the lead: a chord tone at least a minor third below every chord tone, a
    diatonic third below every passing note."""
    changes = [(b * 16 + st, ln, c) for p in parts for b, st, ln, c in p.changes]
    out = []
    for n in notes:
        pos = bar0 * 16 + n.step
        c = next(c for start, ln, c in changes if start <= pos < start + ln)
        tones = c.tones()
        if n.midi % 12 in tones:
            m = n.midi - 3
            while m % 12 not in tones:
                m -= 1
        else:
            degree = scale.index(n.midi % 12)
            m = n.midi - (n.midi % 12 - scale[(degree - 2) % 7]) % 12
        out.append(Note(n.step, m, n.length, n.vel * 0.9))
    return out


def iron(variant: int = 0) -> np.ndarray:
    """A soca 'iron' (a car's brake drum struck with a steel rod): a bright, clanky ring."""
    n = s.samples(0.16)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(31 + variant)
    ring = sum(a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-t / d)
               for f, a, d in ((1180.0, 1.0, 0.05), (1730.0, 0.7, 0.035), (2470.0, 0.45, 0.025), (3320.0, 0.25, 0.015)))
    click = s.bandpass(rng.uniform(-1, 1, n), 2000, 6000) * np.exp(-t / 0.003) * 0.5
    return ins.normalize(ins.eq(ring + click, ("lp", 6500), ("hp", 700)))


def pea_whistle(length: float, pitch: float = 2500.0) -> np.ndarray:
    """A carnival pea whistle: a high tone the rattling pea chops into a trill."""
    n = s.samples(length + 0.03)
    t = np.arange(n) / s.SR
    trill = 0.55 + 0.45 * np.sin(2 * np.pi * 34 * t)
    f = pitch * (1 + 0.01 * np.sin(2 * np.pi * 34 * t)) * (1 + 0.03 * np.exp(-t / 0.03))
    tone = s.sine(f, n) + 0.06 * s.sine(f * 2, n)
    breath = s.bandpass(np.random.default_rng(5).uniform(-1, 1, n), 1500, 4500) * 0.12
    e = ins.env(n, 0.012, 0.1, 0.9, 0.03, gate=length)
    return ins.normalize(ins.eq((tone * trill + breath) * e, ("lp", 5500)))


def conch(midi: float, length: float) -> np.ndarray:
    """A conch-shell horn: a hollow, breathy call that scoops up into its note."""
    n = s.samples(length + 0.2)
    t = np.arange(n) / s.SR
    pitch = midi - 2.5 * np.exp(-t / 0.09) + 0.12 * np.clip((t - 0.3) / 0.3, 0, 1) * np.sin(2 * np.pi * 4.8 * t)
    f = s.midi_hz(pitch)
    tone = s.sine(f, n) + 0.45 * s.sine(2 * f, n) + 0.25 * s.saw(f, n) * 0.5
    breath = s.bandpass(np.random.default_rng(9).uniform(-1, 1, n), 600, 2600) * 0.18
    e = ins.env(n, 0.09, 0.4, 0.85, 0.2, gate=length)
    return ins.normalize(ins.formant((tone + breath) * e, [(500, 5, 1.4), (1100, 3, 2.0)]))


def tiki_bumper_bash():
    """Tiki Bumper Bash (128 bpm, F major, soca): a beach party on the tiki island. A steel band (a lead
    tenor pan with a second pan under it on the chord tones, chopping guitar pans, rolled chords) over
    soca drums: four-on-the-floor kick, a skipping snare, the iron, log drums and a pea whistle; horns in
    the chorus. BIG BUMPS (45 s after GO) lands on bar 24 after GO: up to G major, the horns take a
    counter-line under the hook, and a tag swings back down into F for the loop."""
    tr = Track(bpm=128, bars=43)
    parts = plan(tr, [
        ("intro", 7, "F | F | Bb | F | Dm | Bb | C7"),
        ("A1", 8, "F | C | Dm | Bb | F | C | Bb C | F"),
        ("A2", 8, "F | C | Dm | Bb | F | C | Bb C | F"),
        ("B", 8, "Bb | C | Am | Dm | Gm | C | Bb | Eb F"),
        ("climax", 8, "G | D | Em | C | G | D | C D | G"),
        ("final", 4, "G | Em | C | C7"),
    ])
    hook = melody("""C5:3 F5:3 A5:2 G5:3 F5:3 C5:2 | E5:3 G5:3 C6:2 Bb5:2 A5:2 G5:4 | D5:3 F5:3 A5:2 G5:3 F5:3 D5:2 | F5:4 D5:2 F5:2 G5:8 |
                     C5:3 F5:3 A5:2 G5:3 F5:3 C5:2 | E5:3 G5:3 C6:2 D6:2 C6:2 Bb5:2 A5:2 | Bb5:3 A5:3 G5:2 C6:3 Bb5:3 G5:2 | A5:6 F5:2 r:4 A4:2 Bb4:2""")
    chorus = melody("""D6:6 C6:2 Bb5:4 F5:4 | E5:6 F5:2 G5:4 C6:4 | C6:6 A5:2 E5:4 A5:4 | F5:8 E5:4 D5:4 |
                       D6:6 C6:2 Bb5:4 G5:4 | E5:6 F5:2 G5:4 Bb5:4 | A5:4 Bb5:4 C6:4 D6:4 | Eb6:4 D6:4 C6:4 D6:4""")
    counter = melody("B3:16 | A3:16 | G3:12 B3:4 | C4:8 E4:8 | D4:16 | F#4:8 A4:8 | G4:8 F#4:8 | G4:16")
    tag = melody("""D5:3 G5:3 B5:2 A5:3 G5:3 D5:2 | E5:3 G5:3 B5:2 A5:3 G5:3 E5:2 | E5:3 G5:3 C6:2 B5:2 A5:2 G5:4 |
                    E5:2 G5:2 Bb5:2 C6:2 Bb5:2 G5:2 A4:2 Bb4:2""")
    sunrise = melody("r:8 C5:3 F5:3 A5:2 | C6:12 r:4 | r:8 D5:3 F5:3 Bb5:2 | C6:8 E5:3 G5:3 Bb5:2")
    horn_answer = melody("r:12 F4:2 A4:2 | Bb4:4 r:12 | r:12 E4:2 G4:2 | A4:4 r:12 | r:12 Bb4:2 D5:2 | C5:4 r:12 | r:16 | r:16")

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.85, section=3)

    rng = np.random.default_rng(23)

    def pans(stem, bar, notes, gain=1.0, pan=0.0, roll_from=6, rate=0.5):
        """Pan strokes; long notes are rolled the way a pannist sustains them (with human jitter)."""
        for n in notes:
            if n.length >= roll_from:
                k = 0.0
                while k < n.length - 0.6:
                    jitter = rng.uniform(-0.05, 0.05) if k else 0.0
                    accent = 1.0 if k == 0 else (0.62 if int(k / rate) % 2 == 0 else 0.5)
                    tr.add(stem, bar, n.step + k + jitter, ins.steel_pan(n.midi, 0.3), gain * n.vel * accent, pan)
                    k += rate
            else:
                tr.add(stem, bar, n.step, ins.steel_pan(n.midi, n.length * tr.step), gain * n.vel, pan)

    kick, clap, snare = s.kick(1.0, 0.4), s.clap(), ins.snare2(230.0, 0.8)
    ohat, chat, shake = s.hat(True), s.hat(False), s.shaker()
    irons = [iron(v) for v in range(3)]
    logs = {"lo": ins.log_drum(240.0), "mid": ins.log_drum(320.0), "hi": ins.log_drum(430.0)}
    toms = [ins.tom(p, 0.4) for p in (120.0, 160.0, 210.0)]
    boings = {"A1": ins.jaw_harp(53, 0.45), "climax": ins.jaw_harp(55, 0.45)}  # F and G: the sections' roots
    congas = {"open": ins.conga(230.0), "slap": ins.conga(330.0, True), "low": ins.conga(175.0)}

    # the island at dawn: surf, a conch call, then the band wakes up
    tr.add("surf", 0, 0, ins.waves(tr.bar * 5), 1.0)
    tr.add("conch", 0, 4, conch(60, tr.beat * 2.4), 0.9)
    tr.add("conch", 1, 4, conch(65, tr.beat * 3.5), 1.0)
    pans("lead", 3, sunrise, 0.55, roll_from=8)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 29) + 12
            notes = voicing(c, 55, 70, prev, size=3)
            prev = notes
            # bass: a double tresillo with octave and fifth kicks
            if name == "intro":
                if local >= 4:
                    for st, off in ((0, 0), (6, 12), (12, 0)):
                        tr.add("bass", bar, st, ins.bass_guitar(root + off, tr.step * 3.2, bright=0.5), 0.6 + 0.12 * (local - 4))
            else:
                pattern = ((0, 0), (3, 0), (6, 12), (8, 0), (11, 7), (14, 12))
                if name == "B":
                    pattern = ((0, 0), (6, 12), (8, 7), (12, 0), (14, 12))
                for st, off in pattern:
                    if step <= st < step + length:
                        note_len = 2.6 if st not in (0, 8) else 2.9
                        tr.add("bass", bar, st, ins.bass_guitar(root + off, tr.step * note_len, bright=0.55), 1.0 if st in (0, 8) else 0.82)
            # rolled chords: the steel band's sustain
            if name == "intro" and 1 <= local <= 5 or name in ("B", "final"):
                for v, m in enumerate(notes):
                    k = 0.0
                    while k < length - 0.5:
                        tr.add("roll", bar, step + k + rng.uniform(-0.06, 0.06), ins.steel_pan(m, 0.3), (0.55 if k else 0.8) * (0.5 if name == "intro" else 1.0), -0.35 + 0.35 * v)
                        k += 0.5
            # chopping guitar pans
            chop = {"A1": "..x...x...x...x.", "A2": "..x..xx...x..x.x", "climax": "x.xx.xx.x.xx.xx.", "final": "..x...x...x...x."}.get(name)
            if chop:
                for k, ch in enumerate(chop):
                    if ch == "x" and step <= k < step + length:
                        strum(tr, "chop", bar, k, notes, ins.steel_pan, tr.step * 1.2, 0.9 if k % 4 == 2 else 0.7, spread=0.006, pan=0.3)
            # horn stabs on the and-of-4 every other bar
            if name in ("B", "climax") and local % 2 == 1 and step + length == 16:
                strum(tr, "brass", bar, 14, voicing(c, 62, 76, size=3), horn, tr.step * 1.6, 1.0, spread=0.0, pan=-0.15)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 1:
                    tr.drum("logs", bar, "X.....X.....X...", logs["lo"], 0.35 + 0.08 * (local - 1), -0.2)
                    tr.drum("logs", bar, "...x.......x..x.", logs["hi"], 0.3 + 0.07 * (local - 1), 0.25)
                if local >= 2:
                    tr.drum("perc", bar, "xoxoxoxoxoxoxoxo", shake, 0.4 + 0.1 * (local - 2), 0.35)
                if local == 3:
                    tr.kick("kick", bar, "X.......X.......", kick, 0.45)
                elif local >= 4:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.55 + 0.12 * (local - 4))
                if local >= 5:
                    tr.drum("iron", bar, "X.xxX.xxX.xxX.xx", irons[local % 3], 0.5 + 0.2 * (local - 5), 0.2)
                    tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.5, -0.2)
                if local == 6:
                    for k in range(16):
                        tr.add("snare", bar, k, snare, 0.2 + 0.045 * k, 0.05)
                    for k, st in enumerate((8, 10, 12, 13, 14, 15)):
                        tr.add("toms", bar, st, toms[2 - k // 2], 0.6 + 0.06 * k)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.5)
                    tr.add("whistle", bar, 12, pea_whistle(tr.beat * 0.4), 0.8)
                    tr.add("whistle", bar, 14, pea_whistle(tr.beat * 0.4), 0.9)
                continue
            big = name in ("climax",)
            tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
            tr.drum("snare", bar, "....X..x....X..x" if name != "B" else "....X.......X...", snare, 0.9, 0.05)
            if name in ("A2", "B", "climax", "final"):
                tr.drum("snare", bar, "....X.......X...", clap, 0.8 if name != "B" else 0.65, -0.05)
            tr.drum("iron", bar, "X.xxX.xxX.xxX.xx" if name != "B" else "x.x.x.x.x.x.x.x.", irons[local % 3], 0.8, 0.2)
            tr.drum("hats", bar, "..X...X...X...X.", ohat, 0.9, -0.2)
            if big:
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.5, 0.25)
            tr.drum("perc", bar, "xoxoxoxoxoxoxoxo", shake, 1.0, 0.35)
            tr.drum("logs", bar, "X.....X.....X...", logs["lo"], 0.7, -0.2)
            tr.drum("logs", bar, "...x..x....x..x." if local % 2 == 0 else "...x.......xx.x.", logs["mid" if local % 2 else "hi"], 0.55, 0.25)
            if local == 0:
                tr.add("hats", bar, 0, s.crash(), 1.8, 0.2)
                if name in boings:
                    tr.add("fx", bar, 0, boings[name], 0.7, 0.1)
            if big or name == "final":
                tr.drum("congas", bar, "..x....x..x....x", congas["open"], 0.8, -0.35)
                tr.drum("congas", bar, "....x.......x.x.", congas["slap"], 0.7, -0.35)
                tr.drum("congas", bar, "x.....x.........", congas["low"], 0.7, -0.35)
            if big and local == 0:
                strum(tr, "brass", bar, 0, voicing(part.changes[0][3], 62, 76, size=3), horn, tr.step * 3, 1.2, spread=0.0, pan=-0.1)
            if big and local == 4:
                tr.add("hats", bar, 0, s.crash(), 1.4, -0.2)
            # fills into the next section
            if local == part.bars - 1 and name in ("A1", "A2", "climax", "final"):
                for k, st in enumerate((12, 13, 14, 15)):
                    tr.add("toms", bar, st, toms[2 - k // 2], 0.75)
            if name == "final" and local == part.bars - 1:  # into the loop, the way the intro goes into GO
                tr.add("whistle", bar, 12, pea_whistle(tr.beat * 0.4), 0.75)
                tr.add("whistle", bar, 14, pea_whistle(tr.beat * 0.4), 0.85)
            if name == "B" and local == part.bars - 1:
                for k in range(8, 16):
                    tr.add("snare", bar, k, snare, 0.45 + 0.06 * (k - 8), 0.05)
                tr.add("fx", bar, 0, s.riser(tr.bar), 0.4)
            if name == "A2" and local in (3, 7):
                tr.add("whistle", bar, 12, pea_whistle(tr.beat * 0.35), 0.75)
                tr.add("whistle", bar, 14, pea_whistle(tr.beat * 0.8), 0.85)
            if big and local % 2 == 1:
                tr.add("whistle", bar, 14, pea_whistle(tr.beat * 0.4), 0.7)

    pans("lead", 7, hook)
    pans("lead", 15, hook)
    pans("harmony", 15, under(hook, 15, parts, F_MAJOR), 0.85, pan=-0.3)
    pans("chorus", 23, chorus, roll_from=4)
    tr.play("brass", 23, horn_answer, horn, 0.9, pan=-0.15)
    pans("lead", 31, shift(hook, 2))
    pans("harmony", 31, under(shift(hook, 2), 31, parts, G_MAJOR), 0.85, pan=-0.3)
    tr.play("brass", 31, counter, horn, 1.0, pan=-0.1)
    pans("lead", 39, tag)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.16, delay=0.07),
        "chorus": Bus(-6, reverb=0.2, delay=0.06),
        "harmony": Bus(-13, reverb=0.18),
        "roll": Bus(-15, pump=0.2, reverb=0.25),
        "chop": Bus(-15, pump=0.15, reverb=0.12),
        "brass": Bus(-11, reverb=0.16),
        "conch": Bus(-18, reverb=0.35),
        "surf": Bus(-20),
        "bass": Bus(-8, pump=0.25),
        "kick": Bus(-9, drive=1.4),
        "snare": Bus(-13, reverb=0.12),
        "toms": Bus(-13, reverb=0.12),
        "iron": Bus(-18),
        "hats": Bus(-18),
        "perc": Bus(-20),
        "logs": Bus(-14, reverb=0.1),
        "congas": Bus(-16, reverb=0.1),
        "whistle": Bus(-19, reverb=0.2),
        "fx": Bus(-16, reverb=0.3),
    }, reverb_decay=1.4, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.28, pump_release=0.18)
    return finish(tr, mix), tr


SONG = Song("BumperBallers", "Tiki Bumper Bash", 128, 7, 43, tiki_bumper_bash)
