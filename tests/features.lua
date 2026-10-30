vim.opt.runtimepath:prepend(vim.fn.getcwd())
local model = require("input-tools.model")
local view = require("input-tools.view")
local config = require("input-tools.config")
local function eq(a, b)
  assert(vim.deep_equal(a, b), vim.inspect({ expected = a, actual = b }))
end
local function state(firstc, prompt)
  local s = model.new()
  model.event(s, "cmdline_show", { { { 0, "hello" } }, 5, firstc, prompt or "", 0, 1 }, true)
  return s
end
local opts = config.resolve({
  window = { row = 3 },
  profiles = {
    search = { width = 0.4, max_width = 100, min_width = 20, col = -4, title = "Search" },
    input = { width = 30, title = "Rename" },
  },
})
vim.o.columns, vim.o.lines = 120, 40
view.highlights()
for _, firstc in ipairs({ "/", "?" }) do
  local s = state(firstc)
  eq("search", model.command(s).kind)
  view.render(s, opts)
  local win = vim.api.nvim_win_get_config(view.cursor.win)
  eq(48, win.width)
  eq(31, win.col)
  eq("Search", win.title[1][1])
end
view.render(state(":", "Rename: "), opts)
eq("input", model.command(state(":", "Rename: ")).kind)
eq(30, vim.api.nvim_win_get_width(view.cursor.win))
view.render(state(":"), opts)
eq(80, vim.api.nvim_win_get_width(view.cursor.win))
eq("expression", model.command(state("=")).kind)
assert(not pcall(config.resolve, { profiles = { search = { width = 0 } } }))
assert(not pcall(config.resolve, { profiles = { typo = {} } }))
assert(not pcall(config.resolve, { window = { min_width = 90 } }))
assert(not pcall(config.resolve, { window = { col = -math.huge } }))
vim.o.columns, vim.o.lines = 18, 6
view.render(state("/"), opts)
local box = vim.api.nvim_win_get_config(view.cursor.win)
assert(box.col >= 0 and box.col + box.width + 2 <= 18)
view.close()
print("features: per-kind profiles, fractional widths, titles and small-screen clamps passed")
