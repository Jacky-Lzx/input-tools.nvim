vim.opt.runtimepath:prepend(vim.fn.getcwd())
local input = require("input-tools")
input.setup()
for _, name in ipairs({ "view", "modal", "text", "highlights", "layout", "blink" }) do
  assert(not package.loaded["input-tools." .. name], name .. " must stay lazy during setup")
end
local blink = require("input-tools.blink")
blink.menu_config()
local schedule, mode = vim.schedule, vim.api.nvim_get_mode
local scheduled = {}
vim.schedule = function(f)
  scheduled[#scheduled + 1] = f
end
vim.api.nvim_get_mode = function()
  return { mode = "c" }
end
blink.position_changed()
assert(#scheduled == 0, "absent Blink must not schedule work")
local menu_key = "blink.cmp.completion.windows.menu"
local previous = package.loaded[menu_key]
local visible, updated = false, 0
package.loaded[menu_key] = {
  win = {
    is_open = function()
      return visible
    end,
  },
  update_position = function()
    updated = updated + 1
  end,
}
blink.position_changed()
assert(#scheduled == 0, "hidden menu must not schedule work")
visible = true
blink.position_changed()
blink.position_changed()
assert(#scheduled == 1, "visible menu updates must coalesce")
visible = false
scheduled[1]()
assert(updated == 0, "closed menus must not receive stale updates")
package.loaded[menu_key] = previous
vim.schedule, vim.api.nvim_get_mode = schedule, mode
input.disable()
local handle = input.input({ vim_mode = true, default = "name" }, function() end)
assert(package.loaded["input-tools.modal"] and package.loaded["input-tools.highlights"])
assert(
  not package.loaded["input-tools.view"] and not package.loaded["input-tools.text"],
  "Vim input must not load native rendering/decoder"
)
handle.cancel()
vim.wait(40)
print(
  "lazy: setup and Vim input defer native renderer/decoder; Blink updates only visible menus passed"
)
vim.cmd.qa({ bang = true })
