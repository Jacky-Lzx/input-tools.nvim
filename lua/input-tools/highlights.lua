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
  local function definition(name)
    local seen = {}
    while name and not seen[name] do
      seen[name] = true
      local value = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
      if not value.link then
        return value
      end
      name = value.link
    end
    return {}
  end
  -- Popup borders share the popup surface, independently of command floats.
  vim.api.nvim_set_hl(0, "InputToolsDefaultMenuBorder", {
    fg = definition("InputToolsBorder").fg,
    bg = definition("Pmenu").bg or "NONE",
  })
  local empty =
    vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "InputToolsMenuBorder", create = false }))
  vim.api.nvim_set_hl(
    0,
    "InputToolsMenuBorder",
    { link = "InputToolsDefaultMenuBorder", default = not empty }
  )
  initialized = true
end

return M
