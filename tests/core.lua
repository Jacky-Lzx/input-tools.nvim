vim.opt.runtimepath:prepend(vim.fn.getcwd())
local model = require("input-tools.model")
local tools = require("input-tools")
local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end
local s = model.new()
local function event(name, ...)
  return model.event(s, name, { ... }, true)
end
assert(not event("msg_show", "emsg", { { 0, "belongs to notifications" } }))
assert(not event("msg_history_show", {}))
local mode = vim.fn.mode
vim.fn.mode = function()
  return "rm"
end
assert(event("msg_show", "", { { 0, "legacy choice" } }))
eq("legacy choice ", model.command(s).lines[1])
vim.fn.mode = mode
s = model.new()
event("cmdline_show", { { 0, "echo '你好🙂'" } }, 6, ":", "", 0, 1)
local command = model.command(s)
eq(":echo '你好🙂' ", command.lines[1])
eq(7, command.col)
local handled, changed = event("cmdline_show", { { 0, "echo '你好🙂'" } }, 6, ":", "", 0, 1)
assert(handled and not changed, "repeated redraw events must not schedule an endless render loop")
event("cmdline_show", { { 0, "2+3" } }, 3, "=", "", 0, 2)
eq("=2+3 ", model.command(s).lines[1])
event("cmdline_hide", 2)
eq(":echo '你好🙂' ", model.command(s).lines[1])
event("cmdline_pos", 0, 1)
event("cmdline_special_char", "^", true, 1)
eq(":^echo '你好🙂' ", model.command(s).lines[1])
event("cmdline_show", { { 0, "你好" } }, 0, ":", "", 0, 1)
event("cmdline_special_char", "?", false, 1)
eq(":?好 ", model.command(s).lines[1])
event("cmdline_block_show", { { { 0, "function Foo()" } } })
event("cmdline_block_append", { { 0, "  return 1" } })
eq(3, #model.command(s).lines)
event("cmdline_block_hide")
event("cmdline_hide", 1)
eq(nil, model.command(s))
event("msg_show", "confirm", { { 0, "Choose?" } })
eq("Choose? ", model.command(s).lines[1])
event("msg_show", "confirm", { { 0, " yes/no" } }, false, false, true)
eq("Choose? yes/no ", model.command(s).lines[1])
event("msg_showmode", { { 0, "-- INSERT --" } })
event("msg_showcmd", { { 0, "2d" } })
eq("-- INSERT --  2d", model.status(s))

-- Real float geometry, Unicode cursor columns and a scrolling completion list.
local view = require("input-tools.view")
local original_position = { 42, 9 }
vim.g.ui_cmdline_pos = original_position
local config = require("input-tools.config").resolve()
view.highlights()
s = model.new()
model.event(s, "cmdline_show", { { { 0, string.rep("你", 90) } }, 270, ":", "", 0, 1 }, true)
view.render(s, config)
eq(271, vim.api.nvim_win_get_cursor(view.cursor.win)[2])
assert(not vim.deep_equal(original_position, vim.g.ui_cmdline_pos))
local focus = vim.api.nvim_get_current_win()
eq(1, #vim.tbl_filter(function(win)
  return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "input-tools-command"
end, vim.api.nvim_list_wins()))
model.event(
  s,
  "popupmenu_show",
  { { { "One", "", "", "" }, { "Two", "", "", "" } }, 1, 0, 0, -1 },
  true
)
view.render(s, config)
eq(focus, vim.api.nvim_get_current_win())
config.window.row = 3
view.render(s, config)
local positioned = vim.api.nvim_win_get_config(view.cursor.win)
eq(3, positioned.row)
eq(math.floor((vim.o.columns - positioned.width - 2) / 2), positioned.col)
for _, win in ipairs(vim.api.nvim_list_wins()) do
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "input-tools-menu" then
    eq(6, vim.api.nvim_win_get_config(win).row)
  end
end
vim.o.columns, vim.o.lines = 18, 6
view.render(s, config)
view.close()
eq(original_position, vim.g.ui_cmdline_pos)
view.render(s, config)
vim.g.ui_cmdline_pos = { 88, 12 }
view.close()
eq({ 88, 12 }, vim.g.ui_cmdline_pos) -- A later owner must survive teardown.
vim.g.ui_cmdline_pos = nil

-- Lifecycle ownership, validation before replacement and no hard dependency.
local attach, detach = vim.ui_attach, vim.ui_detach
local callback, attached, detached
vim.ui_attach = function(_, opts, handler)
  callback, attached = handler, opts
end
vim.ui_detach = function()
  detached = true
end
tools.setup()
eq({ ext_cmdline = true, ext_popupmenu = true }, attached)
assert(tools.is_enabled())
assert(not package.loaded["notification-tools"], "standalone setup must not load notifications")
assert(not package.loaded["blink.cmp"], "UI setup must not eagerly load Blink")
assert(not pcall(tools.setup, { window = { max_width = 0 } }))
assert(tools.is_enabled(), "invalid reconfiguration must preserve the working renderer")
assert(not pcall(tools.setup, { window = { row = -1 } }))
eq(nil, callback("msg_show", "echo", { { 0, "not ours" } }))
vim.cmd("InputTools disable")
assert(detached and not tools.is_enabled())
vim.cmd("InputTools enable")
assert(tools.is_enabled())
vim.cmd("InputTools toggle")
assert(not tools.is_enabled())
eq({ "enable" }, vim.fn.getcompletion("InputTools en", "cmdline"))
assert(not pcall(vim.cmd, "InputTools invalid"))
assert(not tools.status().blink.loaded)
assert(not package.loaded["blink.cmp"])
tools.teardown()
assert(detached and not tools.is_enabled())
eq(nil, callback("cmdline_show", { { 0, "stale" } }, 0, ":", "", 0, 1))
tools.teardown()
vim.ui_attach, vim.ui_detach = attach, detach
assert(not pcall(tools.setup, { return_prompt = "yes" }))
assert(not pcall(tools.setup, { popupmenu = { enabled = 1 } }))
-- A failed renderer releases the message lease BEFORE its own subscription.
local original_notifications = package.loaded["notification-tools"]
local original_notify, original_render = vim.notify, view.render
local active, reported = false, false
package.loaded["notification-tools"] = {
  attach_messages = function()
    active = true
    return {
      is_active = function()
        return active
      end,
      detach = function()
        active = false
      end,
    }
  end,
}
vim.ui_attach = function(_, _, handler)
  callback = handler
end
vim.ui_detach = function()
  assert(not active, "input detached before its message lease")
end
vim.notify = function(message)
  reported = message:find("forced render failure", 1, true) ~= nil
end
tools.setup()
view.render = function()
  error("forced render failure")
end
callback("cmdline_show", { { 0, "broken" } }, 6, ":", "", 0, 1)
assert(not active and not tools.is_enabled())
assert(tools.status().last_error:find("forced render failure", 1, true))
vim.wait(30)
assert(reported)
view.render, vim.notify = original_render, original_notify
package.loaded["notification-tools"] = original_notifications
vim.ui_attach, vim.ui_detach = attach, detach
print(
  "core: nested command lines, literal Unicode/byte cursors, special chars, blocks, prompts, geometry and lifecycle passed"
)
