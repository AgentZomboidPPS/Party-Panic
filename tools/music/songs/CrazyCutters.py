"""Cookie Cutter Swing: the round song for CrazyCutters (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


@lru_cache(maxsize=None)
def vib(m: float, sec: float) -> np.ndarray:
    """Vibraphone played with the damper: rings a moment past the note, its motor's tremolo moving across."""
    tone = ins._gate(np.asarray(ins.fm(m, sec, 4.0, 0.6, 1.1, mod_decay=0.05)), sec + 0.18, 0.3)
    t = np.arange(tone.shape[-1]) / s.SR
    left = 1 - 0.3 * (1 + np.sin(2 * np.pi * 5.6 * t)) / 2
    right = 1 - 0.3 * (1 + np.sin(2 * np.pi * 5.6 * t + 1.2)) / 2
    return np.vstack([tone * left, tone * right])


@lru_cache(maxsize=None)
def kick(low: float = 64.0, length: float = 0.3) -> np.ndarray:
    """A jazz bass drum: tuned up near 64 Hz so a phone still hears it, with the beater's tick."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    f = low + 110 * np.exp(-t / 0.025)
    body = np.sin(2 * np.pi * np.cumsum(f) / s.SR) * np.exp(-t / 0.08)
    tick = s.bandpass(ins._rng("kick", low).uniform(-1, 1, n), 1500, 5000) * np.exp(-t / 0.004) * 0.3
    return ins.normalize(np.tanh((body + tick) * 1.5))


@lru_cache(maxsize=None)
def chick() -> np.ndarray:
    """The hi-hat pedal on 2 and 4: a short, dark 'chick'."""
    n = s.samples(0.08)
    t = np.arange(n) / s.SR
    noise = ins.eq(ins._rng("chick").uniform(-1, 1, n), ("hp", 3000), ("lp", 8000), ("peak", 5200, 5, 1.5))
    return ins.normalize(noise * np.exp(-t / 0.018))


@lru_cache(maxsize=None)
def ding() -> np.ndarray:
    """The oven timer: the cookies are done."""
    bell = np.asarray(ins.fm(91, 1.0, 3.47, 1.1, 1.2, mod_decay=0.12)).copy()
    ping = np.asarray(ins.fm(103, 0.3, 2.0, 0.4, 0.4))
    bell[: len(ping)] += 0.25 * ping[: len(bell)]
    return ins.normalize(ins.eq(bell, ("hp", 600), ("lp", 7000)))


def play_struck(tr, stem, bar, notes, voice, gain=1.0, pan=0.0, humanize=0.0):
    """Plays mallet notes: a bar struck again stops the note still ringing on it, so quick repeats
    don't pile up in phase."""
    rng = np.random.default_rng(int(bar * 1000 + len(notes)))
    for i, n in enumerate(notes):
        sound = np.asarray(voice(n.midi, max(0.03, n.length * tr.step)))
        again = next((o.step for o in notes[i + 1:] if o.midi == n.midi), None)
        if again is not None:
            sound = ins._gate(sound, (again - n.step) * tr.step, 0.03)
        vel = n.vel * (1 + rng.uniform(-humanize, humanize)) if humanize else n.vel
        tr.add(stem, bar, n.step, sound, gain * vel, pan)


def shell(c) -> list:
    """A rhythm guitarist's three-note shell: the root (F2..E3), the 6th or 7th above it, the 3rd an octave up."""
    root = 41 + (c.root - 41) % 12
    third = c.intervals[1] % 12
    seventh = next((i for i in c.intervals[2:] if i % 12 in (9, 10, 11)), 7)
    return [root, root + seventh, root + 12 + third]


def crazy_cutters():
    """Cookie Cutter Swing (160 bpm swing, C major): a picnic bake-off's jazz combo. A vibraphone and a
    clarinet trade a bouncy head over a walking upright bass, brushes, a ride cymbal and a chunking rhythm
    guitar; the clarinet sings the bridge, the head comes back with both in octaves as the third (hardest)
    cookie is cut, then a shout chorus up in D major and the oven timer's DING when the cookies are done."""
    tr = Track(bpm=160, bars=58, spb=12)
    head = "C6 A7 | Dm7 G7 | C6 A7 | Dm7 G7 | C6 C7 | F6 F#dim7 | C6/G A7"
    parts = plan(tr, [
        ("intro", 10, "C6 | A7 | Dm7 | G7 | C6 | A7 | Dm7 | G7 | Dm7 | G7"),
        ("A1", 8, head + " | Dm7 G7"),
        ("A2", 8, head + " | Dm7 G7"),
        ("B", 8, "E7 | E7 | A7 | A7 | D7 | D7 | G7 | G7"),
        ("A3", 8, head + " | Em7 A7"),
        ("shout", 8, "D6 B7 | Em7 A7 | D6 B7 | Em7 A7 | D6 D7 | G6 G#dim7 | D6/A B7 | Em7 A7"),
        ("tag", 8, "D6 | D6 | Dm7 | G7 | C6 | A7 | Dm7 | G7"),
    ])
    tune = """E5:2 G5:1 A5:3 G5:2 E5:1 C#5:3 | D5:2 F5:1 A5:2 G5:1 ~:3 B4:3 |
              E5:2 G5:1 A5:3 C6:2 A5:1 C#6:3 | D6:3 C6:2 A5:1 G5:6 |
              G5:2 C6:1 E6:3 D6:2 C6:1 Bb5:3 | A5:3 F5:2 A5:1 C6:2 A5:1 F#5:3 |
              G5:3 E5:2 C5:1 C#5:2 E5:1 G5:3 | """
    theme = melody(tune + "F5:3 D5:2 B4:1 ~:3 D5:2 D#5:1", 12)
    lift = melody(tune + "G5:3 E5:2 C#5:1 ~:3 E5:2 F5:1", 12)  # A3: its last bar turns towards D
    bridge = melody("""G#4:6 B4:3 D5:3 | E5:3 D5:2 B4:1 G#4:6 | C#5:6 E5:3 G5:3 | F#5:3 E5:2 C#5:1 A4:6 |
                       A4:3 F#4:2 A4:1 C5:3 B4:2 A4:1 | F#4:6 r:3 D4:2 F#4:1 |
                       B4:3 G4:2 B4:1 D5:3 F5:3 | E5:3 D5:2 B4:1 G4:2 F4:1 D#4:3""", 12)
    motif = melody("r:6 E5:2 G5:1 A5:3 | r:6 G5:2 E5:1 C#5:3 | r:6 D5:2 F5:1 A5:3 | G5:2 F5:1 D5:3 B4:6", 12)
    guide = melody("E4:12 | G4:6 C#4:6 | F4:12 | F4:6 B3:6", 12)
    run = melody("r:6 G4:1 A4:1 B4:1 C5:1 D5:1 D#5:1", 12)
    ending = melody("F#5:1 A5:1 B5:1 D6:1 E6:1 F#6:1 A6:6 | r:12 | r:6 F5:2 A5:1 C6:3 | B5:3 A5:2 F5:1 D5:6", 12)

    def clar(m, sec):
        return ins.clarinet(m, sec)

    def gtr(m, sec):
        return ins.acoustic_guitar(m, sec, variant=m % 3)

    def bass(m, sec):
        return ins.upright(m, sec, variant=int(m) % 2)

    ride = ins.ride(1.2, 0.35)
    tap, swish = ins.brush(0.2), ins.brush(0.34, swish=True)
    snare = ins.snare2(210.0, 0.6, 0.22)
    bd = kick()
    hh = chick()
    crash = ins.eq(s.crash(2.0), ("lp", 9000))

    rng = np.random.default_rng(31)
    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 38)
            notes = voicing(c, 52, 64, prev)
            prev = notes
            seconds = length * tr.step
            beats = int(round(length / 3))
            # the rhythm guitar: a short chunk on every beat, 2 and 4 leaning in
            if name in ("A1", "A2", "B", "A3", "shout") or (name == "tag" and bar - part.first >= 4):
                for k in range(beats):
                    beat_in_bar = int((step + 3 * k) // 3)
                    strum(tr, "guitar", bar, step + 3 * k, shell(c), gtr, tr.step * 2.2, 1.0 if beat_in_bar % 2 else 0.75, spread=0.008)
            # vibes comping (a Charleston: on the beat, then the and-of-2)
            if name in ("A2", "B") or (name == "intro" and local < 8 and step == 0) or (name == "tag" and local >= 2):
                comp = voicing(c, 55, 67) if name != "B" else voicing(c, 58, 70)
                if name == "intro":
                    strum(tr, "comp", bar, 0, comp + [comp[1] + 12], vib, tr.bar * 0.9, 0.55 + 0.04 * local, spread=0.05)
                elif step == 0:
                    strum(tr, "comp", bar, 0, comp, vib, tr.step * 4, 0.8, spread=0.006)
                    if length >= 12 or name == "B":
                        strum(tr, "comp", bar, 5, comp, vib, tr.step * 5, 0.65, spread=0.006)
                else:
                    strum(tr, "comp", bar, step + 2, comp, vib, tr.step * 3, 0.6, spread=0.006)
            # the bass: a two-feel in the intro and the tag's vamp, walking everywhere else
            if name == "intro":
                if 4 <= local < 8:
                    tr.add("bass", bar, 0, bass(root, tr.step * 5.5), 0.6 + 0.05 * (local - 4))
                    tr.add("bass", bar, 6, bass(root + 7 if root + 7 <= 50 else root - 5, tr.step * 5.5), 0.55)
                elif local >= 8:  # stop-time hits
                    for st, g in ((0, 1.0), (5, 0.9)):
                        tr.add("bass", bar, st, bass(root, tr.step * 1.8), g)
                        strum(tr, "guitar", bar, st, shell(c), gtr, tr.step * 1.6, 1.0, spread=0.006)
                        strum(tr, "comp", bar, st, voicing(c, 57, 69), vib, tr.step * 2, 0.8, spread=0.004)
        if name in ("A1", "A2", "B", "A3", "shout"):
            walking_bass(tr, "bass", part, bass, 1.0, low=38)
        elif name == "tag":
            for bar in part.bars_range():
                local = bar - part.first
                root = bass_note(part.at(bar)[0][2], 38)
                if local == 0:
                    for k, m in enumerate((38, 42, 45, 47)):
                        tr.add("bass", bar, 3 * k, bass(m, tr.step * 2.8), 1.0)
                elif local == 1:
                    tr.add("bass", bar, 0, bass(38, tr.step * 11), 1.0)
                elif local < 4:
                    tr.add("bass", bar, 0, bass(root, tr.step * 5.5), 0.8)
                    tr.add("bass", bar, 6, bass(root + 7 if root + 7 <= 50 else root - 5, tr.step * 5.5), 0.7)
            walking_bass(tr, "bass", Part("vamp", part.first + 4, 4, [ch for ch in part.changes if ch[0] >= part.first + 4]), bass, 0.9, low=38)

        # drums
        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 1:
                    tr.drum("brush", bar, "x.....x.....", swish, 0.35 + 0.05 * min(local, 7))
                if local >= 4:
                    tr.drum("hat", bar, "...x.....x..", hh, 0.6)
                    tr.drum("brush", bar, "x..x.xx..x.x", tap, 0.25 + 0.05 * (local - 4))
                if local >= 8:
                    tr.drum("kick", bar, "x....x......", bd, 1.0)
                    tr.drum("snare", bar, "x....x......", snare, 0.7)
                if local == 9:  # the fill into GO
                    for k in range(6, 12):
                        tr.add("snare", bar, k, snare, 0.35 + 0.1 * (k - 6))
                    tr.add("kick", bar, 9, bd, 0.8)
                continue
            if name == "tag" and local < 2:
                if local == 0:
                    tr.drum("snare", bar, "......xxxxxx", snare, 0.7)
                    tr.drum("kick", bar, "x.....X.....", bd, 1.0)
                    tr.add("cymbal", bar, 6, crash, 1.0, 0.25)
                else:
                    for k in range(12):  # a soft cymbal roll under the held chord
                        tr.add("ride", bar, k, ride, 0.1 + 0.02 * k, -0.2)
                    tr.add("kick", bar, 0, bd, 0.8)
                    tr.add("fx", bar, 0, ding(), 1.0, 0.3)
                continue
            brushes = name == "A2" or name == "tag"
            if brushes:
                tr.drum("brush", bar, "x..x.xx..x.x", tap, 0.75 if name != "tag" else 0.55)
                tr.drum("brush", bar, "x.....x.....", swish, 0.6)
            else:
                tr.drum("ride", bar, "x..X.xx..X.x" if name != "shout" else "X..X.xX..X.x", ride, 0.75 if name in ("A1", "B") else 0.9, -0.2)
            tr.drum("hat", bar, "...x.....x..", hh, 0.8)
            tr.drum("kick", bar, "o..o..o..o..", bd, 0.6)
            if name in ("B", "A3", "shout"):
                # the drummer's left hand: ghost notes on the triplets' last partials, now and then a dig
                for k in (2, 5, 8, 11):
                    if rng.random() < (0.35 if name == "B" else 0.5):
                        tr.add("snare", bar, k, snare, 0.25 + 0.2 * rng.random())
            if name == "shout":
                tr.drum("snare", bar, "...x.....x..", snare, 0.5)
                if local % 2 == 1:
                    tr.drum("kick", bar, ".....x....x.", bd, 0.9)
            if local == 0 and name in ("A1", "B", "A3", "shout"):
                tr.add("cymbal", bar, 0, crash, 0.9 if name != "A1" else 1.0, 0.25)
                tr.add("kick", bar, 0, bd, 1.0)
            if local == part.bars - 1 and name in ("A2", "B", "A3", "shout"):
                for k in range(6, 12):  # a triplet fill into the next chorus
                    tr.add("snare", bar, k, snare, 0.3 + 0.08 * (k - 6))
            if name == "tag" and local == 7:
                for k in range(6, 12):
                    tr.add("snare", bar, k, snare, 0.3 + 0.1 * (k - 6))

    # intro: the oven is set, the vibes noodle, the clarinet joins, then a run up into GO
    tr.add("fx", 0, 0, ding(), 0.3, 0.3)
    play_struck(tr, "vibes", 0, [n for n in motif if n.step < 12 * 2], vib, 0.38)
    play_struck(tr, "vibes", 0, [n for n in motif if n.step >= 12 * 2], vib, 0.55)
    play_struck(tr, "vibes", 4, motif, vib, 0.62, humanize=0.08)
    tr.play("clar2", 4, guide, clar, 0.65)
    tr.play("clar", 9, run, clar, 0.9)
    # the head, the bridge, the head again, the shout chorus
    play_struck(tr, "vibes", 10, theme, vib, humanize=0.1)
    tr.play("clar", 18, shift(theme, -12), clar, humanize=0.05)
    tr.play("clar", 26, bridge, clar, humanize=0.05)
    play_struck(tr, "vibes", 34, lift, vib, humanize=0.1)
    tr.play("clar", 34, shift(lift, -12), clar, 0.85)
    play_struck(tr, "vibes", 42, shift(theme, 2), vib, 1.0, humanize=0.08)
    tr.play("clar", 42, shift(theme, 2 - 12), clar, 0.9)
    # the ending lick, the DING, then a quiet vamp that walks back into the head
    play_struck(tr, "vibes", 50, ending, vib, 1.0)
    tr.play("clar", 50, shift([n for n in ending if n.step < 12], -12), clar, 0.85)
    tr.add("clar", 51, 0, clar(66, tr.bar * 0.9), 0.7)
    play_struck(tr, "vibes", 54, motif, vib, 0.6, humanize=0.08)
    tr.play("clar2", 54, guide, clar, 0.7)
    tr.play("clar", 57, run, clar, 0.85)

    mix = Mix(buses={
        "vibes": Bus(-6, reverb=0.18, delay=0.05),
        "clar": Bus(-7, reverb=0.2),
        "clar2": Bus(-15, reverb=0.25),
        "comp": Bus(-15, reverb=0.25),
        "guitar": Bus(-15, eq=(("hp", 120), ("lp", 4800)), reverb=0.12),
        "bass": Bus(-9),
        "ride": Bus(-18, eq=(("lp", 9000),), reverb=0.08),
        "brush": Bus(-19, eq=(("lp", 8500),)),
        "snare": Bus(-18, reverb=0.12),
        "hat": Bus(-22, eq=(("lp", 8500),)),
        "kick": Bus(-15),
        "cymbal": Bus(-19, reverb=0.15),
        "fx": Bus(-13, reverb=0.3, delay=0.1),
    }, reverb_decay=1.3, reverb_tone=6000, delay_time=tr.beat * 2 / 3, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("CrazyCutters", "Cookie Cutter Swing", 160, 10, 58, crazy_cutters)
