#!/usr/bin/env node
// Generates the voice clip for every spoken line of a campaign with ElevenLabs text-to-speech.
// The game plays campaigns/<id>/voice/<key>.mp3 automatically when the line is shown (docs/VOICE.md).
//
//   npm run voices -- <campaign> --list       show every line, its speaker, and what is missing (free)
//   npm run voices -- <campaign> --voices     list the voices your ElevenLabs account can use (free)
//   npm run voices -- <campaign> --assign     give every speaker without a voice one of the pre-made voices
//   npm run voices -- <campaign>              generate clips that are missing or whose text/voice changed
//   options: --only=<speaker or key prefix>  --limit=<n>  --force  --yes  --model=<id>  --dry-run
//
// Where lines and voice keys come from (must match src/engine/campaign.gd, _assign_voice_keys):
//   dialogue node  -> "dlg.<dialogue id>.<node id>"      speaker = node.speaker or "narrator"
//   cutscene line  -> "cs.<cutscene id>.<n>"             n = running number of say/narrate steps (depth first)
//   any line with an explicit "voice": "<key>" uses that key (this is also how map triggers get a voice)
// Which voice speaks: campaign.json  "voices": { "<speaker id>": "<ElevenLabs voice id>", "narrator": "..." }
// Optional per line: "voiceText" = the text sent to ElevenLabs when it should differ from the shown text
// (for example to add v4 audio tags like "[whispers]").
import { client, saveAudio, readJson, writeJson, parseArgs, loadCampaign, loadFolder, describeError, guardSpend, existsSync, path } from "./eleven_common.mjs";

const { args, flags } = parseArgs();
const campaign = loadCampaign(args[0]);
const MODEL = typeof flags.model === "string" ? flags.model : "eleven_v4";
const voiceDir = path.join(campaign.dir, "voice");
const manifestFile = path.join(voiceDir, "manifest.json");

/** Every voiced line of the campaign: [{ key, speaker, text }] */
function collectLines() {
  const lines = [];
  const add = (key, speaker, node) => {
    const shown = String(node.text ?? "");
    let text = String(node.voiceText ?? shown);
    if (/\{(race|class|gold)\}/.test(text)) return lines.push({ key, speaker, text, skip: "contains {race}/{class}/{gold}" });
    text = text.replace(/\{(player|leader)\}/g, campaign.info.voiceName ?? "traveller");
    lines.push({ key, speaker: speaker || "narrator", text });
  };
  for (const { id, data } of loadFolder(campaign.dir, "dialogues")) {
    for (const [nodeId, node] of Object.entries(data.nodes ?? {})) {
      if (node && typeof node === "object" && node.text) add(node.voice ?? `dlg.${id}.${nodeId}`, node.speaker, node);
    }
  }
  for (const { id, data } of loadFolder(campaign.dir, "cutscenes")) {
    let n = 0;
    const walk = (steps) => {
      for (const s of steps ?? []) {
        if (!s || typeof s !== "object") continue;
        if (s.op === "say" || s.op === "narrate") {
          n += 1;
          add(s.voice ?? `cs.${id}.${n}`, s.op === "say" ? s.speaker : "narrator", s);
        }
        if (Array.isArray(s.steps)) walk(s.steps);
      }
    };
    walk(data.steps);
  }
  // Script actions elsewhere (map triggers, encounters, entities) are voiced only with an explicit key.
  const scan = (value) => {
    if (Array.isArray(value)) return value.forEach(scan);
    if (!value || typeof value !== "object") return;
    if ((value.op === "narrate" || value.op === "say") && value.voice && value.text) add(value.voice, value.op === "say" ? value.speaker : "narrator", value);
    Object.values(value).forEach(scan);
  };
  for (const { data } of loadFolder(campaign.dir, "maps")) scan(data);
  for (const name of ["encounters.json", "entities.json"]) scan(readJson(path.join(campaign.dir, name), {}));
  scan(campaign.info.start ?? {});
  const seen = new Set();
  return lines.filter((l) => (seen.has(l.key) ? false : seen.add(l.key)));
}

async function listAccountVoices() {
  const res = await client().voices.search({ pageSize: 100 });
  return res.voices ?? [];
}

const voices = campaign.info.voices ?? {};
const settings = campaign.info.voiceSettings ?? {};
const manifest = readJson(manifestFile, {});
const lines = collectLines();

function status(line) {
  if (line.skip) return "skip";
  const voice = voices[line.speaker] || voices._default;
  if (!voice) return "no voice";
  const file = path.join(voiceDir, `${line.key}.mp3`);
  if (!existsSync(file)) return "missing";
  const m = manifest[line.key];
  if (!m || m.text !== line.text || m.voice !== voice) return "changed";
  return "ok";
}

if (flags.voices) {
  try {
    for (const v of await listAccountVoices()) {
      const labels = Object.values(v.labels ?? {}).join(", ");
      console.log(`${v.voiceId}  ${String(v.name ?? "").padEnd(34)} ${String(v.category ?? "").padEnd(12)} ${labels}`);
    }
    console.log('\nPut ids into campaign.json:  "voices": { "narrator": "<id>", "<speaker id>": "<id>" }');
  } catch (err) {
    console.error("Could not list voices: " + describeError(err));
    process.exit(1);
  }
  process.exit(0);
}

if (flags.assign) {
  // Pre-made voices work on every plan. Speakers may carry a hint in campaign.json:
  //   "voiceHints": { "reeve": "female middle aged calm" }   (matched against the voice labels)
  const speakers = [...new Set(lines.filter((l) => !l.skip).map((l) => l.speaker))].filter((s) => !voices[s]);
  if (!speakers.length) {
    console.log("Every speaker already has a voice.");
    process.exit(0);
  }
  let pool;
  try {
    pool = (await listAccountVoices()).filter((v) => v.category === "premade");
  } catch (err) {
    console.error("Could not list voices: " + describeError(err));
    process.exit(1);
  }
  if (!pool.length) {
    console.error("The account has no pre-made voices to choose from.");
    process.exit(1);
  }
  const used = new Set(Object.values(voices));
  const hints = campaign.info.voiceHints ?? {};
  for (const speaker of speakers) {
    const words = String(hints[speaker] ?? "").toLowerCase().split(/\s+/).filter(Boolean);
    // Whole-word matching ("male" must not match "female"); a wrong gender is heavily penalised.
    const wantGender = words.find((w) => w === "male" || w === "female");
    const scored = pool.map((v) => {
      const tokens = `${v.name} ${Object.values(v.labels ?? {}).join(" ")}`.toLowerCase().split(/[^a-z]+/);
      let score = words.filter((w) => tokens.includes(w)).length * 10 - (used.has(v.voiceId) ? 5 : 0);
      const gender = String(v.labels?.gender ?? "").toLowerCase();
      if (wantGender && gender && gender !== wantGender) score -= 100;
      return { v, score };
    }).sort((a, b) => b.score - a.score);
    const pick = scored[0].v;
    voices[speaker] = pick.voiceId;
    used.add(pick.voiceId);
    console.log(`${speaker.padEnd(16)} -> ${pick.name} (${pick.voiceId})`);
  }
  campaign.info.voices = voices;
  writeJson(campaign.file, campaign.info);
  console.log(`\nSaved to ${path.relative(process.cwd(), campaign.file)}. Change any id by hand if you prefer another voice.`);
  process.exit(0);
}

let todo = lines.filter((l) => flags.force ? !l.skip && (voices[l.speaker] || voices._default) : ["missing", "changed"].includes(status(l)));
if (typeof flags.only === "string") todo = todo.filter((l) => l.speaker === flags.only || l.key.startsWith(flags.only));
if (flags.limit) todo = todo.slice(0, Number(flags.limit));

if (flags.list || flags["dry-run"]) {
  const counts = {};
  for (const l of lines) {
    const st = status(l);
    counts[st] = (counts[st] ?? 0) + 1;
    console.log(`${st.padEnd(9)} ${l.key.padEnd(34)} ${l.speaker.padEnd(14)} ${l.text.slice(0, 70)}`);
  }
  const noVoice = [...new Set(lines.filter((l) => status(l) === "no voice").map((l) => l.speaker))];
  console.log(`\n${lines.length} lines: ${Object.entries(counts).map(([k, v]) => `${v} ${k}`).join(", ")}`);
  if (noVoice.length) console.log(`Speakers without a voice in campaign.json "voices": ${noVoice.join(", ")}   (try --assign)`);
  console.log(`A normal run would generate ${todo.length} clips, about ${todo.reduce((n, l) => n + l.text.length, 0)} characters.`);
  process.exit(0);
}

if (!todo.length) {
  console.log("Nothing to generate: every line with a voice is up to date. (--list shows the details)");
  process.exit(0);
}
const chars = todo.reduce((n, l) => n + l.text.length, 0);
console.log(`Generating ${todo.length} clips (${chars} characters) with model ${MODEL}...`);
guardSpend(chars, 20000, "characters", flags);

const api = client();
let done = 0;
let failed = 0;
for (const line of todo) {
  const voice = voices[line.speaker] || voices._default;
  try {
    const request = { text: line.text, modelId: MODEL };
    if (settings[line.speaker]) request.voiceSettings = settings[line.speaker];
    const audio = await api.textToSpeech.convert(voice, request);
    await saveAudio(audio, path.join(voiceDir, `${line.key}.mp3`));
    manifest[line.key] = { speaker: line.speaker, voice, model: MODEL, text: line.text };
    writeJson(manifestFile, manifest);
    done += 1;
    console.log(`  ok   ${line.key}`);
  } catch (err) {
    failed += 1;
    console.error(`  FAIL ${line.key}: ${describeError(err)}`);
    if ([401, 402].includes(err?.statusCode)) break;
  }
}
console.log(`\n${done} clips written to ${path.relative(process.cwd(), voiceDir)}${failed ? `, ${failed} failed` : ""}.`);
process.exit(failed ? 1 : 0);
