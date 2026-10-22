"""Quicksand Caravan: the round song for SinkingSands (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


@lru_cache(maxsize=None)
def zill(variant: int = 0):
    """Finger cymbals: two little bronze cups struck together, a bright 'ting' that rings on."""
    n = s.samples(1.0)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(31 + variant)
    out = np.zeros(n)
    for f, a, d in ((2630.0, 1.0, 0.45), (2652.0, 0.8, 0.4), (3940.0, 0.5, 0.3), (5310.0, 0.25, 0.18)):
        out += a * np.sin(2 * np.pi * f * (1 + 0.003 * variant) * t + rng.uniform(0, 6)) * np.exp(-t / d)
    click = s.bandpass(rng.uniform(-1, 1, n), 1800, 6000) * np.exp(-t / 0.002) * 0.6
    return ins.normalize(ins.eq(out + click, ("lp", 7000), ("hp", 1500)))


@lru_cache(maxsize=None)
def mizmar(m: float, sec: float):
    """A mizmar (the folk shawm): a loud, nasal double reed for the last dig."""
    n = s.samples(sec + 0.1)
    t = np.arange(n) / s.SR
    pitch = m - 0.4 * np.exp(-t / 0.03) + 0.14 * np.clip((t - 0.18) / 0.25, 0, 1) * np.sin(2 * np.pi * 5.6 * t)
    f = s.midi_hz(pitch)
    tone = s.square(f, n, 0.32) * 0.55 + s.saw(f, n) * 0.45
    tone = ins.formant(tone, [(1150.0, 7, 2.0), (2500.0, 4, 2.5), (640.0, 3, 1.5)])
    tone = ins.eq(tone, ("hp", 280), ("lp", 4200), ("lp", 5600))
    return ins.normalize(tone * ins.env(n, 0.025, 0.3, 0.85, 0.08, gate=sec))


@lru_cache(maxsize=None)
def qanun(m: float, sec: float, variant: int = 0):
    """The qanun (a plucked zither): bright metal strings, for glittering runs."""
    tone = ins.ks(m, sec + 0.6, bright=0.78, decay=1.8, pick=0.12, soft=0.05, variant=variant)
    tone = ins.formant(tone, [(850.0, 3, 1.4), (2400.0, 3, 2.0)])
    return ins.normalize(ins.eq(tone, ("hp", 220), ("lp", 7000)))


def sinking_sands():
    """Quicksand Caravan (120 bpm, E Hijaz): a treasure dive on a desert mesa. An oud riff and a breathy
    ney over darbuka (doum, tek and ka), riq, finger cymbals and handclaps; a swirling break as the Sand
    Kings stir the sand, a GOLDEN IDOL fanfare (brass, choir and a glittering qanun) just as the idol
    drops (23 s in), then up to F Hijaz for the last dig, whose closing F falls back into the drop."""
    tr = Track(bpm=120, bars=36)
    parts = plan(tr, [
        ("intro", 8, "E | E | E | E | E | E | F | E"),
        ("A", 8, "E F | Am E | Dm E | F E | E Am | E | F E | Dm E"),
        ("swirl", 4, "Am | Am | Dm | E"),
        ("idol", 8, "Am | G | F | E | Am | G | F | E"),
        ("climax", 8, "F Gb | Bbm F | Ebm F | Gb F | F Bbm | F | Gb F | Ebm F"),
    ])
    theme = melody("""E5:3 F5:1 G#5:4 F5:3 E5:1 F5:4 | E5:3 D5:1 C5:2 D5:2 E5:8 |
                      A5:3 G#5:1 F5:4 G#5:3 F5:1 E5:4 | F5:3 E5:1 D5:2 C5:2 B4:8 |
                      E5:3 F5:1 G#5:4 A5:3 B5:1 C6:4 | B5:3 A5:1 G#5:2 F5:2 G#5:8 |
                      C6:3 B5:1 A5:4 G#5:3 F5:1 E5:4 | F5:3 E5:1 F5:2 G#5:2 E5:8""")
    taqsim = melody("""r:4 B4:10 C5:1 B4:1 | A4:4 G#4:4 F4:2 G#4:2 E4:4 | E4:12 r:4 |
                       r:4 E5:6 F5:2 E5:2 D5:2 | C5:4 D5:2 C5:2 B4:8 | C5:4 A4:4 F5:6 E5:2 | G#5:12 r:4""")
    answers = melody("""r:16 | r:10 E4:1 F4:1 G#4:1 B4:1 D5:1 E5:1 | r:16 | r:10 G#4:1 A4:1 B4:1 C5:1 D5:1 E5:1 |
                        r:16 | r:10 B4:1 C5:1 D5:1 E5:1 F5:1 G#5:1 | r:16 | r:8 E5:1 D5:1 C5:1 B4:1 A4:1 G#4:1 F4:1 E4:1""")
    runs = melody("""r:8 E5:1 F5:1 G#5:1 A5:1 B5:1 C6:1 B5:1 A5:1 | C6:6 B5:1 A5:1 G#5:1 A5:1 B5:1 C6:1 E6:4 |
                     r:8 F5:1 G#5:1 A5:1 B5:1 C6:1 D6:1 C6:1 B5:1 | A5:4 G#5:2 F5:2 E5:2 F5:2 G#5:4""")
    swirl_line = melody("A3:8 C4:8 | E4:8 C4:8 | D4:8 F4:8 | G#3:8 B3:8")
    fanfare = melody("""A4:3 B4:1 C5:4 E5:8 | D5:3 C5:1 B4:4 G4:8 | C5:3 B4:1 A4:4 F4:4 A4:4 | G#4:12 B4:4 |
                        A4:3 B4:1 C5:4 E5:4 A5:4 | G5:3 F5:1 D5:4 B4:4 G4:4 | A5:3 G5:1 F5:4 C5:4 A4:4 | G#4:4 B4:4 E5:8""")
    descant = melody("E6:12 F6:2 E6:2 | D6:12 E6:2 D6:2 | C6:12 D6:2 C6:2 | B5:12 r:4")
    riff = melody("E3:2 E4:1 E3:1 F3:2 E3:1 D3:1 E3:2 E4:1 E3:1 F3:2 E3:1 D3:1")
    turn = melody("E3:2 E4:1 E3:1 F3:2 E3:1 D3:1 E3:1 F3:1 G#3:1 A3:1 B3:2 G#3:1 F3:1")  # every fourth bar

    def ney(m, sec):
        return ins.flute(m, sec, breath=0.16, vibrato=0.1)

    def ney_free(m, sec):  # the intro's solo: long notes sigh down at the end
        return ins.flute(m, sec, breath=0.18, vibrato=0.12, fall=0.5 if sec > 1.1 else 0.0)

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.8, section=3)

    def play_riff(bar, transpose=0, gain=1.0, fill=False):
        for k, n in enumerate(turn if fill else riff):
            accent = 1.0 if n.step % 8 == 0 else (0.85 if n.step % 2 == 0 else 0.7)
            tr.add("oud", bar, n.step, ins.oud(n.midi + transpose, n.length * tr.step * 1.2, variant=k % 4), gain * accent, 0.12)

    doum = [ins.doum(84.0), ins.doum(90.0)]
    tek = [ins.tek(1.0, v) for v in range(3)]
    ka = [ins.tek(0.45, v) for v in range(2)]
    riq = [ins.jingles(0.16, 0.8, v) for v in range(3)]
    kick, clap = s.kick(0.9, 0.4), s.clap()
    boom = ins.taiko(70.0, 1.4, 0.6)

    # The intro: wind over the dunes, a drone and the ney's free solo; the oud and the drums gather.
    tr.add("fx", 0, 0, ins.whoosh(4.5, True), 0.5, -0.3)
    tr.add("fx", 2, 4, ins.whoosh(4.0, False), 0.45, 0.3)
    for bar, step, v in ((0, 8, 0), (2, 8, 1), (4, 0, 2), (6, 0, 0)):
        tr.add("zill", bar, step, zill(v), 0.8, 0.35)
    tr.add("pad", 0, 0, ins.strings((52, 59), tr.bar * 6, attack=3.0, bright=0.2, release=1.0), 0.7)
    tr.play("lead", 1, taqsim, ney_free, 0.6)
    tr.add("oud", 3, 0, ins.oud(52, 1.2, slide=1.0), 0.75, 0.12)
    tr.add("oud", 3, 10, ins.oud(53, 0.25, variant=1), 0.6, 0.12)
    tr.add("oud", 3, 12, ins.oud(52, 0.5, variant=2), 0.7, 0.12)
    tr.add("fx", 6, 0, s.riser(tr.bar * 2), 0.45)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 28) + 12  # E2 .. D#3: phone speakers hear it
            notes = voicing(c, 57, 71, prev)
            prev = notes
            seconds = length * tr.step
            span = int(length)
            # bass
            if name == "intro":
                if local >= 5:
                    for k in range(0, span, 8):
                        tr.add("bass", bar, step + k, ins.synth_bass(root, tr.step * 6, cutoff=500, env_amt=600, sub=0.5), 0.6 + 0.15 * (local - 5))
            elif name == "A":
                for k in range(0, span, 8):
                    tr.add("bass", bar, step + k, ins.synth_bass(root, tr.step * 2.6, cutoff=700, env_amt=1100, sub=0.45), 1.0)
                    tr.add("bass", bar, step + k + 3, ins.synth_bass(root, tr.step * 0.9, cutoff=700, env_amt=900, sub=0.45), 0.55)
                    tr.add("bass", bar, step + k + 6, ins.synth_bass(root + 12, tr.step * 1.6, cutoff=700, env_amt=1100, sub=0.3), 0.7)
            elif name == "swirl":
                tr.add("bass", bar, 0, ins.synth_bass(root, tr.step * 14, cutoff=450, env_amt=500, sub=0.6), 1.0)
                tr.add("bass", bar, 14, ins.synth_bass(root + 12, tr.step * 1.5, cutoff=600, env_amt=800, sub=0.3), 0.6)
            elif name == "idol":
                fifth = root + 7 if root + 7 <= 52 else root - 5
                for st, m, g, ln in ((0, root, 1.0, 2.6), (3, root, 0.55, 0.9), (6, fifth, 0.75, 1.6),
                                     (8, root, 0.95, 2.6), (11, root, 0.55, 0.9), (14, root + 12, 0.75, 1.6)):
                    tr.add("bass", bar, st, ins.synth_bass(m, tr.step * ln, cutoff=750, env_amt=1200, sub=0.45), g)
            else:  # climax: driving eighths, the octave popping on the off-beats
                for k in range(0, span, 2):
                    up = 12 if (k // 2) % 2 else 0
                    tr.add("bass", bar, step + k, ins.synth_bass(root + up, tr.step * 1.6, cutoff=800, env_amt=1300, sub=0.4), 1.0 if up == 0 else 0.75)
            # pads
            if name == "intro" and local >= 6:
                tr.add("pad", bar, step, ins.strings(tuple(n - 12 for n in notes), seconds, attack=0.8, bright=0.25), 0.9)
            elif name == "swirl":
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.4, bright=0.35), 1.0)
            elif name in ("idol", "climax"):
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.2, bright=0.45), 1.0)
                tr.add("choir", bar, step, ins.choir(tuple(notes[:3]), seconds, "ah", attack=0.25), 1.0)
            # the oud
            if name == "idol":
                ring = voicing(c, 50, 64)[:3]
                ring = ring + [ring[0] + 12]
                for k, (st, idx) in enumerate(((0, 0), (2, 3), (3, 1), (4, 2), (6, 1), (8, 0), (10, 3), (11, 1), (12, 2), (14, 1))):
                    tr.add("oud", bar, st, ins.oud(ring[idx], tr.step * 2, variant=k % 4), 0.9 if st % 4 == 0 else 0.7, 0.12)
                if local < 4:  # the idol's glitter: the qanun runs up and down the chord
                    up = voicing(c, 69, 90, size=5)
                    for k in range(16):
                        tr.add("qanun", bar, k, qanun(up[(0, 1, 2, 3, 4, 3, 2, 1)[k % 8]], 0.3, variant=k % 3), 0.9 if k % 4 == 0 else 0.65, 0.35)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    play_riff(bar, 0, 0.55 + 0.12 * (local - 4))
                    tr.drum("doum", bar, "X.......X......." if local < 6 else "X.....x.X.......", doum[0], 0.45 + 0.12 * (local - 4))
                    tr.drum("riq", bar, "x.x.x.x.x.x.x.x.", riq[local % 3], 0.35 + 0.1 * (local - 4), 0.3)
                if local >= 5:
                    tr.drum("tek", bar, "..x...x.....x...", tek[local % 3], 0.45 + 0.15 * (local - 5), 0.1)
                if local == 7:  # tak-a-tak-a-TAK, a breath, and the drop
                    for k in range(8, 15):
                        tr.add("tek", bar, k, tek[k % 3] if k % 2 == 0 else ka[k % 2], 0.4 + 0.08 * (k - 8), 0.1)
                    tr.add("doum", bar, 14, doum[1], 0.9)
                continue
            if name == "A":
                play_riff(bar, fill=local % 4 == 3)
                tr.drum("doum", bar, "X.......X......." if local % 4 != 3 else "X.......X.....x.", doum[local % 2], 1.0)
                tr.drum("tek", bar, "..x...x.....x...", tek[local % 3], 0.9, 0.1)
                tr.drum("ka", bar, "....o..o..o...oo", ka[local % 2], 0.8, -0.15)
                tr.drum("riq", bar, "x.x.X.x.x.x.X.x.", riq[local % 3], 0.8, 0.3)
                tr.kick("kick", bar, "X.......X.......", kick, 1.0)
                if local == 0:
                    tr.add("cymbal", bar, 0, s.crash(), 1.4, 0.2)
                    tr.add("zill", bar, 0, zill(1), 0.9, -0.35)
                if local == 4:
                    tr.add("zill", bar, 0, zill(2), 0.7, 0.35)
                continue
            if name == "swirl":  # the Kings stir the sand: a galloping malfuf, the sand whooshing round
                tr.drum("doum", bar, "X.......X.......", doum[0], 1.0)
                tr.drum("tek", bar, "...x..x....x..x.", tek[local % 3], 0.85, 0.1)
                tr.drum("ka", bar, ".o..o..o.o..o..o", ka[local % 2], 0.7, -0.15)
                tr.drum("riq", bar, "x..x..x.x..x..x.", riq[local % 3], 0.8, 0.3)
                tr.kick("kick", bar, "X.......X.......", kick, 0.85)
                tr.add("fx", bar, 0, ins.whoosh(tr.bar * 0.9, local % 2 == 0), 0.55, -0.5 if local % 2 == 0 else 0.5)
                if local == 3:
                    for k in range(8, 16):
                        tr.add("doum", bar, k, doum[k % 2], 0.45 + 0.07 * (k - 8))
                        tr.add("tek", bar, k + 0.5, tek[k % 3], 0.35 + 0.06 * (k - 8), 0.1)
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.4)
                continue
            big = name == "climax"
            tr.drum("doum", bar, "X.......X.....x." if big else "X.......X.......", doum[local % 2], 1.0)
            tr.drum("tek", bar, "..x...x.....x.x." if big else "..x...x.....x...", tek[local % 3], 0.9, 0.1)
            tr.drum("ka", bar, "o.oo.o.oo.o.oo.o" if big else "....o..o..o...oo", ka[local % 2], 0.75, -0.15)
            tr.drum("riq", bar, "xoxoXoxoxoxoXoxo", riq[local % 3], 0.8, 0.3)
            tr.drum("claps", bar, "....X.......X...", clap, 1.0, -0.05)
            tr.kick("kick", bar, "X...X...X...X..." if big else "X.......X.......", kick, 1.0)
            if local % 4 == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.3 if local == 0 else 0.9, 0.2)
                tr.add("zill", bar, 0, zill(local % 3), 0.8, -0.35)
            if local == 0:
                tr.add("fx", bar, 0, ins.gong(4.0, 98.0 if name == "idol" else 104.0), 1.0)
            if local == 0 or name == "idol":
                tr.add("doum", bar, 0, boom, 0.9 if local == 0 else 0.55)
            if name == "idol" and local % 2 == 0:  # golden glints off the idol
                c = part.at(bar)[0][2]
                for k, m in enumerate(voicing(c, 76, 98, size=5)):
                    tr.add("sparkle", bar, 2 + k * 0.5, ins.glock(m, 0.5), 0.7, 0.3 - 0.15 * k)
            if name == "idol" and local == 7:
                for k in range(12, 16):
                    tr.add("doum", bar, k, doum[k % 2], 0.6 + 0.1 * (k - 12))

    for k, n in enumerate(answers):
        tr.add("qanun", 8, n.step, qanun(n.midi, 0.25, variant=k % 3), 0.85, 0.35)
    tr.play("lead", 8, theme, ney)
    tr.play("lead", 16, runs, ney, 0.9)
    tremolo(tr, "oud", 16, swirl_line, lambda m, sec: ins.oud(m, sec), 1, 0.9, 0.12)
    tr.play("brass", 20, fanfare, horn)
    tr.play("lead", 24, descant, ney, 0.8)
    tr.play("lead", 28, shift(theme, 1), ney)
    tr.play("lead2", 28, shift(theme, 1 - 12), mizmar)
    for bar in range(28, 36):
        play_riff(bar, 1, fill=bar % 4 == 3)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.22, delay=0.08),
        "lead2": Bus(-12, reverb=0.18),
        "brass": Bus(-6, reverb=0.2),
        "oud": Bus(-9, reverb=0.12),
        "qanun": Bus(-14, reverb=0.2, delay=0.12),
        "bass": Bus(-9),
        "pad": Bus(-15, reverb=0.3),
        "choir": Bus(-15, reverb=0.35),
        "doum": Bus(-9, drive=1.3, reverb=0.08),
        "tek": Bus(-13, reverb=0.08),
        "ka": Bus(-18),
        "riq": Bus(-19, eq=(("lp", 8500),)),
        "claps": Bus(-14, reverb=0.15),
        "kick": Bus(-12, drive=1.3),
        "cymbal": Bus(-20, eq=(("lp", 9000),)),
        "zill": Bus(-19, reverb=0.2),
        "sparkle": Bus(-17, reverb=0.3, delay=0.15),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=1.9, reverb_tone=5000, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("SinkingSands", "Quicksand Caravan", 120, 8, 36, sinking_sands)
