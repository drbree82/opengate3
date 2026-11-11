# Rules: what is implemented

The rules follow Pathfinder 1st edition. All maths lives in `src/rules/` (pure functions on
Dictionaries) and is covered by `tests/test_rules.gd`. Data lives in `data/*.json`; each file
starts with a `_doc` entry describing its fields.

## Implemented

| Area | Where | Notes |
|---|---|---|
| Ability scores, modifiers, 15-point buy | char_rules.gd | racial modifiers, level 4/8/... increases |
| Races | data/races.json | human, dwarf, elf, gnome, half-elf, half-orc, halfling, with traits as modifiers |
| Classes | data/classes.json | fighter, rogue, cleric, wizard: hit die, BAB, saves, class skills, proficiencies, features |
| Skills | data/skills.json | all 35; ranks, class-skill +3, armor check penalty, trained-only |
| Feats | data/feats.json | passive feats as modifier bundles (only implemented feats are listed) |
| Modifier stacking | mods.gd | typed bonuses do not stack (highest wins) except dodge/circumstance/untyped; penalties stack |
| Derived stats | char_rules.gd `derive()` | hp, AC (touch, flat-footed), saves, initiative, CMB/CMD, speed, attacks, spell slots |
| Monsters | data/monsters.json, monster_rules.gd | stat blocks; same stats shape as characters |
| Checks | checks.gd | skill, save (natural 1/20), ability, initiative |
| Attacks | combat_rules.gd | natural 1/20, critical threat + confirmation, multipliers, damage reduction, sneak attack |
| Combat flow | engine/encounter.gd | initiative, rounds, move + standard action, flat-footed, flanking (+2), attacks of opportunity, range penalties, total defense, dying and stabilising |
| Conditions and effects | effects.gd, data/conditions.json | durations in rounds / encounter / rest |
| Spells | spell_rules.gd, data/spells.json | touch attacks, saves (negates/half), damage, healing, buffs, cones and bursts, HD limits, immunities; cleric channel energy |
| Experience | progression.gd | medium track, level-ups (hp roll, skill ranks, feats, ability increase, wizard spells) |
| Gear | data/items.json | weapons, armor, shields, potions, simple magic items; small-size weapon damage |

## Deliberate simplifications (good first tasks to remove - see docs/TASKS.md)

- Casters spend a slot of the spell's level for any spell they know of that level (no preparation). Cantrips are at will.
- One attack per standard action (no full attacks); movement may be split around the action; a single 1-square step never provokes.
- No reach weapons, cover, concealment, charging, combat manoeuvres, casting defensively or arcane spell failure.
- 0 hp or less = unconscious; dead at negative Constitution. With `rules.reviveAfterCombat` (default) the fallen stand up with 1 hp after a won fight.
- Ammunition and encumbrance are not tracked. A character carries one melee and one ranged weapon and swaps freely.
- Poison, disease and several class features (evasion, domains, schools, arcane bond) are not implemented yet.
- Spell slot tables stop at character level 10.

## How to add things

**An item** - add to `data/items.json`:
`"scimitar": {"name": "Scimitar", "type": "weapon", "category": "martial", "hands": 1, "damage": "1d6", "crit": [18, 2], "dtype": "S", "cost": 15, "sprite": "sword"}`

**A monster** - add a stat block to `data/monsters.json` (copy `goblin`). `ai` is `melee`, `ranged`
or `caster`. Give it `spells: [{"id": "...", "uses": 1}]` to make it cast.

**A spell** - add to `data/spells.json`; the fields are explained at the top of
`src/rules/spell_rules.gd`. Example: `"shield_of_faith"`. Most spells need no code.

**A feat** - add to `data/feats.json` with `modifiers`. Targets and types are listed at the top of
`src/rules/mods.gd`. A feat that needs new behaviour (not just numbers) needs code in the rules
or the encounter; add a test for it.

**A class** - add to `data/classes.json` (copy `fighter`). `features` may carry `modifiers` with
`scale` for level scaling. Spellcasters need `casting`. Anything beyond numbers needs code.

**A condition** - add to `data/conditions.json`: `modifiers` plus `flags`
(`skipTurn`, `helpless`, `wakeOnDamage`, `noMove`, `singleAction`).

After any data change run `./check.sh` (`test_data_integrity` checks every reference).
