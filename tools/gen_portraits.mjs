#!/usr/bin/env node
// Paints character portraits with ElevenLabs image generation (flows.image).
// The game shows campaigns/<id>/portraits/<character id>.png on the character sheet, the party
// list, the hero cards and in dialogue, and falls back to the pixel sprite when there is no file.
//
//   npm run portraits -- <campaign> --list     who would be painted, and the prompt for each (free)
//   npm run portraits -- <campaign> --prompts  one complete, ready-to-paste prompt per missing portrait (free)
//   npm run portraits -- <campaign>            paint the portraits that do not exist yet
//   options: --only=<id>  --force  --yes  --model=<id>  --resolution=512|1K
//
// PLAN NOTE: the image API answers HTTP 402 below the ElevenLabs Pro plan (all models, checked 2026-11-12).
// The ElevenLabs website can still paint images on lower plans: use --prompts, paint each one there
// (square, 1:1) and save it as campaigns/<id>/portraits/<character id>.png - the game finds it by name.
//
// Who gets a portrait: every companion, and every named NPC / monster template in entities.json and
// the campaign's monsters.json that has a humanoid sprite or a "portrait" prompt.
// The prompt = campaign.json "portraitStyle" (or the default below) + the character's "portrait"
// text if it has one, otherwise a description built from race, class, look and bio.
import { writeFileSync, mkdirSync } from "node:fs";
import { client, readJson, parseArgs, loadCampaign, describeError, guardSpend, existsSync, path, ROOT } from "./eleven_common.mjs";

const { args, flags } = parseArgs();
const campaign = loadCampaign(args[0]);
const MODEL = typeof flags.model === "string" ? flags.model : "gemini-3.1-flash-image";
const RESOLUTION = typeof flags.resolution === "string" ? flags.resolution : "1K";
const outDir = path.join(campaign.dir, "portraits");
const EXTS = ["png", "jpg", "jpeg", "webp"];
const STYLE = campaign.info.portraitStyle ??
  "Painted fantasy character portrait, head and shoulders, three-quarter view, looking toward the viewer, " +
  "dramatic warm rim light against a dark muted background, rich painterly brushwork in the style of classic " +
  "computer role-playing game character portraits. Tasteful and fully clothed. No text, no letters, no frame, no border.";

const races = readJson(path.join(ROOT, "data", "races.json"), {});
const classes = readJson(path.join(ROOT, "data", "classes.json"), {});
const baseMonsters = readJson(path.join(ROOT, "data", "monsters.json"), {});

/** "#b8452a" -> "red" (good enough for a prompt). */
function colorName(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex ?? ""));
  if (!m) return "";
  const n = parseInt(m[1], 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => v / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
  if (d < 0.08) return l > 0.82 ? "white" : l > 0.6 ? "silver-grey" : l > 0.3 ? "grey" : "black";
  let h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  h = (h * 60 + 360) % 360;
  const dark = l < 0.3 ? "dark " : l > 0.7 ? "pale " : "";
  if (h < 20 || h >= 340) return dark + (l < 0.35 ? "auburn" : "red");
  if (h < 45) return l < 0.3 ? "dark brown" : l < 0.5 ? "brown" : "golden blonde";
  if (h < 70) return l > 0.6 ? "blonde" : "tawny";
  if (h < 170) return dark + "green";
  if (h < 260) return dark + "blue";
  if (h < 300) return dark + "purple";
  return dark + "pink";
}

const BUILD = {
  heroic: "broad-shouldered, strong-jawed and classically handsome", athletic: "athletic and strong",
  slim: "lean", rustic: "sturdy, plain and weathered by outdoor work", heavy: "heavyset", stout: "stout and solid",
  curvy: "beautiful, with a graceful hourglass figure", slender: "slender, elegant and beautiful", small: "small and nimble",
};
const HAIR = {
  short: "short hair", long: "long straight hair", wavy: "long flowing wavy hair", ponytail: "hair tied in a ponytail",
  bun: "hair in a neat bun", braids: "long braids", curly: "curly hair", topknot: "a topknot", mohawk: "a mohawk",
  bald: "a bald head", hood: "a hood over the hair", helm: "a steel helmet", hat: "a pointed wizard hat",
};
// {c} is replaced by the colour of the outfit
const OUTFIT = {
  armor: "{c} plate and mail armour", robe: "long {c} robes", dress: "an elegant {c} dress", bodice: "a fitted, laced {c} bodice",
  leather: "worn {c} leather armour", tunic: "a simple {c} tunic",
};
/** Cloth colours: yellowish light tones read better as cream / tan than as "blonde". */
function clothColor(hex) {
  const n = colorName(hex);
  return { "golden blonde": "tan", blonde: "cream", tawny: "ochre", "silver-grey": "pale grey" }[n] ?? n;
}
const RACE = { half_elf: "half-elf", half_orc: "half-orc with green-grey skin and small tusks", goblin: "goblin with green skin and huge ears" };

function describe(s) {
  if (s.portrait) return `${s.name}. ${s.portrait}`;
  const look = s.look ?? {};
  const race = look.race ?? s.race ?? "human";
  const cls = classes[s.cls]?.name?.toLowerCase() ?? s.role ?? "";
  const outfitKey = look.outfit ?? classes[s.cls]?.look?.outfit ?? (look.robe ? "robe" : "tunic");
  const bits = [];
  bits.push(`${s.name}, ${look.age === "old" ? "an elderly" : "a"} ${look.body === "feminine" ? "woman" : look.body === "masculine" ? "man" : "person"}, ` +
    `${RACE[race] ?? races[race]?.name?.toLowerCase() ?? race}${cls ? " " + cls : ""}`);
  const build = look.build || (race === "elf" ? "slender" : "");
  if (BUILD[build]) bits.push(BUILD[build]);
  const hair = HAIR[look.hairStyle ?? "short"];
  const hairColour = look.hair ? colorName(look.hair) : look.age === "old" ? "grey" : "";
  if (hair) bits.push(["bald", "hood", "helm", "hat"].includes(look.hairStyle) ? hair : `${hairColour} ${hair}`.trim());
  if (look.beard === true) bits.push("a full beard");
  if (look.beard === "stubble") bits.push("stubble");
  if (look.style === "skeleton") bits.push("an animated skeleton, bare bone");
  if (look.style === "zombie") bits.push("a rotting undead corpse");
  bits.push(`wearing ${(OUTFIT[outfitKey] ?? "{c} travelling clothes").replace("{c}", clothColor(look.top)).replace(/\s+/g, " ")}`);
  if (look.cloak) bits.push(`a ${clothColor(look.cloak)} cloak`);
  if (look.horns) bits.push("small curved horns");
  if (look.wings) bits.push(`${look.wings === "bat" ? "bat-like" : "feathered"} wings`);
  return `${bits.join(", ")}.${s.bio ? " " + s.bio : ""}`;
}

function subjects() {
  const out = [];
  const companions = readJson(path.join(campaign.dir, "companions.json"), {});
  for (const [id, c] of Object.entries(companions)) {
    if (id.startsWith("_") || typeof c !== "object") continue;
    out.push({ id, ...c });
  }
  const entities = readJson(path.join(campaign.dir, "entities.json"), {});
  const monsters = { ...baseMonsters, ...readJson(path.join(campaign.dir, "monsters.json"), {}) };
  for (const [id, e] of Object.entries(entities)) {
    if (id.startsWith("_") || typeof e !== "object" || e.companion) continue;
    const sprite = e.sprite ?? monsters[e.monster ?? id]?.sprite;
    if (!e.portrait && (sprite?.template !== "humanoid" || !e.name)) continue;
    const m = monsters[e.monster ?? ""];
    out.push({ id, name: e.name ?? m?.name ?? id, look: sprite?.look, bio: e.bio ?? m?.desc, portrait: e.portrait, role: e.kind === "monster" ? "" : "" });
  }
  for (const [id, m] of Object.entries(readJson(path.join(campaign.dir, "monsters.json"), {}))) {
    if (id.startsWith("_") || typeof m !== "object" || out.some((s) => s.id === id)) continue;
    if (m.portrait || m.sprite?.template === "humanoid") out.push({ id, name: m.name ?? id, look: m.sprite?.look, bio: m.desc, portrait: m.portrait });
  }
  return out;
}

const hasFile = (id) => EXTS.some((x) => existsSync(path.join(outDir, `${id}.${x}`)));
let list = subjects();
if (typeof flags.only === "string") list = list.filter((s) => s.id === flags.only);

if (flags.list) {
  for (const s of list) console.log(`${hasFile(s.id) ? "ok     " : "missing"} ${s.id.padEnd(16)} ${describe(s)}`);
  console.log(`\nStyle: ${STYLE}`);
  process.exit(0);
}

const fullPrompt = (s) => `${STYLE}\n\nSubject: ${describe(s)}`;

if (flags.prompts) {
  const missing = list.filter((s) => flags.force || !hasFile(s.id));
  for (const s of missing) {
    console.log(`=== ${s.id}  ->  save as ${path.relative(process.cwd(), path.join(outDir, `${s.id}.png`))}  (square, 1:1) ===`);
    console.log(fullPrompt(s) + "\n");
  }
  console.log(`${missing.length} prompt(s). Characters that already have a portrait are skipped (--force lists them too).`);
  process.exit(0);
}

const todo = list.filter((s) => flags.force || !hasFile(s.id));
if (!todo.length) {
  console.log("Nothing to paint: every character already has a portrait. (--force repaints)");
  process.exit(0);
}
console.log(`Painting ${todo.length} portraits with ${MODEL} at ${RESOLUTION}...`);
guardSpend(todo.length, 30, "images", flags);

const api = client();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = 0;
for (const s of todo) {
  try {
    const created = await api.flows.image.create({ modelId: MODEL, prompt: fullPrompt(s), aspectRatio: "1:1", resolution: RESOLUTION });
    let result = null;
    for (let i = 0; i < 90; i++) {
      await sleep(2500);
      result = await api.flows.image.get(created.id);
      if (result.status === "completed" || result.status === "failed") break;
    }
    if (!result || result.status !== "completed") {
      throw new Error(result?.status === "failed" ? `${result.failureReason}: ${result.errorMessage}` : "timed out waiting for the image");
    }
    const res = await fetch(result.contentUrl);
    if (!res.ok) throw new Error(`download failed (HTTP ${res.status})`);
    const mime = String(result.contentMimeType ?? "image/png");
    const ext = mime.includes("jpeg") ? "jpg" : mime.includes("webp") ? "webp" : "png";
    mkdirSync(outDir, { recursive: true });
    writeFileSync(path.join(outDir, `${s.id}.${ext}`), Buffer.from(await res.arrayBuffer()));
    console.log(`  ok   ${s.id}.${ext}`);
  } catch (err) {
    failed += 1;
    console.error(`  FAIL ${s.id}: ${describeError(err)}`);
    if (err?.statusCode === 402) {
      console.error("\nThe ElevenLabs API only paints images on the Pro plan and above. On a lower plan you can still\n" +
        "paint them on the ElevenLabs website: run this tool with --prompts, paint each prompt there (square, 1:1)\n" +
        `and save it as ${path.relative(process.cwd(), outDir)}/<character id>.png. The game finds the files by name.`);
    }
    if ([401, 402].includes(err?.statusCode)) break;
  }
}
console.log(`\nDone. Files are in ${path.relative(process.cwd(), outDir)}.`);
process.exit(failed ? 1 : 0);
