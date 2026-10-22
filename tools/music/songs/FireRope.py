"""Dragon Temple Drums - the round track for FireRope (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan


def fire_rope():
    """Dragon Temple Drums (126 bpm, D minor pentatonic): a fire festival on a stone bridge over lava.
    Taiko, a bamboo flute (dizi) with a heroic theme, koto, an erhu, gongs and a choir; up to E minor
    for the climax and G major for the final stretch, as the rope gets faster."""
    tr = Track(bpm=126, bars=52)
    parts = plan(tr, [
        ("intro", 8, "Dm | Dm | Dm | Dm | Bb | C | Dm | Dm"),
        ("A1", 8, "Dm | Dm | Bb | C | Dm | Dm | Gm | A"),
        ("A2", 8, "Dm | Dm | Bb | C | Dm | Dm | Gm | A"),
        ("B", 8, "F | C | Dm | Bb | F | C | Bb | C"),
        ("break", 4, "Dm | Dm | Bb | C"),
        ("climax", 8, "Em | Em | C | D | Em | Em | Am | B"),
        ("finale", 8, "G | D | Em | C | G | D | C | D"),
    ])
    theme = melody("""D5:4 F5:2 G5:2 A5:6 C6:2 | A5:4 G5:2 F5:2 G5:8 | F5:4 D5:2 F5:2 G5:4 F5:2 D5:2 | C5:6 D5:2 E5:8 |
                      D5:4 F5:2 G5:2 A5:6 C6:2 | D6:4 C6:2 A5:2 C6:8 | Bb5:4 A5:2 G5:2 D5:4 G5:4 | A5:12 r:4""")
    counter = melody("A3:8 D4:8 | C4:16 | D4:8 F4:8 | E4:16 | A3:8 D4:8 | F4:16 | D4:8 G4:8 | E4:8 C#4:8")
    lyric = melody("""C6:6 A5:2 G5:4 F5:4 | G5:8 E5:4 G5:4 | A5:6 F5:2 D5:4 F5:4 | F5:12 D5:4 |
                      C6:6 D6:2 C6:4 A5:4 | G5:6 A5:2 G5:4 E5:4 | F5:4 G5:4 A5:4 Bb5:4 | C6:16""")
    solo = melody("""r:4 A5:8 G5:4 | A5:6 C6:2 D6:8 | C6:4 A5:4 G5:4 F5:4 | G5:16 |
                     r:4 D6:4 C6:4 A5:4 | G5:8 r:8""")

    def dizi(m, sec):
        return ins.flute(m, sec, breath=0.09, vibrato=0.14, buzz=0.35, fall=0.6 if sec > 0.9 else 0.0)

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.55, section=3)

    odaiko = [ins.taiko(58.0, 1.4, 1.0, v) for v in range(3)]
    mid = [ins.taiko(105.0, 0.7, 0.8, v) for v in range(3)]
    shime = ins.tom(420.0, 0.15)
    ka = ins.rim_click(1500.0)
    chappa = s.hat(True)
    kick, clap = s.kick(1.0, 0.45), s.clap()

    tr.add("fx", 0, 0, ins.crackle(tr.bar * 2), 0.5)
    tr.add("fx", 2, 0, ins.gong(5.0, 98.0), 1.0)
    tr.play("lead", 2, solo, dizi, 0.8)

    prev = None
    for part in parts:
        for bar, step, length, c in part.changes:
            root = bass_note(c, 26)
            notes = voicing(c, 57, 72, prev)
            prev = notes
            local = bar - part.first
            seconds = length * tr.step
            name = part.name
            if name == "intro":
                tr.add("pad", bar, 0, ins.strings((root + 12, root + 19), seconds, attack=0.8, bright=0.25), 1.0)
            elif name in ("B", "finale"):
                tr.add("pad", bar, step, ins.strings(tuple(notes), seconds, attack=0.3, bright=0.45), 1.0)
            if name in ("break", "climax", "finale"):
                tr.add("choir", bar, step, ins.choir(tuple(n - 12 for n in notes[:3]), seconds, "ah"), 1.0)
            if name in ("A1", "A2", "climax"):
                for k, offset in enumerate((0, 0, 12, 0, 7, 0, 12, 0)):
                    tr.add("bass", bar, k * 2, ins.synth_bass(root + 12 + offset, tr.step * 1.6, cutoff=700, env_amt=1200, sub=0.4), 1.0)
                    tr.add("ostinato", bar, k * 2, ins.spiccato(root + 24 + offset, tr.step * 1.5), 1.0, -0.25)
            elif name in ("B", "finale"):
                tr.add("bass", bar, 0, ins.synth_bass(root + 12, tr.step * 7, cutoff=600, env_amt=600, sub=0.5), 1.0)
                tr.add("bass", bar, 8, ins.synth_bass(root + (19 if name == "B" else 12), tr.step * 7, cutoff=600, env_amt=600, sub=0.5), 0.85)
            elif name == "break":
                tr.add("bass", bar, 0, ins.synth_bass(root + 12, tr.step * 14, cutoff=500, env_amt=300, sub=0.6), 1.0)
            ring = notes + [notes[0] + 12, notes[1] + 12]
            if name in ("A1", "A2", "climax"):
                for k, idx in enumerate((0, 1, 2, 1, 3, 1, 2, 1)):
                    tr.add("koto", bar, k * 2, ins.koto(ring[idx], tr.step * 2, variant=k), 1.0, 0.3)
            elif name in ("B", "finale"):
                for k in range(16):
                    tr.add("koto", bar, k, ins.koto(ring[(0, 1, 2, 3, 4, 3, 2, 1)[k % 8]], tr.step * 1.5, variant=k), 0.85 if k % 2 else 1.0, 0.35 if k % 2 else -0.1)
            elif name == "intro" and local >= 4:
                for k in (0, 6, 10):
                    tr.add("koto", bar, k, ins.koto(ring[k % 3], tr.step * 4, press=1.0 if k == 6 else 0.0), 1.0, 0.3)

        for bar in part.bars_range():
            local = bar - part.first
            name = part.name
            if name == "intro":
                if local >= 3:
                    tr.drum("taiko", bar, "X.......X.......", odaiko[local % 3], 0.6 + 0.08 * (local - 3))
                if local >= 5:
                    tr.drum("taiko", bar, "....x......x.x..", mid[local % 3], 0.6)
                if local >= 6:
                    tr.drum("perc", bar, "x.x.x.x.x.x.x.x.", shime, 0.6 + 0.2 * (local - 6), 0.3)
                if local == 7:
                    for k in range(16):
                        tr.add("taiko", bar, k, mid[k % 3], 0.25 + 0.05 * k)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.5)
                continue
            if name == "break":
                tr.drum("taiko", bar, "X.....X.....X...", odaiko[local % 3], 1.0)
                tr.drum("taiko", bar, "....x.....x...x." if local % 2 == 0 else "..x.x..x..x.x.xx", mid[local % 3], 0.6)
                tr.drum("perc", bar, "..X...X...X...X.", ka, 0.8, 0.2)
                if local == 3:
                    for k in range(8, 16):
                        tr.add("taiko", bar, k, mid[k % 3], 0.35 + 0.08 * (k - 8))
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.5)
                continue
            big = name in ("climax", "finale")
            tr.kick("kick", bar, "X.......X.......", kick, 1.0)
            tr.drum("taiko", bar, "X.....x.X.......", odaiko[local % 3], 0.8)
            tr.drum("taiko", bar, "....X..x....X..x" if local % 2 == 0 else "....X..x..x.X.xx", mid[local % 3], 0.55)
            tr.drum("snare", bar, "....X.......X...", clap, 1.0, 0.05)
            tr.drum("perc", bar, "x.x.x.x.x.x.x.x." if name in ("A1", "B") else "xoxoxoxoxoxoxoxo", shime, 0.8, 0.3)
            tr.drum("perc", bar, "..x...x...x...x.", ka, 0.7, -0.3)
            tr.drum("cymbal", bar, "..x...x...x...x." if not big else "..x.x.x...x.x.x.", chappa, 1.0, -0.2)
            if local % 8 == 0:
                tr.add("fx", bar, 0, ins.gong(3.0, 110.0), 0.8)
                tr.add("cymbal", bar, 0, s.crash(), 1.6, 0.2)

    tr.play("lead", 8, theme, dizi)
    tr.play("lead", 16, theme, dizi)
    tr.play("harmony", 16, shift(theme, -5), ins.koto)
    tr.play("brass", 16, counter, horn, pan=-0.2)
    tr.play("lead", 24, lyric, ins.erhu)
    tr.play("lead", 36, shift(theme, 2), dizi)
    tr.play("brass", 36, shift(theme, 2 - 12), horn, pan=-0.15)
    tr.play("lead", 44, shift(lyric, 7 - 12), dizi)
    tr.play("brass", 44, shift(lyric, 7 - 24), horn, pan=-0.15)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.2, delay=0.08),
        "harmony": Bus(-15, reverb=0.2),
        "brass": Bus(-11, reverb=0.18),
        "koto": Bus(-13, reverb=0.18, delay=0.1),
        "ostinato": Bus(-14, pump=0.2, reverb=0.1),
        "pad": Bus(-14, pump=0.15, reverb=0.25),
        "choir": Bus(-14, reverb=0.35),
        "bass": Bus(-9, pump=0.2),
        "taiko": Bus(-6, drive=1.6, reverb=0.1),
        "kick": Bus(-10, drive=1.4),
        "snare": Bus(-14, reverb=0.15),
        "perc": Bus(-15, reverb=0.08),
        "cymbal": Bus(-19, reverb=0.1),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=2.2, reverb_tone=5000, delay_time=tr.beat * 0.75, delay_feedback=0.3)
    return finish(tr, mix), tr


SONG = Song("FireRope", "Dragon Temple Drums", 126, 8, 52, fire_rope)
