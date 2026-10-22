"""Crazy Cutters: "Cookie Cutter Swing" (144 bpm swing, B flat major).

A bake-off jazz combo in the cookie kitchen: a clarinet with a bouncy, cut-along hook, a vibraphone,
electric piano comping, a walking upright bass and brushes on the snare. AABA head, a vibes solo,
then a shout chorus a whole step up (C major) with a muted horn section, and a ii-V tag that walks
back into the start. The kitchen timer dings at GO and at the shout chorus.
"""

from __future__ import annotations

import instruments as ins
import synth as s
from modes import Song, finish, plan, strum, walking_bass
from score import Bus, Mix, Track, bass_note, melody, shift, voicing

SPB = 12  # triplet grid: a beat is 3 steps, a swung 8th pair is 2 + 1


def render():
    tr = Track(bpm=144, bars=60, spb=SPB)
    a_changes = "Bb6 | Gm7 | Cm7 | F7 | Bb6 | Bb7 | Eb6 Edim7 | Bb6/F F7"
    parts = plan(tr, [
        ("intro", 8, "Bb6 | Gm7 | Cm7 | F7 | Bb6 | Gm7 | Cm7 | F7"),
        ("A1", 8, a_changes),
        ("A2", 8, "Bb6 | Gm7 | Cm7 | F7 | Bb6 | Bb7 | Eb6 Edim7 | Bb6 F7"),
        ("B", 8, "Ebmaj7 | Ebmaj7 | Dm7 | G7 | Cm7 | F7 | Dm7 G7 | Cm7 F7"),
        ("A3", 8, "Bb6 | Gm7 | Cm7 | F7 | Bb6 | Bb7 | Eb6 Edim7 | Bb6 F7"),
        ("solo", 8, "Bb6 | Gm7 | Cm7 | F7 | Bb6 | Bb7 | Eb6 Edim7 | Dm7 G7"),
        ("shout", 8, "C6 | Am7 | Dm7 | G7 | C6 | C7 | F6 F#dim7 | C6 G7"),
        ("tag", 4, "Cm7 | F7 | Cm7 | F7"),
    ])

    # the head: "da-ba DAH, da-ba DAH", a cookie cutter bouncing round the outline
    head_front = """D5:2 F5:1 G5:3 F5:2 D5:1 Bb4:3 | D5:2 F5:1 Bb5:6 G5:3 | G5:2 Eb5:1 C5:3 Eb5:2 G5:1 Bb5:3 | A5:6 G5:2 F5:1 Eb5:3 |
                    D5:2 F5:1 G5:3 F5:2 D5:1 Bb4:3 | Ab4:2 Bb4:1 D5:3 F5:3 Ab5:3 | G5:3 C6:3 Bb5:2 G5:1 E5:3 |"""
    head_turn = melody(head_front + " F5:6 r:3 C5:2 C#5:1", SPB)  # leads back into the hook
    head_home = melody(head_front + " Bb4:9 r:3", SPB)  # lands on the tonic
    bridge = melody("""G5:3 Bb5:3 D6:6 | C6:2 Bb5:1 G5:3 Eb5:6 | F5:3 A5:3 C6:6 | B5:2 A5:1 G5:3 D5:6 |
                       Eb5:3 G5:3 Bb5:3 C6:3 | A5:6 F5:3 Eb5:3 | D5:3 F5:3 F5:2 D5:1 B4:3 | C5:3 Eb5:3 A4:3 C5:2 C#5:1""", SPB)
    bridge_counter = melody("G4:12 | G4:12 | F4:12 | F4:12 | Eb4:12 | Eb4:12 | D4:6 D4:6 | C4:6 Eb4:6", SPB)
    solo = melody("""F5:1 G5:1 F5:1 D5:2 F5:1 Bb5:3 A5:2 G5:1 | F5:3 D5:2 Bb4:1 G4:3 r:3 | r:1 Eb5:1 G5:1 Bb5:3 G5:2 Eb5:1 C5:3 | A5:2 C6:1 Eb6:3 C6:2 A5:1 F5:3 |
                     D6:6 C6:2 Bb5:1 G5:3 | Ab5:3 F5:2 D5:1 Bb4:3 D5:3 | Eb5:2 G5:1 Bb5:2 C6:1 Db6:2 Bb5:1 G5:2 E5:1 | A5:3 F5:3 F5:2 D5:1 D#5:3""", SPB)
    tag_line = melody("G5:3 Eb5:3 C5:6 | A4:3 C5:3 Eb5:6 | G5:3 Bb5:3 G5:2 Eb5:1 C5:3 | A4:6 r:3 C5:2 C#5:1", SPB)
    # intro: the vibes try the hook alone, softly
    tease = melody("""D5:2 F5:1 G5:3 F5:2 D5:1 Bb4:3 | D5:2 F5:1 Bb5:6 r:3 | G5:2 Eb5:1 C5:3 Eb5:2 G5:1 Bb5:3 | A5:9 r:3 |
                      D5:2 F5:1 G5:3 F5:2 D5:1 Bb4:3 | D5:2 F5:1 Bb5:6 r:3 | G5:2 Eb5:1 C5:3 Eb5:2 G5:1 Bb5:3 | A5:6 r:3 C5:2 C#5:1""", SPB)

    def vib(m, sec):
        return ins.vibes(m, max(0.5, sec), 4.5)

    def horns(m, sec):
        return ins.brass(m, sec, bright=0.45, section=3, vibrato=0.04)

    ride = ins.ride(1.0, 0.35)
    foot = s.hat(False)
    tap, swish = ins.brush(0.2), ins.brush(0.45, swish=True)
    snare = ins.snare2(210.0, 0.6, 0.22)
    kick = s.kick(0.6, 0.3)
    ding = [ins.glock(96, 0.8), ins.glock(91, 0.8)]

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            notes = voicing(c, 57, 70, prev, size=4)
            prev = notes
            seconds = length * tr.step
            if name == "intro":
                # the piano on beat 1 only, then the Charleston as the band gathers
                tr.add("piano", bar, step, ins.epiano(notes[0], seconds * 0.9), 0.5 if local < 4 else 0.0)
                if local >= 2:
                    strum(tr, "piano", bar, step, notes, ins.epiano, tr.beat * 1.5, 0.45 + 0.07 * (local - 2), spread=0.006)
                if local >= 5:
                    strum(tr, "piano", bar, step + 5, notes, ins.epiano, tr.step * 1.5, 0.35 + 0.08 * (local - 5), spread=0.004)
                continue
            if name in ("B", "tag"):
                # long chords from the vibes, the piano answering on the "and" of 2
                strum(tr, "comp", bar, step, [n + 12 for n in notes[:3]], vib, seconds, 0.75, spread=0.01)
                strum(tr, "piano", bar, step + 5, notes, ins.epiano, tr.step * 2, 0.8, spread=0.004)
            else:
                # Charleston comping: beat 1 and the swung "and" of 2
                strum(tr, "piano", bar, step, notes, ins.epiano, tr.step * 2, 1.0, spread=0.005)
                if length >= 12:
                    strum(tr, "piano", bar, step + 5, notes, ins.epiano, tr.step * 1.2, 0.8, spread=0.004)
                if name in ("A3", "shout") and length >= 12:
                    strum(tr, "piano", bar, step + 10, notes, ins.epiano, tr.step * 1.0, 0.6, spread=0.004)
            if name == "shout" and local % 2 == 1 and length >= 12:
                strum(tr, "horns", bar, 11, [n + 12 for n in notes[1:4]], horns, tr.step * 2.5, 1.0, spread=0.0)
            if name == "shout" and local % 2 == 0 and length >= 12:
                strum(tr, "horns", bar, 0, [n + 12 for n in notes[1:4]], horns, tr.step * 2.0, 0.9, spread=0.0)
                strum(tr, "horns", bar, 5, [n + 12 for n in notes[1:4]], horns, tr.step * 1.5, 0.8, spread=0.0)

        # bass: a two-feel creeping in under the intro, walking everywhere else
        if name == "intro":
            for bar, step, length, c in part.changes:
                local = bar - part.first
                if local >= 2:
                    root = bass_note(c, 36)
                    tr.add("bass", bar, 0, ins.upright(root, tr.beat * 1.8), 0.6 + 0.06 * local)
                    tr.add("bass", bar, 6, ins.upright(root + 7 if root + 7 <= 48 else root - 5, tr.beat * 1.8), 0.5 + 0.06 * local)
        else:
            walking_bass(tr, "bass", part, ins.upright, 1.0, low=36)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if local >= 3:
                    tr.drum("brush", bar, "x.xx.xx.xx.x", tap, 0.35 + 0.06 * (local - 3))
                if local >= 4:
                    tr.drum("brush", bar, "x...........", swish, 0.5)
                if local >= 5:
                    tr.drum("ride", bar, "x..x.xx..x.x", ride, 0.4 + 0.12 * (local - 5))
                    tr.drum("hats", bar, "...x.....x..", foot, 0.5)
                if local == 7:  # a snare fill into the drop
                    tr.drum("snare", bar, "......x.xxxX", snare, 0.7)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.25)
                continue
            big = name in ("A3", "shout")
            tr.drum("ride", bar, "x..x.xx..x.x", ride, 1.0 if name != "B" else 0.8)
            tr.drum("hats", bar, "...x.....x..", foot, 0.9)
            tr.drum("kick", bar, "x.....x....." if not big else "x..o..x..o..", kick, 0.7)
            # snare comping: ghosted swung 8ths, a few kicks of the "and"
            comp = ("..o..o..x..o", ".....x..o..x", "..o.....o.x.", "..x..o.....x")[local % 4]
            tr.drum("snare", bar, comp, snare, 0.55 if not big else 0.8)
            if name == "B":
                tr.drum("brush", bar, "x.....x.....", swish, 0.6)
            if local == 0:
                tr.add("ride", bar, 0, s.crash(1.8), 1.4, 0.2)
                if name in ("A1", "shout"):
                    tr.add("fx", bar, 0, ding[0], 0.8, 0.4)
                    tr.add("fx", bar, 3, ding[1], 0.6, 0.4)
            if local == part.bars - 1 and name in ("A2", "B", "solo", "shout"):
                tr.drum("snare", bar, ".......x.xxX", snare, 0.85)

    tr.play("lead2", 0, tease, vib, 0.7)
    tr.play("lead", 8, head_turn, ins.clarinet)
    tr.play("lead", 16, head_home, ins.clarinet)
    tr.play("lead2", 16, shift(head_home, -12), vib, 0.9)
    tr.play("lead", 24, bridge, vib, 0.65)
    tr.play("lead2", 24, bridge_counter, ins.clarinet, 0.8)
    tr.play("lead", 32, head_home, ins.clarinet)
    tr.play("lead2", 32, shift(head_home, 12), vib, 0.8)
    tr.play("lead", 40, solo, vib, 0.65)
    tr.play("lead", 48, shift(head_home, 2), ins.clarinet)
    tr.play("lead2", 48, shift(head_home, 14), vib, 0.85)
    tr.play("horns", 48, shift(head_home, 2 - 12), horns, 0.8, pan=-0.2)
    tr.play("lead", 56, tag_line, ins.clarinet)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.18, delay=0.05),
        "lead2": Bus(-12, reverb=0.22),
        "comp": Bus(-15, reverb=0.25),
        "piano": Bus(-12, reverb=0.15),
        "horns": Bus(-13, reverb=0.18),
        "bass": Bus(-8, eq=(("hp", 45),)),
        "ride": Bus(-16, reverb=0.08),
        "hats": Bus(-22),
        "kick": Bus(-17),
        "snare": Bus(-17, reverb=0.12),
        "brush": Bus(-21, reverb=0.1),
        "fx": Bus(-16, reverb=0.3),
    }, reverb_decay=1.4, reverb_tone=5500, delay_time=tr.beat * 2 / 3, delay_feedback=0.25)
    return finish(tr, mix), tr


SONG = Song("CrazyCutters", "Cookie Cutter Swing", 144, 8, 60, render)
