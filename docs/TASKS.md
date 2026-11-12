# Task backlog

How to use this file: pick ONE task, read the files it names, make the change, add a test, run
`./check.sh`, look at a screenshot if it is visual, then tick the task here and note any
follow-ups. Tasks are grouped by area and marked **[S]** small (one file, under an hour),
**[M]** medium (a few files), **[L]** large (design needed - split it first).
Each task says where the code is and what "done" means.

## Good first tasks

- [x] **[S] Paint the portraits.** Done 2026-11-12: twelve portraits in `campaigns/hollowmere/portraits/*.webp`,
  made on the ElevenLabs website (the API still refuses image generation below the Pro plan). How to make
  matching ones for new characters: docs/VOICE.md, "Portraits". `tests/test_hollowmere.gd test_portraits` guards them.

- [x] **[M] Creature sheets in the journal.** Done 2026-11-12: Journal -> Creatures lists what the party has fought;
  pointing at a name (there, or in a "You face: ..." story line) opens a tooltip with the stat block and
  plain-English strengths, weaknesses and powers (`src/rules/monster_lore.gd`, `journal_panel.gd`).
  Follow-ups: [S] show the same tooltip when the mouse rests on an enemy in the 3D view or on its initiative
  chip (`combat_hud.gd on_hover`, call `main.journal.show_creature(id)`); [S] hide numbers until a Knowledge
  check succeeds (optional rule, `campaign.rules`).
- [x] **[M] Bodies and allies in the way.** Done 2026-11-12: bodies never block, allies can be walked through
  (not stopped on), monsters queue up behind their own front line instead of standing still, and a body's
  sprite no longer steals mouse clicks from someone standing behind it (`encounter.gd can_pass/can_stop`,
  `combat_ai.gd _approach`, `world_view.gd pick`). Tests: `tests/test_engine.gd test_combat_movement_rules`.

- [ ] **[S] Item tooltips.** `src/ui/sheet_panel.gd` `_gear()`: show weapon damage/crit and armor numbers
  as a tooltip (`[hint=...]` BBCode). Done: hovering an item in Gear shows its stats.
- [ ] **[S] More passive feats.** `data/feats.json`: add Skill Focus variants, Run, Endurance, Spell Focus
  (needs a `spellDC.<school>` modifier target in `spell_rules.gd dc_of`). Done: test in `tests/test_rules.gd`.
- [ ] **[S] More monsters.** `data/monsters.json`: kobold, orc, ghoul, bat swarm stand-in, ogre. Give each a
  sprite look (docs/SPRITES.md). Done: `./check.sh` passes; they show in `tools/render_map.gd` on a test map.
- [ ] **[S] More props.** `sprite_factory.gd _draw_simple()`: cart, fence, banner, fountain, bookshelf variants,
  stalagmite. Add to `TEMPLATES` and `data/props.json`.
- [ ] **[S] Combat log colours.** `src/ui/journal_panel.gd _format()`: colour hits, misses and criticals differently.
- [ ] **[S] Settings: volume sliders.** `src/ui/pause_menu.gd` + `audio_bank.gd` (sfx, voice, music volume).
- [ ] **[S] Hit-chance preview.** `src/ui/combat_hud.gd on_hover()`: show "65% to hit" for the hovered enemy
  (needed roll = AC - attack bonus). Done: visible in the `combat` screenshot tour.
- [ ] **[S] Skill Focus chooser in the builder.** `src/ui/builder_screen.gd _feat_entry()` currently always
  picks Perception; add a small OptionButton.
- [ ] **[S] Fighter bonus feats must be combat feats.** `builder_screen.gd` / `levelup_screen.gd`: enforce `"combat": true`.

## Rules

- [ ] **[M] Full attacks.** Iterative attacks at BAB +6/+11/+16 as a full-round action.
  `char_rules.gd` (attack list), `encounter.gd` (new action `full_attack` using both move and standard), `combat_ai.gd`, `combat_hud.gd`.
- [ ] **[M] Power Attack and other toggles.** A "stance" list on the actor that adds modifiers while on.
  `data/feats.json` (`"toggle": true`), `char_rules.collect_mods`, a toggle button in `combat_hud.gd`.
- [ ] **[M] Poison and disease.** Giant spider poison, dire rat filth fever: an effect with a save each round/day.
  `effects.gd` (tick with save), `data/monsters.json` (`"onHit": {...}`), `encounter.gd _strike`.
- [ ] **[M] Combat manoeuvres.** Trip, bull rush, grapple using CMB vs CMD (`stats.cmb`, `stats.cmd` exist).
- [ ] **[M] Cast defensively + concentration; arcane spell failure in armor.**
- [ ] **[M] Evasion, uncanny dodge, trap sense** (rogue features listed as "not yet implemented" in `data/classes.json`).
- [ ] **[M] Spell preparation.** Replace "any known spell per slot" with prepared slots for wizard/cleric
  (UI at rest in camp). Keep the old behaviour as a campaign rule option `rules.simpleCasting`.
- [ ] **[M] Cleric domains, wizard schools and arcane bond.**
- [ ] **[M] More spells** (levels 1-3): colour spray, grease, shield, enlarge person, web, invisibility, fireball,
  spiritual weapon, prayer. Some need new effect kinds (walls, summons) - split those out.
- [ ] **[L] More classes**: barbarian (rage), ranger (favoured enemy), paladin (smite, lay on hands), bard, sorcerer, druid, monk.
  Start with barbarian and sorcerer (least new machinery).
- [ ] **[M] Multiclassing.** Characters store one `cls` + `level`; change to a list of class levels.
- [ ] **[S] Spell slot tables to level 20** in `data/classes.json`.
- [ ] **[M] Proper movement rules.** 5-foot step as its own action, withdraw, charge, reach weapons, cover.
- [ ] **[M] Stealth and surprise.** Sneaking up on a group (Stealth vs Perception) grants a surprise round;
  `Game.start_combat(group, "party")` already supports it.
- [ ] **[S] Encumbrance and ammunition** (optional rule in `campaign.rules`).
- [ ] **[S] Cache derived stats.** `Game.stats()` re-derives every call; cache per actor and invalidate on change.

## Engine

- [ ] **[M] Patrols and schedules.** NPCs/monsters that walk between markers (`"patrol": ["a", "b"]` on an entity),
  handled in `World.update`.
- [ ] **[M] LLM Game Master (optional).** A provider that writes narration for unscripted actions and reacts to
  free-text input. Keep ALL dice in `src/rules`; the model only narrates. Hook: `GM` in `src/engine/gm.gd`.
- [ ] **[M] Day/night and time.** `state.day` exists; add hours, map `"sky"` per time, shops closing.
- [ ] **[M] Multi-level maps.** Stairs connecting maps with `exit` exist; add per-tile wall heights and floor steps in `RoomBuilder`.
- [ ] **[M] Companion banter and approval consequences.** `state.approval` is tracked; add barks on events
  and dialogue conditions (`{"approval": {"id": "pip", "min": 2}}`).
- [ ] **[M] Save slots UI + save migration** (`SAVE_VERSION` in game.gd).
- [ ] **[M] Fast travel / world map** between known maps.
- [ ] **[L] Multiplayer.** The engine is already UI-free (`GameIO`); a network `GameIO` per player and an
  authoritative host are the path. Design first.
- [ ] **[M] In-game campaign editor** (map painter that writes the JSON format).
- [ ] **[S] Loot from individual monsters** (`"loot"` on a stat block) in addition to `encounters.json`.
- [ ] **[S] Stealing / pickpocket op** using Sleight of Hand.

## Rendering and audio

- [ ] **[S] Door opening animation** (`RoomBuilder.build_doors` makes separate slabs: rotate instead of removing).
- [ ] **[S] Flickering torch light** and animated water texture.
- [ ] **[M] Spell and hit particles** (`WorldView.spell_fx` is a single glow today).
- [ ] **[M] 3D dice** in the dice tray (`src/ui/dice_panel.gd` draws 2D polygons).
- [ ] **[M] More sprite animation** (bow shot arrows, shield block, sitting, sleeping).
- [ ] **[M] Image-generated sprite sheets.** Try `flows.image` with a reference image per character to make
  walk frames; needs background removal and a frame grid. Portraits already work (`tools/gen_portraits.mjs`).
- [ ] **[S] Ambient sound loops per map** (`"ambience"` on a map, generated with `npm run sfx -- <campaign>` + `loop`).
- [ ] **[S] Weather** (rain/snow billboards) for outdoor maps.

## UI

- [ ] **[M] Controller support.**
- [ ] **[M] Inventory screen** with drag and drop between characters (inventory is shared today).
- [ ] **[S] Condition and feat tooltips** on the sheet.
- [ ] **[S] Rebindable keys** (`src/main.gd _unhandled_key_input`).
- [ ] **[S] Portrait for the custom hero** (generate from the builder's choices at character creation).

## Content (Embers of Hollowmere)

- [ ] **[M] A second dungeon level** below the Barrow with a puzzle door.
- [ ] **[M] Companion personal quests** (one each) and camp conversations.
- [ ] **[S] More side quests in town** (the orchard keeper, the missing shrine bell).
- [ ] **[S] Balance pass** using real play (boss fight at level 1 vs level 2).

## Licensing and release (read docs/LICENSING.md first)

- [x] **[S] Open Game License file.** Done 2026-11-12: `OGL.txt` (designation of Open Game Content, the
  licence text, Section 15), shown in the game under Licences -> "Game rules" and guarded by
  `tests/test_notices.gd`.
- [x] **[S] The name "Pathfinder".** Decided by the owner on 2026-11-12: the project follows Paizo's
  Community Use Policy. The prescribed notice is in README.md, on the title screen (short form) and on the
  Licences screen ("Game rules" tab); `tests/test_notices.gd` guards it. The conditions are listed in
  docs/LICENSING.md - read them before adding content or anything to do with money.
- [ ] **[M] Export preset for Linux.** Create `export_presets.cfg` (Linux x86_64), include
  `LICENSE, THIRD_PARTY_NOTICES.md, OGL.txt` and the campaign/data files in the non-resource filter, and add
  `tools/build.sh` that exports to `build/` and then runs `tools/write_notices.gd` so the notices file
  always ships with the game. Done: the exported game starts from `build/`, plays the intro with sound,
  and Licences -> "This game" and "Game rules" show the real LICENSE and OGL texts (not the one-line fallbacks).
  Also on the way: `src/render/tex_factory.gd` (campaign `textures/*.png`) and `src/render/sprite_factory.gd`
  (sprite sheets) still read raw image files with `Image.load_from_file`, which does not work in an exported
  build. Give them the same treatment as `src/ui/portraits.gd` (`ResourceLoader.exists(path)` -> `load(path)`,
  raw file only as a fallback).

## Known rough edges

- Monsters do not move while exploring; fights start when the party comes within sight.
- The room camera cuts between camera tiles; add a short blend if it feels abrupt.
- Out of combat, equipment changes are free; in combat they are blocked.
- A fight that nobody can reach ends in a "stalemate" after three idle rounds.
