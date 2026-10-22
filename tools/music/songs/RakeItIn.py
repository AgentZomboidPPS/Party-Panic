"""Harvest Hoedown: the round song for RakeItIn (see songkit.py for the rules every song keeps)."""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def harvest_hoedown():
    """Harvest Hoedown (150 bpm, G major): a farmyard band around the turning field. Banjo rolls and a
    fiddle trade the tune over boom-chick guitar, upright bass, washboard and stomps; a barnyard break
    for the jaw harp and the cowbell, a climb up to A major timed so the GOLDEN RUSH (70% of the round,
    38.5 s in) lands on its downbeat, and a "shave and a haircut... two bits!" finish as time runs out,
    with a D7 turnaround that leads back into the drop."""
    tr = Track(bpm=150, bars=45)
    parts = plan(tr, [
        ("intro", 9, "G | G | C | G | G | C | D | D | D7"),
        ("A", 8, "G | G | C | G | G | D | G D | G"),
        ("B", 8, "C | G | C | D | C | G | Am D | G"),
        ("break", 4, "G | G | C | D7"),
        ("build", 4, "C | D | E7 | E7"),
        ("rush", 12, "A | A | D | A | A | E | A E | A | A | E A | D7 | D7"),
    ])
    tune = melody("""G4:2 A4:2 B4:2 D5:2 G5:2 E5:2 D5:2 B4:2 | G5:4 E5:2 G5:2 D5:4 B4:4 |
                     C5:2 E5:2 G5:2 E5:2 C5:2 E5:2 G5:2 A5:2 | B5:4 A5:2 G5:2 D5:4 r:4 |
                     G4:2 A4:2 B4:2 D5:2 G5:2 E5:2 D5:2 B4:2 | F#5:4 A5:2 F#5:2 D5:4 C5:2 A4:2 |
                     B4:2 D5:2 G5:2 B4:2 A4:2 G4:2 F#4:2 A4:2 | G4:4 B4:2 D5:2 G5:4 r:4""")
    bpart = melody("""E5:2 G5:2 C6:4 G5:2 A5:2 G5:2 E5:2 | D5:2 G5:2 B5:4 G5:2 A5:2 B5:2 G5:2 |
                      E5:2 G5:2 C6:4 G5:2 A5:2 G5:2 E5:2 | F#5:4 A5:2 F#5:2 D5:2 E5:2 F#5:2 A5:2 |
                      E5:2 G5:2 C6:4 G5:2 A5:2 G5:2 E5:2 | D5:2 G5:2 B5:4 G5:2 A5:2 B5:2 D6:2 |
                      C6:2 B5:2 A5:2 E5:2 F#5:2 A5:2 D6:2 C6:2 | B5:4 G5:2 D5:2 G5:4 r:4""")
    boing = melody("""G3:3 G3:1 D3:2 G3:2 r:2 B3:2 D4:4 | G3:3 G3:1 D3:2 G3:2 r:2 D4:2 B3:4 |
                      C4:3 C4:1 G3:2 C4:2 r:2 E4:2 G4:4 | D4:3 D4:1 A3:2 D4:2 F#4:2 A4:2 C5:4""")
    climb = melody("""C5:2 E5:2 G5:2 E5:2 C5:2 E5:2 G5:2 C6:2 | D5:2 F#5:2 A5:2 F#5:2 D5:2 F#5:2 A5:2 D6:2 |
                      E5:2 G#5:2 B5:2 G#5:2 E5:2 G#5:2 B5:2 D6:2 | E6:12 r:4""")
    two_bits = melody("""A5:4 E5:2 E5:2 F#5:4 E5:4 | r:4 G#5:4 A5:4 r:4 |
                         r:8 D5:2 F#5:2 A5:2 C6:2 | B5:2 A5:2 F#5:2 D5:2 C5:2 A4:2 F#4:2 A4:2""")
    kickoff = melody("A5:2 F#5:2 D5:2 C5:2 A4:2 F#4:2 D4:2 F#4:2")
    preview = melody("r:8 D5:4 G5:4 | C6:8 G5:4 E5:4 | F#5:8 A5:8 | D6:16")

    def fiddle(m, sec):
        return ins.fiddle(m, sec)

    def banjo(m, sec):
        return ins.banjo(m, sec)

    def chop(m, sec):  # the fiddle's bluegrass chop: a short scratchy off-beat stab
        return ins.fiddle(m, min(sec, 0.09), accent=0.6)

    washboard = [ins.washboard(0.05), ins.washboard(0.08)]
    stomp, clap = s.kick(0.7, 0.3), s.clap()
    bell = ins.cowbell(0.25)

    # The intro: the banjo alone at dawn, the fiddle tuning up, then the band falls in.
    tr.add("tuning", 0, 0, ins.fiddle(55, tr.bar * 2, accent=0.5), 1.0)
    tr.add("tuning", 0, 0, ins.fiddle(62, tr.bar * 2, accent=0.5), 0.8)
    tr.play("fiddle", 4, preview, fiddle, 0.6)
    tr.play("fiddle", 8, kickoff, fiddle)
    tr.add("jaw", 7, 12, ins.jaw_harp(43, 0.45), 0.8)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            step = int(round(step))
            if name == "intro" and local == 8:
                continue  # the kick-off: the fiddle alone (and the washboard), then the band crashes in
            root = bass_note(c, 36)  # C2 .. B2
            notes = voicing(c, 55, 67, prev)
            prev = notes
            span = int(length)
            fifth = root + 7 if root + 7 <= 47 else root - 5
            # banjo forward rolls (behind the fiddle, and alone in the intro)
            ring = voicing(c, 59, 74)[:3]
            ring = [ring[0], ring[1], ring[2], 67 if 67 % 12 in c.tones() else ring[0] + 12]
            roll = (0, 1, 2, 0, 1, 3, 0, 2)
            if name in ("intro", "A", "B", "build") or (name == "rush" and local not in (8, 9)):
                for k in range(span):
                    gain = 1.0 if k % 8 in (0, 3, 6) else 0.7
                    if name == "intro":
                        gain *= min(1.0, 0.35 + 0.1 * local)
                    elif name == "A":
                        gain *= 0.5  # under the banjo's own tune
                    tr.add("rolls", bar, step + k, ins.banjo(ring[roll[(step + k) % 8]], tr.step * 3, variant=k % 3), gain, 0.3)
            # upright bass: root and fifth (half notes, then quarters from the climb on)
            if name == "intro" and local < 4:
                pass
            elif name == "break":
                pass  # the break walks (below)
            elif name == "rush" and local in (8, 9):
                pass  # stop-time: the bass only hits with the band
            else:
                for st in range(0, span, 8 if name in ("intro", "A", "B") else 4):
                    pos = step + st
                    m = root if (pos // (8 if name in ("intro", "A", "B") else 4)) % 2 == 0 else fifth
                    tr.add("bass", bar, pos, ins.upright(m, tr.step * 3.5, variant=pos % 3), 1.0 if pos % 8 == 0 else 0.85)
            # guitar boom-chick: the chick on 2 and 4
            if not (name == "intro" and local < 4) and not (name == "rush" and local in (8, 9)):
                for st in range(0, span):
                    pos = step + st
                    if pos in (4, 12) or (name == "rush" and pos in (6, 14)):
                        strum(tr, "guitar", bar, pos, notes, ins.acoustic_guitar, 0.14, 1.0 if pos in (4, 12) else 0.6, spread=0.008, down=pos in (4, 12))
            # the fiddle chops on 2 and 4 while the banjo has the tune
            if name == "A":
                for pos in (4, 12):
                    if step <= pos < step + span:
                        for m in notes[1:]:
                            tr.add("chops", bar, pos, chop(m + 12, 0.09), 0.8)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if 4 <= local < 8:
                    tr.drum("stomp", bar, "X.......X.......", stomp, 0.5 + 0.1 * (local - 4))
                if 6 <= local < 8:
                    tr.drum("washboard", bar, "x.x.x.x.x.x.x.x.", washboard[0], 0.5 + 0.15 * (local - 6))
                    tr.drum("claps", bar, "....x.......x...", clap, 0.6)
                if local == 8:  # the kick-off: a washboard rattle up into the drop
                    for k in range(16):
                        tr.add("washboard", bar, k, washboard[k % 2], 0.5 + 0.03 * k)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.3)
                continue
            if name == "break":  # the barnyard break: jaw harp, cowbell, stomps and a walking bass
                if local == 0:
                    walking_bass(tr, "bass", part, lambda m, sec: ins.upright(m, sec), 1.0, low=36)
                    tr.add("cymbal", bar, 0, s.crash(), 1.0, 0.2)
                tr.drum("stomp", bar, "X.......X.......", stomp, 1.0)
                tr.drum("claps", bar, "....X.......X...", clap, 1.0)
                tr.drum("washboard", bar, "x.xxx.xxx.xxx.xx", washboard[0], 0.8)
                tr.drum("bell", bar, "X..x..x...X.x...", bell, 0.8, 0.3)
                continue
            if name == "rush" and local in (8, 9):  # stop-time: "shave and a haircut... two bits!"
                hits = "X...X.X.X...X..." if local == 8 else "....X...X......."
                c = part.at(bar)[0][2]
                for st in [k for k, ch in enumerate(hits) if ch == "X"]:
                    cc = part.at(bar)[-1][2] if st >= 8 else c
                    strum(tr, "guitar", bar, st, voicing(cc, 55, 67), ins.acoustic_guitar, 0.25, 1.2, spread=0.006)
                    tr.add("bass", bar, st, ins.upright(bass_note(cc, 36), 0.3), 1.0)
                    tr.add("stomp", bar, st, stomp, 1.0)
                    tr.add("claps", bar, st, clap, 0.9)
                    tr.add("rolls", bar, st, ins.banjo(voicing(cc, 64, 76)[-1], 0.3), 1.0, 0.3)
                if local == 9:
                    tr.add("cymbal", bar, 8, s.crash(), 1.4, 0.2)
                continue
            big = name == "rush"
            tr.kick("stomp", bar, "X.......X......." if not big else "X...X...X...X...", stomp, 1.0)
            tr.drum("claps", bar, "....X.......X..." if name != "A" or local >= 4 else "....x.......x...", clap, 1.0)
            tr.drum("washboard", bar, "x.x.x.x.x.x.x.x." if name in ("A", "B") else "xxxxxxxxxxxxxxxx", washboard[0], 0.75)
            tr.drum("washboard", bar, "....X.......X...", washboard[1], 0.8)
            if big:
                tr.drum("bell", bar, "x...x...x...x...", bell, 0.6, 0.3)
            if local == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.2, 0.2)
            if name == "build" and local == 3:
                for k in range(8, 16):
                    tr.add("washboard", bar, k, washboard[1], 0.6 + 0.05 * (k - 8))
                    tr.add("stomp", bar, k, stomp, 0.3 + 0.06 * (k - 8))
                tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.4)
            if name == "rush" and local == 11:  # the turnaround's stomps lead back to the top
                for k in (8, 10, 12, 14):
                    tr.add("stomp", bar, k, stomp, 0.8)

    tr.play("banjo", 9, tune, banjo)
    tr.play("fiddle", 17, bpart, fiddle)
    tr.play("jaw", 25, boing, ins.jaw_harp)
    tr.play("banjo", 27, melody("r:12 G5:1 E5:1 D5:1 B4:1 | r:12 A5:1 F#5:1 D5:1 C5:1"), banjo)
    tr.play("fiddle", 29, climb, fiddle)
    tr.play("fiddle", 33, shift(tune, 2), fiddle)
    tr.play("banjo", 33, shift(tune, 2), banjo, 0.8)
    tr.play("fiddle", 41, two_bits, fiddle)
    tr.play("banjo", 41, [n for n in two_bits if n.step < 32], banjo, 0.9)
    for bar in (35, 37, 39):  # boings at the phrase ends during the rush
        tr.add("jaw", bar, 12, ins.jaw_harp(45, 0.4), 0.7)

    mix = Mix(buses={
        "fiddle": Bus(-5, reverb=0.15),
        "banjo": Bus(-6, reverb=0.12),
        "rolls": Bus(-12, reverb=0.12),
        "chops": Bus(-17, reverb=0.1),
        "tuning": Bus(-18, reverb=0.3),
        "guitar": Bus(-13, reverb=0.1),
        "bass": Bus(-9),
        "jaw": Bus(-9, reverb=0.15),
        "stomp": Bus(-11, drive=1.3, eq=(("hp", 60), ("hp", 60), ("peak", 120, 4, 1.2))),  # a boot on boards, not a sub
        "claps": Bus(-14, reverb=0.12),
        "washboard": Bus(-16, eq=(("lp", 8000),)),
        "bell": Bus(-18, reverb=0.1),
        "cymbal": Bus(-21, eq=(("lp", 9000),)),
        "fx": Bus(-17, reverb=0.3),
    }, reverb_decay=1.3, reverb_tone=5500, delay_time=tr.beat * 0.75, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("RakeItIn", "Harvest Hoedown", 150, 9, 45, harvest_hoedown)
