-- Blink reads ui_cmdline_pos for anchoring but may process its resize callback
-- before our layout. Refresh only its already-loaded menu after layout settles.
local M = {}
local pending = false
local adapters = setmetatable({}, { __mode = "k" })

local function layout()
  local input = package.loaded["input-tools"]
  local box = type(input) == "table" and type(input.get_layout) == "function" and input.get_layout()
  if not box then
    return
  end
  local below = vim.o.lines - vim.o.cmdheight - box.row - box.outer_height
  local direction = below >= box.row and "s" or "n"
  return { row = box.row, col = box.col, height = box.outer_height, direction = direction }
end

---Blink completion.menu callbacks for outer-frame alignment in command-line mode.
---Factory is safe to call before Blink or the input renderer is loaded.
function M.menu_config(opts)
  opts = opts or {}
  local original_direction, original_position = opts.direction_priority, opts.cmdline_position
  local callbacks = {
    direction_priority = function(...)
      local box = vim.api.nvim_get_mode().mode == "c" and layout()
      if box then
        return { box.direction }
      end
      if type(original_direction) == "function" then
        return original_direction(...)
      end
      return original_direction or { "s", "n" }
    end,
    cmdline_position = function(...)
      local box = layout()
      if box then
        local cmp = package.loaded["blink.cmp"]
        local menu = package.loaded["blink.cmp.completion.windows.menu"]
        local context = type(menu) == "table" and menu.context
          or (type(cmp) == "table" and type(cmp.get_context) == "function" and cmp.get_context())
        local start_col = context and context.bounds and context.bounds.start_col or 1
        local alignment = 0
        local renderer = type(menu) == "table" and menu.renderer
        if renderer and type(renderer.get_alignment_start_col) == "function" then
          local ok, offset = pcall(renderer.get_alignment_start_col, renderer)
          if ok and type(offset) == "number" then
            alignment = offset
          end
        end
        -- Blink adds start_col and its north/south offset after this callback.
        local row = box.direction == "s" and (box.row + box.height - 1) or box.row
        local left = box.col
        local win = type(menu) == "table" and menu.win
        if win and type(win.get_win) == "function" then
          local ok, id = pcall(win.get_win, win)
          if ok and id and vim.api.nvim_win_is_valid(id) then
            local c = vim.api.nvim_win_get_config(id)
            local border = c.border or {}
            local function present(index)
              local value = border[index]
              if type(value) == "table" then
                value = value[1]
              end
              return value and value ~= "" and 1 or 0
            end
            local width = c.width
              + math.max(present(1), present(7), present(8))
              + math.max(present(3), present(4), present(5))
            left = math.max(0, math.min(left, vim.o.columns - width))
          end
        end
        return { row, left - start_col + alignment }
      end
      if type(original_position) == "function" then
        return original_position(...)
      end
      local pos = vim.g.ui_cmdline_pos
      if pos then
        return { pos[1] - 1, pos[2] }
      end
      return { vim.o.lines - math.max(1, vim.o.cmdheight), 0 }
    end,
  }
  adapters[callbacks.cmdline_position] = true
  return callbacks
end

local buffer_source = false

-- Optional Blink source configuration, using Blink's built-in completefunc
-- bridge. Other filetypes, source lists, keymaps and native fallback stay intact.
function M.sources_config(opts)
  local sources = vim.deepcopy(opts or {})
  sources.providers = sources.providers or {}
  sources.providers.input_tools = {
    name = "Input",
    module = "blink.cmp.sources.complete_func",
    opts = {
      complete_func = function()
        if vim.bo.filetype == "input-tools-input" and vim.b.input_tools_completion then
          return vim.bo.completefunc
        end
      end,
    },
  }
  sources.per_filetype = sources.per_filetype or {}
  sources.per_filetype["input-tools-input"] = { "input_tools" }
  buffer_source = true
  -- The first input may have triggered lazy-loading Blink via InsertEnter.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].input_tools_completion then
      vim.b[buf].completion = true
    end
  end
  return sources
end

function M.buffer_enabled()
  return buffer_source
end

---Inspect only already-loaded Blink modules; never activate completion.
function M.status()
  local config = package.loaded["blink.cmp.config"]
  local menu = package.loaded["blink.cmp.completion.windows.menu"]
  local win = type(menu) == "table" and menu.win
  local visible = false
  if win and type(win.is_open) == "function" then
    local ok, result = pcall(win.is_open, win)
    visible = ok and result == true
  end
  local options = type(config) == "table" and config.completion and config.completion.menu
  return {
    loaded = package.loaded["blink.cmp"] ~= nil,
    visible = visible,
    adapter = type(options) == "table" and adapters[options.cmdline_position] == true,
  }
end

local function visible_menu()
  if vim.api.nvim_get_mode().mode ~= "c" then
    return
  end
  local menu = package.loaded["blink.cmp.completion.windows.menu"]
  local win = type(menu) == "table" and menu.win
  if
    type(menu) ~= "table"
    or type(menu.update_position) ~= "function"
    or not win
    or type(win.is_open) ~= "function"
  then
    return
  end
  local ok, visible = pcall(win.is_open, win)
  return ok and visible and menu or nil
end

function M.position_changed()
  if pending or not visible_menu() then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    local menu = visible_menu()
    if menu then
      pcall(menu.update_position)
    end
  end)
end

return M
