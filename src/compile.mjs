// gram-quarto compile entry — bundled by esbuild into dist/gram-compile.cjs
// Reads a batch job spec on stdin, writes results JSON on stdout.
//
// stdin:  { "jobs": [ { "id": "job0", "source": "...gram text...",
//                        "scale": 2, "lang": "en", "db": "/abs/path.yaml",
//                        "outputs": ["html"] }, ... ] }
// stdout: { "results": { "job0": { "html": "...", "warnings": ["..."] }
//                       | { "error": "..." } , ... } }
// Output kinds: html | gantt | snippet | nutrition | meta. Result has one
// field per requested kind (+ warnings).

import { readFileSync } from "node:fs";
import { getAST } from "@gram-lang/parser";
import { compile } from "@gram-lang/kitchen";
import { analyze } from "@gram-lang/analyzer";
import { toHTML, toGanttHTML } from "@gram-lang/renderer";
import { toSnippetHTML } from "./snippet.mjs";
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

const VALID_OUTPUTS = new Set(["html", "gantt", "snippet", "nutrition", "meta"]);

function nutritionHTML(r) {
  const n = r.metrics?.nutrition;
  if (!n || !n.total || !n.total.calories) return "";
  const row = (label, v, unit) =>
    `<tr><th>${esc(label)}</th><td>${v == null ? "—" : Math.round(v * 10) / 10 + (unit ? " " + unit : "")}</td></tr>`;
  const t = n.total;
  let html =
    `<table class="gram-nutrition"><thead><tr><th colspan="2">Nutrition</th></tr></thead><tbody>` +
    row("Calories", t.calories, "kcal") +
    row("Protein", t.protein, "g") +
    row("Carbs", t.carbs, "g") +
    row("Fat", t.fat, "g");
  if (n.per100g?.calories != null)
    html += row("Per 100 g", n.per100g.calories, "kcal");
  html += `</tbody></table>`;
  if (n.coverage != null && n.coverage < 1)
    html += `<p class="gram-nutrition-coverage">Estimate covers ${Math.round(n.coverage * 100)}% of ingredients.</p>`;
  return html;
}

const esc = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function metaJSON(r) {
  const m = r.meta ?? {};
  return {
    title: r.title,
    slug: r.slug,
    portions: m.portions ?? null,
    category: m.category ?? null,
    source: m.source ?? null,
    image: m.image ?? null,
    totalTime: r.metrics?.totalTime ?? null,
    activeTime: r.metrics?.activeTime ?? null,
  };
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
  // analyze always runs: it enriches nutrition/mass even on an empty DB
  const analyzed = analyze(compiled, loadDb(job.db), {
    lang: job.lang || "en",
  });
  if (analyzed && analyzed.result) recipe = analyzed.result;
  const cleanRender = { ...recipe, meta: { title: recipe.title, portions: recipe.meta?.portions } };
  const lang = job.lang || "en";
  let outputs = job.outputs;
  if (!Array.isArray(outputs) || outputs.length === 0) outputs = ["html"];
  for (const o of outputs)
    if (!VALID_OUTPUTS.has(o)) throw new Error(`unknown output kind "${o}"`);
  const warnings = Array.isArray(recipe.warnings)
    ? recipe.warnings.map((w) =>
        typeof w === "string" ? w : w.message ?? JSON.stringify(w),
      )
    : [];
  const out = {};
  for (const o of outputs) {
    if (o === "html") out.html = toHTML(cleanRender, { lang });
    else if (o === "gantt") out.gantt = toGanttHTML(cleanRender, { lang });
    else if (o === "snippet") out.snippet = toSnippetHTML(cleanRender);
    else if (o === "nutrition") out.nutrition = nutritionHTML(recipe);
    else if (o === "meta") out.meta = metaJSON(recipe);
  }
  return { ...out, warnings };
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
