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
    search = {
      width = 0.4,
      max_width = 100,
      min_width = 20,
      col = -4,
      title = "Search",
      title_pos = "right",
    },
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
  eq("right", win.title_pos)
end
view.render(state(":", "Rename: "), opts)
eq("input", model.command(state(":", "Rename: ")).kind)
eq(30, vim.api.nvim_win_get_width(view.cursor.win))
view.render(state(":"), opts)
eq(80, vim.api.nvim_win_get_width(view.cursor.win))
eq(nil, vim.api.nvim_win_get_config(view.cursor.win).title)
local bottom =
  config.resolve({ window = { row = 3 }, profiles = { search = { row = false, bottom = 2 } } })
view.render(state("/"), bottom)
assert(vim.api.nvim_win_get_config(view.cursor.win).row > 3)
eq("expression", model.command(state("=")).kind)
assert(not pcall(config.resolve, { profiles = { search = { width = 0 } } }))
assert(not pcall(config.resolve, { profiles = { typo = {} } }))
assert(not pcall(config.resolve, { window = { min_width = 90 } }))
assert(not pcall(config.resolve, { window = { col = -math.huge } }))
-- Chunk colors use group IDs, never reinterpret screen attribute IDs as groups.
local rich = require("input-tools.text")
vim.api.nvim_set_hl(0, "InputToolsTestRed", { fg = "#ff1234" })
local red = vim.api.nvim_get_hl_id_by_name("InputToolsTestRed")
local chunks = { { 0, "你", red }, { 0, "好tail", red } }
local edited = rich.special(chunks, 3, { char = "^", shift = false })
local lines, marks = rich.lines(edited)
eq({ "你^tail" }, lines)
eq(3, marks[2].col)
eq(4, marks[3].col)
eq(red, marks[3].hl)
local colored = state(":")
model.event(colored, "cmdline_show", { chunks, 3, ":", "", 0, 1 }, true)
model.event(colored, "cmdline_block_show", { { { { 0, "context", red } } } }, true)
local cmd = model.command(colored)
eq(2, cmd.highlights[#cmd.highlights].row)
eq(4, cmd.highlights[#cmd.highlights].col)
view.render(colored, config.resolve())
local buf = vim.api.nvim_win_get_buf(view.cursor.win)
local extmarks = vim.api.nvim_buf_get_extmarks(
  buf,
  vim.api.nvim_create_namespace("input-tools.view"),
  0,
  -1,
  { details = true }
)
assert(#extmarks >= 3)
-- Replacing colored text with plain text must also remove old attributes.
model.event(colored, "cmdline_block_hide", {}, true)
model.event(colored, "cmdline_show", { { { 0, "plain" } }, 5, ":", "", 0, 1 }, true)
view.render(colored, config.resolve())
for _, mark in
  ipairs(
    vim.api.nvim_buf_get_extmarks(
      buf,
      vim.api.nvim_create_namespace("input-tools.view"),
      0,
      -1,
      { details = true }
    )
  )
do
  assert(mark[4].hl_group ~= "InputToolsTestRed", "old text highlights must be removed")
end
view.close()
print("highlights: multiline context, Unicode ranges and special-character edits passed")

vim.o.columns, vim.o.lines = 18, 6
view.render(state("/"), opts)
local box = vim.api.nvim_win_get_config(view.cursor.win)
assert(box.col >= 0 and box.col + box.width + 2 <= 18)
view.close()
print("features: per-kind profiles, fractional widths, titles and small-screen clamps passed")

-- Reuse the merged profile, while respecting profile/setup/per-call changes.
local layout = require("input-tools.layout")
local base = layout.style(opts, "input")
assert(base == layout.style(opts, "input"))
local custom = layout.style(opts, "input", { title = "Custom", title_pos = "left", width = 24 })
assert(custom == layout.style(opts, "input", { title = "Custom", title_pos = "left", width = 24 }))
eq("Rename", opts.profiles.input.title)
eq("Custom", custom.title)
eq(24, custom.width)
eq(30, layout.style(opts, "input").width)
opts.profiles.input.width = 20
eq(20, layout.style(opts, "input").width)
opts.window.winblend = 10
eq(10, layout.style(opts, "input").winblend)
eq(0, layout.style(config.resolve(), "input").winblend)
print("layout: cached styles, per-call isolation and configuration invalidation passed")
