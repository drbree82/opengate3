#!/usr/bin/env node
// Generates sound effects with the ElevenLabs sound-effects API.
//
// Two kinds of sounds:
//   engine sounds    described in data/sfx.json, written to assets/sfx/<name>.mp3.
//                    The game uses the file instead of its built-in synthesised beep of the same name
//                    (names are listed in src/ui/audio_bank.gd, RECIPES).
//   campaign sounds  described in campaign.json "sfx": { "<name>": { "prompt": "...", "seconds": 2 } },
//                    written to campaigns/<id>/sfx/<name>.mp3 and played with the script op
//                    {"op": "sfx", "name": "<name>"}.
//
//   npm run sfx -- --list                 engine sounds: what exists / is missing (free)
//   npm run sfx                           generate the missing engine sounds
//   npm run sfx -- <campaign> [--list]    the same for a campaign's own sounds
//   options: --only=<name>  --force  --yes  --model=<id>
import { client, saveAudio, readJson, parseArgs, loadCampaign, describeError, guardSpend, existsSync, path, ROOT } from "./eleven_common.mjs";

const { args, flags } = parseArgs();
const MODEL = typeof flags.model === "string" ? flags.model : "eleven_text_to_sound_v3";

let sounds;
let outDir;
if (args[0]) {
  const campaign = loadCampaign(args[0]);
  sounds = campaign.info.sfx ?? {};
  outDir = path.join(campaign.dir, "sfx");
} else {
  sounds = readJson(path.join(ROOT, "data", "sfx.json"), {});
  outDir = path.join(ROOT, "assets", "sfx");
}
const fileOf = (name) => path.join(outDir, `${name}.mp3`);

let names = Object.keys(sounds).filter((n) => !n.startsWith("_"));
if (!names.length) {
  console.log('No sounds are described. Add entries like  "door": { "prompt": "Heavy wooden door creaking open", "seconds": 1.5 }');
  process.exit(0);
}
if (typeof flags.only === "string") names = names.filter((n) => n === flags.only);

if (flags.list) {
  for (const n of names) console.log(`${existsSync(fileOf(n)) ? "ok     " : "missing"} ${n.padEnd(14)} ${String(sounds[n].seconds ?? "auto").padEnd(5)} ${sounds[n].prompt}`);
  process.exit(0);
}

const todo = names.filter((n) => flags.force || !existsSync(fileOf(n)));
if (!todo.length) {
  console.log("Nothing to generate: every sound already has a file. (--force regenerates)");
  process.exit(0);
}
console.log(`Generating ${todo.length} sound effects with model ${MODEL}...`);
guardSpend(todo.length, 40, "sound effects", flags);

const api = client();
let failed = 0;
for (const name of todo) {
  const s = sounds[name];
  try {
    const request = { text: s.prompt, modelId: MODEL, promptInfluence: s.influence ?? 0.6 };
    if (s.seconds) request.durationSeconds = Number(s.seconds);
    if (s.loop) request.loop = true;
    const audio = await api.textToSoundEffects.convert(request);
    await saveAudio(audio, fileOf(name));
    console.log(`  ok   ${name}`);
  } catch (err) {
    failed += 1;
    console.error(`  FAIL ${name}: ${describeError(err)}`);
    if ([401, 402].includes(err?.statusCode)) break;
  }
}
console.log(`\nDone. Files are in ${path.relative(process.cwd(), outDir)}.`);
process.exit(failed ? 1 : 0);
