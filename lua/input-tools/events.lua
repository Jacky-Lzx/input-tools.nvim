-- Publish immutable layout snapshots after rendering, outside UI callbacks.
local M = {}
local current, delivered, pending

function M.get()
  return current and vim.deepcopy(current) or nil
end

local function emit(name, layout)
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = name,
    modeline = false,
    data = { layout = vim.deepcopy(layout) },
  })
  if not ok then
    vim.schedule(function()
      vim.notify("input-tools " .. name .. " handler: " .. tostring(err), vim.log.levels.ERROR)
    end)
  end
end

function M.set(layout)
  if vim.deep_equal(current, layout) then
    return
  end
  current = layout and vim.deepcopy(layout) or nil
  require("input-tools.blink").position_changed()
  if pending then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    local previous, next_layout = delivered, M.get()
    local replaced = previous and next_layout and previous.win ~= next_layout.win
    if previous and (not next_layout or replaced) then
      delivered = nil
      emit("InputToolsClose", previous)
    end
    -- A close handler can disable/reconfigure the renderer. Do not announce
    -- a stale open or layout change after that action.
    if not vim.deep_equal(current, next_layout) then
      return
    end
    if next_layout and (not previous or replaced) then
      delivered = vim.deepcopy(next_layout)
      emit("InputToolsOpen", next_layout)
    elseif next_layout and not vim.deep_equal(previous, next_layout) then
      delivered = vim.deepcopy(next_layout)
      emit("InputToolsLayoutChanged", next_layout)
    end
  end)
end
return M
