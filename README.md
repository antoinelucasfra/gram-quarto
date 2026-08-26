# gram-quarto

A [Quarto](https://quarto.org) extension that renders [Gram](https://docs.gram-lang.org)
recipes into styled HTML at build time — no runtime JavaScript, no npm install
for users.

## Install

``` bash
quarto add tonio-lucasfra/gram-quarto   # once published to GitHub
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

## Caching

Compiled results are cached in `.quarto-gram-cache/` (project root), keyed by
content hash + scale + lang + db. Add it to `.gitignore`. Delete it if you
upgrade the extension.

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
