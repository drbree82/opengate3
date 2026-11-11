# Sprites

Characters, monsters and props are drawn by code (`src/render/sprite_factory.gd`) from a small JSON
description, so a campaign needs no art files. See them all:

```bash
godot --headless --path . -s res://tools/sprite_gallery.gd -- /tmp/gallery.png        # data/sprite_samples.json
godot --headless --path . -s res://tools/sprite_gallery.gd -- /tmp/mine.png my_looks.json
```

A sprite definition (used in `entities.json`, monsters, and built automatically for characters):

```json
{"template": "humanoid", "height": 0.95, "look": { ... }}
```

`height` is the height of the whole frame in world units (a wall is 1.0 by default; a human is
0.95, a dwarf 0.8, a halfling 0.64). For player characters and companions the engine fills in
`race`, the class outfit, and the weapon and shield they have equipped.

## Humanoid look options

The art direction: every kind of character should read at a glance and suit who they are -
attractive where that fits the character (an elven enchantress, a classically handsome knight),
plain and sturdy where that fits (a farmhand), and unmistakably their own race (orc, gnome, dwarf).
Keep it tasteful: characters are always clothed, and nothing may be adult, offensive or unsuitable for
minors - that is also a condition of Paizo's Community Use Policy (docs/LICENSING.md).

| Key | Values | Notes |
|---|---|---|
| `race` | human, elf, half_elf, dwarf, gnome, halfling, half_orc, orc, goblin | changes proportions and features: long elf ears, dwarf width and beard, big gnome head and nose, bare halfling feet, tusks and brow for orcs, huge goblin ears |
| `body` | masculine, feminine | feminine: narrower waist, hips, lashes, lips, longer legs; masculine: broader shoulders, brows, square jaw |
| `build` | masculine: heroic, athletic, slim, rustic, heavy, stout. feminine: curvy, slender, athletic, rustic, heavy, stout. both: small | leave it out for the race's usual build. `heroic` = broad shoulders and V-taper; `curvy` = hourglass; `rustic` = stocky, plain; `heavy` = big all round |
| `age` | old | grey hair by default, lined eyes |
| `style` | skeleton, zombie | undead bodies |
| `skin`, `hair`, `top`, `bottom`, `boots`, `trim`, `cloak`, `skirt`, `lips`, `eyes` | `"#rrggbb"` | colours. `cloak` also adds the cloak. `eyes` is the iris colour |
| `hairStyle` | short, long, wavy, ponytail, bun, braids, curly, topknot, mohawk, bald, hood, helm, hat | `wavy` is long and voluminous; `hat` is a wizard hat |
| `beard` | true, "stubble", false | dwarven men are bearded unless `false` |
| `outfit` | tunic, armor, robe, dress, bodice, leather | `armor` adds pauldrons and greaves; `robe`/`dress` have skirts; `bodice` is fitted with lacing and bare arms |
| `sleeves` | true / false | bare arms |
| `weapon` | sword, dagger, axe, mace, staff, spear, bow, none | |
| `shield` | true / false | |
| `horns` | true or a colour | |
| `wings` | bat, feather (+ `wingColor`) | |
| `tail` | true | |

Examples to copy are in `data/sprite_samples.json`, for instance a succubus:

```json
{"race": "human", "body": "feminine", "build": "curvy", "skin": "#e8a8a8", "hair": "#1a0a14", "hairStyle": "wavy",
 "outfit": "bodice", "top": "#5a1028", "bottom": "#2a0a18", "horns": "#2a1018", "wings": "bat", "tail": true}
```

Each humanoid sheet has 7 animations (idle, walk, attack, cast, talk, hurt, dead) in 3 views
(front, back, side). The view is chosen from where the camera is relative to where the character faces.

## Other templates

Creatures: `rat`, `wolf`, `spider` (look: `fur` / `body` colour).
Props: `barrel`, `crate`, `sack`, `chest`, `table`, `bed`, `bookshelf`, `torch`, `brazier`, `campfire`,
`lamp_post`, `tree`, `pine`, `bush`, `rock`, `log`, `tent`, `well`, `sign`, `market_stall`, `anvil`,
`pillar`, `statue`, `altar`, `coffin`, `gravestone`, `bones`, `stairs`, `loot`.

## Using your own art

```json
{"sheet": "sprites/dragon.png", "frameW": 96, "frameH": 96, "views": 1, "height": 1.8,
 "anims": {"idle": {"row": 0, "frames": 2, "fps": 2}, "walk": {"row": 1, "frames": 4, "fps": 8},
           "attack": {"row": 2, "frames": 3, "fps": 9, "loop": false}, "dead": {"row": 3, "frames": 1}}}
```

The PNG lives in the campaign folder. One row per animation, one column per frame, transparent
background, the creature facing right. With `"views": 3` each animation uses three rows: front, back, side.

## Changing the generator

- A new prop or creature: add a branch in `_draw_simple()`, list it in `TEMPLATES`
  (and in `_simple_frames()` / `CREATURES` if it animates), add it to `data/props.json`.
- Humanoid bodies are built from the numbers returned by `_figure()` (head, shoulder, waist, hip,
  torso and leg sizes). To add a build, add an entry to the `builds` tables there. To add a race,
  add a branch to the `match race` block. Hair styles are in `_hair()` (front/back) and `_side()`.
- Drawing uses `Px` (src/render/px.gd): record rectangles, and `stamp()` adds the dark outline.
- Always look at the result with `tools/sprite_gallery.gd` before finishing.

## Portraits

`npm run portraits -- <campaign>` paints a portrait for each companion and named NPC with
ElevenLabs image generation and saves `campaigns/<id>/portraits/<id>.png`. The game shows a
portrait when the file exists and falls back to the pixel sprite otherwise. See docs/VOICE.md.
