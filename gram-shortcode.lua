-- gram-shortcode.lua — {{< gram src="path" [scale=N] [lang=xx] [db=path] >}}
local M = dofile(debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") .. "/gram-common.lua")

local function attrStr(kwargs, key)
  local v = kwargs[key]
  if v == nil then return "" end
  return pandoc.utils.stringify(v)
end

return {
  ["gram"] = function(args, kwargs)
    local src = ""
    if args[1] ~= nil then src = pandoc.utils.stringify(args[1]) end
    if src == "" then src = attrStr(kwargs, "src") end
    if src == "" then
      error("[gram] usage: {{< gram src=\"path/to/recipe.gram\" [scale=2] [lang=en] [db=path.yaml] >}}")
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
    local r = M.compile(source, scale ~= "" and scale or 1,
      attrStr(kwargs, "lang") ~= "" and attrStr(kwargs, "lang") or "en", db)
    M.injectCss()
    return pandoc.RawBlock("html", r.html)
  end,
}
