# Store art

The pictures people see before they join: the **icon** (the small square in Discover, search and
on phones) and the **thumbnails** (the big pictures on the game's page). They are rendered from the
real game: the lobby and the arenas come from snapshots of a test server, so what they show is
what players get.

| File | What it is |
| --- | --- |
| `icon_512.png` | **The icon.** A blocky player screaming in panic, hands up, party hat flying off, the fire rope sweeping in. |
| `icon_alt_duo.png` | Another icon idea, if you like it better: two friends, one laughing in a party hat, one screaming. |
| `icon_alt_leap.png` | Another icon idea: a player jumping the fire rope over the lava. |
| `thumb_1_lobby.jpg` | Thumbnail 1, **PARTY PANIC / VOTE THE CHAOS!**: a crowd in front of the vote stage, the four portals playing game previews. |
| `thumb_2_firerope.jpg` | Thumbnail 2, **JUMP THE FIRE ROPE!**: players in mid-air over the burning rope, the Dragon Temple behind. |
| `thumb_3_bobsled.jpg` | Thumbnail 3, **LEAN TO WIN THE BOBSLED RUN!**: a crew of three racing down the ice. |
| `thumb_4_hexmeltdown.jpg` | Thumbnail 4, **FIND YOUR COLOR / DON'T MELT!**: the referee calls YELLOW and the other hexes sink into the lava. |
| `thumb_5_party.jpg` | Thumbnail 5, **12 PLAYERS / TOTAL PARTY CHAOS!**: twelve friends in front of Honey Trap, Rake It In and Crazy Cutters. |

## Uploading them

The API key can't change the icon or the thumbnails, so this part is by hand, on
[create.roblox.com](https://create.roblox.com):

**The icon**

1. Click **Creations**, then Party Panic.
2. In the menu on the left, under **Configure**, click **Places**, then the start place (the one
   with the star).
3. Click **Icon**, then **Change**, pick `icon_512.png`, and click **Save Changes**.

**The thumbnails**

1. On the same place page, click **Thumbnails**.
2. Remove the old ones (they show mini-games that are gone: Yeet Arena, Shopping Cart Grand Prix,
   Floor Is Lava, Don't Get Flattened).
3. Upload `thumb_1_lobby.jpg` to `thumb_5_party.jpg` and drag them into that order: the first one
   is shown the most.
4. Click **Save Changes**.

Roblox checks every new image first, so they can take a few minutes to show up.

## Making them again

`tools/art/make_art.py` makes all of them (it needs Blender's Python module, `bpy`, and Pillow):

```sh
python tools/art/make_art.py --dumps art_dumps --fetch     # snapshot the lobby and arenas on a test server
python tools/art/make_art.py --dumps art_dumps --out art   # render everything into art/
```

`--only firerope,icon` renders just those; `--only sheet` puts the icons side by side at full size
and at 128 px (about as big as the Discover grid shows them) in `icon_sheet.png`. Copy the results
here when they look right.

## Ads

[`ads/`](ads) holds the loud versions: 1920x1080 pictures made to be clicked in a crowded feed (for
Roblox sponsored ads, or as extra thumbnails). Same real renders as above, framed as close-ups with one
giant screaming face, one obvious threat and a two-word headline. Nothing in them is a thing the game
doesn't have.

| File | Headline | What it shows |
| --- | --- | --- |
| `ads/ad_1_firerope.jpg` | **JUMP OR BURN!** | A giant screaming jumper over the Fire Rope, shot from the ground, the Dragon Temple behind. |
| `ads/ad_2_hexmeltdown.jpg` | **THE FLOOR IS MELTING!** | A player riding a sinking hex into the lava, the referee's YELLOW board and the safe hexes above. |
| `ads/ad_3_poster.jpg` | **PARTY PANIC** (30 GAMES! / 12 PLAYERS) | The brand ad: three big faces on a sunburst, the fire rope across the bottom. |
| `ads/ad_4_halloween.jpg` | **HALLOWEEN PARTY!** (2X COINS) | The event at dusk: the glowing Pumpkin Hat, a ghost, bats and jack-o'-lanterns. |
| `ads/ad_5_bobsled.jpg` | **HOLD ON!** | A crew hurtling down the Bobsled Run at the lens, ice spraying. |
| `ads/ads_sheet.jpg` | | All five at 640 px and at the ~320 px a feed shows them (the legibility check). |

Two things to know before running them:

- **The Halloween ad is only true while the event is on** (22 October to 1 November 2026), and
  **2X COINS is only on its two weekends** (24-25 October and 31 October-1 November, UTC). Run it
  for those days, or change the badge text in `scene_halloween`.
- At the ~320 px a feed shows them (the bottom strip of `ads_sheet.jpg`) every headline still reads;
  the smallest text is the poster's "12 PLAYERS" badge, which is the first thing to cut if it gets
  hard to read.

Make them again with `tools/art/make_ads.py` (same setup as `make_art.py`; it reads the same
snapshots, plus `lobby_halloween.json` for the Halloween ad):

```sh
python tools/art/make_ads.py --dumps art_dumps --out ads              # all the ads (a few minutes each)
python tools/art/make_ads.py --dumps art_dumps --out ads --preview    # small and quick, to look at
python tools/art/make_ads.py --dumps art_dumps --out ads --only firerope --set fov=55 --set rope_angle=20
python tools/art/make_ads.py --out ads --sheet                        # ads_sheet.jpg from what is in ads/
```

`--set key=value` tries a different framing without editing code (each scene's settings are at the top
of its function: `cam_x`, `aim_y`, `fov`, `hero_scale`, ...). `lobby_halloween.json` is the lobby
snapshot with the event's decorations on: run `tools/preview/dump_world.luau` with
`EventDecor.Show("Halloween")` added after the build, and `World/Props/RakeItIn` added to `PROPS` in
`tools/preview/bundle.py` (the decorations use its golden pumpkin mesh).
