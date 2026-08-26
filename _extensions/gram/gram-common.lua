-- gram-common.lua — shared helpers, loaded via dofile by shortcode & filter
-- Exposes: M.projectDir, M.resolvePath, M.readFile, M.fileExists, M.findDb,
--          M.compile(source, scale, lang, dbPath) -> html string
--          M.injectCss()

local M = {}

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

-- find nearest .gram/ingredients.yaml walking up from projectDir
function M.findDb()
  local prefix = ""
  for seg in M.projectDir():gsub("\\", "/"):gmatch("[^/]+") do
    prefix = prefix .. seg .. "/"
    local candidate = "/" .. prefix .. ".gram/ingredients.yaml"
    if M.fileExists(candidate) then return candidate end
  end
  return nil
end

local CACHE_DIR = nil
local function cacheDir()
  if CACHE_DIR == nil then CACHE_DIR = M.projectDir() .. "/.quarto-gram-cache" end
  return CACHE_DIR
end

local function ensureCacheDir()
  local ok = pcall(function() pandoc.system.make_directory(cacheDir(), true) end)
  if not ok then os.execute('mkdir -p "' .. cacheDir() .. '"') end
end

local cssDone = false
function M.injectCss()
  if cssDone then return end
  cssDone = true
  pcall(function()
    quarto.doc.add_html_dependency({
      name = "gram-css",
      version = "1.0.0",
      stylesheets = { "resources/gram.css" },
    })
  end)
end

-- compile one gram source -> {html=..., warnings={...}}
-- results cached in-memory per render and on disk keyed by content hash
local memcache = {}

function M.compile(source, scale, lang, dbPath)
  scale = tonumber(scale) or 1
  lang = lang or "en"
  if scale ~= scale or scale <= 0 or math.huge == scale then
    error("[gram] scale must be a positive number, got: " .. tostring(scale))
  end

  local key = table.concat(
    { pandoc.utils.sha1(source .. "\0" .. scale .. "\0" .. lang .. "\0" .. tostring(dbPath)) })

  if memcache[key] then return memcache[key] end

  ensureCacheDir()
  local htmlFile = cacheDir() .. "/" .. key .. ".html"
  local warnFile = cacheDir() .. "/" .. key .. ".warnings"
  local cachedHtml = M.readFile(htmlFile)
  if cachedHtml then
    local warnings = {}
    local raw = M.readFile(warnFile) or ""
    for w in raw:gmatch("[^\n]+") do table.insert(warnings, w) end
    memcache[key] = { html = cachedHtml, warnings = warnings }
    return memcache[key]
  end

  -- write batch spec to temp file (no shell-quoting hazards)
  local specPath = os.tmpname()
  local spec = pandoc.json.encode({
    jobs = { { id = "job0", source = source, scale = scale, lang = lang, db = dbPath } },
  })
  writeFile(specPath, spec)

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
  local r = decoded and decoded.results and decoded.results.job0
  if r == nil then
    error("[gram] compiler returned malformed output:\n" .. out:sub(1, 500))
  end
  if r.error ~= nil then
    error("[gram] compilation failed:\n" .. r.error)
  end
  for _, w in ipairs(r.warnings or {}) do
    quarto.log.warning("[gram] " .. w)
  end
  writeFile(htmlFile, r.html)
  writeFile(warnFile, table.concat(r.warnings or {}, "\n"))
  memcache[key] = r
  return r
end

return M
