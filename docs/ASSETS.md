# Meshes and audio

All art props and audio are **original and generated from code**, so there's nothing to license.

| Folder | What | Generator |
| --- | --- | --- |
| `assets/meshes/*.obj, *.glb` | 15 toy-style props (shopping cart, glove, chest, trophy, trees...) | `python3 tools/meshgen/generate_meshes.py` |
| `assets/audio/music/*.ogg` | "Party Plaza" + "Sunset Social" (lobby playlist), "Panic Mode" (rounds) | `python3 tools/music/compose.py` |
| `assets/audio/sfx/*.ogg` | 15 sound effects, plus `SfxSprite.ogg` (all of them in one file) | same |
| `assets/audio/rounds/*.ogg` | each mini-game's own round track | `python3 tools/music/rounds.py` |

Requirements for regenerating: Python 3.10+, `numpy`, `scipy`, `scikit-image` (meshes), and
`ffmpeg` with libvorbis (audio).

![Props](images/props-preview.png)

## How the game uses them

The game works without uploading anything. Until the assets are uploaded:

- **Props** come from `World/MeshLibrary`'s fallbacks, which are small groups of rounded CSG
  shapes (they look decent but are less detailed).
- **Sound effects** use sounds that ship with the Roblox client.
- **Music** is silent.

After upload, `MeshLibrary` builds one template per prop from the uploaded mesh and clones it
everywhere. Identical MeshParts are GPU-instanced, so a lobby full of trees or a race full of
carts stays cheap on phones.

## Uploading (Open Cloud)

1. Create an Open Cloud API key at <https://create.roblox.com/dashboard/credentials> with the
   **Assets** API (read + write), and export it: `export ROBLOX_API_KEY=...`
2. Find the user or group id that **owns your game** (the game can only load meshes its creator
   owns).
3. Run:

```sh
python3 tools/upload_assets.py --user-id <id> --dry-run   # see the plan
python3 tools/upload_assets.py --user-id <id>             # upload and write ids into the config
rojo build -o build/PartyPanic.rbxl                        # rebuild with the real assets
```

This needs 15 model uploads and only **4 audio uploads** (3 tracks + 1 effects sprite). Roblox
allows 10 audio uploads a month without ID verification, and 100 with it. Uploads go through
moderation, and the game keeps using fallbacks until an asset is approved.

### Or import the meshes in Studio

Use **File > Import 3D** on `assets/meshes/<Prop>.obj` (or `.glb`), name the result after the
prop (`ShoppingCart`, `Trophy`, ...) and put it in `ServerStorage/MeshTemplates`. Studio templates
take priority over uploaded ids.

## Changing the music

`tools/music/compose.py` holds each song's chords, melodies and section plan. Edit and re-run
`python3 tools/music/compose.py --preview previews/` to get MP3s you can listen to. To use a track
from the Roblox audio library instead, paste its id into `src/shared/AudioAssets.luau`.

How the client plays music (`AudioController`):

- The lobby playlist **resumes** where it left off on each lobby visit, so players hear about
  4 minutes of music before anything repeats.
- Music starts at a gentle default volume and **fades in** over 6 seconds on first launch.
- Music **ducks** while a menu is open. Players choose Off / Low / Medium / High in Settings.
- The round track **speeds up** during the last 10 seconds.

## Mini-game round tracks

Every mini-game has its own round track (owner: "put in the backlog custom music for each mini
game"): an original song with its own band and tune, written as a lead sheet in
`tools/music/songs/<ModeId>.py` (the first three live in `tools/music/modes.py`, which also holds the
shared helpers and explains the plan). Each track opens with an intro of at least 13 seconds that
plays under the rules card and the 3-2-1, the band drops in on GO, then comes at least the round's
length of music (up to 90 s; longer rounds loop it seamlessly).

```sh
python3 tools/music/rounds.py --list                                  # songs, and modes without one
python3 tools/music/rounds.py --only SharkBait --preview /tmp/music   # render, check, encode, MP3
python3 tools/upload_assets.py --user-id <owner> --what rounds --only SharkBait
```

`rounds.py` checks the intro length, the length after the drop, loudness (-11 LUFS), true peak
(at most -1 dBTP), the loop seam and the low end (phone speakers), writes
`assets/audio/rounds/<ModeId>.ogg`, and regenerates `src/shared/RoundMusic.luau` (each track's drop
time and length). The upload writes the asset id into `AudioAssets.Rounds`. Each track is one audio
upload, and Roblox caps those per month, so upload the ones you mean with `--only`.

**Adding a track for a new mini-game:** copy one of `tools/music/songs/*.py`, write the new tune and
band, `SONG = Song("<ModeId>", "<Title>", bpm, intro_bars, bars, render)`, then render and upload it
as above. Nothing else changes: `AudioController` plays the mode's own track when `AudioAssets.Rounds`
has it, starting it so the drop lands exactly on GO, and plays "Panic Mode" for a mode without one
(or whose track doesn't load within 4 seconds). The round harness's client notes which music plays
(`music: ...` lines in the summary).

## Store art

`assets/store/` holds the experience icon (512×512) and five thumbnails (1920×1080): the lobby
key art, Fire Rope, Bobsled Run, Hex Meltdown and a "12 players" collage of Honey Trap, Rake It In
and Crazy Cutters, plus two other icon ideas. [assets/store/README.md](../assets/store/README.md)
says which is which and where to upload them (by hand in the Creator Hub: the API key can't).

They're rendered with Blender from snapshots of the real lobby and arenas (a few seconds of a round
played on a test server, like the portal previews), with the stand-in players swapped for posed
blocky avatars whose faces are drawn like Roblox face decals:

```sh
python tools/art/make_art.py --dumps art_dumps --fetch     # the snapshots (Open Cloud Luau execution)
python tools/art/make_art.py --dumps art_dumps --out art   # needs bpy and Pillow
```

Lettering uses Luckiest Guy (Apache 2.0, `tools/art/fonts/LICENSE.txt`), the same face as the
in-game signs.
