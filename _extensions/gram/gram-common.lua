-- gram-common.lua — shared helpers, loaded via dofile by shortcode & filter
-- Exposes: M.projectDir, M.resolvePath, M.readFile, M.fileExists, M.findDb,
--          M.compile(source, scale, lang, dbPath) -> html string
--          M.injectCss()

local M = {}
M.hasGram = false -- set true by shortcode/filter when a doc contains gram content

-- bump when compiled-output format changes so disk caches invalidate cleanly
local CACHE_VERSION = "2"

local HERE = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or "."

function M.projectDir()
  if quarto.project ~= nil and quarto.project.directory ~= nil then
    return quarto.project.directory
  end
  return "."
end



function M.fileExists(p)
  local f = io.open(p, "r")
  if not f then return false end
  f:close()
  return true
end

function M.readFile(p)
  local f = io.open(p, "r")
  if not f then return nil end
  local c = f:read("*a")
  f:close()
  return c
end

local function writeFile(p, content)
  local f = io.open(p, "w")
  if not f then error("[gram] cannot write file: " .. p) end
  f:write(content)
  f:close()
end

M.writeFile = writeFile

function M.resolvePath(p)
  p = p:gsub("\\", "/")
  if p:match("^/") or p:match("^%a:") then return p end
  return M.projectDir() .. "/" .. p
end

-- find nearest .gram/ingredients.yaml walking up from the extension dir
-- (independent of CWD / quarto.project quirks; the extension lives inside
-- the Quarto project so its ancestors include the project root)
function M.findDb()
  local segs = {}
  for seg in HERE:gsub("\\", "/"):gmatch("[^/]+") do table.insert(segs, seg) end
  for i = #segs, 1, -1 do
    local candidate = table.concat(segs, "/", 1, i) .. "/.gram/ingredients.yaml"
    if M.fileExists(candidate) then return candidate end
    if not candidate:match("^%a:") then
      local abs = "/" .. candidate
      if M.fileExists(abs) then return abs end
    end
  end
  return nil
end

local CACHE_DIR = nil
local function cacheDir()
  if CACHE_DIR == nil then CACHE_DIR = M.projectDir() .. "/.quarto-gram-cache" end
  return CACHE_DIR
end

local function ensureCacheDir()
  -- pandoc.system.make_directory is sandbox-safe; avoid os.execute/os.tmpname
  -- (os.tmpname crashes pandoc >= 3.6/Quarto 1.9 on Windows)
  pandoc.system.make_directory(cacheDir(), true)
end

local cssDone = false
function M.injectCss()
  if cssDone then return end
  cssDone = true
  pcall(function()
    quarto.doc.add_html_dependency({
      name = "gram-css",
      version = "1.1.0",
      stylesheets = { "resources/gram.css" },
    })
  end)
end

local appDone = false
function M.injectApp()
  if appDone then return end
  appDone = true
  pcall(function()
    quarto.doc.add_html_dependency({
      name = "gram-app",
      version = "1.1.0",
      stylesheets = { "resources/gram-app.css" },
      scripts = { "resources/gram-app.js" },
    })
  end)
end

local UI_STRINGS = {
  en = {
    portions = "Portions",
    cookStart = "▶ Cook mode",
    cookActive = "Cook mode active —",
    cookNext = "Next step →",
    cookExit = "Exit",
    overview = "⚡ Quick overview",
    timeline = "⏱ Timeline",
  },
  fr = {
    portions = "Portions",
    cookStart = "▶ Mode cuisine",
    cookActive = "Mode cuisine actif —",
    cookNext = "Étape suivante →",
    cookExit = "Quitter",
    overview = "⚡ Aperçu rapide",
    timeline = "⏱ Chronologie",
  },
}

function M.uiStrings(lang)
  return UI_STRINGS[lang] or UI_STRINGS.en
end

-- compile gram source(s) -> {html=..., gantt=..., ..., warnings={...}}
-- outputs: array of kinds (default {"html"}); scales: array of numbers (default {1})
-- results cached in-memory per render and on disk keyed by content hash
local memcache = {}

local function normalizeOutputs(outputs)
  local list = {}
  local seen = {}
  for _, o in ipairs(outputs or { "html" }) do
    if o == true then o = "html" end
    if not seen[o] then table.insert(list, o); seen[o] = true end
  end
  if #list == 0 then list = { "html" } end
  return list
end

local function compileSpec(source, scales, lang, dbPath, outputs)
  local jobs = {}
  for i, s in ipairs(scales) do
    table.insert(jobs, {
      id = "s" .. i,
      source = source,
      scale = tonumber(s) or 1,
      lang = lang,
      db = dbPath,
      outputs = outputs,
    })
  end
  return pandoc.json.encode({ jobs = jobs })
end

-- run one node batch for a (source,lang,db,outputs) key over scales
local function runBatch(source, scales, lang, dbPath, outputs, key)
  ensureCacheDir()
  -- keep the batch spec inside the cache dir, named per cache key: a fixed
  -- name would let concurrent renders overwrite each other's spec
  local specPath = cacheDir() .. "/" .. key .. ".spec.json"
  writeFile(specPath, compileSpec(source, scales, lang, dbPath, outputs))
  local bundle = HERE .. "/resources/gram-compile.cjs"
  if not M.fileExists(bundle) then
    error("[gram] bundled compiler missing: " .. bundle)
  end
  local pipe = io.popen('node "' .. bundle .. '" < "' .. specPath .. '"', "r")
  if not pipe then
    os.remove(specPath)
    error("[gram] failed to launch node — the Gram extension requires Node >= 18 on PATH")
  end
  local out = pipe:read("*a")
  local closeOk, _, closeCode = pipe:close()
  os.remove(specPath)
  if out == nil or out == "" then
    error("[gram] compiler produced no output (exit "
      .. tostring(closeCode) .. "). Is Node >= 18 installed?")
  end
  local decoded = pandoc.json.decode(out)
  local results = decoded and decoded.results
  if results == nil then
    error("[gram] compiler returned malformed output:\n" .. out:sub(1, 500))
  end
  return results
end

-- M.compile(source, scale|scales, lang, dbPath, outputs) -> table of results:
--   single scale: { html=..., gantt=..., warnings={...} }
--   multi scale:  { ["0.5"]={...}, ["1"]={...}, ... } (string keys)
function M.compile(source, scale, lang, dbPath, outputs)
  lang = lang or "en"
  local scales
  if type(scale) == "table" then scales = scale else scales = { scale or 1 } end
  for _, s in ipairs(scales) do
    local n = tonumber(s)
    if n == nil or n ~= n or n <= 0 or n == math.huge then
      error("[gram] scale must be a positive number, got: " .. tostring(s))
    end
  end
  outputs = normalizeOutputs(outputs)
  local single = #scales == 1
  table.sort(scales)

  -- hash the ingredient DB content so edits invalidate the cache (empty
  -- string when there is no db); bump CACHE_VERSION when output format changes
  local dbHash = ""
  if dbPath ~= nil and M.fileExists(dbPath) then
    dbHash = pandoc.utils.sha1(M.readFile(dbPath)):sub(1, 12)
  end
  local key = pandoc.utils.sha1(CACHE_VERSION .. "\0" .. source .. "\0"
    .. table.concat(scales, ",") .. "\0" .. lang .. "\0" .. tostring(dbPath)
    .. "\0" .. dbHash .. "\0" .. table.concat(outputs, ","))
  if memcache[key] then return memcache[key] end

  ensureCacheDir()
  local cacheFile = cacheDir() .. "/" .. key .. ".json"
  local warnFile = cacheDir() .. "/" .. key .. ".warnings"
  local cached = M.readFile(cacheFile)
  if cached then
    local warnings = {}
    local raw = M.readFile(warnFile) or ""
    for w in raw:gmatch("[^\n]+") do table.insert(warnings, w) end
    memcache[key] = pandoc.json.decode(cached)
    if single then memcache[key].warnings = warnings
    else for _, r in pairs(memcache[key]) do r.warnings = warnings end end
    return memcache[key]
  end

  local results = runBatch(source, scales, lang, dbPath, outputs, key)
  local merged, warnings = {}, {}
  for i, s in ipairs(scales) do
    local r = results["s" .. i]
    if r == nil then
      error("[gram] compiler returned malformed output (missing result s" .. i .. ")")
    end
    if r.error ~= nil then
      error("[gram] compilation failed:\n" .. r.error)
    end
    for _, w in ipairs(r.warnings or {}) do
      quarto.log.warning("[gram] " .. w)
      table.insert(warnings, w)
    end
    r.warnings = nil
    merged[tostring(scales[i])] = r
  end
  writeFile(warnFile, table.concat(warnings, "\n"))
  local payload = single and merged[tostring(scales[1])] or merged
  writeFile(cacheFile, pandoc.json.encode(payload))
  if single then payload.warnings = warnings end
  memcache[key] = payload
  return payload
end

return M
