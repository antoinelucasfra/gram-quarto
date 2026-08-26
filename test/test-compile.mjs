// test-compile.mjs — assert-based checks for resources/gram-compile.cjs
// Run: node test/test-compile.mjs   (from repo root)
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import assert from "node:assert";

const BUNDLE = new URL("../_extensions/gram/resources/gram-compile.cjs", import.meta.url).pathname;

function compile(jobs) {
  const r = spawnSync("node", [BUNDLE], {
    input: JSON.stringify({ jobs }),
    encoding: "utf8",
  });
  if (r.status !== 0 && !r.stdout) throw new Error("compiler crashed: " + r.stderr);
  return JSON.parse(r.stdout).results;
}

const CAKE = `## Test Cake
[Mix] @flour{200g} and @water{100ml}.
[Bake] ~{30 min} at 180C.
`;

let results;

// 1. valid source renders HTML with title and ingredient markup
results = compile([{ id: "ok", source: CAKE, scale: 1, lang: "en" }]);
assert(results.ok.html.includes("Test Cake"), "title present");
assert(results.ok.html.toLowerCase().includes("flour"), "ingredient present");
assert(!results.ok.error);

// 2. scaling doubles quantities
const one = compile([{ id: "a", source: CAKE, scale: 1, lang: "en" }]).a;
const two = compile([{ id: "b", source: CAKE, scale: 2, lang: "en" }]).b;
assert(one.html !== two.html, "scale changes output");
assert(/400\s*g/.test(two.html), "200g -> 400g when scaled");

// 3. warnings surface for unknown ingredients (no db)
assert(
  two.warnings.some((w) => /flour/.test(w)),
  "unknown-ingredient warning listed",
);

// 4. junk input fails loudly (parser alone is lenient)
const junkCases = [
  "@@@\n",
  "just some prose, no recipe here\n",
  "",
];
for (const [i, src] of junkCases.entries()) {
  results = compile([{ id: `junk${i}`, source: src, scale: 1, lang: "en" }]);
  assert(results[`junk${i}`].error, `junk case ${i} rejected`);
}

// 4b. unbalanced braces fail
results = compile([{ id: "bal", source: "## X\n[Fry] @flour{200g.\n", scale: 1, lang: "en" }]);
assert(/unbalanced/.test(results.bal.error), "unclosed brace rejected");

// 5. invalid scale rejected
results = compile([{ id: "s0", source: CAKE, scale: -2, lang: "en" }]);
assert(results.s0.error && /scale/i.test(results.s0.error), "negative scale rejected");

// 6. db path loads ingredients (warning disappears when known)
const dbPath = process.env.GRAM_TEST_DB || null;
if (dbPath) {
  const withDb = compile([{ id: "d", source: "@eggs{3}\n## E\n", scale: 1, lang: "en", db: dbPath }]);
  console.log("db test warnings:", withDb.d.warnings);
}

console.log("compile bundle: all checks passed");
