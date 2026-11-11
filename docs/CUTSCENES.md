# Cutscenes

A cutscene is a JSON file in `campaigns/<id>/cutscenes/`. It uses the same 3D room and the same
sprites as the game: you move the camera and the actors, and characters speak in subtitles (with
voice clips when they exist). Play one with `{"op": "cutscene.play", "id": "<file name>"}`.

```json
{
  "map": "town",
  "steps": [
    {"op": "fade", "to": "black", "seconds": 0},
    {"op": "title", "text": "Embers of Hollowmere", "sub": "An OpenGate adventure", "seconds": 2.2},
    {"op": "camera.set", "at": [9, 16], "z": 1.2, "look": "square", "fov": 62},
    {"op": "fade", "to": "clear", "seconds": 1.5},
    {"op": "parallel", "steps": [
      {"op": "camera.move", "at": [12, 16], "z": 0.9, "look": "square", "fov": 55, "seconds": 6},
      {"op": "narrate", "text": "Dusk settles over Hollowmere."}
    ]},
    {"op": "say", "speaker": "reeve", "text": "You came."},
    {"op": "flag.set", "flag": "met_reeve"}
  ]
}
```

Always give `"map"`: the cutscene switches to that map if the party is elsewhere.
Steps run one after another; `parallel` runs its steps together and waits for all of them.

| op | fields | |
|---|---|---|
| `camera.set` | at, z?, look \| angle, lookZ?, fov? | cut the camera to a position |
| `camera.move` | same + seconds, ease? (`inout`, `linear`, `in`, `out`) | glide the camera |
| `camera.auto` | focus? (entity id) | hand the camera back to the game (follow an entity) |
| `camera.shake` | seconds | |
| `actor.spawn` | id, template, at, facing?, set?, keep? | add an extra actor (removed afterwards unless `keep`) |
| `actor.move` | id, to, speed? | walk an actor (finds a path) |
| `actor.teleport` | id, to | |
| `actor.face` | id, toward (position) or angle (`N`,`E`,`S`,`W` or degrees) | |
| `actor.anim` | id, anim (`idle`,`walk`,`attack`,`cast`,`talk`,`hurt`,`dead`), seconds? | |
| `actor.show` / `actor.hide` / `actor.remove` | id | |
| `say` | speaker, text, voice?, voiceText? | subtitle + voice; the speaker's sprite talks |
| `narrate` | text, voice? | narrator subtitle |
| `title` | text, sub?, seconds | full-screen title card |
| `fade` | to, seconds | |
| `wait` | seconds | |
| `parallel` / `sequence` | steps | grouping |
| any script op | | `flag.set`, `quest.stage`, `entity.spawn`... all work (docs/SCRIPTING.md) |

Positions (`at`, `to`, `look`, `toward`) are `[x, y]` tile coordinates, a marker name, or an entity
id (`"player"` is the party leader, a companion id is that party member).
`z` is the camera height (walls are `wallHeight` high, people about 0.8). `fov` in degrees: 60 is
normal, 35 is a close-up.

While a cutscene plays, Space or a click skips the current line and Esc skips the whole scene.
Skipped steps still run instantly, so flags and quests stay correct.

Voice: every `say` / `narrate` line gets the key `cs.<cutscene id>.<n>` (n counts the say/narrate
steps from the top, including those inside `parallel`). `npm run voices -- <campaign>` generates
`voice/<key>.mp3` for each. See docs/VOICE.md.

Tips: place the camera on an open tile a few tiles from the subject; check the framing with a
screenshot tour (`--shots`, see AGENTS.md); keep lines short - one subtitle per breath.
