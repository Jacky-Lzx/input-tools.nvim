-- Theme links shared by both renderers; no native text decoder dependency.
local M = {}
local initialized = false

function M.setup(reset)
  if reset then
    initialized = false
    local text = package.loaded["input-tools.text"]
    if text then
      text.reset()
    end
  end
  if initialized then
    return
  end
  for name, target in pairs({
    Normal = "NormalFloat",
    Border = "FloatBorder",
    Text = "NormalFloat",
    Prompt = "Question",
    Cursor = "Cursor",
    Menu = "Pmenu",
    Selection = "PmenuSel",
    Status = "ModeMsg",
    Title = "FloatTitle",
    Scrollbar = "PmenuSbar",
    Thumb = "PmenuThumb",
    ConfirmText = "NormalFloat",
    ConfirmChoice = "NormalFloat",
    ConfirmDefault = "PmenuSel",
    ConfirmKey = "Special",
  }) do
    vim.api.nvim_set_hl(0, "InputTools" .. name, { default = true, link = target })
  end
  initialized = true
end

return M
