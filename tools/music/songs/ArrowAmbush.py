"""Archer's Jig: the round song for ArrowAmbush (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


@lru_cache(maxsize=None)
def pipes(m: float, sec: float):
    """A bagpipe drone: a buzzing reed that swells in and holds, wobbling a hair."""
    n = s.samples(sec + 0.4)
    t = np.arange(n) / s.SR
    f = s.midi_hz(m + 0.03 * np.sin(2 * np.pi * 0.35 * t))
    tone = s.saw(f, n) * 0.5 + s.square(f, n, 0.18) * 0.5
    tone = ins.formant(tone, [(700.0, 6, 2.0), (1600.0, 4, 2.5), (2900.0, 3, 3.0)])
    tone = ins.eq(tone, ("hp", 150), ("lp", 3200))
    return ins.normalize(tone * ins.env(n, 0.35, 0.5, 0.95, 0.35, gate=sec))


def diatonic(notes, degrees: int, tonic: int, scale=(0, 2, 4, 5, 7, 9, 11)):
    """The same tune moved `degrees` steps along the major scale (a third below is -2)."""
    out = shift(notes, 0)
    for n in out:
        rel = (n.midi - tonic) % 12
        if rel in scale:
            k = scale.index(rel) + degrees
            n.midi = tonic + 12 * ((n.midi - tonic) // 12 + k // 7) + scale[k % 7]
        else:
            n.midi -= 3
    return out


def archers_jig():
    """Archer's Jig (120 bpm in 12/8, D major): a storybook castle's archery tournament. A fife and a lute
    over a theorbo bass, a bagpipe drone, tabor, bodhran and tambourine, with herald trumpets: they
    call the tournament open, answer the tune's B part and sound the volley before the last stretch,
    which goes up to E major for the final scramble and ends on an A7 that leads back into the drop."""
    tr = Track(bpm=120, bars=32, spb=12)
    parts = plan(tr, [
        ("intro", 8, "D | D | D | D | G | A | D | A"),
        ("A", 8, "D | A | G D | A | D | A | G D | A D"),
        ("B", 8, "Bm | A | G D | A | Bm | A | G D | A D"),
        ("fanfare", 2, "A | B7"),
        ("climax", 6, "E | B | A E | B E | A B | E A7"),
    ])
    tune = melody("""D5:2 A4:1 D5:2 F#5:1 A5:2 F#5:1 D5:1 E5:1 F#5:1 | E5:2 C#5:1 A4:2 C#5:1 E5:1 F#5:1 G5:1 A5:3 |
                     B5:2 G5:1 D5:2 G5:1 F#5:2 D5:1 A4:2 D5:1 | E5:1 F#5:1 G5:1 E5:1 C#5:1 B4:1 A4:3 r:3 |
                     D5:2 A4:1 D5:2 F#5:1 A5:2 F#5:1 D5:1 E5:1 F#5:1 | E5:2 C#5:1 A4:2 C#5:1 E5:1 F#5:1 G5:1 A5:3 |
                     B5:2 G5:1 D5:2 G5:1 F#5:2 D5:1 A4:2 D5:1 | E5:1 F#5:1 G5:1 E5:1 C#5:1 A4:1 D5:3 r:3""", 12)
    bpart = melody("""F#5:2 B5:1 B5:2 A5:1 B5:1 C#6:1 D6:1 B5:3 | A5:2 E5:1 C#5:2 E5:1 A5:1 G5:1 F#5:1 E5:3 |
                      G5:2 B5:1 D6:2 B5:1 A5:2 F#5:1 D5:2 F#5:1 | E5:1 G5:1 F#5:1 E5:1 D5:1 C#5:1 A4:1 B4:1 C#5:1 E5:3 |
                      F#5:2 B5:1 B5:2 A5:1 B5:1 C#6:1 D6:1 B5:3 | A5:2 E5:1 C#5:2 E5:1 A5:1 G5:1 F#5:1 E5:3 |
                      G5:2 B5:1 D6:2 B5:1 A5:2 F#5:1 D5:2 F#5:1 | E5:1 G5:1 F#5:1 E5:1 C#5:1 A4:1 D5:3 r:3""", 12)
    herald = melody("A4:1 A4:1 A4:1 D5:3 A4:2 D5:1 F#5:3 | D5:1 D5:1 D5:1 F#5:3 D5:2 F#5:1 A5:3", 12)
    call = melody("A4:1 D5:1 F#5:1 A5:3 F#5:2 A5:1 D6:3 | E5:3 E5:1 E5:1 E5:1 A5:6", 12)
    pickup = melody("r:9 A4:1 B4:1 C#5:1", 12)
    answers = melody("""r:12 | r:12 | r:12 | r:9 A4:1 C#5:1 E5:1 | r:12 | r:12 | r:12 | r:9 D5:1 F#5:1 A5:1""", 12)
    volley = melody("E5:1 E5:1 E5:1 A5:3 r:6 | F#5:1 F#5:1 F#5:1 B5:3 r:6", 12)
    volley_fife = melody("r:6 C#6:1 B5:1 A5:1 E6:3 | r:6 B5:1 A5:1 F#5:1 D#5:1 E5:1 F#5:1", 12)
    # the last stretch: the tune's second ending up in E, and a two-bar tag whose A7 leads back to the drop
    final = shift([n for n in tune if n.step >= 4 * 12], 2, -4 * 12) + shift(melody(
        """C#5:2 E5:1 A5:2 E5:1 D#5:2 F#5:1 B5:2 A5:1 |
           G#5:1 F#5:1 E5:1 B4:1 E5:1 G#5:1 A5:1 E5:1 C#5:1 A4:1 B4:1 C#5:1""", 12), 0, 4 * 12)

    def fife(m, sec):
        return ins.flute(m, sec, breath=0.05, vibrato=0.05)

    def recorder(m, sec):
        return ins.flute(m, sec, breath=0.1, vibrato=0.0)

    def trumpet(m, sec):
        return ins.brass(m, sec, bright=1.0, section=2, vibrato=0.05)

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.45, section=3)

    tabor = [ins.snare2(185.0, 0.45, 0.22, v) for v in range(3)]
    bodhran = [ins.tom(92.0, 0.45, v) for v in range(2)]
    tamb = [ins.jingles(0.14, 0.7, v) for v in range(3)]
    kick, clap = s.kick(0.8, 0.35), s.clap()

    # The intro: the lute alone, the heralds call the tournament open from the walls, the band gathers.
    tr.play("herald", 1, herald, trumpet, 0.55)
    tr.play("herald", 6, call, trumpet, 0.9)
    tr.play("lead", 7, pickup, fife)
    tr.add("fx", 6, 0, s.riser(tr.bar * 2), 0.35)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 38)  # D2 .. C#3: the theorbo's deep strings, heard on a phone
            notes = voicing(c, 55, 67, prev)
            prev = notes
            seconds = length * tr.step
            span = int(length)
            fifth = root + 7 if root + 7 <= 50 else root - 5
            # the lute: rolling triplet arpeggios
            ring = notes[:3] + [notes[0] + 12]
            pattern = (0, 2, 1, 3, 2, 1, 0, 2, 1, 3, 2, 1)
            for k in range(span):
                if name == "intro" and local < 3 and k % 3 != 0:
                    continue  # the lute starts alone, just on the beats
                gain = (1.0 if k % 3 == 0 else 0.7) * (0.55 if name == "intro" and local < 3 else 1.0)
                tr.add("lute", bar, step + k, ins.lute(ring[pattern[k % 12]], tr.step * 2.5, variant=k % 3), gain, 0.25)
            # the theorbo's bass
            if name == "intro":
                if local >= 3:
                    tr.add("bass", bar, step, ins.lute(root, tr.step * 5, variant=1), 0.8)
                    tr.add("bass", bar, step + 6, ins.lute(fifth, tr.step * 5, variant=2), 0.65)
            elif name == "fanfare":
                tr.add("bass", bar, 0, ins.lute(root, tr.step * 11, variant=0), 1.0)
            else:  # beats 1 and 3 in the A part, every beat (root, fifth) after that
                for st in range(0, span, 3):
                    pos = step + st
                    if name == "A" and pos % 6:
                        continue
                    m = root if (pos // 3) % 2 == 0 else fifth
                    tr.add("bass", bar, pos, ins.lute(m, tr.step * 2.8, variant=pos % 3), 1.0 if pos % 6 == 0 else 0.8)
            # the bagpipe drone: D and A, then E and B for the climax
            if name in ("intro", "A", "B") and not (name == "intro" and local < 2):
                if step == 0:
                    tr.add("drone", bar, 0, pipes(50, tr.bar), 0.5 + 0.1 * min(local, 5) if name == "intro" else 1.0, -0.2)
                    tr.add("drone", bar, 0, pipes(57, tr.bar), 0.4 + 0.08 * min(local, 5) if name == "intro" else 0.8, 0.2)
            elif name == "climax" and step == 0:
                tr.add("drone", bar, 0, pipes(52, tr.bar), 1.0, -0.2)
                tr.add("drone", bar, 0, pipes(59, tr.bar), 0.8, 0.2)
            # strings for the big finish
            if name in ("fanfare", "climax"):
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.15, bright=0.5), 1.0)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 3:
                    tr.drum("bodhran", bar, "X.....X.....", bodhran[0], 0.4 + 0.1 * (local - 3))
                if local >= 4:
                    tr.drum("tabor", bar, "x.xx.xx.xx.x", tabor[local % 3], 0.35 + 0.1 * (local - 4))
                    tr.drum("tamb", bar, "..x..x..x..x", tamb[local % 3], 0.5)
                if local == 6:
                    for k in range(12):
                        tr.add("timp", bar, k, ins.timpani(38, 0.5, 0.4), 0.25 + 0.03 * k)
                if local == 7:  # the drum roll into the drop
                    for k in range(12):
                        tr.add("tabor", bar, k, tabor[k % 3], 0.45 + 0.05 * k)
                        tr.add("tabor", bar, k + 0.5, tabor[(k + 1) % 3], 0.3 + 0.04 * k)
                    tr.add("timp", bar, 0, ins.timpani(45, 1.2, 0.8), 0.9)
                continue
            if name == "fanfare":  # the volley: timpani and the tabor roll under the trumpets' call
                for k in range(12):
                    tr.add("timp", bar, k, ins.timpani(45 if local == 0 else 47, 0.5, 0.4), 0.3 + 0.04 * k)
                    tr.add("tabor", bar, k, tabor[k % 3], 0.4 + 0.04 * k + 0.2 * local)
                tr.drum("bodhran", bar, "X.....X.....", bodhran[0], 1.0)
                tr.kick("kick", bar, "X.....X.....", kick, 0.9)
                if local == 0:
                    tr.add("cymbal", bar, 0, s.crash(), 1.0, -0.2)
                continue
            big = name == "climax"
            tr.drum("bodhran", bar, "X..x..X..x.." if not big else "X..x.xX..x.x", bodhran[local % 2], 1.0)
            tr.drum("tabor", bar, "X.xx.xX.xx.x" if name == "A" and local < 4 else "X.xxxxX.xxxx", tabor[local % 3], 0.85, 0.15)
            tr.drum("tamb", bar, "..x..x..x..x" if name == "A" else "x.xx.xx.xx.x", tamb[local % 3], 0.8, -0.3)
            tr.kick("kick", bar, "X.....X....." if not big else "X..X..X..X..", kick, 1.0)
            if name == "B" and local >= 4 or big:
                tr.drum("claps", bar, "...X.....X..", clap, 1.0, 0.05)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.3, -0.2)
            if big and local % 2 == 0:
                tr.add("timp", bar, 0, ins.timpani(40 if local != 4 else 45, 1.0, 0.9), 0.9)
            if name in ("A", "B") and local == part.bars - 1:  # a bodhran tumble into the next part
                for k in range(6, 12):
                    tr.add("bodhran", bar, k, bodhran[k % 2], 0.5 + 0.08 * (k - 6))

    tr.play("lead", 8, tune, fife)
    tr.play("harmony", 8, diatonic([n for n in tune if n.step >= 4 * 12], -2, 2), recorder)
    tr.play("brass", 8, answers, trumpet, 0.8)
    tr.play("lead", 16, bpart, fife)
    tr.play("harmony", 16, diatonic([n for n in bpart if n.step >= 4 * 12], -2, 2), recorder)
    tr.play("brass", 16, melody("""r:9 B4:1 D5:1 F#5:1 | r:9 C#5:1 E5:1 A5:1 | r:12 | r:9 A4:1 C#5:1 E5:1 |
                                  r:9 B4:1 D5:1 F#5:1 | r:9 C#5:1 E5:1 A5:1 | r:12 | r:12""", 12), trumpet, 0.85)
    tr.play("brass", 24, volley, trumpet)
    tr.play("lead", 24, volley_fife, fife)
    tr.play("lead", 26, final, fife)
    tr.play("brass", 26, final, trumpet, 0.9)
    tr.play("horns", 26, diatonic(final, -2, 4), horn, pan=-0.2)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.2, delay=0.06),
        "harmony": Bus(-13, reverb=0.2),
        "brass": Bus(-8, reverb=0.22),
        "herald": Bus(-9, reverb=0.45),
        "horns": Bus(-14, reverb=0.25),
        "lute": Bus(-11, reverb=0.15),
        "bass": Bus(-10, reverb=0.08),
        "drone": Bus(-17, reverb=0.2),
        "pad": Bus(-16, reverb=0.3),
        "tabor": Bus(-13, reverb=0.12),
        "bodhran": Bus(-11, drive=1.3, reverb=0.1),
        "kick": Bus(-14, drive=1.3),
        "tamb": Bus(-20, eq=(("lp", 8500),)),
        "claps": Bus(-16, reverb=0.15),
        "timp": Bus(-13, reverb=0.25),
        "cymbal": Bus(-21, eq=(("lp", 9000),)),
        "fx": Bus(-17, reverb=0.3),
    }, reverb_decay=1.8, reverb_tone=5500, delay_time=tr.beat / 3 * 2, delay_feedback=0.28)
    return finish(tr, mix), tr


SONG = Song("ArrowAmbush", "Archer's Jig", 120, 8, 32, archers_jig)
