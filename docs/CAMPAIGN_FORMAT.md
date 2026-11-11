# Campaign format

A campaign is a folder in `campaigns/`. The folder name is the campaign id. Copy `campaigns/_template`
(`tools/new_campaign.sh my_id "My Name"`) and look at `campaigns/hollowmere` for a full example.
After any edit run `./check.sh` - the validator names the file and the problem.

```
campaigns/<id>/
  campaign.json        name, where the game starts, camp, voices, music prompts
  maps/<map>.json      one file per map; the file name is the map id
  dialogues/<id>.json  one file per conversation
  cutscenes/<id>.json  one file per cutscene (docs/CUTSCENES.md)
  entities.json        NPC / prop / special monster templates
  companions.json      pre-made heroes (playable and recruitable)
  quests.json  encounters.json  shops.json
  items.json  monsters.json  spells.json ...   optional: add to / override data/*.json
  textures/<name>.png  sprites/*.png           optional art overrides
  voice/  music/  sfx/  portraits/             generated audio and images (docs/VOICE.md)
```

Keys starting with `_` (like `"_doc"`) are comments and are ignored.

## campaign.json

```json
{
  "name": "Embers of Hollowmere", "author": "...", "description": "...",
  "maxPartySize": 4,
  "start": {"map": "town", "marker": "start", "facing": "E", "gold": 15,
            "do": [{"op": "cutscene.play", "id": "intro"}, {"op": "quest.start", "id": "a_cold_welcome"}]},
  "camp": {"map": "camp", "marker": "start"},
  "rules": {"reviveAfterCombat": true},
  "voices": {"narrator": "<ElevenLabs voice id>", "reeve": "..."},
  "voiceHints": {"reeve": "female middle aged calm"},
  "music": {"town": {"prompt": "calm medieval lute...", "seconds": 60}},
  "sfx": {"bell": {"prompt": "a distant church bell", "seconds": 2}}
}
```

`camp` is optional; with it the player can press Camp (G) on maps that allow it.

## Maps

A map is drawn as rows of characters. Each character is looked up in the `legend`.

```json
{
  "name": "The Test Room", "subtitle": "shown on arrival",
  "outdoor": false, "sky": "", "wallHeight": 1.0,
  "ambient": 0.55, "ambientColor": "#ffffff", "fog": {"color": "#0a0a12", "distance": 16},
  "music": "barrow", "allowCamp": true,
  "defaults": {"wall": "stone", "floor": "flagstone", "ceiling": "plank"},
  "legend": {
    "#": {"wall": "stone"},
    ".": {},
    "s": {"marker": "start"},
    "c": {"camera": true},
    "G": {"entity": "guide"},
    "r": {"entity": "dire_rat", "group": "rats"},
    "D": {"door": "door_wood", "locked": {"key": "cellar_key", "dc": 20, "break": 22, "text": "Locked."}},
    "x": {"trigger": "tripwire"},
    ">": {"exit": {"map": "camp", "marker": "start"}}
  },
  "rows": ["#####", "#s.G#", "#####"],
  "onEnter": [ ...actions run every time the party arrives... ],
  "triggers": {"tripwire": {"once": true, "if": {...}, "do": [ ...actions... ]}}
}
```

Rules for rows: every row must have the same length; every character must be in the legend
(`#`, `.` and space are pre-defined: default wall, default floor, nothing). x counts from the left
starting at 0, y from the top starting at 0. One tile is one 5-ft square.

Legend entry keys (combine freely):

| Key | Meaning |
|---|---|
| `wall` | a solid block with this texture |
| `floor`, `ceiling` | textures of an open tile (fall back to `defaults`; ceiling `"sky"` = open air) |
| `door` | a closed door (texture). Opens when clicked. `locked: {key, dc, break, text}` makes it need the key item, a Disable Device check (`dc`) or a Strength check (`break`) |
| `void` / `blocked` | nothing here / open but not walkable (water) |
| `entity` | spawn this template here. Any other keys in the entry override the template (`group`, `hostile`, `id`, `facing`, `name`, `dialogue`, `if`...) |
| `marker` | a named position for scripts, exits and cutscenes |
| `trigger` | run `triggers[<id>]` when the party leader steps on the tile |
| `exit` | `{map, marker}`: walking here travels to another map |
| `camera` | a room-camera position: the view sits here and tracks the party while it can see them |

Texture names: see `NAMES` in `src/render/tex_factory.gd` (stone, brick, crypt, timber, cobble,
grass, plank, carpet, door_wood...). Sky kinds: `day`, `dusk`, `night`, `overcast`.
Extra positions by coordinate are possible with `"markers": {"name": [x, y]}` and `"cameras": [[x, y]]`.

Look at your map without playing:
`godot --path . -s res://tools/render_map.gd -- <campaign> <map> /tmp/shots <marker>`

## entities.json

```json
"bram":  {"kind": "npc", "name": "Bram", "dialogue": "bram", "facing": "S",
          "sprite": {"template": "humanoid", "height": 0.95, "look": {...}}},
"snagrot": {"kind": "monster", "monster": "goblin", "name": "Snagrot", "hostile": false,
            "group": "orchard_goblins", "dialogue": "snagrot"},
"camp_chest": {"kind": "prop", "name": "Cache", "sprite": {"template": "chest", "height": 0.4},
               "blocking": true, "once": true, "keep": true, "interact": [ ...actions... ]},
"pip_town": {"companion": "pip", "when": ["absent"], "dialogue": "pip"},
"pip_camp": {"companion": "pip", "when": ["camp"]}
```

- `kind`: `npc`, `monster` (uses a stat block from the bestiary) or `prop`.
- `interact`: actions run when the player uses it. `once` = only the first time; `keep` = stay visible afterwards.
- `light`: `{radius, color, power}` makes it a light source.
- Companion placements appear only while the companion's state matches `when`
  (`absent` = not recruited yet, `camp` = waiting at camp). A companion placement without a
  `dialogue` gets a built-in join / wait-at-camp conversation.
- Base props (barrel, crate, torch, tree, tent, altar...) from `data/props.json` and every monster in the
  bestiary can be placed on maps without being listed here.
- Sprite looks: docs/SPRITES.md.

## companions.json

Pre-made characters. The player may pick one as their hero (it keeps the companion's id); the
others can be recruited with the `party.add` op.

```json
"kaelen": {"name": "Kaelen Ashford", "race": "human", "cls": "fighter", "racialChoice": "str",
  "abilities": {"str": 15, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 8},
  "feats": ["weapon_focus:longsword", "dodge", "toughness"], "skillRanks": {"intimidate": 1},
  "spells": [], "look": {"body": "masculine", "build": "heroic", ...}, "bio": "...", "greeting": "..."}
```

`abilities` are base scores before racial modifiers (15-point buy). Gear comes from the class's
starting kit unless you give `"equipped": {"mainHand": "...", ...}`.

## quests.json

```json
"rats_in_the_cellar": {"name": "Rats in the Cellar", "type": "side", "summary": "...",
  "stages": [{"id": "clear", "text": "Clear the cellar."}, {"id": "report", "text": "Tell Bram."}],
  "rewards": {"xp": 300, "gold": 25, "items": [{"id": "potion_clw", "qty": 1}]}}
```

A quest starts at its first stage. Rewards are paid by `quest.complete`.

## encounters.json

Optional extras for a fight, keyed by the monster **group**:
`name`, `xp` (bonus), `gold`, `loot: [{id, qty}]`, `onStart`, `onVictory`, `onDefeat` (scripts),
`onRound: [{"round": 3, "do": [...]}]`. Without an entry a fight still works (XP comes from the monsters).

A fight starts when a hostile monster sees the party within 4.5 tiles (`"aggro"` on the entity
changes the distance) or when a script runs `combat.start`.

## shops.json

`"smith": {"name": "Tova's Forge", "greeting": "...", "stock": [{"id": "longsword"}, {"id": "potion_clw", "price": 35}]}`
Opened with `{"op": "shop.open", "id": "smith"}`. Shops buy at half an item's cost.

## Dialogues

```json
{
  "start": [{"if": {"flag": "met_bram"}, "node": "again"}, {"node": "hello"}],
  "nodes": {
    "hello": {"speaker": "bram", "text": "Welcome, {player}!", "do": [{"op": "flag.set", "flag": "met_bram"}],
      "choices": [
        {"text": "Any work?", "goto": "work"},
        {"text": "Lower your price.", "check": {"skill": "diplomacy", "dc": 14}, "success": "cheap", "failure": "no"},
        {"text": "Goodbye.", "if": {"gold": 1}, "do": [...], "goto": "end"}]},
    "work": {"speaker": "bram", "text": "Rats.", "goto": "hello"}
  }
}
```

- `start`: a node id, or a list tried top to bottom (the last one should have no `if`).
- A node shows `text` (spoken by `speaker`, or narration without one), runs `do`, then offers `choices`.
  Without choices it continues to `goto`. `"end"` ends the conversation.
- A choice may have `if` (hidden when false), `do`, and either `goto` or a `check` with `success` / `failure` nodes.
- A node may itself have a `check` + `success` / `failure`, and `if` + `else`.
- `speaker` is an entity or companion id (its name is shown and its sprite talks).
- Text may contain `{player}`, `{leader}`, `{race}`, `{class}`, `{gold}`.
- Actions and conditions: docs/SCRIPTING.md.
