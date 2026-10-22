"""Snowbreaker Ska - the round track for Spleef (tools/music/modes.py: how round tracks work)."""

from __future__ import annotations

import numpy as np

import instruments as ins
import synth as s
from score import Bus, Mix, Track, bass_note, melody, shift, voicing
from modes import Song, finish, plan, strum, walking_bass


def spleef():
    """Snowbreaker Ska (160 bpm, G major): a snow-day ska band on three floors of snow over an icy
    pool. Offbeat guitar skanks chip away like shovels, a combo organ bubbles, trumpet and trombone
    play the hook in octaves, and boots crunch snow between the phrases. When the floors start to
    crack on their own (30 s in, bar 20 of the round) it turns to E minor with ice creaking and
    splashes; then the hook comes back, a climb lifts it to A major, and the finale (66 s on, as the
    last floor crumbles and the last ones standing fight it out) is the whole band at full tilt."""
    tr = Track(bpm=160, bars=61)
    parts = plan(tr, [
        ("intro", 9, "G | G | Em | Em | C | C | D | D | D7"),
        ("A1", 8, "G | Em | C | D | G | Em | C D | G"),
        ("A2", 8, "G | Em | C | D | G | Em | C D | G"),
        ("bridge", 4, "C | D | B7 | B7"),
        ("crack", 8, "Em | C | Am | B7 | Em | C | Am B7 | Em B7"),
        ("A3", 8, "G | Em | C | D | G | Em | C D | G"),
        ("climb", 8, "C | D | Bm | Em | C | D | E7sus4 | E7"),
        ("finale", 8, "A | F#m | D | E | A | F#m | D E | D7"),
    ])
    hook = melody("""D5:2 r:2 B4:2 D5:2 G5:4 F#5:2 G5:2 | E5:6 D5:2 B4:8 | C5:2 r:2 E5:2 G5:2 C6:4 B5:2 A5:2 | A5:6 G5:2 F#5:8 |
                     D5:2 r:2 B4:2 D5:2 G5:4 A5:2 B5:2 | C6:4 B5:2 A5:2 G5:4 E5:4 | E5:2 G5:2 C6:4 D6:2 C6:2 A5:4 | G5:12 r:4""")
    crack = melody("""E5:2 E5:2 G5:2 E5:2 B5:4 A5:2 G5:2 | E5:2 E5:2 G5:2 E5:2 C6:4 B5:2 A5:2 |
                      A5:2 C6:2 A5:2 E5:2 F#5:2 G5:2 A5:4 | B5:4 A5:2 F#5:2 D#5:8 |
                      E5:2 E5:2 G5:2 E5:2 B5:4 A5:2 G5:2 | E5:2 E5:2 G5:2 E5:2 C6:4 B5:2 A5:2 |
                      C6:4 B5:2 A5:2 B5:4 F#5:4 | E5:8 r:2 B4:2 D#5:2 F#5:2""")
    climb = melody("""E5:4 G5:4 C6:8 | D6:4 C6:2 B5:2 A5:8 | F#5:4 B5:4 D6:8 | E6:6 D6:2 B5:8 |
                      C6:4 B5:2 A5:2 G5:4 E5:4 | F#5:4 A5:4 D6:8 | A5:4 D6:4 E6:8 | D6:4 B5:4 G#5:4 E5:4""")
    bridge = melody("E5:2 r:2 E5:2 r:2 G5:4 E5:4 | F#5:2 r:2 F#5:2 r:2 A5:4 F#5:4 | D#5:2 F#5:2 A5:2 B5:2 D#6:8 | B5:16")
    intro_tune = melody("r:16 | r:16 | r:16 | r:16 | r:16 | r:16 | r:16 | r:16 | r:8 D4:2 F#4:2 A4:2 C5:2")
    organ_intro = melody("G5:8 B5:8 | D6:16 | E5:8 G5:8 | B5:16 | E5:8 G5:8 | C6:16 | F#5:8 A5:8 | D6:16 | C6:16")

    def trumpet(m, sec):
        return ins.brass(m, sec, bright=0.95, section=2)

    def trombone(m, sec):
        return ins.brass(m, sec, bright=0.45, section=2, vibrato=0.05)

    def bass(m, sec):
        return ins.bass_guitar(m, sec, bright=0.6)

    kick, clap = s.kick(0.9, 0.35), s.clap(0.25)
    snare = [ins.snare2(240.0, 0.9, 0.22, v) for v in range(3)]
    rim = ins.rim_click(1700.0)
    chat, ohat = s.hat(False), s.hat(True)
    crunch = [ins.snow_crunch(0.14, v) for v in range(4)]
    rng = np.random.default_rng(12)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            notes = voicing(c, 60, 72, prev, size=3)
            prev = notes
            # the skank: guitar upstrokes on every offbeat, the organ's bubble behind them
            if name != "intro" or local >= 2:
                g = 0.5 + 0.08 * local if name == "intro" else 1.0
                for st in range(2, int(length), 4):
                    strum(tr, "skank", bar, step + st, [n + 12 for n in notes], lambda m, sec: ins.electric_guitar(m, sec, mute=True, variant=st), tr.step * 1.2, g, spread=0.006, down=False, pan=0.3)
            if name not in ("intro", "bridge") or (name == "intro" and local >= 4):
                for st in range(2, int(length), 4):
                    for i, m in enumerate(notes):
                        tr.add("organ", bar, step + st, ins.combo_organ(m, tr.step * 0.8), 0.5, -0.3)
                        if name in ("A3", "climb", "finale"):
                            tr.add("organ", bar, step + st + 1, ins.combo_organ(m, tr.step * 0.6), 0.3, -0.3)
            if name == "bridge":
                for i, m in enumerate(notes):
                    tr.add("horns", bar, step, trombone(m, tr.step * 2), 0.6)
                    tr.add("horns", bar, step + 10, trombone(m, tr.step * 2), 0.6)
            if name in ("climb", "finale"):
                tr.add("pad", bar, step, ins.strings(tuple(n + 12 for n in notes), length * tr.step, attack=0.1, bright=0.55), 1.0)
            if name in ("A3", "finale"):
                tr.add("choir", bar, step, ins.choir(tuple(notes), length * tr.step, "ah", attack=0.08), 1.0 if name == "finale" else 0.6)
        # bass: a walking line (a slower root-fifth in the intro)
        if name == "intro":
            for bar, step, length, c in part.changes:
                local = bar - part.first
                if local >= 5:
                    root = bass_note(c, 40)
                    tr.add("bass", bar, 0, bass(root, tr.step * 6), 0.8)
                    tr.add("bass", bar, 8, bass(root + 7 if root + 7 <= 52 else root - 5, tr.step * 6), 0.7)
        else:
            walking_bass(tr, "bass", part, bass, 1.0, low=40)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                # boots in the snow, then the band tiptoes in
                for k in (0, 6, 8, 14) if local < 7 else (0, 4, 8, 12):
                    tr.add("snow", bar, k, crunch[(bar + k) % 4], 0.6 + 0.04 * local, -0.4 if k % 8 == 0 else 0.4)
                if local >= 6:
                    tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.4 + 0.1 * (local - 6), 0.25)
                if local >= 7:
                    tr.kick("kick", bar, "X.......X.......", kick, 0.6 + 0.15 * (local - 7))
                    tr.drum("snare", bar, "....x.......x...", rim, 0.6, 0.1)
                if local == 8:
                    for k in range(8, 16):
                        tr.add("snare", bar, k, snare[k % 3], 0.4 + 0.07 * (k - 8), 0.1)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.45)
                continue
            if name == "bridge":
                tr.kick("kick", bar, "X.......X.......", kick, 0.9)
                tr.drum("snare", bar, "....X.......X...", snare[local % 3], 0.9, 0.1)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.6, -0.25)
                if local >= 2:
                    for k in range(0, 16, 2 if local == 2 else 1):
                        tr.add("snare", bar, k, snare[k % 3], 0.3 + 0.03 * k + 0.2 * (local - 2), 0.1)
                if local == 3:
                    tr.add("fx", bar, 0, ins.clank(1900.0, 1.2), 0.5, 0.3)  # the first crack in the ice
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.5)
                continue
            big = name in ("A3", "climb", "finale")
            fin = name == "finale"
            tr.kick("kick", bar, "X...X...X...X..." if (fin or name == "climb") else "X.......X.......", kick, 1.0)
            tr.drum("snare", bar, "....X.......X...", snare[local % 3], 1.0, 0.1)
            tr.drum("snare", bar, "....x.......x...", clap, 0.6 if big else 0.4, -0.1)
            tr.drum("hats", bar, "..X...X...X...X.", ohat, 0.6, 0.25)
            tr.drum("hats", bar, "x.x.x.x.x.x.x.x." if not big else "xxxxxxxxxxxxxxxx", chat, 0.5, -0.25)
            if local % 4 == 3:
                fill = "............x.xx" if not fin else "........x.x.xxxx"
                tr.drum("snare", bar, fill, snare[(local + 1) % 3], 0.75, 0.1)
            if local == 0 or (fin and local % 2 == 0):
                tr.add("cymbal", bar, 0, s.crash(2.2), 1.3 if not fin else 1.6, 0.2 if local % 4 == 0 else -0.2)
            if local == 0 and name in ("A1", "A3", "finale"):
                tr.add("fx", bar, 0, ins.orchestra_hit(tuple(voicing(part.changes[0][3], 60, 76))), 0.7)
            # shovels in the snow on the gaps; splashes as people drop out
            if name in ("A1", "A2", "A3") and local % 2 == 1:
                tr.add("snow", bar, 14, crunch[local % 4], 0.8, rng.uniform(-0.6, 0.6))
            if name == "crack":
                tr.add("fx", bar, 0, ins.clank(1500.0 + 300 * (local % 3), 0.9), 0.4, rng.uniform(-0.6, 0.6))
                if local % 2 == 1:
                    tr.add("fx", bar, 10, ins.plunge(), 0.6, rng.uniform(-0.6, 0.6))
                tr.add("snow", bar, 6, crunch[local % 4], 0.8, -0.5)
                tr.add("snow", bar, 7, crunch[(local + 1) % 4], 0.6, 0.5)
            if fin and local in (1, 3, 5):
                tr.add("fx", bar, 12, ins.plunge(), 0.5, rng.uniform(-0.6, 0.6))
            if name == "climb" and local == 7:
                tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.6)
                for k in range(0, 16):
                    tr.add("snare", bar, k, snare[k % 3], 0.35 + 0.035 * k, 0.1)
            if fin and local == 7:
                tr.add("fx", bar, 0, s.downlifter(tr.bar), 0.4)

    tr.play("organ_lead", 0, organ_intro, lambda m, sec: ins.combo_organ(m, sec), 0.45)
    tr.play("lead", 0, intro_tune, trumpet, 0.8)
    tr.play("lead", 9, hook, trumpet)
    tr.play("lead2", 9, shift(hook, -12), trombone, 0.9, pan=-0.2)
    tr.play("lead", 17, hook, trumpet)
    tr.play("lead2", 17, shift(hook, -12), trombone, 0.9, pan=-0.2)
    tr.play("lead", 25, bridge, trumpet)
    tr.play("organ_lead", 29, crack, lambda m, sec: ins.combo_organ(m, sec))
    tr.play("lead2", 29, [n for n in shift(crack, -12) if (n.step // 16) % 4 in (2, 3)], trombone, 0.9, pan=-0.2)
    tr.play("lead", 29, [n for n in crack if (n.step // 16) % 4 in (2, 3)], trumpet, 0.7)
    tr.play("lead", 37, hook, trumpet)
    tr.play("lead2", 37, shift(hook, -12), trombone, 0.9, pan=-0.2)
    tr.play("organ_lead", 37, shift(hook, 12), lambda m, sec: ins.combo_organ(m, sec), 0.5, pan=0.3)
    tr.play("lead", 45, climb, trumpet)
    tr.play("lead2", 45, shift(climb, -12), trombone, 0.9, pan=-0.2)
    tr.play("lead", 53, shift(hook, 2), trumpet, 1.3)
    tr.play("lead2", 53, shift(hook, 2 - 12), trombone, 1.0, pan=-0.2)
    tr.play("organ_lead", 53, shift(hook, 14), lambda m, sec: ins.combo_organ(m, sec), 0.55, pan=0.3)
    tr.play("glock", 53, shift(hook, 14), ins.glock, 0.6, pan=-0.3)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.15, delay=0.05),
        "lead2": Bus(-12, reverb=0.15),
        "organ_lead": Bus(-13, reverb=0.15),
        "glock": Bus(-17, reverb=0.25),
        "horns": Bus(-14, reverb=0.15),
        "skank": Bus(-11, reverb=0.12, delay=0.08),
        "organ": Bus(-15, pump=0.1),
        "pad": Bus(-16, reverb=0.25),
        "choir": Bus(-16, reverb=0.3),
        "bass": Bus(-8),
        "kick": Bus(-11, drive=1.3),
        "snare": Bus(-11, reverb=0.12),
        "hats": Bus(-18),
        "cymbal": Bus(-20, reverb=0.1),
        "snow": Bus(-17, reverb=0.1),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=1.3, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.3, pump_release=0.12)
    return finish(tr, mix), tr


SONG = Song("Spleef", "Snowbreaker Ska", 160, 9, 61, spleef)
