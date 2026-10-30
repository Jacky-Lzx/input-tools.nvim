local M = {}
M.defaults = {
  notifications = true,
  return_prompt = "auto",
  status = true,
  window = {
    border = "rounded",
    min_width = 1,
    max_width = 80,
    max_height = 8,
    bottom = 1,
    col = 0,
    title = false,
    winblend = 0,
    zindex = 250,
  },
  profiles = {},
  popupmenu = {
    enabled = true,
    border = "single",
    min_width = 1,
    max_height = 8,
    max_width = 60,
    align = "frame",
    scrollbar = true,
  },
}

local borders = { "rounded", "single", "double", "solid", "none", "" }
local function integer(value, minimum)
  return type(value) == "number"
    and value >= minimum
    and value > -math.huge
    and value < math.huge
    and value == math.floor(value)
end

local function window(opts)
  assert(type(opts) == "table", "window must be a table")
  assert(vim.tbl_contains(borders, opts.border), "unsupported border")
  for key, minimum in pairs({
    min_width = 1,
    max_width = 1,
    max_height = 1,
    bottom = 0,
    winblend = 0,
    zindex = 1,
  }) do
    assert(integer(opts[key], minimum), key .. " must be a finite integer >= " .. minimum)
  end
  assert(opts.min_width <= opts.max_width, "min_width must be <= max_width")
  assert(opts.winblend <= 100, "winblend must be <= 100")
  assert(
    opts.row == nil or opts.row == false or integer(opts.row, 0),
    "window.row must be a nonnegative integer, false or nil"
  )
  assert(integer(opts.col, -math.huge), "window.col must be a finite integer offset")
  assert(
    type(opts.title) == "string" or opts.title == false,
    "window.title must be a string or false"
  )
  local width = opts.width
  assert(
    width == nil or (type(width) == "number" and width > 0 and width <= 1) or integer(width, 1),
    "window.width must be a positive integer or a fraction in (0, 1]"
  )
end

---Resolve one input kind without mutating the base configuration.
function M.window(config, kind)
  return vim.tbl_deep_extend("force", {}, config.window, config.profiles[kind] or {})
end

function M.resolve(opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  for _, value in ipairs({
    config.notifications,
    config.status,
    config.popupmenu.enabled,
    config.popupmenu.scrollbar,
  }) do
    assert(type(value) == "boolean", "notifications, status and popupmenu.enabled must be booleans")
  end
  assert(
    config.return_prompt == "auto" or config.return_prompt == "show",
    "return_prompt must be auto or show"
  )
  window(config.window)
  assert(type(config.profiles) == "table", "profiles must be a table")
  for kind, profile in pairs(config.profiles) do
    assert(
      vim.tbl_contains({ "command", "search", "input", "expression", "confirm" }, kind),
      "unsupported input profile: " .. tostring(kind)
    )
    assert(type(profile) == "table", "profile must be a table")
    window(M.window(config, kind))
  end
  assert(vim.tbl_contains(borders, config.popupmenu.border), "unsupported popupmenu border")
  assert(
    vim.tbl_contains({ "frame", "cursor" }, config.popupmenu.align),
    "popupmenu.align must be frame or cursor"
  )
  assert(
    config.popupmenu.min_width <= config.popupmenu.max_width,
    "popupmenu.min_width must be <= max_width"
  )
  for _, key in ipairs({ "min_width", "max_width", "max_height" }) do
    assert(integer(config.popupmenu[key], 1), "popupmenu." .. key .. " must be a positive integer")
  end
  return config
end
return M
