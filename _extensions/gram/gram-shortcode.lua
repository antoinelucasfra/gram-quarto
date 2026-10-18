-- gram-shortcode.lua — {{< gram src="path" [scale=N] [lang=xx] [db=path] >}}
-- plus output variants: gram-gantt, gram-snippet, gram-nutrition, gram-meta,
-- and the full interactive recipe block: gram-interactive.
local M = dofile(debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") .. "/gram-common.lua")

local function attrStr(kwargs, key)
  local v = kwargs[key]
  if v == nil then return "" end
  return pandoc.utils.stringify(v)
end

-- shared attribute handling for the simple output shortcodes
-- kind: "html" | "gantt" | "snippet" | "nutrition"
local function renderSimple(kind, args, kwargs)
  local src = ""
  if args[1] ~= nil then src = pandoc.utils.stringify(args[1]) end
  if src == "" then src = attrStr(kwargs, "src") end
  if src == "" then
    error("[gram] usage: {{< gram-" .. kind .. " src=\"path/to/recipe.gram\" [scale=2] [lang=en] [db=path.yaml] >}}")
  end
  local path = M.resolvePath(src)
  local source = M.readFile(path)
  if source == nil then
    error("[gram] cannot read gram file: " .. path
      .. " (resolved from '" .. src .. "')")
  end
  local scale = attrStr(kwargs, "scale")
  if scale ~= "" then
    local n = tonumber(scale)
    if n == nil or n <= 0 then
      error("[gram] 'scale' must be a positive number, got: " .. scale)
    end
  end
  local db = attrStr(kwargs, "db")
  if db ~= "" then
    db = M.resolvePath(db)
    if not M.fileExists(db) then error("[gram] db file not found: " .. db) end
  else
    db = M.findDb()
  end
  local lang = attrStr(kwargs, "lang") ~= "" and attrStr(kwargs, "lang") or "en"
  local r = M.compile(source, scale ~= "" and scale or 1, lang, db, { kind })
  M.injectCss()
  local html = r[kind]
  if html == nil or html == "" then
    return pandoc.Null()
  end
  return pandoc.RawBlock("html", html)
end

return {
  ["gram"] = function(args, kwargs) return renderSimple("html", args, kwargs) end,
  ["gram-gantt"] = function(args, kwargs) return renderSimple("gantt", args, kwargs) end,
  ["gram-snippet"] = function(args, kwargs) return renderSimple("snippet", args, kwargs) end,
  ["gram-nutrition"] = function(args, kwargs) return renderSimple("nutrition", args, kwargs) end,

  -- {{< gram-meta src="..." [field=title] [scale=1] [lang=xx] [db=path] >}}
  -- emits the field value as text: title | slug | portions | category |
  -- source | image | totalTime | activeTime
  ["gram-meta"] = function(args, kwargs)
    local src = attrStr(kwargs, "src")
    if src == "" and args[1] ~= nil then src = pandoc.utils.stringify(args[1]) end
    if src == "" then
      error("[gram] usage: {{< gram-meta src=\"recipe.gram\" field=\"totalTime\" >}}")
    end
    local source = M.readFile(M.resolvePath(src))
    if source == nil then error("[gram] cannot read gram file: " .. src) end
    local db = attrStr(kwargs, "db")
    if db ~= "" then
      db = M.resolvePath(db)
      if not M.fileExists(db) then error("[gram] db file not found: " .. db) end
    else
      db = M.findDb()
    end
    local lang = attrStr(kwargs, "lang") ~= "" and attrStr(kwargs, "lang") or "en"
    local r = M.compile(source, attrStr(kwargs, "scale") ~= "" and attrStr(kwargs, "scale") or 1,
      lang, db, { "meta" })
    local meta = r.meta
    if type(meta) ~= "table" then return pandoc.Null() end
    local field = attrStr(kwargs, "field")
    if field == "" then field = "title" end
    local v = meta[field]
    if v == nil then
      error("[gram] no meta field '" .. field .. "' (have: title, slug, portions, category, source, image, totalTime, activeTime)")
    end
    return pandoc.Str(tostring(v))
  end,

  -- {{< gram-interactive src="..." [scales="0.5,1,2,3"] [lang=xx] [db=path]
  --      [snippet=true] [gantt=true] >}} — full recipe app: scale switcher,
  --   cook mode, optional quick-overview snippet and timeline.
  ["gram-interactive"] = function(args, kwargs)
    local src = attrStr(kwargs, "src")
    if src == "" and args[1] ~= nil then src = pandoc.utils.stringify(args[1]) end
    if src == "" then
      error("[gram] usage: {{< gram-interactive src=\"recipe.gram\" [scales=\"0.5,1,2,3\"] [lang=en] >}}")
    end
    local source = M.readFile(M.resolvePath(src))
    if source == nil then
      error("[gram] cannot read gram file: " .. M.resolvePath(src) .. " (resolved from '" .. src .. "')")
    end
    local lang = attrStr(kwargs, "lang") ~= "" and attrStr(kwargs, "lang") or "en"
    local scales = {}
    for s in attrStr(kwargs, "scales"):gsub("%s", ""):gmatch("[^,]+") do
      local n = tonumber(s)
      if n == nil or n <= 0 then
        error("[gram] 'scales' must be positive numbers, got: " .. s)
      end
      table.insert(scales, n)
    end
    if #scales == 0 then scales = { 0.5, 1, 2, 3 } end
    local db = attrStr(kwargs, "db")
    if db ~= "" then
      db = M.resolvePath(db)
      if not M.fileExists(db) then error("[gram] db file not found: " .. db) end
    else
      db = M.findDb()
    end
    local wantSnippet = attrStr(kwargs, "snippet") ~= "false"
    local wantGantt = attrStr(kwargs, "gantt") ~= "false"

    local outputs = { "html" }
    if wantSnippet then table.insert(outputs, "snippet") end
    if wantGantt then table.insert(outputs, "gantt") end
    local all = M.compile(source, scales, lang, db, outputs)
    M.injectCss()
    M.injectApp()

    local ui = M.uiStrings(lang)
    local parts = {}
    local function tokey(n) return tostring(n) end
    -- initial render at 1× when available, else the first listed scale
    local initial = tokey(scales[1])
    for _, s in ipairs(scales) do if tokey(s) == "1" then initial = "1" end end
    -- JSON object keys must be strings with a stable numeric feel
    local data = {}
    for _, s in ipairs(scales) do data[tokey(s)] = all[tokey(s)] end
    local jsonData = pandoc.json.encode(data):gsub("<", "\\u003c")

    table.insert(parts, [[<div class="recipe-app gram-interactive">]])
    if #scales > 1 then
      local btns = {}
      for _, s in ipairs(scales) do
        table.insert(btns, string.format(
          '<button class="scale-btn" data-scale="%s">%s×</button>',
          tokey(s), tokey(s)))
      end
      table.insert(parts, string.format(
        [[<div class="recipe-toolbar"><div class="scale-controls" role="group" aria-label="%s">%s</div><button class="cook-start">%s</button></div>]],
        ui.portions, table.concat(btns), ui.cookStart))
    else
      table.insert(parts, string.format(
        [[<div class="recipe-toolbar"><button class="cook-start">%s</button></div>]], ui.cookStart))
    end
    table.insert(parts, string.format(
      [[<details class="cook-bar"><summary>%s <span class="cook-step-label"></span></summary><button class="cook-next">%s</button><button class="cook-exit">%s</button></details>]],
      ui.cookActive, ui.cookNext, ui.cookExit))
    if wantSnippet then
      local snip = all[initial].snippet or ""
      table.insert(parts, string.format(
        [[<details class="snippet-box" open><summary>%s</summary><div class="snippet-slot">%s</div></details>]],
        ui.overview, snip))
    end
    local html = all[initial].html or ""
    table.insert(parts, string.format(
      [[<div class="recipe-render"><div class="gram-preview">%s</div></div>]], html))
    if wantGantt then
      table.insert(parts, string.format(
        [[<details class="gantt-details"><summary>%s</summary><div class="gantt-render"></div></details>]],
        ui.timeline))
    end
    table.insert(parts, string.format(
      [[<script type="application/json" class="recipe-data">%s</script>]], jsonData))
    table.insert(parts, "</div>")
    return pandoc.RawBlock("html", table.concat(parts, "\n"))
  end,
}
