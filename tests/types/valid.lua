local input = require("input-tools")
---@type input_tools.Config
local opts = {
  notifications = true,
  return_prompt = "show",
  window = { border = "rounded", max_width = 70, row = 3 },
  profiles = {
    search = { width = 0.4, min_width = 20, col = -2, title = "Search", title_pos = "right" },
  },
  popupmenu = { enabled = false },
}
---@type input_tools.API
local api = input.setup(opts)
---@type input_tools.Status
local status = api.status()
---@type boolean
local enabled = api.is_enabled()
---@type input_tools.Layout|nil
local layout = api.get_layout()
---@type integer|nil
local window = api.get_window()
api.input({
  title = "Project",
  title_pos = "center",
  position = "cursor",
  width = 32,
  default = "foo",
  scope = "cursor",
}, function(value)
  if value then
    assert(type(value) == "string")
  end
end)
api.disable()
api.enable()
api.toggle()
api.sync_notifications()
api.teardown()
return { status = status, enabled = enabled, window = window, layout = layout }
