"""Mirror Ball Showdown: the round song for LastDancer (see songkit.py for the rules every song keeps).

Last Dancer is a rhythm game, so this song is also its chart: the lead plays every note the dancers have to
tap (CHART_BARS below), a chord tone for each lane, and tools/music/lastdancer_chart.py writes the same
notes out for the game (src/shared/LastDancerChart.luau). Change a bar here and run that script again.
"""

from songkit import *  # noqa: F403 (the kit: score, instruments, synth and the song helpers)

BPM = 120
INTRO = 8  # bars before the drop (GO)
PHRASES = 8  # of 4 bars: the cuts come after phrases 2-7, the last phrase is the final duel

# The chart: one string per bar of the round (bar 0 is GO), 16 steps each, a digit for a note in that lane
# and a dot for nothing. Lane 1-4 is the chord's root, third, fifth and the root an octave up, so tapping
# the lanes plays arpeggios of the chord under them. Notes sit on eighth notes (even steps); every phrase
# that ends with a cut leaves its last beat free, for the drum fill.
CHART_BARS = [
    # phrase 1: the count-in bar, then quarter notes
    "................",
    "2...3...2...3...",
    "1...2...3...2...",
    "1...2...3...4...",
    # phrase 2: a first run of eighths (cut)
    "3...2...1...2.1.",
    "2...3...4...3.2.",
    "1...2.3.4...3.2.",
    "4...3...2.1.....",
    # phrase 3 (cut)
    "1.2.3...4.3.2...",
    "1.2.3.4...3.2.1.",
    "2.3.4...4.3.2.3.",
    "3.2.1.2.3.......",
    # phrase 4 (cut)
    "1.2.3.4.3.2.1.2.",
    "3.4.3.2.1.2.3...",
    "2.3.4.3.2.3.4.4.",
    "1.2.3.4.3.2.....",
    # phrase 5: wider jumps (cut)
    "1.4.1.4.2.3.2.3.",
    "4.1.4.1.3.2.3.2.",
    "1.2.3.4.4.3.2.1.",
    "2.3.2.3.4.......",
    # phrase 6 (cut)
    "1.2.3.4.3.2.1.4.",
    "4.3.2.1.2.3.4.3.",
    "1.3.2.4.1.3.2.4.",
    "4.3.4.3.2.1.....",
    # phrase 7: up a tone (cut)
    "1.2.3.4.1.2.3.4.",
    "4.3.2.1.4.3.2.1.",
    "1.4.2.3.1.4.2.3.",
    "2.3.4.3.2.......",
    # phrase 8: the final duel
    "1.2.3.4.3.2.1.2.",
    "3.4.3.4.2.3.2.3.",
    "4.3.2.1.1.2.3.4.",
    "1.2.3.4.4.......",
]

PROGRESSION = (
    ["C", "G", "Am", "F", "C", "G", "F", "G"]  # the intro
    + ["C", "G", "Am", "F"] * 4  # phrases 1-4
    + ["Am", "F", "C", "G"] * 2  # phrases 5-6
    + ["D", "A", "Bm", "G"] * 2  # phrases 7-8, up a tone
)


def chart_notes() -> list[tuple[float, int, int]]:
    """(seconds after GO, lane, bar of the round) for every note in CHART_BARS."""
    beat = 60 / BPM
    step = beat * 4 / 16
    notes = []
    for bar, text in enumerate(CHART_BARS):
        if len(text) != 16:
            raise ValueError(f"chart bar {bar} has {len(text)} steps, not 16: {text!r}")
        for k, ch in enumerate(text):
            if ch != ".":
                notes.append((round((bar * 16 + k) * step, 6), int(ch), bar))
    return notes


def mirror_ball():
    """Mirror Ball Showdown (120 bpm, C major, up to D for the last two phrases): a disco-house floor filler.
    The intro builds from a shimmer to the kick and a snare roll, the drop is the count-in bar, and every
    phrase adds a layer (claps, 16th hats, offbeat keys, a glock an octave up, a big saw chord for the
    last two) with a drum fill and a crash at each cut. The lead is the chart."""
    tr = Track(bpm=BPM, bars=INTRO + len(CHART_BARS))
    chords_by_bar = PROGRESSION
    parts = plan(tr, [
        ("intro", INTRO, " | ".join(chords_by_bar[:INTRO])),
        ("round", len(CHART_BARS), " | ".join(chords_by_bar[INTRO:])),
    ])
    lead_chords = {}
    for part in parts:
        for bar, step, length, c in part.changes:
            lead_chords[bar] = c

    kick, clap, snare = s.kick(1.1, 0.4), s.clap(), s.snare(0.2)
    ohat, chat, shaker = s.hat(True), s.hat(False), s.shaker()

    def lane_pitch(c, lane):
        root = bass_note(c, 69)
        third, fifth = c.intervals[1], c.intervals[2]
        return root + (0, third, fifth, 12)[lane - 1]

    prev = None
    for bar in range(tr.bars):
        c = lead_chords[bar]
        local = bar - INTRO  # bar of the round; negative in the intro
        phrase = local // 4  # 0-based phrase of the round
        in_phrase = local % 4
        notes = voicing(c, 55, 71, prev)
        prev = notes
        root = bass_note(c, 36)

        # ---- the pad under everything
        if bar < INTRO:
            tr.add("pad", bar, 0, ins.strings(tuple(n - 12 for n in notes[:3]), tr.bar, attack=0.7, bright=0.3), 0.6 + 0.05 * bar)
        else:
            tr.add("pad", bar, 0, ins.strings(tuple(notes), tr.bar, attack=0.1, bright=0.5 + 0.04 * phrase), 1.0)

        # ---- the beat
        fill = local >= 0 and in_phrase == 3 and 1 <= phrase <= 6  # the bar before a cut
        if bar >= 4:  # four on the floor, from the intro's second half
            tr.kick("kick", bar, "X...X...X...X...", kick, 1.0 if local >= 0 else 0.6 + 0.1 * (bar - 4))
        if bar >= 2:
            tr.drum("hats", bar, "..x...x...x....." if fill else "..x...x...x...x.", ohat, 0.55 if bar < INTRO else 0.7, 0.25)
        if local >= 4 or bar >= 6:  # claps on 2 and 4 from the second phrase (and the intro's last bars)
            tr.drum("clap", bar, "....X..........." if fill else "....X.......X...", clap, 0.9, 0.05)
        if local >= 8:  # 16th hats from the third phrase
            tr.drum("hats", bar, "xoxoxoxoxoxo...." if fill else "xoxoxoxoxoxoxoxo", chat, 0.45, -0.25)
        if local >= 0 and phrase >= 3:
            tr.drum("perc", bar, "xoxoxoxoxoxoxoxo", shaker, 0.8, 0.35)

        # ---- the bass: root and octave, eighths, with a pump from the kick
        if bar >= 4:
            for k in range(8):
                if fill and k >= 6:
                    continue
                tr.add("bass", bar, 2 * k, ins.synth_bass(root + (12 if k % 2 else 0), tr.step * 1.8, cutoff=600, env_amt=900), 0.85 if k % 2 else 1.0)

        # ---- offbeat keys from the second phrase
        if local >= 4:
            for k in (2, 6, 10, 14):
                if fill and k > 10:
                    continue
                strum(tr, "keys", bar, k, [n + 12 for n in notes[:3]], ins.epiano, tr.step * 1.5, 0.8, spread=0.004, pan=0.2)

        # ---- the lead: the chart. A doubled glock from the fifth phrase, a saw chord stab for the last two.
        if local >= 0:
            for k, ch in enumerate(CHART_BARS[local]):
                if ch == ".":
                    continue
                lane = int(ch)
                midi = lane_pitch(c, lane)
                tr.add("lead", bar, k, ins.synth_pluck(midi, tr.step * 2.2, bright=3600 + 400 * phrase), 1.0 if lane != 4 else 1.1, (lane - 2.5) * 0.12)
                if phrase >= 4:
                    tr.add("glock", bar, k, ins.glock(midi + 12, 0.3), 0.7, 0.25)
        elif bar >= 4:  # a hint of the tune in the intro, so the lanes' sound is no surprise
            for k, lane in ((0, 1), (4, 2), (8, 3), (12, 2)):
                tr.add("lead", bar, k, ins.synth_pluck(lane_pitch(c, lane), tr.step * 3, bright=2500), 0.55)

        # ---- the phrase's drum fill, the cut's crash and the risers
        if fill:
            for k, step in enumerate(range(12, 16)):
                tr.add("drums", bar, step, snare, 0.5 + 0.15 * k, 0.1)
            tr.add("fx", bar, 12, s.riser(tr.beat), 0.5 + 0.05 * phrase)
        if local >= 0 and in_phrase == 0:
            tr.add("hats", bar, 0, s.crash(), 1.6 if phrase >= 2 else 1.0, 0.2)
            if phrase >= 2:
                tr.add("fx", bar, 0, s.impact(), 0.7)
            if phrase >= 6:
                tr.add("lead2", bar, 0, s.supersaw([n for n in notes], tr.beat * 2, cutoff=5500), 0.8)
        if bar == INTRO - 1:  # the intro's last bar: snare roll and a riser into the drop
            for k in range(16):
                tr.add("drums", bar, k, snare, 0.2 + 0.05 * k, 0.1)
            tr.add("fx", bar, 0, s.riser(tr.bar), 0.7)
        if bar == tr.bars - 1:  # the loop's last bar leads back into the drop
            tr.add("fx", bar, 0, s.riser(tr.bar), 0.6)
        if bar == INTRO - 2 or bar == tr.bars - 2:
            tr.add("fx", bar, 8, s.downlifter(tr.bar / 2), 0.5)

    mix = Mix(buses={
        "lead": Bus(-6, reverb=0.15, delay=0.1),
        "lead2": Bus(-14, pump=0.2, reverb=0.2),
        "glock": Bus(-17, reverb=0.2, delay=0.1),
        "keys": Bus(-15, pump=0.25, delay=0.08),
        "bass": Bus(-8, pump=0.35),
        "pad": Bus(-15, pump=0.3, reverb=0.25),
        "kick": Bus(-8, drive=1.4),
        "drums": Bus(-12, reverb=0.12),
        "clap": Bus(-12, reverb=0.1),
        "hats": Bus(-17),
        "perc": Bus(-21),
        "fx": Bus(-15, reverb=0.3),
    }, reverb_decay=1.5, reverb_tone=6000, delay_time=tr.beat * 0.75, delay_feedback=0.3, pump_release=0.16)
    return finish(tr, mix), tr


SONG = Song("LastDancer", "Mirror Ball Showdown", BPM, INTRO, INTRO + len(CHART_BARS), mirror_ball)
