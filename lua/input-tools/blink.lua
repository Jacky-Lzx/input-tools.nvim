-- Blink reads ui_cmdline_pos for anchoring but may process its resize callback
-- before our layout. Refresh only its already-loaded menu after layout settles.
local M = {}
local pending = false

function M.position_changed()
  if pending then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    if vim.api.nvim_get_mode().mode ~= "c" then
      return
    end
    local menu = package.loaded["blink.cmp.completion.windows.menu"]
    if type(menu) == "table" and type(menu.update_position) == "function" then
      pcall(menu.update_position)
    end
  end)
end

return M
