# Third-party notices

OpenGate's own code and original content are released under the MIT License (see the LICENSE file).
This file lists everything in or around the project that comes from somebody else.
The same information is shown inside the game: title screen or pause menu -> Licences.
Plain-language background and the "before you publish a build" checklist: docs/LICENSING.md.

## Godot Engine (the engine the game runs on)

Godot Engine is not stored in this repository, but it is part of every exported build of the game,
so every build must carry the notice below. Project page: https://godotengine.org
License: MIT (Godot's own files call it "Expat") - https://godotengine.org/license

```
Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Godot Engine itself contains third-party components (FreeType, mbed TLS, zlib and many more), each
with its own copyright notice and licence. They are not copied into this file because the list changes
with every Godot version. Instead:

- in the game they are listed under Licences -> "Third-party" and "Licence texts"
  (read live from the engine that is running);
- `godot --headless --path . -s res://tools/write_notices.gd` writes all of them, together with this
  file, LICENSE and OGL.txt, to `build/THIRD_PARTY_NOTICES.txt`, to ship next to an exported build.

The game's text is drawn with Godot's built-in default font (Open Sans, SIL Open Font License 1.1),
which is one of those components. The project adds no other fonts.

## Pathfinder Roleplaying Game rules (Open Game Content)

The rules data in `data/*.json` and the rules maths in `src/rules/` follow the Pathfinder Roleplaying
Game Reference Document (first edition), which Paizo Inc. published as Open Game Content under the
Open Game License version 1.0a. That material is used under that licence. The file `OGL.txt` in the
repository root says exactly which parts are Open Game Content and contains the full licence text
with its Section 15 copyright notices (Open Game License, System Reference Document, Pathfinder
Roleplaying Game Reference Document, Core Rulebook and Bestiary). In the game: Licences -> "Game rules".

The project uses the game mechanics only. It contains no Paizo setting material, characters, fiction
or artwork, and it is not published, endorsed or approved by Paizo. Background: docs/LICENSING.md.

## ElevenLabs (generated audio)

The voice lines (`campaigns/hollowmere/voice/`), the music (`campaigns/hollowmere/music/`) and the
sound effects (`assets/sfx/`) were generated with ElevenLabs (https://elevenlabs.io) on the project
owner's subscription, using ElevenLabs' stock voices. The prompts and scripts are the project's own
(`campaign.json`, `data/sfx.json`, `tools/gen_*.mjs`). ElevenLabs' terms of service apply to how these
files may be used; check them again before selling a build.

## @elevenlabs/elevenlabs-js (development tool, not part of the game)

MIT License, Copyright (c) 2026 Elevenlabs. Used only by the generator scripts in `tools/*.mjs`.
`npm install` puts it in `node_modules/`, which is neither committed nor shipped with the game.

## Art

All sprites and textures are drawn by the game's own code (`src/render/`).
There are no third-party images, models or sound recordings in the repository.

## Adding something that is not yours?

Add an entry to this file in the same change: what it is, where it lives in the repository, who
made it, its licence, and where it came from. If it has a licence text, keep that text next to the
files. Do not add anything whose licence you cannot name.
