"""Crayon Cruise: the round song for TraceRace (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from score import Note
from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


# ---------------------------------------------------------------- an 80s synth-pop band's sounds

def _vibrato(t, depth, rate, delay, rise):
    return depth * np.clip((t - delay) / rise, 0, 1) * np.sin(2 * np.pi * rate * t)


@lru_cache(maxsize=None)
def pop_lead(m, sec, glide_from=None):
    """The lead synth: three detuned saws and a square an octave down, a filter that blips open on
    every note, delayed vibrato, and a short portamento into notes it glides to."""
    n = s.samples(sec + 0.2)
    t = np.arange(n) / s.SR
    pitch = m + _vibrato(t, 0.15, 5.5, 0.22, 0.25)
    if glide_from is not None:
        pitch = pitch + (glide_from - m) * np.exp(-t / 0.035)
    tone = sum(s.saw(s.midi_hz(pitch + d), n, start=k * 0.31) for k, d in enumerate((-0.08, 0.0, 0.08))) / 3
    tone = tone + 0.45 * s.square(s.midi_hz(pitch - 12), n, 0.5)
    e = ins.env(n, 0.006, 0.25, 0.75, 0.12, gate=sec)
    cutoff = 1300 + 3000 * np.exp(-t / 0.18) + s.midi_hz(m) * 2
    tone = ins.tv_lowpass(tone * e, cutoff, q=1.3)
    return ins.normalize(ins.eq(tone, ("hp", 200), ("peak", 2400, 2, 1.0), ("lp", 7000)))


@lru_cache(maxsize=None)
def gated_snare(variant=0):
    """The 80s snare: a fat snare into a big room that a noise gate chops off short."""
    n = s.samples(0.34)
    t = np.arange(n) / s.SR
    body = np.asarray(ins.snare2(185.0, 0.9, 0.3, variant))
    room = ins.eq(np.random.default_rng(100 + variant).uniform(-1, 1, n), ("hp", 300), ("lp", 6500), ("peak", 1800, 3, 1.0))
    gate = np.clip(t / 0.004, 0, 1) * (0.5 + 0.5 * np.exp(-t / 0.05)) * (1 - np.clip((t - 0.19) / 0.03, 0, 1))
    out = room * gate * 0.45
    out[: len(body)] += body[:n]
    return ins.normalize(out)


@lru_cache(maxsize=None)
def simmons(pitch, length=0.45):
    """An electronic hexagon-pad tom: a sine that dives in pitch, a little square edge and a stick tick."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    f = pitch * (1 + 1.1 * np.exp(-t / 0.05))
    tone = s.sine(f, n) + 0.2 * ins.eq(s.square(f, n, 0.5), ("lp", 1800))
    tick = s.bandpass(np.random.default_rng(int(pitch)).uniform(-1, 1, n), 400, 3500) * np.exp(-t / 0.012) * 0.35
    return ins.normalize(ins.drive((tone * np.exp(-t / (0.35 * length)) + tick), 1.3))


@lru_cache(maxsize=None)
def scribble(length=0.5, seed=0):
    """A crayon scribbling across paper: waxy strokes of scratchy noise, back and forth."""
    n = s.samples(length)
    rng = np.random.default_rng(seed)
    strokes = np.zeros(n)
    pos = 0
    while pos < n:
        dur = int(rng.uniform(0.045, 0.085) * s.SR)
        seg = np.sin(np.pi * np.linspace(0, 1, min(dur, n - pos))) ** 2 * rng.uniform(0.5, 1.0)
        strokes[pos:pos + len(seg)] += seg
        pos += dur
    paper = s.bandpass(rng.uniform(-1, 1, n), 1200, 5200)
    grain = 0.6 + 0.4 * np.abs(s.lowpass(rng.uniform(-1, 1, n), 300)) / 0.3
    return ins.normalize(paper * strokes * np.clip(grain, 0, 1.6))


def lead_line(tr, stem, bar, notes, voice, gain=1.0, pan=0.0):
    """Plays a lead with portamento: a held note (a quarter or longer) straight after a near one glides in."""
    last = None
    for n in notes:
        glide = None
        if last is not None and n.length >= 4 and n.step - (last.step + last.length) < 0.5 and 0 < abs(n.midi - last.midi) <= 7:
            glide = last.midi
        tr.add(stem, bar, n.step, voice(n.midi, max(0.05, n.length * tr.step * 0.95), glide), gain * n.vel, pan)
        last = n


def octave_up(notes, ceiling=96):
    """A doubling an octave up, staying in unison where that would climb past `ceiling` (C7)."""
    return [Note(n.step, n.midi + (12 if n.midi + 12 <= ceiling else 0), n.length, n.vel) for n in notes]


def zigzag(root, scale):
    """The winding-line motif from a chord's root: up a third, back a step, up a third... (8 eighths)."""
    pcs = sorted(scale)
    base, i = root - root % 12, pcs.index(root % 12)
    return [base + pcs[(i + k) % 7] + 12 * ((i + k) // 7) for k in (0, 2, 1, 3, 2, 4, 3, 4)]


# ---------------------------------------------------------------- the song

def trace_race():
    """Crayon Cruise (140 bpm, A minor): an 80s synth-pop drive down a giant crayon's guideline. The
    intro draws a scribble and opens an arpeggio's filter bar by bar; at GO a zig-zag synth riff that
    winds like the line rides a bright octave bass, gated snares and Simmons toms (0-14 s after GO),
    then a syncopated chorus hook in C (14-27 s) and a half-time loop-the-loop bridge that climbs
    (27-34 s). The last chorus goes up a step to D with an 'aah' choir and the zig-zag riff winding
    under the hook for the final straight (34-48 s; the 45 s round ends in its seventh bar), and a
    short fill drops back down to the riff for the loop."""
    tr = Track(bpm=140, bars=36)
    parts = plan(tr, [
        ("intro", 8, "Am | Am | F | G | Am | Am | F | E"),
        ("drive", 8, "Am | F | C | G | Am | F | Dm | E"),
        ("chorus", 8, "F | G | Em | Am | F | G | C | C"),
        ("loop", 4, "Bb | C | D | F#"),
        ("final", 8, "G | A | F#m | Bm | G | A | D | E"),
    ])
    riff = melody("""A4:2 C5:2 B4:2 D5:2 C5:2 E5:2 D5:2 E5:2 | F5:6 E5:2 C5:4 A4:4 |
                     G4:2 C5:2 B4:2 D5:2 C5:2 E5:2 D5:2 G5:2 | G5:6 F5:2 D5:4 B4:4 |
                     A4:2 C5:2 B4:2 D5:2 C5:2 E5:2 D5:2 E5:2 | F5:6 E5:2 C5:4 A4:4 |
                     A4:2 D5:2 C5:2 F5:2 E5:2 A5:2 G5:2 F5:2 | E5:4 G#5:4 B5:4 D6:4""")
    hook = melody("""C6:3 C6:3 A5:2 C6:4 D6:2 C6:2 | B5:3 B5:3 G5:2 B5:4 C6:2 B5:2 |
                     G5:3 G5:3 E5:2 G5:2 A5:2 B5:4 | A5:12 r:2 E5:2 |
                     C6:3 C6:3 A5:2 C6:4 D6:2 C6:2 | D6:3 D6:3 B5:2 D6:4 E6:2 D6:2 |
                     E6:4 D6:2 C6:2 G5:4 E5:2 G5:2 | C6:12 r:4""")
    climb = melody("D5:4 F5:4 Bb5:8 | E5:4 G5:4 C6:8 | F#5:4 A5:4 D6:8 | C#6:16")
    home = melody("B5:4 G#5:2 E5:2 D5:4 B4:2 G#4:2")  # the last bar: back down to the riff's A
    teaser = melody("A4:2 C5:2 B4:2 D5:2 C5:2 E5:2 D5:2 E5:2 | E5:6 D5:2 C5:4 A4:4")

    kick = s.kick(1.0, 0.4)
    snare = gated_snare()
    roll = ins.snare2(200.0, 0.8, 0.12, variant=3)
    clap = s.clap()
    chat, ohat = s.hat(False), s.hat(True)
    tick = ins.rim_click(1700.0)
    toms = [simmons(p) for p in (220.0, 165.0, 120.0)]
    d_major, e_mixolydian = (2, 4, 6, 7, 9, 11, 1), (4, 6, 8, 9, 11, 1, 2)

    # the opening: a crayon drawn across the page, then the arpeggio wakes up
    tr.add("scribble", 0, 0, scribble(0.9, 1), 0.35, -0.3)
    tr.add("scribble", 1, 8, scribble(0.6, 2), 0.3, 0.3)
    tr.add("scribble", 3, 8, scribble(0.8, 3), 0.45, -0.2)
    tr.play("bell", 4, teaser, lambda m, sec: ins.fm(m + 12, min(sec, 0.5), 3.5, 1.2, 0.5, mod_decay=0.06), 0.8, pan=0.15)
    tr.add("fx", 6, 0, s.riser(tr.bar * 2), 0.55)

    prev_arp, prev_pad = None, None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 28)  # the bass plays it an octave up (E2 to E flat 3) and pops the octave above
            seconds = length * tr.step * (0.6 if name == "final" and local == 7 else 1.0)  # no tails round the loop
            arp = voicing(c, 57, 69, prev_arp, size=3)
            prev_arp = arp
            pad = voicing(c, 55, 67, prev_pad, size=4 if len(c.intervals) > 3 else 3)
            prev_pad = pad
            ring = arp + [arp[0] + 12, arp[1] + 12]
            # ---- the arpeggio
            if name == "intro":
                bright = 150 + 380 * local  # the filter opens bar by bar
                level = 0.35 + 0.08 * local
                for k, idx in enumerate((0, 1, 2, 3, 1, 2, 3, 2) * 2):
                    tr.add("arp", bar, k, ins.synth_pluck(ring[idx], tr.step * 0.9, bright=bright), level * (1.0 if k % 2 == 0 else 0.8), 0.3 if k % 4 == 1 else -0.2)
            elif name in ("drive", "chorus"):
                pattern = (0, 1, 2, 3, 1, 2, 3, 2) if name == "drive" else (0, 2, 3, 4, 3, 2, 1, 2)
                for k, idx in enumerate(pattern * 2):
                    tr.add("arp", bar, k, ins.synth_pluck(ring[idx], tr.step * 0.9, bright=3200), 1.0 if k % 4 == 0 else 0.75, 0.35 if k % 2 else -0.35)
            elif name == "loop":  # loop-the-loop: up and over, two octaves
                big = ring + [arp[2] + 12]
                for k, idx in enumerate((0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5)):
                    tr.add("arp", bar, k, ins.synth_pluck(big[idx], tr.step * 1.1, bright=1200 + 700 * local), 0.6, 0.5 * np.sin(k * np.pi / 8))
            # ---- bass
            if name == "intro":
                if local >= 4:
                    for k in range(8):
                        tr.add("bass", bar, 2 * k, ins.synth_bass(root + 12, tr.step * 1.6, cutoff=380 + 120 * local, env_amt=900 + 250 * (local - 4), sub=0.35), 0.4 + 0.1 * (local - 4))
            elif name == "loop":
                if local < 3:
                    tr.add("bass", bar, 0, ins.synth_bass(root + 12, tr.step * 7, cutoff=500, env_amt=700, sub=0.4), 0.8)
                    tr.add("bass", bar, 8, ins.synth_bass(root + 12, tr.step * 7, cutoff=500, env_amt=700, sub=0.4), 0.7)
                else:
                    for k in range(16):
                        tr.add("bass", bar, k, ins.synth_bass(root + (24 if k % 2 else 12), tr.step * 0.8, cutoff=600, env_amt=1500 + 100 * k, sub=0.3), 0.6 + 0.025 * k)
            else:
                for k in range(8):
                    m = root + (24 if k % 2 else 12)
                    tr.add("bass", bar, 2 * k, ins.synth_bass(m, tr.step * 1.5, cutoff=750, env_amt=2600, sub=0.35, q=1.5), 1.0 if k % 2 == 0 else 0.8)
            # ---- pads and stabs
            if name == "intro":
                tr.add("pad", bar, 0, ins.strings(tuple(pad), seconds, attack=1.0 if local == 0 else 0.4, bright=0.3 + 0.04 * local), 0.45 + 0.06 * local)
            elif name == "drive":
                tr.add("pad", bar, 0, ins.strings(tuple(pad), seconds, attack=0.3, bright=0.45), 0.7)
            elif name in ("chorus", "final"):
                tr.add("pad", bar, 0, ins.strings(tuple(pad + [pad[0] + 12]), seconds, attack=0.04, bright=0.7), 1.0)
                for st in (6, 14):  # synth-brass stabs on the off-beats
                    strum(tr, "stabs", bar, st, [n + 12 for n in pad[:3]], lambda m, sec: ins.brass(m, sec, bright=1.2, section=2, vibrato=0.0), tr.step * 1.2, 1.0, spread=0.0)
            elif name == "loop":
                tr.add("pad", bar, 0, ins.strings(tuple(pad), seconds, attack=0.6, bright=0.4 + 0.1 * local), 0.9)
            # ---- the final straight: the zig-zag riff winds under the hook, a big 80s 'aah' choir
            if name == "final":
                tr.add("choir", bar, 0, ins.choir(tuple(n + 12 for n in pad[:3]), seconds, "ah", attack=0.12), 1.0)
                for k, idx in enumerate((0, 2, 3, 4, 3, 2, 1, 2) * 2):
                    tr.add("arp", bar, k, ins.synth_pluck(ring[idx] + 12, tr.step * 0.8, bright=2600), 0.55 if k % 4 == 0 else 0.4, 0.4 if k % 2 else -0.4)
                scale = d_major if local < 7 else e_mixolydian
                for k, m in enumerate(zigzag(bass_note(c, 55), scale)):
                    tr.add("zig", bar, 2 * k, ins.synth_pluck(m, tr.step * 1.7, bright=2600), 1.0 if k % 2 == 0 else 0.8, -0.25)

        # ---- drums
        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                if 2 <= local < 4:
                    tr.drum("perc", bar, "x...x...x...x...", tick, 0.35 + 0.1 * (local - 2))
                if local >= 4:
                    tr.kick("kick", bar, "X...X...X...X...", kick, 0.4 + 0.1 * (local - 4))
                    tr.drum("hats", bar, "..x...x...x...x." if local < 6 else "x.x.x.x.x.x.x.x.", chat, 0.5)
                if local == 6:
                    tr.drum("snare", bar, "....X.......X...", snare, 0.75)
                if local == 7:
                    tr.drum("snare", bar, "....X...........", snare, 0.8)
                    for k in range(8, 16):
                        tr.add("snare", bar, k, roll, 0.25 + 0.07 * (k - 8))
                    for k, st in enumerate((10, 11, 12, 13, 14, 15)):
                        tr.add("toms", bar, st, toms[min(2, k // 2)], 0.7 + 0.04 * k)
                continue
            if name == "loop":  # half time: the line loops, the band holds its breath
                tr.kick("kick", bar, "X.........X....." if local < 3 else "X...X...X...X...", kick, 0.75)
                tr.drum("snare", bar, "........X......." if local < 3 else "....X.......X...", snare, 0.7)
                tr.drum("hats", bar, "x.x.x.x.x.x.x.x.", chat, 0.45)
                tr.drum("toms", bar, "......x.......x." if local < 3 else "................", toms[1], 0.55)
                if local == 3:
                    for k in range(16):
                        tr.add("snare", bar, k, roll, 0.1 + 0.035 * k)
                    for k, st in enumerate((12, 13, 14, 15)):
                        tr.add("toms", bar, st, toms[k // 2 + (1 if k == 3 else 0)], 0.8)
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.6)
                if local == 0:
                    tr.add("cymbal", bar, 0, s.crash(), 1.0, -0.2)
                    tr.add("scribble", bar, 4, scribble(1.2, 7), 0.6, 0.4)
                continue
            big = name in ("chorus", "final")
            tr.kick("kick", bar, "X...X...X...X...", kick, 1.0)
            tr.drum("snare", bar, "....X.......X...", snare, 1.0)
            tr.drum("hats", bar, "xoxoxoxoxoxoxoxo" if big else "x.xox.xox.xox.xo", chat, 0.6)
            if big:
                tr.drum("claps", bar, "....X.......X...", clap, 1.0, 0.1)
                tr.drum("hats", bar, "..x...x...x...x.", ohat, 0.5, 0.25)
            if local % 4 == 0:
                tr.add("cymbal", bar, 0, s.crash(), 1.0 if local == 0 else 0.7, 0.2 if local else -0.2)
            if name == "final" and local == 7:  # back to the drop: a short fill (nothing rings round the loop)
                for k, st in enumerate((8, 10, 12)):
                    tr.add("toms", bar, st, simmons((220.0, 165.0, 120.0)[k], 0.22), 0.8)
                tr.drum("snare", bar, "..............xx", roll, 0.6)
            elif local % 4 == 3:
                if local == 7 or name == "final":  # a Simmons fill into the next phrase
                    for k, st in enumerate((12, 13, 14, 15)):
                        tr.add("toms", bar, st, toms[k // 2 + (1 if k == 3 else 0)], 0.8)
                else:
                    tr.add("scribble", bar, 12, scribble(0.4, 10 + local + part.first), 0.55, 0.3)

    # ---- the tunes
    tr.play("lead", 8, riff, lambda m, sec: pop_lead(m, sec), 1.0, legato=0.85)
    lead_line(tr, "lead", 16, hook, pop_lead, 1.0)
    tr.play("lead2", 16, octave_up(hook), lambda m, sec: ins.synth_pluck(m, sec, bright=2400), 0.9, pan=0.2)
    lead_line(tr, "lead", 24, climb, pop_lead, 0.85)
    final = [n for n in shift(hook, 2) if n.step < 7 * 16] + shift(home, 0, 7 * 16)
    lead_line(tr, "lead", 28, final, pop_lead, 1.0)
    tr.play("lead2", 28, octave_up([n for n in final if n.step < 7 * 16]), lambda m, sec: ins.synth_pluck(m, sec, bright=2400), 0.9, pan=0.2)

    mix = Mix(buses={
        "lead": Bus(-5.5, reverb=0.15, delay=0.16),
        "lead2": Bus(-16, reverb=0.2, delay=0.2),
        "bell": Bus(-12, reverb=0.25, delay=0.25),
        "zig": Bus(-13, pump=0.15, delay=0.12),
        "arp": Bus(-14, pump=0.25, delay=0.22, reverb=0.1),
        "pad": Bus(-15, pump=0.35, reverb=0.25),
        "stabs": Bus(-16, pump=0.2, reverb=0.2),
        "bass": Bus(-9.5, pump=0.25),
        "kick": Bus(-10, drive=1.3),
        "snare": Bus(-12, reverb=0.1),
        "claps": Bus(-16, reverb=0.15),
        "hats": Bus(-19),
        "toms": Bus(-15, reverb=0.15),
        "choir": Bus(-15, pump=0.2, reverb=0.3),
        "perc": Bus(-19, reverb=0.1),
        "cymbal": Bus(-19),
        "scribble": Bus(-18, reverb=0.12),
        "fx": Bus(-16, reverb=0.3),
    }, reverb_decay=1.5, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.33, pump_release=0.15)
    return finish(tr, mix), tr


SONG = Song("TraceRace", "Crayon Cruise", 140, 8, 36, trace_race)
