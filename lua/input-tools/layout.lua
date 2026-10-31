-- Shared sizing/placement for native command lines and editable buffer inputs.
local M = {}
local styles = setmetatable({}, { __mode = "k" })

-- Treat returned styles as immutable. Observe configuration mutations as well as
-- setup() replacement, but merge/copy only when the effective profile changes.
function M.style(config, kind, opts)
  local cache = styles[config]
  if not cache then
    cache = {}
    styles[config] = cache
  end
  local profile = config.profiles[kind] or {}
  local item = cache[kind]
  if
    not item
    or not vim.deep_equal(item.base, config.window)
    or not vim.deep_equal(item.profile, profile)
  then
    item = { base = vim.deepcopy(config.window), profile = vim.deepcopy(profile) }
    item.window = require("input-tools.config").window(config, kind)
    cache[kind] = item
  end
  opts = opts or {}
  if
    not item.style
    or item.title ~= opts.title
    or item.title_pos ~= opts.title_pos
    or item.width ~= opts.width
  then
    item.style = vim.tbl_extend("force", {}, item.window)
    for _, key in ipairs({ "title", "title_pos", "width" }) do
      if opts[key] ~= nil then
        item.style[key] = opts[key]
      end
    end
    item.title, item.title_pos, item.width = opts.title, opts.title_pos, opts.width
  end
  return item.style
end

function M.screen()
  return math.max(1, vim.o.columns), math.max(1, vim.o.lines - vim.o.cmdheight)
end

function M.box(row, col, width, height, border, zindex, focusable)
  return {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    focusable = focusable == true,
    border = border,
    zindex = zindex,
    noautocmd = true,
  }
end

-- count may depend on the available width (wrapped, read-only prompts).
function M.input(w, count, source, focusable)
  local edge = (w.border == "none" or w.border == "") and 0 or 2
  local columns, rows = M.screen()
  local width = w.width or w.max_width
  if width <= 1 then
    width = math.floor(columns * width)
  end
  width = math.max(1, math.min(math.max(w.min_width, width), w.max_width, columns - edge - 2))
  count = type(count) == "function" and count(width) or count
  local height = math.max(1, math.min(count, w.max_height, rows - edge - w.bottom))
  local row = math.max(0, rows - height - edge - w.bottom)
  if w.row == "center" then
    row = math.max(0, math.floor((rows - height - edge) / 2))
  elseif w.row ~= nil and w.row ~= false then
    row = math.max(0, math.min(w.row, rows - height - edge))
  end
  local col =
    math.max(0, math.min(columns - width - edge, math.floor((columns - width - edge) / 2) + w.col))
  local point
  if source then
    local r, c, origin =
      require("input-tools.position").place(source, width + edge, height + edge, columns, rows)
    point = origin
    if r then
      row, col = r, c
    end
  end
  local box = M.box(row, col, width, height, w.border, w.zindex, focusable)
  if edge > 0 and w.title ~= false and w.title ~= "" then
    box.title, box.title_pos = w.title, w.title_pos
  end
  return box, edge, point
end

return M
