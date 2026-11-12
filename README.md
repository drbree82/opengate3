# OpenGate

An open framework for building and playing Baldur's-Gate-style RPGs with the **Pathfinder (1st edition)**
rules. The computer is the Game Master; you play solo with a party of companions.

OpenGate is an **unofficial, free fan project**. It is not made, endorsed or approved by Paizo - see
[Paizo Community Use notice](#paizo-community-use-notice).

Built with Godot 4 (GDScript). Runs on Linux. No art or audio files are required: rooms, textures,
characters and sound effects are generated in code, and ElevenLabs can add voices, music and portraits.

![Exploring Hollowmere](docs/img/screenshot_explore.png)

![The people of Hollowmere](docs/img/portraits.jpg)

## Play

```bash
./run.sh
```

`./run.sh --windowed` runs in a window. F11 toggles fullscreen. You need Godot 4.7+ on your PATH
(`sudo pacman -S godot` on Arch/Omarchy).

## The screen

| | |
|---|---|
| **Top left: character sheet** - stats, skills, gear, spells, traits. Click gold names to roll them. | **Top right: dice tray** - every d20, check, attack and damage roll is animated here with its full breakdown. |
| **Bottom left: journal** - the story, your dialogue choices (with skill checks), quests, the creatures you have fought (point at a name for its stats, strengths and weaknesses), and the log. | **Bottom right: the world** - a retro 3D view of the room built from a 2D map, with animated 2D sprites. |

## Controls

| | |
|---|---|
| Left click | walk there / talk / use / open door / pick a combat target |
| W A S D | walk (relative to the camera) |
| Q, E or right-drag | turn the camera (switches to the chase camera) |
| C | switch between room camera and chase camera |
| 1-9 | pick a dialogue choice |
| Space / Enter | hurry text and dice along; end your turn in combat |
| G | go to camp / leave camp (rest at the campfire) |
| M or Tab | bigger minimap (click it to walk, or to pick a tile or enemy in combat when sprites overlap) |
| Esc | menu (save, load, settings); skip a cutscene; cancel spell targeting |
| F5 / F9 | quick save / quick load |

## What is in the box

- **Rules engine**: abilities, races, classes (fighter, rogue, cleric, wizard), skills, feats, attacks,
  criticals, damage reduction, saving throws, conditions, spells, channel energy, sneak attack,
  attacks of opportunity, initiative, experience and level-ups. See docs/RULES.md.
- **Character builder** (15-point buy) or pick a **pre-made hero**; the others become recruitable companions.
- **Party, camp and rest**, shops, loot, locked doors, traps, perception checks.
- **Turn-based combat** on the map grid with a monster AI.
- **Cutscenes** scripted in JSON with camera moves and sprite actors, with optional voice-over.
- **Starter campaign**: *Embers of Hollowmere* - one town, one camp, one dungeon, five missions.
- **Campaign format**: a folder of JSON files. Copy `campaigns/_template` to start your own
  (`tools/new_campaign.sh`). See docs/CAMPAIGN_FORMAT.md.

Every roll lands in the dice tray - here the Game Master calls for a Perception check when the party
walks onto a trap:

![Perception check in the dice tray](docs/img/live_trap_perception.png)

Characters are drawn by code from a short description (race, body, build, hair, outfit...):

![Sprite gallery](docs/img/sprite_gallery.png)

## For developers and AI agents

Start with [AGENTS.md](AGENTS.md). The short version: change something, run `./check.sh`.

## Paizo Community Use notice

> OpenGate uses trademarks and/or copyrights owned by Paizo Inc., used under Paizo's Community Use Policy (paizo.com/licenses/communityuse). We are expressly prohibited from charging you to use or access this content. OpenGate is not published, endorsed, or specifically approved by Paizo. For more information about Paizo Inc. and Paizo products, visit paizo.com.

Pathfinder and Pathfinder Roleplaying Game are trademarks of Paizo Inc.

OpenGate is free for everyone: no price, no paywall, no sign-up. Nobody may charge for it or for
access to it while it refers to Paizo's trademarks under this policy. If you fork it, the permission
does not pass to you automatically - follow the policy yourself (with your own project name and
contact address) or remove Paizo's trademarks. Details: [docs/LICENSING.md](docs/LICENSING.md).

**Contact:** open an issue at <https://github.com/drbree82/opengate3/issues>.

## Licence

- The **code and the original content** of this repository (engine, tools, the starter campaign,
  generated art and audio) are released under the [MIT License](LICENSE).
- The game runs on **[Godot Engine](https://godotengine.org)**, which is MIT-licensed too. Every
  build has to carry Godot's licence notice and those of the libraries inside it: the game shows them
  under **Licences** (title screen and pause menu), and `tools/write_notices.gd` writes them to a
  file to ship with a build.
- The **game mechanics** follow the Pathfinder Roleplaying Game Reference Document, which is Open
  Game Content under the Open Game License 1.0a. The rules data is used under that licence:
  [OGL.txt](OGL.txt) says which parts are Open Game Content and carries the licence text and its
  copyright notices. This project contains no Paizo Product Identity (no setting names, characters
  or prose from published books) and is not affiliated with or endorsed by Paizo.

Everything from third parties is listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
What each licence asks for, in plain language, and the checklist to run before publishing a build:
[docs/LICENSING.md](docs/LICENSING.md).
