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
| `gold_pass_512.png` | **The GOLD PASS's icon** (the game pass, not the game): the Royal Crown, the gold lane's level 25 hat, on a gold sunburst with a GOLD PASS ribbon. Roblox shows pass icons round, so everything that matters sits inside the circle. |

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

**The GOLD PASS's icon**

1. Click **Creations**, then Party Panic.
2. In the menu on the left, under **Monetization**, click **Passes**, then **GOLD PASS**.
3. On the pass's page, change its image to `gold_pass_512.png` and click **Save Changes**.

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

The GOLD PASS's icon has its own script (same needs):

```sh
python tools/art/gold_pass_icon.py    # writes assets/store/gold_pass_512.png
```
