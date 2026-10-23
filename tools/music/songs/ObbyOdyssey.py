"""Bounce to the Crown: the round song for ObbyOdyssey (see songkit.py for the rules every song keeps).

Owner: "Make the custom song for it" (for Obby Odyssey, the obby race to a gold crown)."""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def obby_odyssey():
    """Bounce to the Crown (150 bpm, F major): a bubblegum electro-pop run up an obby. A hook that leaps
    up in octaves like a jump from block to block, a slap-bass bounce, bright plucks, glockenspiel
    sparkle and big supersaw chords in the chorus; slide whistles take off on the launch pads,
    jaw-harp boings and water bloops in the bounce break, then up a whole step to G for the last
    chorus, and a turn back to F that leads into the drop when the round loops it."""
    tr = Track(bpm=150, bars=53)
    parts = plan(tr, [
        ("intro", 9, "F | F | Dm | Dm | Bb | Bb | C | C | C7"),
        ("A", 8, "F | C | Dm | Bb | F | C | Bb | C"),
        ("build", 4, "Dm | Bb | Gm7 | C7sus4"),
        ("chorus", 8, "Bb | C | Am7 | Dm | Bb | C | F | F"),
        ("bounce", 4, "Dm | Bb | Gm7 | C"),
        ("A2", 8, "F | C | Dm | Bb | F | C | Bb | C"),
        ("chorus2", 8, "C | D | Bm7 | Em | C | D | G | G"),
        ("turn", 4, "Eb | F | Gm7 | C7"),
    ])
    hook = melody("""F5:2 C5:2 A4:2 C5:2 F5:4 G5:2 A5:2 | G5:4 E5:2 C5:2 G4:4 r:4 |
                     D5:2 F5:2 A5:2 F5:2 D5:4 E5:2 F5:2 | D5:6 C5:2 Bb4:4 r:4 |
                     F5:2 C5:2 A4:2 C5:2 F5:4 A5:2 C6:2 | Bb5:4 G5:2 E5:2 C5:4 r:4 |
                     D5:2 F5:2 Bb5:4 A5:2 G5:2 F5:4 | G5:4 E5:4 C5:4 r:4""")
    chorus = melody("""D5:4 F5:4 Bb5:6 A5:2 | G5:4 C6:4 G5:4 E5:4 | A5:6 G5:2 E5:4 C5:4 | D5:4 F5:4 A5:8 |
                       Bb5:4 A5:4 G5:4 F5:4 | G5:4 C6:6 Bb5:2 G5:4 | A5:4 C6:4 F6:8 | F6:8 r:8""")
    build = melody("A4:4 C5:4 D5:4 F5:4 | F5:4 D5:4 Bb4:4 D5:4 | G5:4 F5:4 D5:4 Bb4:4 | C5:2 E5:2 G5:2 C6:2 E6:8")
    bounce = melody("""D5:2 r:2 A5:2 r:2 F5:4 r:4 | Bb4:2 r:2 F5:2 r:2 D5:4 r:4 |
                       G4:2 r:2 D5:2 r:2 Bb4:4 r:4 | C5:2 E5:2 G5:2 C6:2 r:8""")
    turn = melody("Eb5:4 G5:4 Bb5:8 | F5:4 A5:4 C6:8 | G5:4 Bb5:4 D6:4 C6:4 | C6:4 Bb5:4 G5:4 E5:4")
    teaser = melody("F5:2 C5:2 A4:2 C5:2 F5:4 r:4 | D5:2 F5:2 A5:2 F5:2 D5:4 r:4")

    def lead(m, sec):
        return s.lead(m, sec, cutoff=6200, vibrato=0.1)

    def plucky(m, sec):
        return ins.synth_pluck(m, sec, bright=3200)

    kick, clap, ohat, chat, shake = s.kick(1.1, 0.42), s.clap(), s.hat(True), s.hat(False), s.shaker()
    toms = [ins.tom(p, 0.4) for p in (120.0, 160.0, 210.0)]
    rng = np.random.default_rng(31)
    prev = None

    for part in parts:
        name = part.name
        chorus_like = name in ("chorus", "chorus2")
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 29)
            notes = voicing(c, 60, 74, prev)
            prev = notes
            seconds = length * tr.step
            # bass: a bouncing slap octave, a held synth note in the intro and the bounce break
            if name == "intro":
                if local >= 4:
                    for k in range(0, 16, 4):
                        tr.add("bass", bar, k, ins.synth_bass(root + 12, tr.step * 3, cutoff=600, env_amt=900), 0.8)
            elif name == "bounce":
                for k, st in enumerate((0, 6, 10)):
                    tr.add("bass", bar, st, ins.slap_bass(root + 12, tr.step * 2.5, k == 1), 0.95)
            else:
                for st, pop in ((0, False), (2, True), (4, False), (6, True), (8, False), (10, True),
                                (12, False), (14, True)):
                    tr.add("bass", bar, step + st, ins.slap_bass(root + 12, tr.step * 1.6, pop), 0.8 if pop else 1.0)
            # plucked chords: an arpeggio up and down (the intro starts with it alone)
            if name in ("intro", "A", "A2", "build", "turn"):
                arp = notes + [notes[-1] + 12] + list(reversed(notes[1:]))
                gain = 0.55 + 0.05 * min(local, 6) if name == "intro" else 0.85
                for k in range(16):
                    tr.add("pluck", bar, step + k, plucky(arp[k % len(arp)] + 12, tr.step * 0.9), gain * (1.0 if k % 4 == 0 else 0.7), 0.3 if k % 2 else -0.3)
            # big chords in the choruses, a soft pad elsewhere
            if chorus_like:
                tr.add("saw", bar, step, s.supersaw([n + 12 for n in notes], seconds, cutoff=7000), 1.0)
                strum(tr, "stabs", bar, step, [n + 12 for n in notes[:3]], lambda m, sec: ins.brass(m, sec, bright=1.0, section=2), tr.step * 2, 0.9, spread=0.0)
            elif name in ("A", "A2", "build", "bounce", "turn") or (name == "intro" and local >= 6):
                tr.add("pad", bar, step, ins.strings(tuple(notes[:3]), seconds, attack=0.2, bright=0.45), 1.0)
            # glockenspiel sparkles over the second verse and the bounce break
            if name in ("A2", "bounce") and local % 2 == 1:
                for k in (3, 7, 11, 15):
                    tr.add("sparkle", bar, k, ins.glock(notes[rng.integers(len(notes))] + 24, 0.5), 0.6, 0.4 if k % 8 == 3 else -0.4)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 2:
                    tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.3 + 0.06 * local)
                if local >= 4:
                    tr.kick("kick", bar, "X.......X.......", kick, 0.6)
                if local >= 6:
                    tr.drum("drums", bar, "....x.......x...", clap, 0.6 + 0.1 * (local - 6), 0.05)
                if local == 7:
                    tr.add("fx", bar, 0, s.riser(tr.bar * 2), 0.7)
                if local == 8:
                    for k in range(8, 16):
                        tr.add("drums", bar, k, toms[2 - (k - 8) // 3], 0.7 + 0.04 * (k - 8))
                    # the launch: a slide whistle up into the drop
                    tr.add("fx", bar, 4, ins.slide_whistle(72, 96, tr.step * 12), 0.8, 0.2)
                continue
            if name == "bounce":
                # half time, with boings and bloops: the launch pads and the splashes
                tr.kick("kick", bar, "X.........X.....", kick, 0.95)
                tr.drum("drums", bar, "........X.......", clap, 1.0, 0.05)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.5, -0.25)
                tr.add("fx", bar, 4, ins.jaw_harp(50 + (local % 2) * 5, 0.5), 0.9, -0.3)
                tr.add("fx", bar, 12, ins.bloop(110.0 + 40 * local, 2.4, 0.22), 0.8, 0.35)
                if local == 3:
                    tr.add("fx", bar, 0, ins.slide_whistle(70, 94, tr.bar * 0.9), 0.75, -0.2)
                    for k in range(8, 16):
                        tr.add("drums", bar, k, s.snare(0.15), 0.3 + 0.06 * (k - 8), 0.1)
                continue
            tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
            tr.drum("drums", bar, "....X.......X..x", clap, 1.0, 0.05)
            tr.drum("hats", bar, "..X...X...X...X.", ohat, 0.85, 0.25)
            tr.drum("hats", bar, "xxxxxxxxxxxxxxxx" if chorus_like else "x.x.x.x.x.x.x.x.", chat, 0.45, -0.25)
            tr.drum("perc", bar, "xoxoxoxoxoxoxoxo", shake, 0.9, 0.35)
            if local == 0:
                tr.add("hats", bar, 0, s.crash(), 2.0, 0.2)
                if chorus_like:
                    tr.add("fx", bar, 0, ins.orchestra_hit(tuple(voicing(part.changes[0][3], 60, 76))), 0.8)
            if local == part.bars - 1:
                for k, step in enumerate((12, 13, 14, 15)):
                    tr.add("drums", bar, step, toms[2 - k // 2], 0.8)
                if name in ("build", "A2"):
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.6)
                if name == "build":
                    tr.add("fx", bar, 8, ins.slide_whistle(74, 98, tr.step * 8), 0.7, -0.2)
            # a jump boing on the hook's leaps
            if name in ("A", "A2") and local in (0, 4):
                tr.add("fx", bar, 8, ins.jaw_harp(57, 0.35), 0.55, 0.3)

    tr.play("teaser", 4, teaser, ins.toy_piano, pan=-0.15)
    tr.play("teaser", 6, teaser, ins.glock, pan=0.15)
    tr.play("lead", 9, hook, lead)
    tr.play("lead2", 9, shift(hook, 12), ins.glock, pan=0.25)
    tr.play("lead", 17, build, lead)
    tr.play("lead", 21, chorus, lead)
    tr.play("lead2", 21, shift(chorus, -12), lambda m, sec: ins.brass(m, sec, bright=0.9, section=3), pan=-0.15)
    tr.play("lead", 29, bounce, ins.marimba)
    tr.play("lead2", 29, shift(bounce, 12), ins.xylophone, pan=0.3)
    tr.play("lead", 33, hook, lead)
    tr.play("lead2", 33, shift(hook, -5), plucky, pan=-0.25)
    tr.play("lead", 41, shift(chorus, 2), lead)
    tr.play("lead2", 41, shift(chorus, -10), lambda m, sec: ins.brass(m, sec, bright=1.0, section=3), pan=-0.15)
    tr.play("sparkle", 41, shift(chorus, 14), ins.glock, pan=0.3)
    tr.play("lead", 49, turn, lead)
    tr.play("lead2", 49, shift(turn, -12), lambda m, sec: ins.brass(m, sec, bright=0.9, section=2), pan=-0.2)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.15, delay=0.1),
        "lead2": Bus(-14, reverb=0.2),
        "teaser": Bus(-10, reverb=0.3, delay=0.15),
        "sparkle": Bus(-18, reverb=0.3, delay=0.2),
        "pluck": Bus(-13, pump=0.25, delay=0.08),
        "saw": Bus(-12, pump=0.35, reverb=0.2),
        "stabs": Bus(-13, reverb=0.15),
        "pad": Bus(-17, pump=0.3, reverb=0.3),
        "bass": Bus(-8, pump=0.3),
        "kick": Bus(-8, drive=1.4),
        "drums": Bus(-12, reverb=0.12),
        "hats": Bus(-17),
        "perc": Bus(-20),
        "fx": Bus(-13, reverb=0.3),
    }, reverb_decay=1.5, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.3, pump_release=0.15)
    return finish(tr, mix), tr


SONG = Song("ObbyOdyssey", "Bounce to the Crown", 150, 9, 53, obby_odyssey)
