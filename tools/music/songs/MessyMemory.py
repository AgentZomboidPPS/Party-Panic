"""Tidy-Up Tango: the round song for MessyMemory (see songkit.py for the rules every song keeps)."""

from functools import lru_cache

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)


def _sealed(x: np.ndarray) -> np.ndarray:
    x.setflags(write=False)  # cached notes are shared: nobody changes them in place
    return x


def _faded(x: np.ndarray, seconds: float = 0.008) -> np.ndarray:
    """Brings a one-shot's last few milliseconds down to silence, so it never ends on a click."""
    k = min(x.shape[-1], s.samples(seconds))
    x[..., -k:] *= np.linspace(1, 0, k)
    return x


@lru_cache(maxsize=None)
def bandoneon(notes: tuple, length: float, swell: float = 0.0) -> np.ndarray:
    """The tango's bandoneon: reedy and drier than a musette accordion (two reeds nearly in tune and a
    quiet octave reed); `swell` is the bellows pushing a long note louder as it goes. Stereo."""
    n = s.samples(length + 0.08)
    t = np.arange(n) / s.SR
    out = np.zeros(n)
    for m in notes:
        for d, w in ((-0.03, 1.0), (0.03, 0.85), (12.01, 0.3)):
            out += w * s.square(s.midi_hz(m + d), n, 0.38)
    out /= 2.15 * max(1, len(notes)) ** 0.7
    out = ins.eq(out, ("lp", 2300), ("peak", 1100, 4, 1.3), ("peak", 500, 2, 1.0), ("hp", 170))
    e = ins.env(n, 0.018, 0.3, 0.72, 0.06, gate=length)
    if swell:
        e = e * (1 + swell * np.clip(t / max(length, 0.05), 0, 1) ** 2)
    out = out * e
    return _sealed(ins.normalize(np.vstack([out, np.roll(out, 7)])))


@lru_cache(maxsize=None)
def violin(midi: float, length: float) -> np.ndarray:
    """The tango violin: short notes bitten off, long ones scooped into from below."""
    if length < 0.27:
        return ins.fiddle(midi, length * 0.7, accent=1.0)
    return ins.fiddle(midi, length, glide_from=midi - 1.5 if length > 0.7 else None)


@lru_cache(maxsize=None)
def clock(high: bool) -> np.ndarray:
    """The toy shop's clock: tick (high) or tock (low), an escapement's click, a little metal ping
    and the wooden case's knock."""
    n = s.samples(0.09)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(3 if high else 4)
    click = s.bandpass(rng.uniform(-1, 1, n), 2000, 6000) * np.exp(-t / 0.0025)
    ping = np.sin(2 * np.pi * (3150 if high else 2350) * t) * np.exp(-t / 0.012)
    case = np.sin(2 * np.pi * (1250 if high else 820) * t) * np.exp(-t / 0.02)
    return _sealed(_faded(ins.normalize(click * 0.8 + ping * 0.3 + case * 0.6)))


@lru_cache(maxsize=None)
def chicharra(length: float = 0.13) -> np.ndarray:
    """The tango violinist's 'chicharra' (cicada): the bow dragged behind the bridge, a rasping zzt."""
    n = s.samples(length)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(21)
    grabs = np.maximum(0, np.sin(2 * np.pi * 88 * t)) ** 6  # the bow's stick-slip
    rasp = s.bandpass(rng.uniform(-1, 1, n), 900, 4200) * (0.25 + grabs)
    body = s.bandpass(s.saw(np.full(n, 88.0), n), 300, 1500) * 0.35
    e = np.clip(t / 0.006, 0, 1) * np.exp(-t / (length * 0.45))
    return _sealed(_faded(ins.normalize((rasp + body) * e)))


@lru_cache(maxsize=None)
def poof() -> np.ndarray:
    """The mischief-makers' puff of smoke: a soft boom and a rush of air that blooms and fades."""
    n = s.samples(1.6)
    t = np.arange(n) / s.SR
    rng = np.random.default_rng(31)
    boom = s.sine(60 + 110 * np.exp(-t / 0.04), n) * np.exp(-t / 0.22)
    air = ins.tv_lowpass(rng.uniform(-1, 1, n), 250 + 4200 * np.exp(-t / 0.3), q=0.8)
    air = air * np.clip(t / 0.012, 0, 1) * np.exp(-t / 0.5)
    return _sealed(ins.normalize(ins.eq(boom * 0.9 + air, ("lp", 7000))))


@lru_cache(maxsize=None)
def squeak(rise: float = 1.0) -> np.ndarray:
    """A rubber toy squashed as it lands: a nasal squeal up and back down."""
    n = s.samples(0.16)
    t = np.arange(n) / s.SR
    f = 950 + 650 * rise * np.sin(np.pi * np.clip(t / 0.15, 0, 1))
    tone = ins.eq(s.square(f, n, 0.3), ("peak", 1700, 8, 3.0), ("lp", 3600), ("hp", 500))
    return _sealed(ins.normalize(tone * np.sin(np.pi * np.clip(t / 0.155, 0, 1)) ** 0.5))


def messy_memory():
    """Tidy-Up Tango (120 bpm, G minor): the toy shop's after-hours tango. A sly violin over a bandoneon,
    string stabs and a ticking clock while the shelf is studied; a puff of smoke and tumbling toys; then
    the band digs in for the 30-second put-back (the clock ticking faster, up to A minor for the last
    seconds) and stops dead on the tango's 'chan-chan'. The reveal tiptoes on pizzicato and a ding for
    every toy until the winner's ta-da, and a bandoneon run leads back round."""
    tr = Track(bpm=120, bars=36)
    parts = plan(tr, [
        ("intro", 8, "Gm | Gm | Gm | D7 | Gm | Cm | Eb | D7"),
        ("study", 4, "Gm | Gm | D7 | D7"),
        ("poof", 2, "C#dim7 | D7"),
        ("tidy", 8, "Gm | Gm | D7 | D7 | Gm | G7 | Cm D7 | Gm"),
        ("swirl", 4, "Eb | F | Dm | E7"),
        ("hurry", 4, "Am | Am | E7 | E7 E7 E7 Am"),
        ("reveal", 6, "Am | F | Dm | E7 | A | D7"),
    ])
    theme = melody("""D5:6 Eb5:6 D5:4 | C5:2 Bb4:2 A4:2 Bb4:2 G4:8 | C5:6 D5:6 C5:4 | Bb4:2 A4:2 G4:2 A4:2 F#4:8 |
                      D5:6 Eb5:6 D5:4 | F5:2 Eb5:2 D5:2 C5:2 B4:8 | C5:2 Eb5:2 G5:2 Eb5:2 F#5:2 A5:2 C6:2 A5:2 | G5:4 D5:2 Bb4:2 G4:4 r:4""")
    swirl = melody("G5:6 Bb5:2 G5:4 Eb5:4 | A5:6 C6:2 A5:4 F5:4 | D6:6 C6:2 A5:4 F5:4 | B5:4 G#5:4 E5:4 D5:2 D#5:2")
    hurry = melody("E5:6 F5:6 E5:4 | D5:2 C5:2 B4:2 C5:2 A4:8 | D5:6 E5:6 D5:4 | C5:2 B4:2 A4:2 B4:2 G#4:2! r:2 A4:2! r:2")
    opening = melody("D5:6 Eb5:2 D5:4 G4:4 | Bb4:3 A4:1 Bb4:4 G4:8 | A4:3 Bb4:1 C5:4 Eb5:4 C5:4 | D5:12 r:4")
    climb = melody("C5:4 Eb5:4 G5:8 | Eb5:4 G5:4 Bb5:8 | A5:8 r:8")
    whisper = melody("E5:8 F5:4 E5:4 | C5:8 D5:4 C5:4 | A4:8 Bb4:4 A4:4 | G#4:12 r:4")
    swirl_box = melody("Bb4:16 | C5:16 | A4:16 | B4:8 G#4:8")

    tick, tock = clock(True), clock(False)
    zzt = chicharra()
    tambor = ins.snare2(240.0, 0.45, 0.16)
    kick = s.kick(0.9, 0.35)
    timp = {m: ins.timpani(m, 1.2, 0.7) for m in (40, 43, 45)}

    def bass(bar, step, m, steps, gain=1.0):
        tr.add("bass", bar, step, ins.upright(m, tr.step * steps), gain)

    def drag_into(bar, target, gain=0.7):
        """The arrastre: the bass drags into the next downbeat from a half step below."""
        tr.add("bass", bar, 15, ins.upright(target - 1, tr.step * 0.9), gain)

    def stab(bar, step, notes, gain=1.0, steps=0.9):
        tr.add("stabs", bar, step, ins.strings(tuple(notes), tr.step * steps, attack=0.004, bright=0.8, release=0.12), gain)

    def box(bar, step, notes, steps, gain=1.0, swell=0.0):
        tr.add("box", bar, step, bandoneon(tuple(notes), tr.step * steps, swell), gain)

    # the toy shelf after hours: the clock alone, then a twinkle
    for k, m in enumerate((67, 70, 74, 79)):
        tr.add("sparkle", 0, 8 + k * 2, ins.celesta(m, 0.5), 0.5 + 0.1 * k, -0.3 + 0.2 * k)

    prev = None
    changes = [ch for part in parts for ch in part.changes]
    following = {(b, st): changes[(i + 1) % len(changes)][3] for i, (b, st, _, _) in enumerate(changes)}
    following[(35, 0)] = parts[1].changes[0][3]  # the last bar leads into the drop (the loop goes back to GO)
    for part in parts:
        name = part.name
        for bar, step, length, c in part.changes:
            local = bar - part.first
            nxt = following[(bar, step)]
            root = bass_note(c, 36)
            fifth = root + (c.intervals[2] if len(c.intervals) > 2 else 7)
            target = bass_note(nxt, 36)
            notes = voicing(c, 50, 64, prev)  # under the violin's lowest notes
            prev = notes
            high = voicing(c, 62, 77)
            seconds = length * tr.step
            if name == "intro":
                if 2 <= local < 7:
                    g = 0.45 + 0.08 * local
                    bass(bar, 0, root, 6, g)
                    bass(bar, 8, fifth, 6, g * 0.85)
                if local >= 3:
                    tr.add("pad", bar, 0, ins.strings(tuple(notes), seconds, attack=0.7, bright=0.3), min(0.7, 0.4 + 0.1 * (local - 3)))
                if local in (4, 5, 6):
                    for k in (4, 12):
                        box(bar, k, notes, 1.5, 0.5 + 0.1 * local)
                if local in (5, 6):
                    for k in (0, 8):
                        stab(bar, k, high, 0.35 + 0.15 * (local - 5))
                if local == 7:  # marcato in four, swelling, then the breath before GO
                    for k, g in ((0, 0.5), (4, 0.6), (8, 0.7), (12, 0.85)):
                        stab(bar, k, high, g)
                        box(bar, k, notes, 1.5, g)
                        bass(bar, k, root if k < 8 else root + 12, 3 if k < 12 else 2, g)
                continue
            if name == "study":
                if local == 0:  # GO: the whole band lands on the downbeat
                    tr.add("stabs", bar, 0, ins.strings(tuple(high + [high[0] + 12]), tr.step * 3, attack=0.004, bright=0.9, release=0.3), 1.2)
                bass(bar, 0, root, 5)
                bass(bar, 8, fifth, 5, 0.85)
                if local % 2 == 1:
                    drag_into(bar, target)
                for k, g in ((0, 1.0), (4, 0.7), (8, 0.9), (12, 0.7)):
                    box(bar, k, notes, 1.4, g)
                stab(bar, 0, high, 0.8)
                stab(bar, 8, high, 0.6)
            elif name == "poof":
                if local == 0:  # a shock chord as the smoke goes off
                    tr.add("stabs", bar, 0, ins.strings(tuple(high), tr.step * 6, attack=0.004, bright=0.9, release=0.6), 1.2)
                    box(bar, 0, notes, 5, 1.0)
                    bass(bar, 0, root, 8)
                else:  # stop-time 3-3-2 stabs, winding back up
                    for k in (0, 6, 12):
                        stab(bar, k, high, 1.0)
                        box(bar, k, notes, 1.5, 0.9)
                        bass(bar, k, root if k != 6 else fifth, 2)
                    drag_into(bar, target, 0.9)
            elif name in ("tidy", "hurry"):
                ending = name == "hurry" and bar == part.first + 3  # chan-chan
                for k, m, g in ((0, root, 1.0), (4, root + 12, 0.75), (8, fifth, 0.9), (12, root + 12, 0.75)):
                    if k < length:
                        bass(bar, step + k, m, 3, g)
                for k in range(0, int(length), 4):
                    accent = 1.0 if (step + k) % 8 == 0 or (ending and step + k == 12) else 0.75
                    stab(bar, step + k, high, accent)
                    box(bar, step + k, notes, 1.4, accent * 0.9)
                for k in range(0, int(length), 2):  # the motor: spiccato 8ths (16ths in the last stretch)
                    if ending and step + k >= 8:
                        break  # nothing under the last two chords
                    pitches = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[1] + 12]
                    tr.add("ostinato", bar, step + k, ins.spiccato(pitches[(k // 2) % 4], 0.12), 1.0 if k % 4 == 0 else 0.8, 0.25)
                    if name == "hurry":
                        tr.add("ostinato", bar, step + k + 1, ins.spiccato(pitches[(k // 2 + 1) % 4], 0.1), 0.6, -0.25)
                if name == "tidy" and local in (3, 7):
                    drag_into(bar, target)
            elif name == "swirl":  # the sincopa: 3+3+2, with the strings singing over it
                for k, m in ((0, root), (6, fifth), (12, root + 12)):
                    bass(bar, k, m, 3 if k == 12 else 4, 1.0 if k == 0 else 0.85)
                    stab(bar, k, high, 1.0 if k == 0 else 0.8)
                    box(bar, k, notes, 2.0, 0.9)
                tr.add("pad", bar, 0, ins.strings(tuple(n + 12 for n in notes), seconds, attack=0.25, bright=0.55), 0.6)
                for k in range(0, 16, 2):
                    tr.add("ostinato", bar, k, ins.spiccato(notes[(k // 2) % len(notes)] + 12, 0.12), 0.9 if k % 4 == 0 else 0.7, 0.25)
                if local == 3:
                    drag_into(bar, target, 0.9)
            elif name == "reveal":
                if local < 4:  # tiptoeing pizzicato under the reveal, a toy at a time
                    lo = bass_note(c, 45)
                    line = [lo, lo + 7, lo + 12, lo + 7, lo + (c.intervals[1] % 12) + 12, lo + 7, lo + 12, lo + 7]
                    for k, m in enumerate(line):
                        tr.add("pizz", bar, k * 2, ins.pizz(m, 0.25), 1.0 if k % 2 == 0 else 0.7, -0.2)
                    bass(bar, 0, root, 12, 0.7)
                    tr.add("pad", bar, 0, ins.strings(tuple(notes), seconds, attack=0.5, bright=0.3), 0.7 + 0.1 * local)
                elif local == 4:  # the winner's ta-da
                    tr.add("stabs", bar, 0, ins.strings(tuple(high + [high[0] + 12]), tr.step * 7, attack=0.004, bright=0.9, release=0.5), 1.3)
                    box(bar, 0, notes, 6, 1.0)
                    bass(bar, 0, root, 8)
                else:  # back round: the strings swell and the bass drags into the drop
                    tr.add("pad", bar, 0, ins.strings(tuple(notes), seconds, attack=1.4, bright=0.5, release=0.1), 1.0)
                    bass(bar, 8, root, 3, 0.8)
                    bass(bar, 12, root + 12, 2, 0.8)
                    drag_into(bar, target, 0.9)

        for bar in part.bars_range():
            local = bar - part.first
            if name == "intro":
                g = 0.35 + 0.06 * local
                for k in (0, 4, 8, 12):
                    tr.add("clock", bar, k, tock if k % 8 == 0 else tick, g, 0.15)
                if local == 6:
                    tr.drum("scrape", bar, "....x.......x...", zzt, 0.6)
                if local == 7:
                    tr.drum("scrape", bar, "....x.......x...", zzt, 0.7)
                    for k in range(8, 16):
                        tr.add("scrape", bar, k, tambor, 0.15 + 0.07 * (k - 8), 0.1)
                    tr.add("fx", bar - 1, 0, s.riser(tr.bar * 2), 0.2)
                    tr.kick("kick", bar, "X...x...x...x...", kick, 0.6)
                continue
            if name == "study":
                for k in (0, 4, 8, 12):
                    tr.add("clock", bar, k, tock if k % 8 == 0 else tick, 0.8, 0.15)
                tr.kick("kick", bar, "X.......x.......", kick, 0.8)
                tr.drum("scrape", bar, "....x.......x...", zzt, 0.75)
                if local == 0:
                    tr.add("cymbal", bar, 0, s.crash(), 1.8, 0.2)
                    tr.add("timp", bar, 0, timp[43], 1.0)
                if local % 2 == 1:  # the toys on the shelf twinkle
                    for k, m in enumerate((79, 82, 86, 91)):
                        tr.add("sparkle", bar, 12 + k, ins.celesta(m, 0.4), 0.6, 0.3)
            elif name == "poof":
                if local == 0:
                    tr.add("fx", bar, 0, poof(), 1.3)
                    tr.add("cymbal", bar, 0, s.crash(), 2.0, -0.2)
                    tr.add("fx", bar, 0, ins.whoosh(0.9, up=False), 0.5, 0.3)
                    for k, (p, pan) in enumerate(((560.0, -0.5), (470.0, 0.4), (390.0, -0.2), (330.0, 0.5), (280.0, -0.4))):
                        tr.add("fx", bar, 4 + k * 2, ins.log_drum(p, 0.25), 0.8, pan)  # toys tumbling off the shelf
                    tr.add("fx", bar, 9, squeak(1.0), 0.55, 0.45)
                    tr.add("fx", bar, 13, squeak(0.6), 0.45, -0.45)
                    for k, m in enumerate((85, 82, 79, 76, 73, 70, 67, 64)):
                        tr.add("sparkle", bar, 8 + k, ins.xylophone(m, 0.15), 0.7, -0.3 + 0.08 * k)
                    tr.add("fx", bar, 4, ins.slide_whistle(84, 62, 1.3), 0.35, 0.2)
                else:
                    tr.kick("kick", bar, "X.....X.....X...", kick, 0.9)
                    tr.drum("scrape", bar, "...x.....x......", zzt, 0.8)
                    tr.add("fx", bar, 3, ins.ratchet(0.4, 10), 0.5, 0.3)
                    for k in range(12, 16):
                        tr.add("scrape", bar, k, tambor, 0.45 + 0.12 * (k - 12), 0.1)
                    for k in range(0, 16, 2):
                        tr.add("clock", bar, k, tick, 0.6 + 0.02 * k, 0.15)
            elif name in ("tidy", "swirl"):
                for k in range(0, 16, 2):
                    tr.add("clock", bar, k, tock if k % 4 == 0 else tick, 0.85 if k % 4 == 0 else 0.7, 0.15)
                tr.kick("kick", bar, "X.......X......." if name == "tidy" else "X.....x.....x...", kick, 0.9)
                tr.drum("scrape", bar, "....x.......x...", zzt, 0.9)
                tr.drum("scrape", bar, "..............o." if local % 2 == 0 else ".............oo.", tambor, 0.6, 0.1)
                if local == 0:
                    tr.add("cymbal", bar, 0, s.crash(), 1.6, 0.2)
            elif name == "hurry":
                last = local == 3
                for k in range(0, 8 if last else 16):  # the clock in a panic
                    tr.add("clock", bar, k, tock if k % 4 == 0 else tick, 0.85 if k % 2 == 0 else 0.6, 0.15)
                if not last:
                    tr.kick("kick", bar, "X...x...X...x...", kick, 0.95)
                    tr.drum("scrape", bar, "....x.......x.xx", zzt, 0.9)
                else:  # chan-chan
                    tr.kick("kick", bar, "X...x...X...X...", kick, 1.0)
                    tr.drum("scrape", bar, "....x...........", zzt, 0.9)
                    tr.add("cymbal", bar, 12, s.crash(1.6), 1.8, -0.2)
                    tr.add("timp", bar, 12, timp[45], 1.0)
                if local == 0:
                    tr.add("cymbal", bar, 0, s.crash(), 1.8, 0.2)
            elif name == "reveal":
                if local < 4:
                    for k in (0, 4, 8, 12):
                        tr.add("clock", bar, k, tock if k % 8 == 0 else tick, 0.6, 0.15)
                if local == 3:  # the drumroll before the winner
                    for k in range(16):
                        tr.add("timp", bar, k, ins.timpani(40, 0.5, 0.4), 0.25 + 0.04 * k)
                    for k in range(8, 16):
                        tr.add("scrape", bar, k, tambor, 0.3 + 0.06 * (k - 8), 0.1)
                if local == 4:
                    tr.kick("kick", bar, "X...............", kick, 1.0)
                    tr.add("cymbal", bar, 0, s.crash(2.4), 2.0, 0.2)
                    tr.add("timp", bar, 0, timp[45], 1.0)
                    for k, m in enumerate((81, 85, 88, 93)):
                        tr.add("sparkle", bar, 2 + k, ins.glock(m, 0.5), 0.8, -0.3 + 0.2 * k)
                if local == 5:
                    tr.add("clock", bar, 0, tock, 0.6, 0.15)
                    tr.add("clock", bar, 4, tick, 0.6, 0.15)
                    for k in range(8, 16):
                        tr.add("scrape", bar, k, tambor, 0.3 + 0.07 * (k - 8), 0.1)
                    tr.add("fx", bar, 0, s.riser(tr.bar), 0.25)

    # the reveal's dings, one toy at a time, climbing
    for bar, pair in zip(range(30, 34), ((81, 84), (84, 89), (86, 89), (88, 92))):
        for k, m in zip((0, 8), pair):
            tr.add("sparkle", bar, k, ins.glock(m, 0.6), 0.9, 0.3 if k else -0.3)

    def squeezebox(m, sec):
        return bandoneon((m,), sec, 0.25 if sec > 0.9 else 0.0)

    tr.play("solo", 1, [n for n in opening if n.step < 32], squeezebox, 0.5)  # softly at first, then growing
    tr.play("solo", 1, [n for n in opening if n.step >= 32], squeezebox, 0.68)
    tr.play("lead", 5, climb, violin, 0.75)
    tr.play("solo", 7, melody("r:8 A4:1 C5:1 D5:1 Eb5:1 F#5:1 A5:1 C6:1 r:1"), lambda m, sec: bandoneon((m,), sec), 0.9)
    tr.play("lead", 8, [n for n in theme if n.step < 4 * 16], violin)
    tr.play("lead", 13, melody("r:8 A4:2 Bb4:2 B4:2 C#5:2"), violin, 0.85)  # winding back up
    tr.play("lead", 14, theme, violin)
    tr.play("double", 14, shift(theme, -12), lambda m, sec: bandoneon((m,), sec * 0.9))
    tr.play("lead", 22, swirl, violin)
    tr.play("double", 22, swirl_box, lambda m, sec: bandoneon((m,), sec, 0.35), 0.8)
    tr.play("lead", 26, hurry, violin)
    tr.play("double", 26, hurry, lambda m, sec: bandoneon((m,), sec * 0.9))
    tr.play("pad", 26, shift(hurry, 12), lambda m, sec: ins.strings((m,), sec, attack=0.03, bright=0.6, release=0.15), 0.7)
    tr.play("solo", 30, whisper, lambda m, sec: bandoneon((m,), sec, 0.2), 0.75)
    tr.play("lead", 33, melody("r:14 E5:2 | A5:8! r:8"), violin)
    tr.play("solo", 35, melody("r:8 D4:1 F#4:1 A4:1 C5:1 D5:1 F#5:1 A5:1 C6:1"), lambda m, sec: bandoneon((m,), sec), 0.9)

    mix = Mix(buses={
        "lead": Bus(-5, reverb=0.18, delay=0.05),
        "solo": Bus(-8, reverb=0.2),
        "double": Bus(-13, reverb=0.12),
        "box": Bus(-11, reverb=0.12),
        "stabs": Bus(-12, reverb=0.15),
        "pad": Bus(-16, reverb=0.3),
        "ostinato": Bus(-16, reverb=0.1),
        "bass": Bus(-9),
        "pizz": Bus(-14, reverb=0.2),
        "clock": Bus(-16, reverb=0.08),
        "scrape": Bus(-17, reverb=0.08),
        "kick": Bus(-13, drive=1.3, eq=(("hp", 45),)),
        "sparkle": Bus(-15, reverb=0.3, delay=0.12),
        "fx": Bus(-12, reverb=0.25, eq=(("lp", 7000),)),
        "cymbal": Bus(-20, reverb=0.1, eq=(("lp", 9000),)),
        "timp": Bus(-15, reverb=0.2),
    }, reverb_decay=1.7, reverb_tone=5500, delay_time=tr.beat * 0.75, delay_feedback=0.28)
    return finish(tr, mix), tr


SONG = Song("MessyMemory", "Tidy-Up Tango", 120, 8, 36, messy_memory)
