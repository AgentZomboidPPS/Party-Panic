"""Tick-Tock Takeoff: the round song for MechaMarathon (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from score import Note
from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


@lru_cache(maxsize=None)
def kick() -> np.ndarray:
    """A punchy kick tuned near 62 Hz (a phone still hears it), with the beater's tick."""
    n = s.samples(0.3)
    t = np.arange(n) / s.SR
    f = 62 + 130 * np.exp(-t / 0.022)
    body = np.sin(2 * np.pi * np.cumsum(f) / s.SR) * np.exp(-t / 0.085)
    beater = s.bandpass(ins._rng("kick").uniform(-1, 1, n), 1800, 5500) * np.exp(-t / 0.004) * 0.4
    return ins.normalize(np.tanh((body + beater) * 1.7))


@lru_cache(maxsize=None)
def hat() -> np.ndarray:
    n = s.samples(0.07)
    t = np.arange(n) / s.SR
    noise = ins.eq(ins._rng("hat").uniform(-1, 1, n), ("hp", 4000), ("lp", 8500), ("peak", 6500, 4, 1.5))
    return ins.normalize(noise * np.exp(-t / 0.015))


@lru_cache(maxsize=None)
def spring(length: float = 0.5) -> np.ndarray:
    """A coil spring let go: a wobbling 'boing' that rises and settles."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    f = 180 + 420 * (1 - np.exp(-t / 0.06)) + 90 * np.sin(2 * np.pi * 16 * t) * np.exp(-t / 0.18)
    tone = np.sin(2 * np.pi * np.cumsum(f) / s.SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(f) / s.SR)
    return ins.normalize(tone * np.exp(-t / 0.16) * np.clip(t / 0.005, 0, 1))


def play_struck(tr, stem, bar, notes, voice, gain=1.0, pan=0.0, roll=0, humanize=0.0):
    """Plays tines and mallets. A note struck again stops the one still ringing (a music box's tooth
    does), so fast repeats don't pile up in phase; with `roll`, a note that long or longer is re-struck
    every `roll` steps (a mechanical tremolo)."""
    rng = np.random.default_rng(int(bar * 1000 + len(notes)))
    hits = []
    for n in notes:
        if roll and n.length >= roll * 3:
            k = 0.0
            while k < n.length - 1e-6:
                hits.append((n.step + k, n.midi, min(roll, n.length - k), n.vel * (1.0 if int(k / roll) % 2 == 0 else 0.72)))
                k += roll
        else:
            hits.append((n.step, n.midi, n.length, n.vel))
    for i, (step, m, length, vel) in enumerate(hits):
        sound = np.asarray(voice(m, max(0.03, length * tr.step)))
        again = next((h[0] for h in hits[i + 1:] if h[1] == m), None)
        if again is not None:
            sound = ins._gate(sound, (again - step) * tr.step, 0.03)
        v = vel * (1 + rng.uniform(-humanize, humanize)) if humanize else vel
        tr.add(stem, bar, step, sound, gain * v, pan)


def mecha_marathon():
    """Tick-Tock Takeoff (144 bpm, D major): a clockwork march for the wind-up toy race on the sunny
    field. A music box carries the tune over ticking escapements, ratchets and a driving four-on-the-floor
    beat. GO opens ten seconds of frantic winding (its hook cranks up a key every two bars: D, E, F sharp),
    a held breath for READY..., then LAUNCH! lands the soaring march theme with brass and strings while the
    toys fly, a gliding-down cadence as they land, and a winner's fanfare that winds back up into GO."""
    tr = Track(bpm=144, bars=27)
    parts = plan(tr, [
        ("intro", 8, "D | D | Bm | Bm | G | G | A7 | A7"),
        ("wind", 6, "D A7 | D | E B7 | E | F# C#7 | F#"),
        ("ready", 1, "A7"),
        ("flight", 4, "D | Bm | G | A7"),
        ("landing", 4, "D | Bm | Em7 A7 | D"),
        ("tag", 4, "G | D/F# | Em7 | A7"),
    ])
    hook = melody("D5:1 E5:1 F#5:2 F#5:2 D5:2 E5:1 F#5:1 G5:2 G5:2 E5:2 | F#5:1 G5:1 A5:2 A5:2 F#5:2 D5:2 A4:2 D5:4")
    ready = melody("G5:12 D5:1 E5:1 F#5:1 G#5:1")
    theme = melody("""A5:3 A5:1 D6:3 F#6:1 A6:6 F#6:2 | B5:3 B5:1 D6:3 F#6:1 B6:6 A6:2 |
                      G6:3 F#6:1 E6:3 D6:1 B5:3 A5:1 G5:2 B5:2 | A5:3 C#6:1 E6:3 G6:1 ~:6 F#6:1 E6:1""")
    landing = melody("""A5:3 A5:1 D6:3 F#6:1 A6:6 F#6:2 | B5:3 B5:1 D6:3 F#6:1 B6:4 A6:2 G6:2 |
                        G6:3 E6:1 B5:2 G6:2 E6:3 C#6:1 A5:2 E6:2 | A6:4 F#6:2 E6:2 D6:8""")
    fanfare = melody("D5:2 G5:2 B5:2 D6:10 | C#6:2 D6:2 A5:4 F#5:8")
    rewind = melody("E5:1 F#5:1 G5:2 G5:2 E5:2 F#5:1 G5:1 A5:2 A5:2 F#5:2 | A5:2 G5:2 E5:2 C#5:2 A4:4 C#5:4")
    # the intro: the march theme slowly, at half speed, as the toy's music box plays it at rest
    slow = [Note(n.step * 2, n.midi, n.length * 2, n.vel) for n in theme if n.step < 16 * 3]

    def horn(m, sec):
        return ins.brass(m, sec, bright=0.6, section=3)

    def trumpet(m, sec):
        return ins.brass(m, sec, bright=1.0, section=2)

    bd, hh = kick(), hat()
    tick, tock = ins.rim_click(2400.0), ins.rim_click(1700.0)
    press = ins.clank(640.0, 0.3)
    clap = s.clap()
    crash = ins.eq(s.crash(2.0), ("lp", 9000))
    krk = ins.ratchet(0.09, 3)

    prev = None
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            root = bass_note(c, 38)
            notes = voicing(c, 62, 74, prev)
            prev = notes
            seconds = length * tr.step
            # the bass: clockwork octaves in 8ths (a held note while everyone waits for LAUNCH)
            if name == "ready":
                tr.add("bass", bar, 0, ins.synth_bass(root + 12, seconds * 0.95, cutoff=500, env_amt=500, sub=0.5), 1.0)
            elif name != "intro" or local >= 4:
                quiet = name == "intro"
                for k in range(int(length // 2)):
                    m = root + (12 if k % 2 else 0)
                    tr.add("bass", bar, step + 2 * k, ins.synth_bass(m, tr.step * 1.4, cutoff=650, env_amt=1500, sub=0.4),
                           (0.5 + 0.1 * (local - 4) if quiet else 1.0) * (0.85 if k % 2 else 1.0))
            # the gears: a xylophone arpeggio in 16ths
            if name in ("wind", "flight", "landing") or (name == "tag" and local < 2):
                ring = [n + 12 for n in voicing(c, 62, 74)]
                for k in range(int(length)):
                    m = ring[(0, 1, 2, 1, 3, 1, 2, 1)[k % 8] % len(ring)]
                    tr.add("xylo", bar, step + k, ins.xylophone(m, tr.step), 0.9 if k % 4 == 0 else 0.6, 0.3)
            # pads: strings while the toys fly, brass for the landing and the winner
            if name in ("ready", "flight", "landing") or (name == "tag" and local < 2):
                tr.add("strings", bar, step, ins.strings(tuple(notes), seconds, attack=0.15 if name != "ready" else 1.2, bright=0.55), 1.0)
            if name == "ready":  # the strings tremble, louder and louder
                for k in range(16):
                    for m in notes[:3]:
                        tr.add("strings", bar, k, ins.spiccato(m, tr.step * 1.2), (0.25 + 0.035 * k) * (1.0 if k % 2 == 0 else 0.8))
            if name in ("landing", "tag") or (name == "flight" and local >= 2):
                strum(tr, "brass", bar, step, [n - 12 for n in notes[:3]], horn, seconds * 0.95, 0.7 if name == "flight" else 0.85, spread=0.0)
            if name == "intro" and local >= 2:
                tr.add("strings", bar, step, ins.strings(tuple(n - 12 for n in notes[:3]), seconds, attack=0.8, bright=0.3), 0.35 + 0.08 * (local - 2))

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                tr.drum("tick", bar, "x...x...x...x...", tick, 0.35 + 0.04 * local, 0.3)
                tr.drum("tick", bar, "..x...x...x...x.", tock, 0.3 + 0.04 * local, -0.3)
                if local >= 2:  # somebody winds the key
                    tr.drum("ratchet", bar, "x...x...x...x..." if local < 6 else "x.x.x.x.x.x.x.x.", ins.ratchet(0.16, 5), 0.35 + 0.06 * local)
                if local >= 4:
                    tr.kick("kick", bar, "x...x...x...x...", bd, 0.45 + 0.08 * (local - 4))
                if local >= 6:
                    tr.drum("hat", bar, "..x...x...x...x.", hh, 0.5)
                if local == 7:
                    tr.drum("ratchet", bar, "........xxxxxxxx", krk, 0.6)
                    for k in range(8):
                        tr.add("clap", bar, 8 + k, press, 0.25 + 0.07 * k)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.45)
                continue
            if name == "ready":  # "READY...": the winding stops, a drum roll, a held breath
                for k in range(16):
                    tr.add("timp", bar, k, ins.timpani(45, 0.5, 0.5), 0.2 + 0.05 * k)
                tr.add("fx", bar, 0, s.riser(tr.bar), 0.5)
                tr.drum("tick", bar, "x.......x.......", tick, 0.5, 0.3)
                continue
            tr.kick("kick", bar, "x...x...x...x...", bd, 1.0)
            tr.drum("clap", bar, "....x.......x...", clap, 0.8)
            tr.drum("clap", bar, "....x.......x...", press, 0.7)
            if name == "wind":
                tr.drum("tick", bar, "x.x.x.x.x.x.x.x.", tick, 0.55, 0.3)
                tr.drum("tick", bar, ".x.x.x.x.x.x.x.x", tock, 0.45, -0.3)
                tr.drum("ratchet", bar, "..x...x...x...x.", krk, 0.8)
                if local % 2 == 0:  # each crank of the key: a long ratchet and a jolt
                    tr.add("ratchet", bar, 0, ins.ratchet(0.32, 10), 0.9)
                    tr.add("cymbal", bar, 0, crash, 1.0 if local == 0 else 0.7 + 0.1 * (local // 2), 0.2)
                if local == 0:  # GO
                    tr.add("timp", bar, 0, ins.timpani(38, 1.4, 1.0), 1.0)
            else:
                tr.drum("tick", bar, "x...x...x...x...", tick, 0.45, 0.3)
                tr.drum("tick", bar, "..x...x...x...x.", tock, 0.4, -0.3)
                tr.drum("hat", bar, "..x...x...x...x." if name == "tag" else "xxxxxxxxxxxxxxxx", hh, 0.55)
            if local == 0 and name in ("flight", "landing", "tag"):
                tr.add("cymbal", bar, 0, crash, 1.0, 0.2)
            if name == "flight" and local == 0:  # LAUNCH!
                tr.add("timp", bar, 0, ins.timpani(38, 1.6, 1.0), 1.0)
                tr.add("fx", bar, 0, ins.whoosh(1.6, True), 0.7)
            if name == "landing" and local == 3:  # touchdown
                tr.add("cymbal", bar, 8, crash, 1.0, -0.2)
                tr.add("timp", bar, 8, ins.timpani(38, 1.4, 0.9), 0.9)
                tr.add("fx", bar, 8, spring(0.5), 0.45)
                tr.drum("clap", bar, "....xxxx........", press, 0.6)
            if name == "tag" and local >= 2:  # winding up again
                tr.drum("ratchet", bar, "x.x.x.x.x.x.x.x." if local == 2 else "xxxxxxxxxxxxxxxx", krk, 0.5 + 0.2 * (local - 2))
                if local == 3:
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.4)

    # the tunes
    play_struck(tr, "lead", 0, slow, ins.music_box, 0.55)
    play_struck(tr, "lead2", 0, shift(slow, -12), ins.celesta, 0.3)
    play_struck(tr, "lead", 6, shift([n for n in theme if n.step >= 48], 0, -48), ins.music_box, 0.65, roll=1)
    for k, m in enumerate((57, 61, 64, 67, 69, 73, 76, 79)):  # a run up the dominant into GO
        tr.add("xylo", 7, 8 + k, ins.xylophone(m, tr.step), 0.6 + 0.05 * k, -0.2 + 0.05 * k)
    for k, key in enumerate((0, 2, 4)):  # the winding hook, a key higher every crank
        play_struck(tr, "lead", 8 + 2 * k, shift(hook, key), ins.music_box, 0.9 + 0.05 * k)
        play_struck(tr, "glock", 8 + 2 * k, shift(hook, key + 12), ins.glock, 0.35 + 0.1 * k)
    play_struck(tr, "lead", 14, ready, ins.music_box, 0.9, roll=1)
    play_struck(tr, "lead", 15, theme, ins.music_box, 1.0, roll=1, humanize=0.06)
    play_struck(tr, "glock", 15, theme, ins.glock, 0.5)
    play_struck(tr, "lead", 19, landing, ins.music_box, 1.0, roll=1, humanize=0.06)
    play_struck(tr, "glock", 19, landing, ins.glock, 0.6)
    tr.play("brass", 19, shift(landing, -12), trumpet, 0.9)
    tr.play("brass", 23, fanfare, trumpet, 1.0)
    play_struck(tr, "lead", 23, fanfare, ins.music_box, 0.7, roll=1)
    play_struck(tr, "glock", 23, fanfare, ins.glock, 0.6)
    tr.add("timp", 23, 0, ins.timpani(43, 1.2, 0.9), 0.8)
    play_struck(tr, "lead", 25, rewind, ins.music_box, 0.85)
    play_struck(tr, "glock", 25, shift(rewind, 12), ins.glock, 0.4)

    mix = Mix(buses={
        "lead": Bus(-6, eq=(("lp", 9000),), reverb=0.15, delay=0.06),
        "lead2": Bus(-16, reverb=0.25),
        "glock": Bus(-15, reverb=0.2),
        "brass": Bus(-10, reverb=0.18),
        "strings": Bus(-14, pump=0.15, reverb=0.25),
        "xylo": Bus(-17, reverb=0.12),
        "bass": Bus(-9, pump=0.2),
        "kick": Bus(-9, drive=1.3),
        "clap": Bus(-13, reverb=0.12),
        "tick": Bus(-19),
        "ratchet": Bus(-18, eq=(("lp", 8000),)),
        "hat": Bus(-21),
        "timp": Bus(-14, reverb=0.2),
        "cymbal": Bus(-18),
        "fx": Bus(-13, reverb=0.25),
    }, reverb_decay=1.4, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.28, pump_release=0.15)
    return finish(tr, mix), tr


SONG = Song("MechaMarathon", "Tick-Tock Takeoff", 144, 8, 27, mecha_marathon)
