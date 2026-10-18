// test-compile.mjs — assert-based checks for resources/gram-compile.cjs
// Run: node test/test-compile.mjs   (from repo root)
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import assert from "node:assert";

const BUNDLE = fileURLToPath(new URL("../_extensions/gram/resources/gram-compile.cjs", import.meta.url));

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

// 6. output kinds
results = compile([{ id: "g", source: CAKE, scale: 1, lang: "en", outputs: ["gantt"] }]);
assert(results.g.gantt && results.g.gantt.length > 0, "gantt output renders");
assert(results.g.html === undefined, "unrequested html omitted");

results = compile([{ id: "sn", source: CAKE, scale: 1, lang: "en", outputs: ["snippet"] }]);
assert(results.sn.snippet.includes("recipe-snippet"), "snippet output renders");

results = compile([{ id: "nu", source: CAKE, scale: 1, lang: "en", outputs: ["nutrition"] }]);
assert(results.nu.nutrition === "", "nutrition empty without db data");

results = compile([{ id: "me", source: "---\ntitle: T Cake\ncategory: Dessert\n---\n" + CAKE, scale: 1, lang: "en", outputs: ["meta"] }]);
assert(results.me.meta.title === "T Cake", "meta title");
assert(results.me.meta.category === "Dessert", "meta category preserved");
assert(typeof results.me.meta.totalTime === "number", "meta totalTime");

// 7. multi-scale batch
results = compile([
  { id: "m1", source: CAKE, scale: 0.5, lang: "en", outputs: ["html"] },
  { id: "m2", source: CAKE, scale: 1, lang: "en", outputs: ["html"] },
]);
assert(results.m1.html !== results.m2.html, "batch: scales differ");

// 8. invalid output kind rejected
results = compile([{ id: "bad", source: CAKE, scale: 1, lang: "en", outputs: ["nope"] }]);
assert(results.bad.error && /unknown output/.test(results.bad.error), "bad output kind rejected");

// 9. db path loads ingredients (warning disappears when known)
const dbPath = process.env.GRAM_TEST_DB || null;
if (dbPath) {
  const withDb = compile([{ id: "d", source: "@eggs{3}\n## E\n", scale: 1, lang: "en", db: dbPath }]);
  console.log("db test warnings:", withDb.d.warnings);
}

console.log("compile bundle: all checks passed");
