-- gram-filter.lua — compile fenced code blocks tagged {.gram}
--   ```{.gram}
--   ## Pancakes
--   [Fry] @flour{200g}, ~{3 min} per side.
--   ```
-- Optional attrs: .scale-2 class or scale=2 attribute; lang=xx; db=path.
local M = dofile(debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") .. "/gram-common.lua")

local function extractScale(el)
  -- scale=2 named attribute wins; .scale-N class as shorthand
  local s = el.attributes and el.attributes.scale
  if s ~= nil and s ~= "" then return s end
  for _, cls in ipairs(el.classes or {}) do
    local n = cls:match("^scale%-(%d+%.?%d*)$")
    if n then return n end
  end
  return 1
end

local function isGram(el)
  if el.classes == nil then return false end
  for _, c in ipairs(el.classes) do
    if c == "gram" then return true end
  end
  return false
end

function Pandoc(doc)
  -- CodeBlock handlers below flag the doc via M.hasGram (by then the blocks
  -- are already RawBlocks, so walking for them here finds nothing)
  if M.hasGram then M.injectCss() end
  return doc
end

function CodeBlock(el)
  if not isGram(el) then return nil end
  local lang = (el.attributes and el.attributes.lang) or "en"
  local db = el.attributes and el.attributes.db or ""
  if db ~= "" then
    db = M.resolvePath(db)
    if not M.fileExists(db) then error("[gram] db file not found: " .. db) end
  else
    db = M.findDb()
  end
  local r = M.compile(el.text, extractScale(el), lang, db)
  M.hasGram = true
  return pandoc.RawBlock("html", r.html)
end
