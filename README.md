# gram-quarto

A [Quarto](https://quarto.org) extension that renders [Gram](https://docs.gram-lang.org)
recipes into styled HTML at build time — no runtime JavaScript, no npm install
for users.

## Why an extension? Gram vs gram-quarto

The [Gram CLI](https://docs.gram-lang.org) (npm package `@gram-lang/cli`) is
the standalone compiler: `gram render recipe.gram` turns a `.gram` file into a
static HTML file you then paste somewhere. It knows nothing about Quarto,
scale switching, or websites.

This extension wraps the same compiler (`@gram-lang/parser`, `kitchen`,
`analyzer`, `renderer`) but makes it a first-class Quarto citizen. What it
adds over running the base Gram tool by hand:

- **Embed recipes where you write.** `` ```` {.gram} `````` code blocks and
  `{{< gram src=... >}}` shortcodes compile during `quarto render`, so a recipe
  is just part of a document — no intermediate HTML files to copy around.
- **Strict validation.** Gram's parser is lenient by design (garbage becomes
  text nodes). The extension adds a gate so a broken recipe fails the build
  with a clear error instead of silently rendering an empty card.
- **Multi-scale, multi-output in one shot.** Each source compiles once across
  `scales="0.5,1,2,3"` into html / gantt / snippet / nutrition / meta outputs
  in a single Node spawn, batched per recipe.
- **Interactive recipe pages.** `{{< gram-interactive >}}` bundles a
  scale-switcher and cook mode (step-through with big text) that the CLI does
  not provide, plus en/fr UI strings and CSS-variable theming
  (`--gram-accent`, `--gram-cook`).
- **Content-hash caching.** Results cache in `.quarto-gram-cache/` keyed on
  source, scales, lang, ingredient-DB *content* and outputs — unchanged
  recipes don't recompile between renders, and DB edits do invalidate.
- **Structured metadata.** `{{< gram-meta field=... >}}` and nutrition outputs
  read front-matter and analyzed nutrition so listings and cards can be built
  from the recipe source itself.

The extension exists because of a concrete project:
[cookbook-web](https://github.com/antoinelucasfra/cookbook-web), a bilingual
(EN/FR) cookbook website built with Quarto. Every recipe there is a `.gram`
source compiled by this extension into an interactive page; an ingredient
analysis database (`ingredients.yaml`) resolves quantities and nutrition;
recipes are submitted through GitHub issues and published after review. The
build emits per-recipe pages that only call `{{< gram-interactive >}}` — the
extension handles compiling, caching, and interactivity, so the site's own
build script stays metadata-only.

## Install

``` bash
quarto add antoinelucasfra/gram-quarto
# or, from a local copy:
quarto add /path/to/gram-quarto
```

**Required one-line setup** in `_quarto.yml` — Quarto requires filters to be
explicitly listed (shortcodes load automatically, filters don't):

``` yaml
filters:
  - gram
```

Without this line, `{{< gram >}}` shortcodes work but ```` ```{.gram} ````
code blocks render as plain code.

Requirements: Node ≥ 18 on PATH (used at build time only).

## Usage

**Embed a `.gram` file:**

    {{< gram src="recipes/pancakes.gram" >}}

Options: `scale="2"` (scale all quantities), `lang="fr"` (labels), `db="path/to/ingredients.yaml"`.

**Write a recipe inline in any document:**

    ```{.gram}
    ## Pancakes
    [Fry] @flour{200g} in @butter{30g}, ~{3 min} per side.
    ```

Same attributes work on the block: ```` ```{.gram scale=2} ````.

**Output variants** (same options):

- `{{< gram-gantt src="..." >}}` — parallel-timeline Gantt chart
- `{{< gram-snippet src="..." >}}` — table-style quick overview (action columns + ingredient rows)
- `{{< gram-nutrition src="..." >}}` — nutrition table (empty without ingredient data)
- `{{< gram-meta src="..." field="totalTime" >}}` — one metadata value as text:
  `title`, `slug`, `portions`, `category`, `source`, `image`, `totalTime`, `activeTime`

**Full interactive recipe** (scale switcher + cook mode + snippet + timeline, one
small bundled script, no dependencies):

    {{< gram-interactive src="recipes/pancakes.gram" scales="0.5,1,2,3" >}}

Attributes: `scales="1,2"` (list of scales to precompile; default `0.5,1,2,3`),
`snippet="false"` / `gantt="false"` to drop sections, plus `src`, `lang`, `db`.

**Validation is automatic**: every referenced or embedded Gram source is
compiled on each render. Broken recipes fail the build. The bundled compiler
also runs strict sanity checks the lenient gram parser skips — control
characters, unbalanced braces, sources with no ingredients or sections, and
unparseable `@ref`s all become build errors instead of silently rendering an
empty card. Unknown ingredients produce warnings.

## Ingredient database

The extension looks for the nearest `.gram/ingredients.yaml` walking up from
the project directory and passes it to the analyzer (nutrition, mass metrics).
No DB found → compiles without nutrition data. Override per-recipe with
`db="..."`.

## Theming

`gram-app.css` (interactive blocks) is driven by CSS custom properties — set
`--gram-accent`, `--gram-accent-soft`, `--gram-cook`, `--gram-cook-soft` on
`:root` or a wrapper to match your site. `gram.css` (recipe body) can be
overridden per class as usual.

## Caching

Compiled results are cached in `.quarto-gram-cache/` (project root), keyed by
content hash + scales + lang + db + outputs. Add it to `.gitignore`. Delete it
if you upgrade the extension.

## How it works

`{{< gram >}}` shortcodes and `{.gram}` code blocks are collected during
render, batched through a self-contained Node bundle
(`resources/gram-compile.cjs`, ~1 MB, bundles `@gram-lang/parser`, `kitchen`,
`analyzer`, `renderer` + YAML parser), cached, and emitted as static HTML.
Renderer CSS (`resources/gram.css`) is injected automatically only on pages
that contain recipes.

## Development

``` bash
npm install            # @gram-lang/* dev deps
npm run build          # esbuild src/compile.mjs -> resources/gram-compile.cjs
node test/test-compile.mjs   # unit checks
cd docs && quarto render     # e2e demo site
```

License GPL-3 (matches `@gram-lang/*`).
