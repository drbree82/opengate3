# Scripting reference

Scripts are lists of **actions**. They appear in `campaign.json start.do`, map `onEnter` and
`triggers`, entity `interact`, dialogue `do`, encounters and cutscenes.

```json
[{"op": "quest.start", "id": "rats"}, {"op": "gold.add", "amount": 25, "if": {"flag": "paid"}}]
```

Any action may have an `"if"` condition. Implementation: `src/engine/script_runner.gd`.
The validator (`./check.sh`) checks every id you reference.

## Actions (ops)

| op | fields | what it does |
|---|---|---|
| `narrate` | text, voice? | Game Master narration in the journal |
| `say` | speaker, text, voice? | a character speaks |
| `log` | text | small system line in the journal |
| `banner` | text, sub? | large text across the 3D view |
| `sfx` | name | play a sound effect |
| `music` | track | switch music (`""` stops it) |
| `wait` | seconds | pause |
| `fade` | to (`black`/`clear`), seconds | fade the 3D view |
| `shake` | seconds | shake the camera |
| `flag.set` | flag, value? (default true) | remember something |
| `flag.inc` | flag, by? (default 1) | count something |
| `quest.start` | id | add a quest at its first stage |
| `quest.stage` | id, stage | move a quest to a stage (starts it if needed) |
| `quest.complete` | id | finish a quest and pay its rewards |
| `quest.fail` | id | mark a quest failed |
| `item.give` / `item.take` | id, qty? | add / remove items in the party pack |
| `gold.add` | amount (negative to charge) | change gold |
| `xp.add` | amount | experience for every character |
| `party.add` | id | recruit a companion (waits at camp if the party is full) |
| `party.remove` | id | send a companion to camp |
| `party.lead` | id | make a party member the leader |
| `approval.add` | id, amount | companion approval |
| `heal` | who? (`party`), amount? (`full`) | heal |
| `rest` | | long rest: full hit points, spells and powers; a day passes |
| `effect.add` | who, effect `{id, name, modifiers, conditions, duration}` | apply a buff / debuff |
| `damage` | dice, who?, label?, save? `{type, dc, half}`, tags? | a trap or hazard, with an optional saving throw |
| `check` | skill \| save \| ability, dc, who?, tags?, label?, success: [..], failure: [..] | roll in the dice tray, then run one branch |
| `choice` | text?, options: [{text, if?, do?, check?, success?, failure?}] | ask the player outside a dialogue |
| `map.goto` | map, marker? | travel to another map |
| `camp.go` / `camp.leave` | | go to camp / return to where the party was |
| `combat.start` | group, surprise? (`party`/`enemy`) | start a fight with a monster group on this map |
| `cutscene.play` | id | play a cutscene |
| `dialogue.start` | id | start a conversation |
| `shop.open` | id | open a shop |
| `save` | | autosave |
| `campaign.end` | victory, text | show the ending / game over |
| `entity.remove` | id | remove an entity for good |
| `entity.spawn` | template, at (marker / entity id / [x, y]), id?, group?, set?, persist? | create an entity (joins a running fight if hostile) |
| `entity.set` | id, set: {hidden, dialogue, name, blocking, anim, facing} | change an entity |
| `group.hostile` | group, hostile? | make a monster group hostile / calm |
| `group.remove` | group | remove every monster of a group (they fled, were bribed...) |
| `tile.set` | at or x, y; char | change a map tile to another legend character |
| `door.open` | at or x, y | open a door |

`who` is `leader`, `party`, `all` (whole roster) or a character id. For `check` it is `leader`,
`best` (the party member with the best bonus) or a character id.
Positions (`at`) are a marker name, an entity id, or `[x, y]` tile coordinates.

Inside a dialogue, `combat.start`, `map.goto`, `dialogue.start`, `camp.go`, `camp.leave` and
`campaign.end` wait until the conversation has closed.

## Checks

```json
{"skill": "perception", "dc": 15, "who": "best", "tags": ["traps"], "label": "Notice the wire"}
{"save": "ref", "dc": 13}
{"ability": "str", "dc": 20}
```

Skill ids are in `data/skills.json`. `tags` switch on situational bonuses (a rogue's trapfinding
applies with `"traps"`, a dwarf's stonecunning with `"stonework"`). A trained-only skill without
ranks fails automatically. Dialogue choices show the check as `[Perception DC 15]`.

## Conditions

A condition is an object; every key in it must hold.

| condition | true when |
|---|---|
| `{"flag": "x"}` / `{"flag": "x", "equals": 3}` | the flag is set / has that value |
| `{"not": {...}}`, `{"all": [...]}`, `{"any": [...]}` | logic |
| `{"quest": "id"}` | the quest is active |
| `{"quest": "id", "stage": "s"}` | active and at that stage |
| `{"quest": "id", "atLeast": "s"}` | has reached that stage at some point |
| `{"quest": "id", "status": "none|active|completed|failed"}` | |
| `{"hasItem": "id", "qty": 2}` | the pack holds it |
| `{"inParty": "id"}` | that character travels with the party |
| `{"companion": "id", "state": "camp"}` | companion state: absent, party, camp, player |
| `{"gold": 15}` | at least that much gold |
| `{"cls": "rogue"}`, `{"race": "elf"}`, `{"level": 2}` | about the leader |
| `{"partyCls": "cleric"}` | anyone in the party has that class |
| `{"skill": "stealth", "min": 5}` | the leader's skill bonus |
| `{"partySize": 3}`, `{"partyFull": true}` | |
| `{"inCombat": true}`, `{"map": "town"}` | |

## Adding an op or a condition

1. Register it in `_register_ops()` / `_register_conds()` in `src/engine/script_runner.gd`
   (one line: `ops["my.op"] = func(a, ctx): ...`; use a named method if it needs several statements).
2. Add its field checks to `_action()` / `_cond()` in `src/engine/campaign_validator.gd`.
3. Document it in the tables above.
4. Add a test (tests/test_engine.gd shows how to run actions headless).
