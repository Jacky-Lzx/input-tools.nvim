vim.opt.runtimepath:prepend(vim.fn.getcwd())
local events = require("input-tools.events")
local seen = {}
local group = vim.api.nvim_create_augroup("InputToolsEventsTest", { clear = true })
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = { "InputToolsOpen", "InputToolsLayoutChanged", "InputToolsClose" },
  callback = function(e)
    seen[#seen + 1] = { e.match, vim.deepcopy(e.data.layout) }
    e.data.layout.col = -999 -- External mutation must not affect renderer state.
  end,
})
local function flush()
  vim.wait(15)
end
local function set(win, col)
  events.set(win and { win = win, col = col } or nil)
end
set(1, 2)
set(1, 4)
flush()
assert(#seen == 1 and seen[1][1] == "InputToolsOpen" and seen[1][2].col == 4)
assert(events.get().col == 4)
local copy = events.get()
copy.col = 77
assert(events.get().col == 4)
set(1, 4)
flush()
assert(#seen == 1, "identical layout emitted an event")
set(1, 5)
set(1, 6)
flush()
assert(#seen == 2 and seen[2][1] == "InputToolsLayoutChanged" and seen[2][2].col == 6)
set(nil)
assert(events.get() == nil)
flush()
assert(#seen == 3 and seen[3][1] == "InputToolsClose" and seen[3][2].col == 6)
set(2, 0)
set(nil)
flush()
assert(#seen == 3, "transient open/close should coalesce")
set(2, 0)
flush()
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = "InputToolsClose",
  once = true,
  callback = function()
    events.set(nil)
  end,
})
set(3, 0)
flush()
assert(seen[#seen][1] == "InputToolsClose" and seen[#seen][2].win == 2)
assert(events.get() == nil, "close callback's state change was lost")
for _, e in ipairs(seen) do
  assert(e[2].win ~= 3, "a stale replacement window was announced")
end
vim.api.nvim_del_augroup_by_id(group)
print("events: coalescing, immutable snapshots, close and reentrant replacement passed")
