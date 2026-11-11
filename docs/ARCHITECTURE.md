# Architecture

## Layers

```
src/core      Util (JSON), Rng                                  no dependencies
src/rules     Pathfinder maths on plain Dictionaries            depends on core
src/engine    game flow, no screen                              depends on rules
src/render    3D room, textures, sprites (Godot nodes)          depends on engine
src/ui        panes, menus, input, audio (Godot nodes)          depends on engine + render
```

Rules and engine are **headless**: they never touch nodes, `Input`, or timers. That is why the whole
game (dialogue, cutscenes, full fights, a complete campaign play-through) can run inside `./check.sh`.

## The objects

| Object | File | Role |
|---|---|---|
| `Game` | engine/game.gd | Owns a play session. `db`, `campaign`, `state`, `world`, `scripts`, `cam`, `anims`, `io`, `rng`, `encounter`. |
| `GameIO` | engine/game_io.gd | Everything the engine needs from the outside (say, choose, show_roll, fade, sfx...). Headless base class. |
| `UiIO` | ui/ui_io.gd | The windowed GameIO: forwards to the panes and waits for the player. |
| `World` | engine/world.gd | Current `MapData` + list of `Ent`; exploration movement, clicks, doors, triggers, aggro. |
| `MapData` | engine/map_data.gd | A parsed map (text rows + legend). |
| `Ent` | engine/ent.gd | One entity on the map (party member, NPC, monster, prop). Plain data. |
| `ScriptRunner` | engine/script_runner.gd | Runs JSON actions (`ops`) and tests JSON conditions (`conds`). |
| `Dialogue`, `Cutscene`, `Quests`, `Party`, `GM` | engine/*.gd | Static helpers for each kind of content. |
| `Encounter`, `CombatAI` | engine/encounter.gd, combat_ai.gd | One fight; decisions for monsters. |
| `CamRig` | engine/cam_rig.gd | Camera numbers (room / chase / dialogue framing / scripted). |
| `Anims` | engine/anims.gd | Tiny tween runner that is instant in tests. |
| `WorldView` | render/world_view.gd | Draws the world; answers "what is under the mouse". |
| `SheetPanel`, `DicePanel`, `JournalPanel`, `ViewPanel`, `CombatHud` | ui/*.gd | The four panes and the combat bar. |
| `Modal` subclasses | ui/*_screen.gd, pause_menu.gd | Title, builder, shop, level-up, menu. |

## Data shapes

- **Character** (saved): see the header of `src/rules/char_rules.gd`.
- **Stats** (derived, never saved): `Stats.of(actor, db)` - same shape for characters and monsters.
- **Roll result** (what the dice tray shows): header of `src/rules/dice.gd`.
- **Modifier** `{target, value, type, when}` and the stacking rules: header of `src/rules/mods.gd`.
- **Save file** = `game.state`: header of `src/engine/game.gd`. JSON-friendly only.

## Flow of one frame (windowed)

`src/main.gd._process` -> reads WASD into `world.move_input` -> `game.update(delta)` ->
`anims.update`, `world.update` (movement, triggers, aggro), `cam.update` -> `WorldView._process`
copies entities and camera to nodes.

## Flow of a story beat

Player clicks an NPC -> `World.interact` -> `Game.run_dialogue` -> `Dialogue.run` loops over nodes:
`game.speak()` (journal + `io.say`), `io.choose()` (journal buttons), `GM.check()` (dice tray),
`ScriptRunner.run()` for the node's actions. While this runs `game.busy > 0`, so exploration input is ignored.
Scene-changing ops inside a dialogue (`combat.start`, `map.goto`...) are deferred until it closes.

## Flow of a fight

`Game.start_combat(group)` -> `Encounter.run()`: initiative rolls -> rounds -> for each combatant
`_take_turn` asks a controller for actions (`CombatAI` or the UI's `CombatHud`) -> `execute()` ->
rolls shown through `game.show_roll()` -> damage through `game.damage_ent()` -> victory / defeat /
stalemate -> XP, loot, `onVictory` script.

## Signals (on Game)

`journal_added(entry)`, `state_changed`, `map_loaded`, `mode_changed`, `combat_changed`.
World: `rebuilt` (geometry/light changed), `ents_changed`.

## Modes

`game.mode`: `menu` | `explore` | `combat`. `game.busy` > 0 while a script, dialogue, cutscene or
fight is in control. `game.in_dialogue`, `game.in_cutscene`, `game.over`.

## Rendering

The 3D view is a low-resolution `SubViewport` (1/3 size, nearest-neighbour upscale). `RoomBuilder`
extrudes the map grid into walls/floors/ceilings (one mesh surface per texture) and bakes lighting
into vertex colours (flood fill from light sources). Entities are `Sprite3D` billboards whose sheets
come from `SpriteFactory`. No art files are needed; campaigns may override textures and sprites with PNGs.
