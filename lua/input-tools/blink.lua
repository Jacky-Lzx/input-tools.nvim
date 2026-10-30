-- Blink reads ui_cmdline_pos for anchoring but may process its resize callback
-- before our layout. Refresh only its already-loaded menu after layout settles.
local M = {}
local pending = false

local function layout()
  local input = package.loaded["input-tools"]
  local win = type(input) == "table" and type(input.get_window) == "function" and input.get_window()
  if not win then
    return
  end
  local config = vim.api.nvim_win_get_config(win)
  local function border(index)
    local value = config.border and config.border[index]
    if type(value) == "table" then
      value = value[1]
    end
    return value and value ~= "" and 1 or 0
  end
  local height = config.height
    + math.max(border(1), border(2), border(3))
    + math.max(border(5), border(6), border(7))
  local below = vim.o.lines - vim.o.cmdheight - config.row - height
  local direction = below >= config.row and "s" or "n"
  return { row = config.row, col = config.col, height = height, direction = direction }
end

---Blink completion.menu callbacks for outer-frame alignment in command-line mode.
---Factory is safe to call before Blink or the input renderer is loaded.
function M.menu_config(opts)
  opts = opts or {}
  local original_direction, original_position = opts.direction_priority, opts.cmdline_position
  return {
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
        return { row, box.col - start_col + alignment }
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
end

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
