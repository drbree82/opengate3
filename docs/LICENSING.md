# Licensing - what applies to this project, in plain language

This is a practical summary, not legal advice. If money or a publisher gets involved, have a lawyer
read the actual licence texts.

## The short version

| Part | Whose it is | Licence | What you have to do |
|---|---|---|---|
| OpenGate code, tools, the starter campaign, the procedural art | this project | **MIT** (`LICENSE`) | Keep `LICENSE` in the repo and ship it with every build. |
| Godot Engine (inside every exported build) | Godot Engine contributors | **MIT** | Every build must show Godot's copyright notice and licence text. Done by the in-game **Licences** screen; also ship the notices file (below). |
| Libraries built into Godot (FreeType, mbed TLS, zlib, ...) | their authors | permissive licences (MIT, BSD, Apache-2.0, zlib, FTL, OFL, ...) | Same: their notices and licence texts must come with every build. Same screen, same file. |
| Pathfinder 1e game rules (`data/*.json`, `src/rules/`) | Paizo Inc. and others | **Open Game License 1.0a** (`OGL.txt`) | Keep `OGL.txt` in the repo and ship it with every build. Never change its wording. One point is still open: the name "Pathfinder" (below). |
| Voices, music, sound effects | generated with ElevenLabs | ElevenLabs terms of service | Listed in `THIRD_PARTY_NOTICES.md`. Re-read their terms before selling a build. |

Everything that is not the project's own is listed in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

## Godot Engine

Godot is free, MIT-licensed software. You may use it for anything, including commercial games, and
your game may have any licence you like. The one condition: **when you give somebody a copy of the
game, Godot's copyright notice and licence text must come with it** - and so must the notices of
the third-party libraries compiled into the engine.

Godot accepts any of these places for the text: a credits screen, a licences screen, a file that is
installed with the game, a printed manual, or the output log. This project uses two of them:

1. **In the game: title screen or pause menu -> Licences** (`src/ui/licenses_screen.gd`).
   Tabs: *This game* (`LICENSE` + `THIRD_PARTY_NOTICES.md`), *Game rules* (`OGL.txt`),
   *Godot Engine* (Godot's licence),
   *Third-party* (every component inside the engine with its copyright holders) and
   *Licence texts* (the full text of each licence).
   The text is read from the running engine by `src/core/notices.gd`
   (`Engine.get_license_text()`, `get_copyright_info()`, `get_license_info()`), so it is always
   right for the Godot version in the build. Nothing to edit when Godot is upgraded.
2. **As a file next to the build:**

   ```bash
   godot --headless --path . -s res://tools/write_notices.gd
   ```

   writes `build/THIRD_PARTY_NOTICES.txt` with all of the above in one file.

The source repository on GitHub does not contain Godot, so the obligation is about **builds**.
The repository still names Godot and carries its licence in `THIRD_PARTY_NOTICES.md` so nobody has
to look for it.

### Before you give anyone an exported build

- [ ] The **Licences** button is still on the title screen and opens the screen.
- [ ] `LICENSE`, `THIRD_PARTY_NOTICES.md` and `OGL.txt` are in the build: add
      `LICENSE, THIRD_PARTY_NOTICES.md, OGL.txt` to the export preset's *"Filters to export
      non-resource files"*. (If they are missing, the *This game* and *Game rules* tabs show a
      one-line fallback instead - the Godot tabs still work.)
- [ ] Run the command above with the **same Godot version** you exported with and put
      `THIRD_PARTY_NOTICES.txt`, `LICENSE` and `OGL.txt` in the same folder / archive as the game.
- [ ] `./check.sh` passes (`tests/test_notices.gd` checks that the notices are complete).

### Rules for anyone changing the code (humans and AI agents)

- Never remove the Licences screen or its buttons, and never trim or reword licence text.
- Do not paste licence texts from memory. Engine texts come from `Notices`; for anything new, copy
  the licence file that ships with the thing itself.
- Adding an asset or library made by someone else? Add it to `THIRD_PARTY_NOTICES.md` in the same
  change (what, where, author, licence, source). If you cannot name its licence, do not add it.
- Code copied from the Godot repository or its demos stays under its original licence: keep its
  header and list it in `THIRD_PARTY_NOTICES.md`.

## Pathfinder rules and the OGL

**What the OGL is.** The *Open Game License 1.0a* is a free licence written by Wizards of the Coast
in 2000 for tabletop role-playing rules. Paizo published the Pathfinder first-edition rules under
it. It has nothing to do with Godot or with software licences: it covers *game content* - classes,
feats, spells, monster statistics. It lets anyone reuse that "Open Game Content", free of charge
and also commercially, if they follow its conditions.

**Why it matters here.** `data/*.json` (classes, feats, spells, monsters, ...) and the formulas in
`src/rules/` come from the Pathfinder Reference Document. That is Open Game Content.

**What the licence asks of anyone who distributes Open Game Content:**

1. Include a complete copy of the Open Game License with it.
2. Keep its "Section 15" copyright notice up to date: the notices of every source you drew on
   (for this project: the OGL itself, the d20 System Reference Document, and the Pathfinder
   Roleplaying Game Reference Document / Core Rulebook / Bestiary), plus a line for your own work.
3. Say clearly which parts of your work are Open Game Content (here: the rules data and rules maths).
4. Do not use "Product Identity": Paizo's setting, its named characters and places, its fiction,
   artwork and logos. (This project uses none - keep it that way in new campaigns.)
5. Do not advertise compatibility with someone's trademark - for example the name "Pathfinder" -
   unless that owner has separately allowed it.

**Where the project stands (2026-11-12):**

- Points 1 to 4 are met by [`OGL.txt`](../OGL.txt) in the repository root. It starts with the
  project's own notice (which parts are Open Game Content, which are not), followed by the licence
  text and Section 15. The licence text is the copy Paizo distributes with the Pathfinder Reference
  Document, checked word for word against the Open Gaming Foundation's copy. The game shows the file
  under Licences -> *Game rules*, and `tools/write_notices.gd` includes it in the notices file.
- Point 5 is **open**: the project describes itself with the name "Pathfinder" (README, AGENTS.md,
  title screen). Paizo's **Community Use Policy** (https://paizo.com/communityuse, last updated
  2024-08-22) allows free, non-commercial fan projects, software included, to refer to Paizo's
  trademarks **if** the project shows the notice that policy prescribes, stays free for everyone,
  and does not suggest Paizo endorses it. If the project should ever be sold, that policy no longer
  applies and the name has to go (or a commercial licence from Paizo is needed) - see
  https://paizo.com/licenses. The alternative is to describe the rules without the trademark.
  The owner has not decided yet; agents must not decide this for them.

**Keeping `OGL.txt` right:**

- Never change the wording of the licence (everything from "OPEN GAME LICENSE Version 1.0a" down to
  Section 14). `tests/test_notices.gd` compares it against a checksum; if that test fails, restore
  the file with `git checkout OGL.txt` instead of "fixing" the test.
- Section 15 lists the sources the rules data draws on. Today that is the Core Rulebook and the first
  Bestiary (plus the documents they build on). **If you add rules content from another book** - a
  monster from Bestiary 2, a class from the Advanced Player's Guide - add that book's copyright
  notice to Section 15, copied exactly from the Section 15 that Paizo publishes for the Pathfinder
  Reference Document (https://legacy.aonprd.com/openGameLicense.html). Not from memory.
- New rules data belongs in the places `OGL.txt` names as Open Game Content (`data/`, a campaign's
  `items.json` / `monsters.json`). If rules data moves somewhere else, update the designation at the
  top of `OGL.txt`.
- The last line of Section 15 names this project and its copyright holder, as written in `LICENSE`.
  Change both together.

**Rules for campaign authors and agents:** invent your own places, people and gods. Do not copy
names, text or art from published Pathfinder books or adventures, and do not copy rules text
word-for-word - write short descriptions in your own words, as the existing data files do.

## ElevenLabs audio and portraits

The generated voice, music and sound-effect files are in the repository
(`campaigns/hollowmere/voice`, `campaigns/hollowmere/music`, `assets/sfx`). They were generated on
the owner's ElevenLabs subscription with stock voices. ElevenLabs' terms decide how generated audio
may be used (the plan matters for commercial use), so check them before selling anything.
Portraits you paint on the ElevenLabs website or elsewhere and drop into
`campaigns/<id>/portraits/` are in the same position: note the tool and the date in
`THIRD_PARTY_NOTICES.md`.
