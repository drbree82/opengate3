#!/usr/bin/env node
// Generates background music for a campaign with the ElevenLabs Music API.
//
// Tracks are described in campaign.json:
//   "music": { "town_dusk": { "prompt": "Warm medieval tavern lutes at dusk, calm, looping", "seconds": 60 } }
// and maps choose one with  "music": "town_dusk"  (the game loops campaigns/<id>/music/<track>.mp3).
//
//   npm run music -- <campaign> --list     show the tracks and which files exist (free)
//   npm run music -- <campaign>            generate the tracks that have no file yet
//   options: --only=<track>  --force  --yes  --model=<id>
import { client, saveAudio, parseArgs, loadCampaign, describeError, guardSpend, existsSync, path } from "./eleven_common.mjs";

const { args, flags } = parseArgs();
const campaign = loadCampaign(args[0]);
const MODEL = typeof flags.model === "string" ? flags.model : "music_v2_5";
const tracks = campaign.info.music ?? {};
const outDir = path.join(campaign.dir, "music");
const fileOf = (name) => path.join(outDir, `${name}.mp3`);

let names = Object.keys(tracks);
if (!names.length) {
  console.log(`campaign.json has no "music" section. Add one, for example:\n  "music": { "town": { "prompt": "Gentle medieval town theme, lute and flute, calm", "seconds": 60 } }`);
  process.exit(0);
}
if (typeof flags.only === "string") names = names.filter((n) => n === flags.only);

if (flags.list) {
  for (const n of names) console.log(`${existsSync(fileOf(n)) ? "ok     " : "missing"} ${n.padEnd(20)} ${tracks[n].seconds ?? 60}s  ${tracks[n].prompt}`);
  process.exit(0);
}

const todo = names.filter((n) => flags.force || !existsSync(fileOf(n)));
if (!todo.length) {
  console.log("Nothing to generate: every track already has a file. (--force regenerates)");
  process.exit(0);
}
const seconds = todo.reduce((s, n) => s + Number(tracks[n].seconds ?? 60), 0);
console.log(`Generating ${todo.length} tracks (${seconds} seconds of music) with model ${MODEL}...`);
guardSpend(seconds, 300, "seconds of music", flags);

const api = client();
let failed = 0;
for (const name of todo) {
  const t = tracks[name];
  try {
    const audio = await api.music.compose({
      prompt: t.prompt,
      musicLengthMs: Math.round(Number(t.seconds ?? 60) * 1000),
      modelId: MODEL,
      forceInstrumental: t.vocals ? false : true,
    });
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
