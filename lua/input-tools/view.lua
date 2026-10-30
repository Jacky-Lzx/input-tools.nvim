local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("input-tools.view")
local surfaces = {}

function M.highlights()
  for name, target in pairs({
    Normal = "NormalFloat",
    Border = "FloatBorder",
    Text = "NormalFloat",
    Prompt = "Question",
    Cursor = "Cursor",
    Menu = "Pmenu",
    Selection = "PmenuSel",
    Status = "ModeMsg",
  }) do
    api.nvim_set_hl(0, "InputTools" .. name, { default = true, link = target })
  end
end

local function close(name)
  local surface = surfaces[name]
  surfaces[name] = nil
  if surface and api.nvim_win_is_valid(surface.win) then
    api.nvim_win_close(surface.win, true)
  end
end

function M.close()
  for _, name in ipairs({ "command", "menu", "status" }) do
    close(name)
  end
  M.cursor = nil
end

local function surface(name, lines, geometry, config)
  local item = surfaces[name]
  if
    item
    and (
      not api.nvim_win_is_valid(item.win)
      or api.nvim_win_get_tabpage(item.win) ~= api.nvim_get_current_tabpage()
    )
  then
    close(name)
    item = nil
  end
  if not item then
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden, vim.bo[buf].filetype = "wipe", "input-tools-" .. name
    local win = api.nvim_open_win(buf, false, geometry)
    item = { win = win, buf = buf }
    surfaces[name] = item
    vim.wo[win].wrap, vim.wo[win].cursorline, vim.wo[win].scrolloff = false, false, 0
    vim.wo[win].sidescrolloff = 2
    vim.wo[win].winhighlight = "Normal:InputTools"
      .. (name == "menu" and "Menu" or "Normal")
      .. ",FloatBorder:InputToolsBorder"
  elseif not vim.deep_equal(item.geometry, geometry) then
    local updated = vim.tbl_extend("force", {}, geometry)
    updated.noautocmd = nil -- Neovim 0.10 accepts this only when opening a window.
    api.nvim_win_set_config(item.win, updated)
  end
  item.geometry = geometry
  vim.wo[item.win].winblend = config.window.winblend
  if not vim.deep_equal(item.lines, lines) then
    api.nvim_buf_set_lines(item.buf, 0, -1, false, lines)
    item.lines = vim.deepcopy(lines)
  end
  api.nvim_buf_clear_namespace(item.buf, ns, 0, -1)
  return item
end

local function geometry(row, col, width, height, border, zindex)
  return {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    focusable = false,
    border = border,
    zindex = zindex,
    noautocmd = true,
  }
end

local function display_width(value)
  return vim.fn.strdisplaywidth(value)
end

function M.render(s, config)
  local model = require("input-tools.model")
  local command = model.command(s)
  local edge = (config.window.border == "none" or config.window.border == "") and 0 or 2
  local columns, rows = math.max(1, vim.o.columns), math.max(1, vim.o.lines - vim.o.cmdheight)
  local anchor
  if command then
    local width = math.max(1, math.min(config.window.max_width, columns - edge - 2))
    local count = #command.lines
    if not command.editable then
      count = 0
      for _, line in ipairs(command.lines) do
        count = count + math.max(1, math.ceil(display_width(line) / width))
      end
    end
    local height =
      math.max(1, math.min(count, config.window.max_height, rows - edge - config.window.bottom))
    local first = math.max(1, command.row - height + 1)
    local lines = vim.list_slice(command.lines, first, first + height - 1)
    local row = math.max(0, rows - height - edge - config.window.bottom)
    if config.window.row ~= nil then
      row = math.max(0, math.min(config.window.row, rows - height - edge))
    end
    local col = math.max(0, math.floor((columns - width - edge) / 2))
    local item = surface(
      "command",
      lines,
      geometry(row, col, width, height, config.window.border, config.window.zindex),
      config
    )
    local cursor_row = math.min(#lines, math.max(1, command.row - first + 1))
    vim.wo[item.win].wrap, vim.wo[item.win].linebreak = not command.editable, not command.editable
    local cursor_col = math.min(command.col, #lines[cursor_row] - 1)
    api.nvim_win_set_cursor(item.win, { cursor_row, math.max(0, cursor_col) })
    if command.prefix ~= "" and cursor_row == 1 then
      api.nvim_buf_set_extmark(
        item.buf,
        ns,
        0,
        0,
        { end_col = math.min(#command.prefix, #lines[1]), hl_group = "InputToolsPrompt" }
      )
    end
    anchor = {
      row = row,
      col = col + edge / 2,
      width = width,
      height = height,
      item = item,
      command = command,
    }
    M.cursor = { win = item.win, row = cursor_row, col = math.max(0, cursor_col) }
  else
    close("command")
    M.cursor = nil
  end

  local menu = s.menu
  local menu_height, menu_row
  if menu and menu.grid == -1 and anchor then
    local below_row = anchor.row + anchor.height + edge
    local above, below = math.max(0, anchor.row - 2), math.max(0, rows - below_row - 2)
    local use_below = (anchor.row < rows / 2 and below > 0) or above == 0
    local available = use_below and below or above
    if available == 0 then
      menu = nil -- No non-overlapping space for a bordered menu.
    else
      menu_height = math.min(config.popupmenu.max_height, #menu.items, available)
      menu_row = use_below and below_row or (anchor.row - menu_height - 2)
    end
  end
  if menu and #menu.items > 0 and (menu.grid ~= -1 or anchor) then
    local height = menu_height
      or math.min(config.popupmenu.max_height, #menu.items, math.max(1, rows - 2))
    local first = math.max(1, menu.selected - height + 2)
    first = math.min(first, math.max(1, #menu.items - height + 1))
    local lines, width = {}, 1
    for i = first, math.min(#menu.items, first + height - 1) do
      local entry = menu.items[i]
      local value = (entry[1] or "")
        .. ((entry[2] or "") ~= "" and ("  " .. entry[2]) or "")
        .. ((entry[3] or "") ~= "" and ("  " .. entry[3]) or "")
      value = value:gsub("[\n\r\t]", " ")
      lines[#lines + 1] = value
      width = math.max(width, display_width(value))
    end
    width = math.max(1, math.min(width + 1, config.popupmenu.max_width, columns - 2))
    local row, col = menu.row, menu.col
    if menu.grid == -1 then
      row = menu_row
      local left = api.nvim_win_call(anchor.item.win, vim.fn.winsaveview).leftcol
      col = anchor.col
        + display_width(anchor.command.prefix .. anchor.command.content:sub(1, menu.col))
        - left
    elseif menu.grid and menu.grid > 1 then
      local position = api.nvim_win_get_position(0)
      row, col = row + position[1], col + position[2]
    end
    if menu.grid ~= -1 then
      row = row + 1
      if row + height + 2 > rows then
        row = math.max(0, row - height - 3)
      end
    end
    row, col =
      math.max(0, math.min(row, rows - height - 2)), math.max(0, math.min(col, columns - width - 2))
    local item = surface(
      "menu",
      lines,
      geometry(row, col, width, height, "single", config.window.zindex + 1),
      config
    )
    local selected = menu.selected + 2 - first
    if selected >= 1 and selected <= #lines then
      api.nvim_buf_set_extmark(
        item.buf,
        ns,
        selected - 1,
        0,
        { end_row = selected, hl_group = "InputToolsSelection", hl_eol = true }
      )
    end
  else
    close("menu")
  end

  local status = config.status and not command and model.status(s) or ""
  if status ~= "" then
    local width = math.max(1, math.min(display_width(status), columns))
    surface(
      "status",
      { status },
      geometry(math.max(0, rows - 1), columns - width, width, 1, "none", config.window.zindex),
      config
    )
  else
    close("status")
  end
  vim.cmd.redraw()
  if M.cursor and api.nvim__redraw then
    pcall(api.nvim__redraw, { win = M.cursor.win, cursor = true, flush = true })
  end
end
return M
