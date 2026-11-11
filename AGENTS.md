# OpenGate - guide for AI coding agents (and humans)

OpenGate is an open framework for Baldur's-Gate-style RPGs using the **Pathfinder 1e** rules.
It is a **Godot 4.7** project written in **GDScript**. Everything is plain text: you never need the
Godot editor. Campaigns are folders of JSON files. Read this file first, every time.

## The one rule that matters most

After **every** change run:

```bash
./check.sh
```

You are done only when it prints `ALL CHECKS PASSED`. It re-imports the project, compiles every
script (parse errors are listed with file and line) and runs all headless tests, including a
validator for every campaign and a scripted play-through of the starter campaign.
If it fails, fix the **first** error shown and run it again.

## Commands

| What | Command |
|---|---|
| Verify everything | `./check.sh` (one test file: `./check.sh test_rules`) |
| Play | `./run.sh` (fullscreen) or `./run.sh --windowed` |
| Skip menus while developing | `./run.sh --windowed -- --campaign=hollowmere --hero=kaelen --skip-intro` |
| **Live UI test** (real mouse + keyboard events in the real window, ~5 min) | `./run.sh --windowed -- --shots=/tmp/live --tour=live --campaign=hollowmere --hero=kaelen` then read `/tmp/live/live_log.txt` (every line must say `ok`; last known-good run: docs/live_test_log.txt). `--tour=live-dungeon` runs only the door / trap / fight half |
| Screenshot tour (look at UI changes) | `./run.sh --windowed -- --shots=/tmp/shots --tour=play --campaign=hollowmere --hero=kaelen` (tours: `title`, `licenses`, `play`, `combat`) |
| Full campaign report (errors + warnings) | `godot --headless --path . -s res://tools/validate_campaign.gd -- hollowmere` |
| Look at a map without playing | `godot --path . -s res://tools/render_map.gd -- hollowmere town /tmp/shots start square` |
| Look at character sprites | `godot --headless --path . -s res://tools/sprite_gallery.gd -- /tmp/gallery.png` |
| New campaign from the template | `tools/new_campaign.sh my_campaign "My Campaign"` |
| Licence notices file to ship with a build | `godot --headless --path . -s res://tools/write_notices.gd` (writes `build/THIRD_PARTY_NOTICES.txt`; see docs/LICENSING.md) |
| Voices / music / sound effects / portraits (ElevenLabs) | `npm run voices -- hollowmere --list` etc. See docs/VOICE.md |

Godot is expected on the PATH as `godot` (this machine: `~/.local/bin/godot` -> 4.7.2). Set `GODOT=/path` otherwise.

## Where things are

```
project.godot        Godot settings (GL Compatibility renderer, 1600x900 base size)
run.sh  check.sh     play / verify
data/*.json          RULES DATA: skills, races, classes, feats, items, spells, monsters, conditions, props, sfx prompts
campaigns/<id>/      CONTENT: one folder per campaign (docs/CAMPAIGN_FORMAT.md)
campaigns/_template  smallest complete campaign; also the fixture used by tests
campaigns/hollowmere the starter campaign: 1 town, 1 camp, 1 dungeon, 5 missions
LICENSE              MIT licence of this project
THIRD_PARTY_NOTICES.md  everything that is NOT ours (Godot Engine, Pathfinder rules, ElevenLabs audio) - docs/LICENSING.md
src/core/            util.gd (JSON, helpers), rng.gd (all randomness), notices.gd (licence texts from the engine)
src/rules/           PURE Pathfinder maths. No nodes, no game state. Fully unit-tested.
src/engine/          game flow WITHOUT any screen: game.gd, world, scripts, dialogue, combat, cutscenes
src/render/          3D room + procedural textures and sprites (Godot nodes)
src/ui/              the four panes, menus, character builder, audio
src/dev/             command-line developer tools (screenshot tours)
tests/               headless tests (run_tests.gd runs every test_*.gd)
tools/               validators, renderers, ElevenLabs generators
docs/                reference documentation - keep it in sync with the code
```

Every source file starts with a comment that says what it is for and how to extend it. Read it
before editing the file, and update it when you change behaviour.

## Architecture in five sentences

1. `src/rules` turns a character or monster Dictionary into a **stats** Dictionary and resolves
   rolls; it knows nothing about the game.
2. `src/engine/game.gd` (`Game`) owns everything for one play session: `db` (rules data),
   `campaign`, `state` (the save file), `world` (current map + entities), `scripts`, `cam`.
3. The engine talks to the player only through `game.io` (`GameIO`). The base class is headless
   (instant, automatic choices) and is what tests use; `src/ui/ui_io.gd` is the real one.
4. `src/render/world_view.gd` draws `game.world`; `src/ui/*` panes listen to `Game` signals
   (`journal_added`, `state_changed`, `map_loaded`, `mode_changed`, `combat_changed`) and redraw.
5. Campaign JSON is executed by `ScriptRunner` (ops and conditions), `Dialogue`, `Cutscene` and
   `Encounter`. Details: docs/ARCHITECTURE.md.

Dependency direction is one-way: `core <- rules <- engine <- render/ui`. Never make `rules` or
`engine` depend on `render`/`ui`, on Godot nodes, on `Input`, or on timers. Use `game.delay()`,
`game.anims.run()` and `game.io.*` instead - otherwise the headless tests break.

## Working rules

- **Prefer data over code.** New items, monsters, spells, feats, maps, quests and dialogue are JSON
  edits. Only touch GDScript when the data format cannot express what you need.
- **One small task at a time.** Pick one item from docs/TASKS.md, finish it, run `./check.sh`.
- **Add a test** for every new rule or script op (copy the style of tests/test_rules.gd).
- **Keep the save file JSON-friendly.** `game.state` may only contain Dictionaries with string
  keys, Arrays, numbers, strings, bools and null. Never store objects or Vector2 in it.
- **Do not rename files, classes or JSON keys** unless the task says so. If you must, update the
  validator (`src/engine/campaign_validator.gd`), the docs and the tests in the same change.
- **When you add a script op or condition**: register it in `src/engine/script_runner.gd`, teach
  `campaign_validator.gd` its fields, document it in docs/SCRIPTING.md, add a test.
- **Secrets**: the ElevenLabs key is in `.env.local`. Never print it, never put it in code, never commit it.
- Rules text must be written in your own words. The mechanics come from the Pathfinder 1e rules
  (Open Game License); do not copy setting names or prose from published books.
- **Licences** (docs/LICENSING.md): the game runs on Godot Engine (MIT), so every build must show
  Godot's licence notices. Never remove the **Licences** screen (`src/ui/licenses_screen.gd`) or its
  buttons, never edit licence text, and when you add anything made by someone else (asset, font,
  library, copied code) add it to `THIRD_PARTY_NOTICES.md` in the same change.

## GDScript 4 pitfalls (these have all bitten this project)

| Symptom | Cause and fix |
|---|---|
| `Cannot infer the type of "x"` | `:=` needs a typed right-hand side. Values read from a Dictionary, an untyped Array or an untyped `for` variable are not typed. Write `var x: int = d.key` or `var x = d.key`. |
| `Too many arguments for "log()"` | `log` is a built-in maths function. The journal method is `game.journal(kind, text)`. Do not name methods after built-ins (`log`, `ceil`, `len`, `range`, `str`...). |
| Parse error near `.if` / `.class` | Keys that are keywords (`if`, `do`, `not`, `class`, `in`...) cannot use dot access. Use `d["if"]` or `d.get("if")`. Characters use the key `cls`, not `class`. |
| `dc == 15` is false, or `%d` prints `15.0` | Godot parses JSON numbers as float. Always load JSON with `Util.load_json()` (it converts whole numbers to int). |
| A full-screen control appears as a tiny box in the corner | Use `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)`, not `set_anchors_preset`. |
| Lambda syntax errors | Keep lambdas to ONE statement: `func(x): return x * 2`. For more, write a named method and pass it (`_my_method.bind(arg)`; bound arguments arrive last). |
| `Nonexistent function 'new' in base 'GDScript'` | The script failed to compile. Run `./check.sh`; the real error is in the "Compiling scripts" step. |
| New `class_name` is "not declared" | Godot's class cache is stale. `./check.sh` re-imports; or run `godot --headless --path . --import`. |
| Function seems to return too early | It contains `await`, so it is a coroutine. Callers that need it finished must `await` it too. |
| Mixed indentation error | GDScript files in this project use TABS only. |
| Old Godot 3 code from memory | Godot 4 uses `@export`, `@onready`, `await` (not `yield`), `signal.connect(callable)`, `super()`, `Callable`. No `export var`, no `connect("sig", self, "method")`. |

## Recipes (the common jobs)

| I want to add... | Do this |
|---|---|
| an item, monster, spell, feat, race, class | add an entry to the matching `data/*.json` (each file starts with a `_doc` describing the fields); campaign-only ones go in `campaigns/<id>/items.json`, `monsters.json`... See docs/RULES.md |
| a map | new `campaigns/<id>/maps/<name>.json` drawn as text rows + legend (docs/CAMPAIGN_FORMAT.md), then look at it with `tools/render_map.gd` |
| an NPC | template in `entities.json`, a legend character on a map with `"entity": "<id>"`, a `dialogues/<id>.json` |
| a quest | entry in `quests.json`; move it with script ops `quest.start` / `quest.stage` / `quest.complete` |
| a fight | put monsters on a map with a shared `"group"`; optional extras in `encounters.json` |
| a cutscene | `cutscenes/<id>.json` (docs/CUTSCENES.md), played with `{"op": "cutscene.play", "id": "..."}` |
| a script op / condition | see "Working rules" above and docs/SCRIPTING.md |
| a wall/floor texture | `src/render/tex_factory.gd`: add the name to `NAMES` and a branch in `_pixel()`; or drop `textures/<name>.png` in the campaign |
| a prop or creature sprite | `src/render/sprite_factory.gd`: `_draw_simple()` + `TEMPLATES`; a character look is just JSON (docs/SPRITES.md) |
| a UI screen | subclass `Modal` (src/ui/modal.gd) like `shop_screen.gd`, open it from `src/main.gd` |
| a sound effect | add a recipe to `RECIPES` in `src/ui/audio_bank.gd`, or a prompt to `data/sfx.json` and run `npm run sfx` |
| a third-party asset, font or library | add it, keep its licence file next to it, and add an entry to `THIRD_PARTY_NOTICES.md` (docs/LICENSING.md). No licence, no add |

## Definition of done

1. `./check.sh` prints `ALL CHECKS PASSED`.
2. For anything visual, you looked at a screenshot (tour, `render_map.gd` or `sprite_gallery.gd`).
   If you touched input, the panes, combat controls or `ui_io.gd`, also run the live UI test above:
   it clicks, types and walks through the real window and must end with `RESULT: n of n steps ok`.
3. Docs and file header comments match the new behaviour.
4. docs/TASKS.md is updated (tick the task, add follow-ups you discovered).
