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

// The gram parser is lenient by design (garbage parses into text nodes), so
// the extension adds its own strict gate: silent-junk input must fail the
// build instead of rendering as an empty/broken card.
function validateSource(src) {
  if (/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(src))
    throw new Error("source contains control characters — not gram text?");
  const open = (src.match(/[{[]/g) || []).length;
  const close = (src.match(/[}\]]/g) || []).length;
  if (open !== close)
    throw new Error(
      `unbalanced braces/brackets (${open} open vs ${close} close) — unclosed @ref{qty} or [Step]`,
    );
}

function validateAst(ast) {
  const errs = [];
  let ingredients = 0;
  let sections = 0;
  const walk = (n) => {
    if (!n || typeof n !== "object") return;
    if (n.type === "Section" && n.title) sections++;
    if (n.type === "Ingredient") {
      ingredients++;
      if (!/^[^@{}\[\]]+$/.test(String(n.name ?? "")))
        errs.push(`unparseable ingredient reference "${n.name}"`);
    }
    for (const c of n.children ?? []) walk(c);
  };
  walk(ast);
  if (ingredients === 0 && sections === 0)
    errs.push("no ingredients (@name{qty}) and no ## sections found");
  return errs;
}

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
  validateSource(job.source);
  const ast = getAST(job.source);
  const astErrs = validateAst(ast);
  if (astErrs.length > 0) throw new Error(`not a valid Gram recipe: ${astErrs[0]}`);
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
