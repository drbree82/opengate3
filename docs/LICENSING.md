# Licensing - what applies to this project, in plain language

This is a practical summary, not legal advice. If money or a publisher gets involved, have a lawyer
read the actual licence texts.

## The short version

| Part | Whose it is | Licence | What you have to do |
|---|---|---|---|
| OpenGate code, tools, the starter campaign, the procedural art | this project | **MIT** (`LICENSE`) | Keep `LICENSE` in the repo and ship it with every build. |
| Godot Engine (inside every exported build) | Godot Engine contributors | **MIT** | Every build must show Godot's copyright notice and licence text. Done by the in-game **Licences** screen; also ship the notices file (below). |
| Libraries built into Godot (FreeType, mbed TLS, zlib, ...) | their authors | permissive licences (MIT, BSD, Apache-2.0, zlib, FTL, OFL, ...) | Same: their notices and licence texts must come with every build. Same screen, same file. |
| Pathfinder 1e game rules (`data/*.json`, `src/rules/`) | Paizo Inc. and others | **Open Game License 1.0a** (`OGL.txt`) | Keep `OGL.txt` in the repo and ship it with every build. Never change its wording. |
| The name "Pathfinder" | Paizo Inc. (trademark) | **Paizo Community Use Policy** | Keep the game free, keep Paizo's notice and a contact address visible, keep the content suitable for all ages. See "The name Pathfinder". |
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
- Point 5 is met through Paizo's Community Use Policy - see "The name Pathfinder" below.

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

## The name "Pathfinder" - Paizo's Community Use Policy

"Pathfinder" is Paizo's trademark. The Open Game License covers the rules but not the name, so the
project uses the name under Paizo's **Community Use Policy**
(https://paizo.com/licenses/communityuse, last updated 2024-08-22; adopted by the project owner on
2026-11-12). The policy is for free, unofficial fan projects, software included. Paizo's FAQ for it
says that rules content stays under the Open Game License and that the policy is what allows a
project to say it is compatible with Paizo's games - so the two are meant to be used together.

**What the policy asks for, and where the project does it:**

| The policy says | In this project |
|---|---|
| Show Paizo's prescribed notice, legibly, in the project | `README.md` ("Paizo Community Use notice"); in the game on the title screen (short form) and under Licences -> *Game rules* (full text, from `Notices.PAIZO_NOTICE`); in the notices file for builds |
| Show up-to-date contact information | `README.md` and the Licences screen point to the project's GitHub issues page (`Notices.CONTACT_URL`) |
| Reproduce Paizo's trademark notices | "Pathfinder and Pathfinder Roleplaying Game are trademarks of Paizo Inc." next to the notice |
| The project must be free for everyone: no price, no paywall, no sign-up or survey gates | The game and the repository are free. Donations, advertising and clearly named sponsors are allowed by the policy; charging is not |
| The project must be unofficial: nothing may suggest Paizo made, endorses or sponsors it | "unofficial" on the title screen and in the README; the notice says the same |
| No adult content, nothing offensive or inappropriate for minors | A content rule for campaigns, sprites, portraits and audio (docs/SPRITES.md) |
| Do not imitate the look of Paizo's products; logos and cover images only unmodified from Paizo's Community Use Package | The project uses none of Paizo's logos, artwork, maps or text |
| Follow the rules of every other owner whose material is used | Godot, the Open Game License and ElevenLabs: this document |

**What the owner has agreed to by using the policy** (worth knowing; this is a summary, read the
policy itself for the exact wording):

- Paizo may withdraw the permission at any time, for any reason. If that happens, the project has
  to stop distributing anything that uses Paizo's trademarks: remove the name "Pathfinder" from the
  README, AGENTS.md, the title screen and `project.godot`, and remove the notice.
- The user of the policy agrees to cover Paizo's legal costs if Paizo is drawn into a dispute
  because of the project.
- Any commercial use ends the permission automatically. Before anything is sold - the game, a
  campaign, early access - either remove Paizo's trademarks or get a commercial licence from Paizo
  (https://paizo.com/licenses).
- The permission is personal: it does not pass to forks. Someone who forks the project must follow
  the policy themselves, with their own project name and contact address in `src/core/notices.gd`
  and the README, or remove Paizo's trademarks.

**Rules for anyone changing the project (humans and AI agents):**

- Never add a price, paywall, paid unlock, mandatory sign-up or anything else that makes access
  less than free. If the owner asks for monetisation, point them to this section first.
- Never remove or reword the notice (`Notices.PAIZO_NOTICE`, the README section, the title screen
  line). `tests/test_notices.gd` checks that the README and the game carry the same text.
- Keep the contact address current (`Notices.CONTACT_URL` and the README).
- Do not add Paizo logos, cover art, maps, fiction or rulebook text, and do not style the game or
  its documents to look like Paizo's products.
- Keep every campaign, sprite, portrait and voice line suitable for all ages.
- The policy does allow describing Paizo's names and places, but this project's campaigns stay
  original: invent your own.

## ElevenLabs audio and portraits

The generated voice, music and sound-effect files are in the repository
(`campaigns/hollowmere/voice`, `campaigns/hollowmere/music`, `assets/sfx`). They were generated on
the owner's ElevenLabs subscription with stock voices. ElevenLabs' terms decide how generated audio
may be used (the plan matters for commercial use), so check them before selling anything.
Portraits you paint on the ElevenLabs website or elsewhere and drop into
`campaigns/<id>/portraits/` are in the same position: note the tool and the date in
`THIRD_PARTY_NOTICES.md`.
