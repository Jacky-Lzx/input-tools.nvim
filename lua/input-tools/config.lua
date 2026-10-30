local M = {}
M.defaults = {
  notifications = true,
  return_prompt = "auto",
  status = true,
  window = {
    border = "rounded",
    max_width = 80,
    max_height = 8,
    bottom = 1,
    winblend = 0,
    zindex = 250,
  },
  popupmenu = { enabled = true, max_height = 8, max_width = 60 },
}

function M.resolve(opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  for _, value in ipairs({ config.notifications, config.status, config.popupmenu.enabled }) do
    assert(type(value) == "boolean", "notifications, status and popupmenu.enabled must be booleans")
  end
  assert(
    config.return_prompt == "auto" or config.return_prompt == "show",
    "return_prompt must be auto or show"
  )
  assert(
    vim.tbl_contains({ "rounded", "single", "double", "solid", "none", "" }, config.window.border),
    "unsupported border"
  )
  for _, section in ipairs({ config.window, config.popupmenu }) do
    for _, key in ipairs({ "max_width", "max_height" }) do
      local value = section[key]
      assert(
        type(value) == "number" and value >= 1 and value < math.huge and value == math.floor(value),
        key .. " must be a positive integer"
      )
    end
  end
  for key, minimum in pairs({ bottom = 0, winblend = 0, zindex = 1 }) do
    local value = config.window[key]
    assert(
      type(value) == "number"
        and value >= minimum
        and value < math.huge
        and value == math.floor(value),
      key .. " must be a finite integer >= " .. minimum
    )
  end
  assert(config.window.winblend <= 100, "winblend must be <= 100")
  return config
end
return M
