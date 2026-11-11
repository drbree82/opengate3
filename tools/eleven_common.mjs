// Shared helpers for the ElevenLabs generator tools (gen_voices.mjs, gen_music.mjs, gen_sfx.mjs).
//
// The API key is NEVER written in code. It lives in .env.local (created by
// `npx -y @elevenlabs/cli@latest onboard init`) and is loaded by running the tools through npm:
//     npm run voices -- <campaign>        (= node --env-file=.env.local tools/gen_voices.mjs <campaign>)
// The SDK then reads ELEVENLABS_API_KEY from the environment.
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
import { createWriteStream, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Project root (the folder with project.godot). */
export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export function client() {
  if (!process.env.ELEVENLABS_API_KEY) {
    console.error("ELEVENLABS_API_KEY is not set.\n" +
      "Run the tool through npm so .env.local is loaded (e.g. `npm run voices -- hollowmere --list`),\n" +
      "or create the key with: npx -y @elevenlabs/cli@latest onboard init");
    process.exit(2);
  }
  return new ElevenLabsClient(); // reads ELEVENLABS_API_KEY
}

/** Writes an SDK audio response (a web ReadableStream) to a file. */
export async function saveAudio(stream, file) {
  mkdirSync(path.dirname(file), { recursive: true });
  await pipeline(Readable.fromWeb(stream), createWriteStream(file));
}

export function readJson(file, fallback = null) {
  if (!existsSync(file)) return fallback;
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch (err) {
    console.error(`Invalid JSON in ${path.relative(ROOT, file)}: ${err.message}`);
    process.exit(1);
  }
}

export function writeJson(file, data) {
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
}

/** `--flag`, `--key=value` and plain words:  { args: ["hollowmere"], flags: { list: true, only: "reeve" } } */
export function parseArgs(argv = process.argv.slice(2)) {
  const args = [];
  const flags = {};
  for (const a of argv) {
    if (a.startsWith("--")) {
      const [k, ...rest] = a.slice(2).split("=");
      flags[k] = rest.length ? rest.join("=") : true;
    } else {
      args.push(a);
    }
  }
  return { args, flags };
}

/** Loads campaigns/<id>/campaign.json. Exits with a list of campaigns when the id is missing/unknown. */
export function loadCampaign(id) {
  const base = path.join(ROOT, "campaigns");
  const dir = path.join(base, id || "");
  const file = path.join(dir, "campaign.json");
  if (!id || !existsSync(file)) {
    const known = existsSync(base) ? readdirSync(base).filter((d) => existsSync(path.join(base, d, "campaign.json"))) : [];
    console.error(`${id ? `Unknown campaign "${id}".` : "Which campaign?"} Available: ${known.join(", ") || "(none)"}`);
    process.exit(2);
  }
  return { id, dir, file, info: readJson(file, {}) };
}

/** JSON files of a campaign sub-folder, sorted by name: [{ id, data }] */
export function loadFolder(dir, sub) {
  const folder = path.join(dir, sub);
  if (!existsSync(folder)) return [];
  return readdirSync(folder).filter((f) => f.endsWith(".json")).sort()
    .map((f) => ({ id: f.slice(0, -5), data: readJson(path.join(folder, f), {}) }));
}

/** Turns an SDK error into one readable line with a hint. */
export function describeError(err) {
  const status = err?.statusCode ?? err?.status;
  const detail = err?.body?.detail?.message ?? err?.body?.detail?.status ?? err?.message ?? String(err);
  const hints = {
    401: "the API key was rejected - run `npx -y @elevenlabs/cli@latest onboard init` again",
    402: "this needs a paid plan (Voice Library voices and some models are not on the free plan)",
    422: "a parameter was rejected (check the voice id, model id, duration)",
    429: "rate limit or quota reached - wait a little, or check your ElevenLabs usage",
  };
  return `${status ? `HTTP ${status}: ` : ""}${detail}${hints[status] ? ` (${hints[status]})` : ""}`;
}

/** Refuses to spend more than `limit` units unless --yes was passed. */
export function guardSpend(total, limit, unit, flags) {
  if (total > limit && !flags.yes) {
    console.error(`This run would generate ${total} ${unit} (safety limit ${limit}). Add --yes to go ahead.`);
    process.exit(3);
  }
}

export { existsSync, path };
