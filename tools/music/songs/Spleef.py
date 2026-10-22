"""Thin Ice: the round song for Spleef (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


@lru_cache(maxsize=None)
def chip(m: float, sec: float, width: float = 0.25, vib: float = 0.12):
    """A chiptune pulse lead: a square wave with a late vibrato, its fizz filtered off for phones."""
    n = s.samples(sec + 0.05)
    t = np.arange(n) / s.SR
    pitch = m + vib * np.clip((t - 0.12) / 0.1, 0, 1) * np.sin(2 * np.pi * 6.0 * t)
    tone = s.square(s.midi_hz(pitch), n, width)
    tone = ins.eq(tone, ("lp", 5000), ("lp", 7000), ("hp", 180))
    return ins.normalize(tone * ins.env(n, 0.003, 0.15, 0.7, 0.03, gate=sec))


@lru_cache(maxsize=None)
def chip_bass(m: float, sec: float):
    """A pulse bass: a square wave with a round body, rounded off on top."""
    n = s.samples(sec + 0.03)
    f = s.midi_hz(m)
    tone = s.square(f, n, 0.5) * 0.7 + s.sine(f, n) * 0.5
    tone = ins.eq(tone, ("lp", 1600), ("hp", 50))
    return ins.normalize(ins.drive(tone * ins.env(n, 0.002, 0.12, 0.75, 0.02, gate=sec), 1.3))


@lru_cache(maxsize=None)
def ice_crack(variant: int = 0):
    """The ice giving way: a sharp snap, a falling glassy ping and a low boom."""
    n = s.samples(1.3)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(70 + variant)
    snap = ins.eq(rng.uniform(-1, 1, n) * np.exp(-t / 0.01), ("hp", 700), ("lp", 7000))
    ping = sum(np.sin(2 * np.pi * f * t * (1 - 0.18 * t)) * np.exp(-t / d) for f, d in ((2150.0, 0.3), (3050.0, 0.18), (1420.0, 0.45)))
    boom = np.sin(2 * np.pi * (52 + 70 * np.exp(-t / 0.05)) * t) * np.exp(-t / 0.4)
    return ins.normalize(ins.eq(snap + ping * 0.25 + boom * 0.9, ("lp", 7500)))


@lru_cache(maxsize=None)


def thin_ice():
    """Thin Ice (128 bpm, C major, then C minor): three floors of snow blocks over an icy pool. A bouncy
    chiptune square lead and arpeggios over real drums, a pulse bass and icy bells; when the floors
    start cracking (40% of the round, 30 s in) the tune turns to C minor and drives harder, a galloping
    second theme climbs, and the finale doubles everything for the fight over the last few blocks,
    ending with the round (75 s)."""
    tr = Track(bpm=128, bars=48)
    parts = plan(tr, [
        ("intro", 8, "C | Am | F | G | C | Am | F | G"),
        ("A", 8, "C | G | Am | F G | C | G | F G | C"),
        ("B", 8, "Am | F | C | G | Am | F | Dm | G7"),
        ("crack", 8, "Cm | G | Ab | Fm G | Cm | G | Fm G | Cm"),
        ("gallop", 8, "Cm | Ab | Eb | Bb | Cm | Ab | Fm | G7"),
        ("finale", 8, "Cm | G | Ab | Fm G | Cm | G | Fm G | Cm"),
    ])
    theme = melody("""E5:1 G5:1 C6:2 B5:1 C6:1 G5:2 E5:2 G5:2 A5:2 G5:2 | D5:1 G5:1 B5:2 A5:1 B5:1 G5:2 D5:2 G5:2 A5:2 B5:2 |
                      C6:3 B5:1 A5:2 E5:2 A5:2 B5:2 C6:4 | A5:2 G5:2 F5:2 C5:2 D5:4 G4:4 |
                      E5:1 G5:1 C6:2 B5:1 C6:1 G5:2 E5:2 G5:2 A5:2 G5:2 | D5:1 G5:1 B5:2 A5:1 B5:1 G5:2 D5:2 G5:2 A5:2 B5:2 |
                      F5:1 A5:1 C6:2 B5:1 C6:1 A5:2 G5:1 B5:1 D6:2 C6:1 D6:1 B5:2 | C6:4 G5:2 E5:2 C5:4 r:4""")
    second = melody("""A5:3 A5:1 C6:2 A5:2 E6:3 D6:1 C6:2 B5:2 | A5:3 A5:1 C6:2 A5:2 F6:3 E6:1 C6:2 A5:2 |
                       G5:3 G5:1 C6:2 G5:2 E6:3 D6:1 C6:2 G5:2 | B5:3 B5:1 D6:2 B5:2 G6:4 r:4 |
                       A5:3 A5:1 C6:2 A5:2 E6:3 D6:1 C6:2 B5:2 | A5:3 A5:1 C6:2 A5:2 F6:3 E6:1 C6:2 A5:2 |
                       F5:3 F5:1 A5:2 F5:2 D6:3 C6:1 A5:2 F5:2 | G5:2 B5:2 D6:2 G6:2 F6:2 D6:2 B5:2 G5:2""")
    cracked = melody("""Eb5:1 G5:1 C6:2 B5:1 C6:1 G5:2 Eb5:2 G5:2 Ab5:2 G5:2 | D5:1 G5:1 B5:2 A5:1 B5:1 G5:2 D5:2 G5:2 A5:2 B5:2 |
                        C6:3 Bb5:1 Ab5:2 Eb5:2 Ab5:2 Bb5:2 C6:4 | Ab5:2 G5:2 F5:2 C5:2 D5:4 G4:4 |
                        Eb5:1 G5:1 C6:2 B5:1 C6:1 G5:2 Eb5:2 G5:2 Ab5:2 G5:2 | D5:1 G5:1 B5:2 A5:1 B5:1 G5:2 D5:2 G5:2 A5:2 B5:2 |
                        F5:1 Ab5:1 C6:2 B5:1 C6:1 Ab5:2 G5:1 B5:1 D6:2 C6:1 D6:1 B5:2 | C6:4 G5:2 Eb5:2 C5:4 r:4""")
    gallop = melody("""C5:3 C5:1 Eb5:2 C5:2 G5:3 F5:1 Eb5:2 D5:2 | C5:3 C5:1 Eb5:2 C5:2 Ab5:3 G5:1 Eb5:2 C5:2 |
                       Bb4:3 Bb4:1 Eb5:2 Bb4:2 G5:3 F5:1 Eb5:2 Bb4:2 | D5:3 D5:1 F5:2 D5:2 Bb5:4 r:4 |
                       C5:3 C5:1 Eb5:2 C5:2 G5:3 F5:1 Eb5:2 D5:2 | C5:3 C5:1 Eb5:2 C5:2 Ab5:3 G5:1 Eb5:2 C5:2 |
                       Ab4:3 Ab4:1 C5:2 Ab4:2 F5:3 Eb5:1 C5:2 Ab4:2 | G4:2 B4:2 D5:2 G5:2 F5:2 D5:2 B4:2 G4:2""")

    def lead(m, sec):
        return chip(m, sec, 0.25, 0.12)

    def lead_wide(m, sec):  # the second chip voice: a fuller 50% square, an octave below once the floors crack
        return chip(m, sec, 0.5, 0.08)

    kick, hat_c, hat_o = s.kick(1.1, 0.4), s.hat(False), s.hat(True)
    snare = [ins.snare2(210.0, 0.9, 0.25, v) for v in range(3)]
    toms = [ins.tom(p, 0.4) for p in (100.0, 135.0, 175.0)]
    ride = ins.ride(1.0, 0.5)

    # The intro: wind across the crater, ice twinkling, the arpeggio waking up, the drums gathering.
    tr.add("fx", 0, 0, ins.whoosh(tr.bar * 3, True), 0.25, -0.2)
    tr.add("fx", 3, 0, ins.whoosh(tr.bar * 2, False), 0.35, 0.3)
    rng = np.random.default_rng(12)
    for bar in range(4):
        for k in sorted(rng.choice(16, size=3, replace=False)):
            tr.add("bells", bar, k, ins.celesta(int(rng.choice([84, 86, 88, 91, 93, 96])), 0.6), 0.5 + 0.1 * bar, float(rng.uniform(-0.5, 0.5)))
    tr.play("bells", 4, [n for n in theme if n.step < 32], lambda m, sec: ins.glock(m, 0.5), 0.8)
    tr.add("fx", 6, 0, s.riser(tr.bar * 2), 0.4)

    prev = None
    for part in parts:
        name = part.name
        minor = name in ("crack", "gallop", "finale")
        for bar, step, length, c in part.changes:
            local = bar - part.first
            step = int(round(step))
            span = int(length)
            root = bass_note(c, 36)  # C2 .. B2
            notes = voicing(c, 60, 72, prev)
            prev = notes
            seconds = length * tr.step
            # the arpeggiator: the chord's tones racing up in sixteenths
            up = voicing(c, 72, 88, size=4)
            arp = (0, 1, 2, 3, 2, 1, 0, 1) if not minor else (0, 1, 2, 3, 0, 1, 2, 3)
            if not (name == "intro" and local < 2):
                for k in range(span):
                    gain = (0.35 + 0.1 * local) if name == "intro" else (1.0 if k % 4 == 0 else 0.75)
                    tr.add("arp", bar, step + k, chip(up[arp[k % 8]], tr.step * 0.9, 0.125, 0.0), gain, 0.3 if k % 2 else -0.3)
            # bass
            if name == "intro":
                if local >= 6:
                    for k in range(0, span, 4):
                        tr.add("bass", bar, step + k, chip_bass(root, tr.step * 3), 0.8)
            elif name == "A":  # the blocky octave bounce
                for k in range(0, span, 2):
                    tr.add("bass", bar, step + k, chip_bass(root + (12 if (k // 2) % 2 else 0), tr.step * 1.6), 1.0 if k % 4 == 0 else 0.8)
            elif name == "B":  # a skipping 3-3-2
                for k, ln in ((0, 2.5), (3, 2.5), (6, 1.6), (8, 2.5), (11, 2.5), (14, 1.6)):
                    if k < span:
                        tr.add("bass", bar, step + k, chip_bass(root + (12 if k in (6, 14) else 0), tr.step * ln), 1.0 if k in (0, 8) else 0.85)
            else:  # driving eighths for the cracking floors, the octave popping in the finale
                for k in range(0, span, 2):
                    pop = name == "finale" and (k // 2) % 2 == 1
                    tr.add("bass", bar, step + k, chip_bass(root + (12 if pop else 0), tr.step * 1.7), 1.0 if k % 4 == 0 else 0.85)
            # pads: an icy choir in the intro, strings when the floors crack
            if name == "intro":
                tr.add("pad", bar, step, ins.choir(tuple(notes[:3]), seconds, "oo", attack=0.6), 0.5 + 0.08 * local)
            elif name == "B":
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.3, bright=0.4), 0.6)
            elif minor:
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.1 if name != "crack" else 0.25, bright=0.5), 1.0)
                if name == "finale":
                    tr.add("choir", bar, step, ins.choir(tuple(n - 12 for n in notes[:3]), seconds, "ah", attack=0.2), 1.0)
            # the counter-voice: a gallop on the chord in the finale
            if name == "finale":
                lo = voicing(c, 55, 67)
                for k, idx, ln in ((0, 0, 3), (3, 0, 1), (4, 1, 2), (6, 0, 2), (8, 2, 3), (11, 1, 1), (12, 0, 2), (14, 1, 2)):
                    if k < span:
                        tr.add("counter", bar, step + k, lead_wide(lo[idx], tr.step * ln * 0.9), 0.9 if k % 4 == 0 else 0.7, -0.25)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 4:
                    tr.kick("kick", bar, "X.......X......." if local < 6 else "X.......X.X.....", kick, 0.55 + 0.1 * (local - 4))
                if local >= 5:
                    tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", hat_c, 0.5 + 0.1 * (local - 5), 0.2)
                if local >= 6:
                    tr.drum("snare", bar, "....X.......X...", snare[0], 0.6 + 0.2 * (local - 6))
                if local == 7:  # the fill into the drop
                    for k, st in enumerate(range(8, 16)):
                        tr.add("snare", bar, st, snare[k % 3], 0.4 + 0.07 * k)
                        if st % 2 == 0:
                            tr.add("toms", bar, st, toms[2 - k // 3], 0.8, 0.3 - 0.2 * (k // 3))
                continue
            minor = name in ("crack", "gallop", "finale")
            if name == "A":
                tr.kick("kick", bar, "X.......X.X....." if local % 2 == 0 else "X.....X...X.....", kick, 1.0)
                tr.drum("snare", bar, "....X.......X...", snare[local % 3], 1.0, 0.05)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", hat_c, 0.8, 0.2)
                tr.drum("hats", bar, "..............x.", hat_o, 0.6, 0.2)
            elif name == "B":
                tr.kick("kick", bar, "X..X....X..X....", kick, 1.0)
                tr.drum("snare", bar, "....X.......X..o", snare[local % 3], 1.0, 0.05)
                tr.drum("hats", bar, "..x...x...x...x.", hat_o, 0.7, 0.2)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", hat_c, 0.6, -0.2)
            else:
                tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
                tr.drum("snare", bar, "....X.......X..." if name != "finale" else "....X.......X.oo", snare[local % 3], 1.0, 0.05)
                tr.drum("hats", bar, "xxxxxxxxxxxxxxxx", hat_c, 0.7, 0.2)
                tr.drum("hats", bar, "..x...x...x...x.", hat_o, 0.6, -0.2)
                if name == "finale":
                    tr.drum("ride", bar, "x...x...x...x...", ride, 0.7, -0.3)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.4, 0.2)
            if local % 4 == 3 or (name == "finale" and local % 2 == 1):  # tom fills at the phrase ends
                for k, st in enumerate((12, 13, 14, 15)):
                    tr.add("toms", bar, st, toms[2 - k * 3 // 4], 0.85, 0.3 - 0.2 * k)
            if name == "B" and local == 7:  # the floors are about to give: a riser and a snare roll
                for k in range(8, 16):
                    tr.add("snare", bar, k, snare[k % 3], 0.4 + 0.07 * (k - 8))
                tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.45)
            if name == "crack" and local == 0:
                tr.add("fx", bar, 0, ice_crack(0), 1.0)
            if name == "gallop" and local == 0:
                tr.add("fx", bar, 0, ice_crack(1), 0.7, -0.3)
            if name == "finale" and local == 7:  # the last stand: everything rolls into the final hit
                for k in range(16):
                    tr.add("snare", bar, k, snare[k % 3], 0.35 + 0.04 * k)
            if minor and local % 2 == 0 and name != "finale":  # the ice ringing under the floors
                top = voicing(part.at(bar)[-1][2], 79, 91)[-1]
                tr.add("bells", bar, 8, ins.vibes(top, 1.2), 0.5, 0.4 - 0.1 * local)

    tr.play("lead", 8, theme, lead)
    tr.play("lead2", 8, shift([n for n in theme if n.step >= 4 * 16], 12), lambda m, sec: ins.glock(m, 0.4), 0.7)
    tr.play("lead", 16, second, lead)
    tr.play("lead2", 16, second, lambda m, sec: ins.celesta(m, 0.5), 0.35)
    tr.play("lead", 24, cracked, lead)
    tr.play("lead2", 24, shift(cracked, -12), lead_wide, 0.6)
    tr.play("lead", 32, gallop, lead)
    tr.play("lead2", 32, shift(gallop, 12), lambda m, sec: ins.glock(m, 0.4), 0.6)
    tr.play("lead", 40, cracked, lead)
    tr.play("lead2", 40, shift(cracked, -12), lead_wide, 0.8)
    tr.play("lead2", 40, shift(cracked, 12), lambda m, sec: ins.glock(m, 0.4), 0.5)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.15, delay=0.12),
        "lead2": Bus(-13, reverb=0.2),
        "counter": Bus(-13, reverb=0.12),
        "arp": Bus(-16, pump=0.3, delay=0.1),
        "bass": Bus(-8, pump=0.25),
        "pad": Bus(-15, pump=0.25, reverb=0.3),
        "choir": Bus(-16, reverb=0.35),
        "bells": Bus(-15, reverb=0.35, delay=0.2),
        "kick": Bus(-9, drive=1.4, eq=(("hp", 50), ("hp", 50), ("peak", 110, 3, 1.2))),
        "snare": Bus(-11, reverb=0.15),
        "toms": Bus(-13, reverb=0.15),
        "hats": Bus(-18, eq=(("lp", 9000),)),
        "ride": Bus(-21, eq=(("lp", 9000),)),
        "cymbal": Bus(-20, eq=(("lp", 9000),)),
        "fx": Bus(-12, reverb=0.3),
    }, reverb_decay=1.8, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.3, pump_release=0.18)
    return finish(tr, mix), tr


SONG = Song("Spleef", "Thin Ice", 128, 8, 48, thin_ice)
