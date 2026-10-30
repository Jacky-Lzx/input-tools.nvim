local input = require("input-tools")
---@type input_tools.Config
local opts = {
  notifications = true,
  return_prompt = "show",
  window = { border = "rounded", max_width = 70, row = 3 },
  popupmenu = { enabled = false },
}
---@type input_tools.API
local api = input.setup(opts)
---@type input_tools.Status
local status = api.status()
---@type boolean
local enabled = api.is_enabled()
---@type integer|nil
local window = api.get_window()
api.sync_notifications()
api.teardown()
return { status = status, enabled = enabled, window = window }
