// gram-quarto compile entry — bundled by esbuild into dist/gram-compile.cjs
// Reads a batch job spec on stdin, writes results JSON on stdout.
//
// stdin:  { "jobs": [ { "id": "job0", "source": "...gram text...",
//                        "scale": 2, "lang": "en", "db": "/abs/path.yaml" }, ... ] }
// stdout: { "results": { "job0": { "html": "...", "warnings": ["..."] }
//                       | { "error": "..." } , ... } }

import { readFileSync } from "node:fs";
import { getAST } from "@gram-lang/parser";
import { compile } from "@gram-lang/kitchen";
import { analyze } from "@gram-lang/analyzer";
import { toHTML } from "@gram-lang/renderer";
import { parse as parseYaml } from "yaml";

const dbCache = new Map();

function loadDb(path) {
  if (!path) return {};
  if (dbCache.has(path)) return dbCache.get(path);
  const raw = parseYaml(readFileSync(path, "utf8"));
  const db = raw?.ingredients ?? raw ?? {};
  dbCache.set(path, db);
  return db;
}

function renderJob(job) {
  if (typeof job.scale !== "number" || !isFinite(job.scale) || job.scale <= 0)
    throw new Error(`invalid scale ${JSON.stringify(job.scale)} (must be > 0)`);
  const ast = getAST(job.source);
  const compiled = compile(ast, {
    scaleFactor: job.scale === 1 ? undefined : job.scale,
  });
  let recipe = compiled;
  if (Object.keys(loadDb(job.db)).length > 0 || true) {
    // analyze always runs: it enriches nutrition/mass even on an empty DB
    const analyzed = analyze(compiled, loadDb(job.db), {
      lang: job.lang || "en",
    });
    if (analyzed && analyzed.result) recipe = analyzed.result;
  }
  const clean = { ...recipe, meta: { title: recipe.title, portions: recipe.meta?.portions } };
  const html = toHTML(clean, { lang: job.lang || "en" });
  const warnings = Array.isArray(recipe.warnings)
    ? recipe.warnings.map((w) =>
        typeof w === "string" ? w : w.message ?? JSON.stringify(w),
      )
    : [];
  return { html, warnings };
}

function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf8"));
  } catch (e) {
    console.error("gram-compile: cannot read stdin JSON: " + e.message);
    process.exit(2);
  }
  const jobs = Array.isArray(input?.jobs) ? input.jobs : [];
  const results = {};
  for (const job of jobs) {
    try {
      results[job.id] = renderJob(job);
    } catch (e) {
      results[job.id] = { error: e.message };
    }
  }
  process.stdout.write(JSON.stringify({ results }));
}

main();
