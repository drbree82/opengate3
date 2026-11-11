# Voices, music, sound effects and portraits (ElevenLabs)

Generated media is optional: without it the game shows text, plays synthesised beeps and uses the
pixel sprites as portraits. With it, lines are spoken, maps have music and characters have painted portraits.

## Setup (already done on this machine)

`npx -y @elevenlabs/cli@latest onboard init` signs in and stores the key in `.env.local`
(never commit it, never print it, never put it in code). The SDK is in `package.json`
(`npm install` restores `node_modules/`). The tools must be run through npm so the key is loaded.

## Tools

| Command | What it makes | Free preview |
|---|---|---|
| `npm run voices -- <campaign>` | `campaigns/<id>/voice/<key>.mp3` for every dialogue and cutscene line | `--list` |
| `npm run music -- <campaign>` | `campaigns/<id>/music/<track>.mp3` from `campaign.json "music"` | `--list` |
| `npm run sfx` | `assets/sfx/<name>.mp3` from `data/sfx.json` (replaces the built-in beeps) | `--list` |
| `npm run sfx -- <campaign>` | `campaigns/<id>/sfx/<name>.mp3` from `campaign.json "sfx"` | `--list` |
| `npm run portraits -- <campaign>` | `campaigns/<id>/portraits/<id>.png` for companions and named NPCs | `--list` |

Every tool only generates what is missing (voices also regenerate lines whose text or voice
changed), stops above a spending limit unless you add `--yes`, and accepts `--only=<name>` and `--force`.
**Generating costs ElevenLabs credits.** Run `--list` first and finish editing the script before generating.

## Voices

1. Choose who sounds like what. `npm run voices -- <campaign> --voices` lists the voices of the
   account. Put ids in `campaign.json`:
   `"voices": {"narrator": "<voice id>", "reeve": "<voice id>", "_default": "<voice id>"}`.
   The keys are speaker ids (the `speaker` of dialogue nodes and cutscene lines; `narrator` for narration).
   Or let the tool pick pre-made voices: `npm run voices -- <campaign> --assign`
   (it reads `"voiceHints": {"reeve": "female middle aged calm"}`).
2. `npm run voices -- <campaign> --list` shows every line, its key and its status.
3. `npm run voices -- <campaign>` generates.

How lines get their key (must stay in sync between `src/engine/campaign.gd` and `tools/gen_voices.mjs`):
dialogue node -> `dlg.<dialogue>.<node>`; cutscene line -> `cs.<cutscene>.<n>`; any line with an
explicit `"voice": "<key>"` uses that key (this is how a map trigger's `narrate` can be voiced).
`"voiceText"` on a line overrides the text sent to ElevenLabs (useful for v4 audio tags such as
`[whispers]`). Lines containing `{race}`, `{class}` or `{gold}` are skipped; `{player}` is spoken
as `campaign.json "voiceName"`. Optional `"voiceSettings": {"varrek": {"stability": 0.3}}`.

In the game the clip plays when the line appears; Space skips it.

## Music

`campaign.json`: `"music": {"town": {"prompt": "calm medieval lute at dusk, seamless loop", "seconds": 60}}`
and in a map: `"music": "town"`. The track loops while the party is on that map.

## Sound effects

Engine sounds are named in `RECIPES` (src/ui/audio_bank.gd). If `assets/sfx/<name>.mp3` exists it is
used instead of the synthesised version. Prompts are in `data/sfx.json`.
Campaign sounds are played with `{"op": "sfx", "name": "<name>"}`.

## Portraits

Note: through the **API**, ElevenLabs image generation needs a **Pro plan or above** (on lower plans
every image model answers HTTP 402 and the tool says so). The ElevenLabs **website** offers image
generation on lower plans too, so there are two ways to get portraits:

- Pro or above: `npm run portraits -- <campaign>` paints them all.
- Any plan: `npm run portraits -- <campaign> --prompts` prints one ready-to-paste prompt per
  character and the file name to save it under. Paint each on the website (square, 1:1) and save it
  as `campaigns/<id>/portraits/<character id>.png` (`.jpg` and `.webp` work too).

Without a portrait file the game uses the pixel sprite as the portrait.

`npm run portraits -- <campaign>` paints one image per companion and per entity that has a
`"portrait"` prompt or a humanoid sprite with a name. The prompt is built from the character's
race, class, look and bio plus `campaign.json "portraitStyle"`; set `"portrait": "..."` on a
companion or entity to describe it yourself. Files: `campaigns/<id>/portraits/<id>.png`.
The character sheet, party list, hero cards and dialogue use the portrait when it exists.

## Code map

`tools/eleven_common.mjs` (client, saving, arguments), `tools/gen_voices.mjs`, `tools/gen_music.mjs`,
`tools/gen_sfx.mjs`, `tools/gen_portraits.mjs`. In the game: `src/ui/audio_bank.gd` (playback),
`src/ui/portraits.gd` (portrait lookup), `src/ui/ui_io.gd` (`say`, `subtitle`, `music`).
