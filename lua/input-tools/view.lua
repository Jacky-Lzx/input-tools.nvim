local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("input-tools.view")
local surfaces = {}
local previous_position, owned_position

local function position(value)
  local current = vim.g.ui_cmdline_pos
  if value then
    if vim.deep_equal(current, value) and vim.deep_equal(owned_position, value) then
      return
    end
    if not owned_position or not vim.deep_equal(current, owned_position) then
      previous_position = vim.deepcopy(current)
    end
    owned_position = value
    vim.g.ui_cmdline_pos = value
    require("input-tools.blink").position_changed()
  else
    if owned_position and vim.deep_equal(current, owned_position) then
      vim.g.ui_cmdline_pos = previous_position
      require("input-tools.blink").position_changed()
    end
    owned_position, previous_position = nil, nil
  end
end

function M.highlights()
  require("input-tools.highlights").setup(true)
end

local function close(name)
  local surface = surfaces[name]
  surfaces[name] = nil
  if surface and api.nvim_win_is_valid(surface.win) then
    api.nvim_win_close(surface.win, true)
    return true
  end
  return false
end

function M.close()
  require("input-tools.events").set(nil)
  position(nil)
  for _, name in ipairs({ "command", "menu", "status" }) do
    close(name)
  end
  M.cursor, M.source_anchor, M.source_point, M.layout = nil, nil, nil, nil
end

local function surface(name, lines, geometry, window)
  local dirty = false
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
    item = { win = win, buf = buf, wrap = false }
    dirty = true
    surfaces[name] = item
    vim.wo[win].wrap, vim.wo[win].cursorline, vim.wo[win].scrolloff = false, false, 0
    vim.wo[win].sidescrolloff, vim.wo[win].linebreak = 2, false
    vim.wo[win].winhighlight = "Normal:InputTools"
      .. (name == "menu" and "Menu" or "Normal")
      .. ",FloatBorder:InputToolsBorder,FloatTitle:InputToolsTitle"
  elseif not vim.deep_equal(item.geometry, geometry) then
    local updated = vim.tbl_extend("force", {}, geometry)
    updated.title = geometry.title or "" -- Clear a title inherited from another input profile.
    updated.noautocmd = nil -- Neovim 0.10 accepts this only when opening a window.
    api.nvim_win_set_config(item.win, updated)
    dirty = true
  end
  item.geometry = geometry
  if item.winblend ~= window.winblend then
    vim.wo[item.win].winblend = window.winblend
    item.winblend, dirty = window.winblend, true
  end
  if not vim.deep_equal(item.lines, lines) then
    api.nvim_buf_set_lines(item.buf, 0, -1, false, lines)
    item.lines = vim.deepcopy(lines)
    item.marks_stale, dirty = true, true
  end
  return item, dirty
end

local function highlights(item, marks)
  if not item.marks_stale and vim.deep_equal(item.marks, marks) then
    return false
  end
  if item.marks ~= nil or #marks > 0 then
    api.nvim_buf_clear_namespace(item.buf, ns, 0, -1)
  end
  for _, mark in ipairs(marks) do
    api.nvim_buf_set_extmark(item.buf, ns, mark[1], mark[2], mark[3])
  end
  item.marks, item.marks_stale = vim.deepcopy(marks), false
  return true
end

local function flush(win, dirty)
  if not dirty and not win then
    return
  end
  if dirty or not win or not api.nvim__redraw then
    vim.cmd.redraw()
    return
  end
  local ok = pcall(api.nvim__redraw, { win = win, valid = true, flush = true })
  if not ok then
    vim.cmd.redraw()
  end
end

local geometry = require("input-tools.layout").box

local function display_width(value)
  return vim.fn.strdisplaywidth(value)
end

function M.render(s, config)
  local model = require("input-tools.model")
  local command = model.command(s)
  local layout_tools = require("input-tools.layout")
  local window =
    layout_tools.style(config, command and command.kind or "command", command and command.input)
  local edge = (window.border == "none" or window.border == "") and 0 or 2
  if edge == 0 and command and command.input and command.input.hide_prompt then
    command = model.command(s, true) -- A borderless window needs the inline label.
  end
  local columns, rows = layout_tools.screen()
  local anchor
  local dirty = false
  M.source_anchor = command
      and command.input
      and command.input.position == "cursor"
      and command.input.anchor
    or nil
  M.source_point = nil
  if command then
    local box, _, point = layout_tools.input(window, function(width)
      if command.editable then
        return #command.lines
      end
      local count = 0
      for _, line in ipairs(command.lines) do
        count = count + math.max(1, math.ceil(display_width(line) / width))
      end
      return count
    end, M.source_anchor)
    M.source_point = point
    local row, col, width, height = box.row, box.col, box.width, box.height
    local first = math.max(1, command.row - height + 1)
    local lines = vim.list_slice(command.lines, first, first + height - 1)
    local item, changed = surface("command", lines, box, window)
    dirty = dirty or changed
    local cursor_row = math.min(#lines, math.max(1, command.row - first + 1))
    if item.wrap ~= not command.editable then
      item.wrap = not command.editable
      vim.wo[item.win].wrap, vim.wo[item.win].linebreak = item.wrap, item.wrap
      dirty = true
    end
    local cursor_col = math.min(command.col, #lines[cursor_row] - 1)
    api.nvim_win_set_cursor(item.win, { cursor_row, math.max(0, cursor_col) })
    local marks = {}
    for _, mark in ipairs(command.highlights) do
      local r = mark.row - first
      if r >= 0 and r < #lines then
        marks[#marks + 1] = { r, mark.col, { end_col = mark.stop, hl_group = mark.hl } }
      end
    end
    dirty = highlights(item, marks) or dirty
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
    dirty = close("command") or dirty
    M.cursor = nil
  end

  local menu = s.menu
  local options = config.popupmenu
  local menu_edge = (options.border == "none" or options.border == "") and 0 or 2
  local menu_height, menu_row
  if menu and menu.grid == -1 and anchor then
    local below_row = anchor.row + anchor.height + edge
    local above, below =
      math.max(0, anchor.row - menu_edge), math.max(0, rows - below_row - menu_edge)
    local desired = math.min(options.max_height, #menu.items)
    local use_below = below >= desired or (above < desired and below >= above)
    local available = use_below and below or above
    if available == 0 then
      menu = nil
    else
      menu_height = math.min(desired, available)
      menu_row = use_below and below_row or (anchor.row - menu_height - menu_edge)
    end
  end
  if
    menu
    and #menu.items > 0
    and (menu.grid ~= -1 or anchor)
    and rows > menu_edge
    and columns > menu_edge
  then
    local height = menu_height or math.min(options.max_height, #menu.items, rows - menu_edge)
    local first = math.max(1, menu.selected - height + 2)
    first = math.min(first, math.max(1, #menu.items - height + 1))
    local lines, width = {}, options.min_width
    local scroll = options.scrollbar and #menu.items > height
    for i = first, math.min(#menu.items, first + height - 1) do
      local entry = menu.items[i]
      local value = (entry[1] or "")
        .. ((entry[2] or "") ~= "" and ("  " .. entry[2]) or "")
        .. ((entry[3] or "") ~= "" and ("  " .. entry[3]) or "")
      value = value:gsub("[\n\r\t]", " ")
      lines[#lines + 1] = value
      width = math.max(width, display_width(value) + 1)
    end
    width =
      math.max(1, math.min(width + (scroll and 1 or 0), options.max_width, columns - menu_edge))
    -- Truncate by cells, preserving UTF-8/combining characters and reserving
    -- the last cell for a scrollbar. This also bounds very long candidates.
    local text_width = width - (scroll and 1 or 0)
    for i, line in ipairs(lines) do
      local value = ""
      for char in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if display_width(value .. char) > text_width then
          break
        end
        value = value .. char
      end
      lines[i] = value .. string.rep(" ", width - display_width(value))
    end
    local row, col = menu.row, menu.col
    if menu.grid == -1 then
      row = menu_row
      if options.align == "frame" then
        col = anchor.col - edge / 2
      else
        local left = api.nvim_win_call(anchor.item.win, vim.fn.winsaveview).leftcol
        col = anchor.col
          + display_width(anchor.command.prefix .. anchor.command.content:sub(1, menu.col))
          - left
      end
    elseif menu.grid and menu.grid > 1 then
      local pos = api.nvim_win_get_position(0)
      row, col = row + pos[1], col + pos[2]
    end
    if menu.grid ~= -1 then
      row = row + 1
      if row + height + menu_edge > rows then
        row = math.max(0, row - height - menu_edge - 1)
      end
    end
    row = math.max(0, math.min(row, rows - height - menu_edge))
    col = math.max(0, math.min(col, columns - width - menu_edge))
    local item, changed = surface(
      "menu",
      lines,
      geometry(row, col, width, height, options.border, window.zindex + 1),
      window
    )
    dirty = dirty or changed
    local marks = {}
    local selected = menu.selected + 2 - first
    if selected >= 1 and selected <= #lines then
      marks[#marks + 1] =
        { selected - 1, 0, { end_row = selected, hl_group = "InputToolsSelection", hl_eol = true } }
    end
    if scroll then
      local thumb = math.max(1, math.floor(height * height / #menu.items))
      local top = math.floor((first - 1) * (height - thumb) / math.max(1, #menu.items - height))
      for i = 0, height - 1 do
        marks[#marks + 1] = {
          i,
          #lines[i + 1] - 1,
          {
            virt_text = {
              {
                "▐",
                i >= top and i < top + thumb and "InputToolsThumb" or "InputToolsScrollbar",
              },
            },
            virt_text_pos = "overlay",
            priority = 210,
          },
        }
      end
    end
    dirty = highlights(item, marks) or dirty
  else
    dirty = close("menu") or dirty
  end

  local status = config.status and not command and model.status(s) or ""
  if status ~= "" then
    local width = math.max(1, math.min(display_width(status), columns))
    local _, changed = surface(
      "status",
      { status },
      geometry(math.max(0, rows - 1), columns - width, width, 1, "none", window.zindex),
      window
    )
    dirty = dirty or changed
  else
    dirty = close("status") or dirty
  end
  local function publish_position()
    if anchor and command.editable then
      local saved = api.nvim_win_call(anchor.item.win, vim.fn.winsaveview)
      local prefix = vim.split(command.prefix, "\n", { plain = true })
      -- Shared UI convention: 1-based screen row, 0-based column before native
      -- command text (Blink adds its 1-based completion start_col).
      position({
        anchor.row + edge / 2 + M.cursor.row - saved.topline + 1,
        anchor.col + display_width(prefix[#prefix]) - saved.leftcol - 1,
      })
    else
      position(nil)
    end
  end
  -- Consumers can reposition in WinResized/WinScrolled during this redraw.
  publish_position()
  flush(M.cursor and M.cursor.win, dirty)
  if M.cursor and api.nvim__redraw then
    pcall(api.nvim__redraw, { win = M.cursor.win, cursor = true, flush = true })
  end
  publish_position() -- Include any horizontal scrolling performed by redraw.
  local layout
  if anchor then
    local saved = api.nvim_win_call(anchor.item.win, vim.fn.winsaveview)
    local prefix = vim.split(command.prefix, "\n", { plain = true })
    local cursor = vim.fn.screenpos(anchor.item.win, M.cursor.row, M.cursor.col + 1)
    layout = {
      win = anchor.item.win,
      buf = anchor.item.buf,
      kind = command.kind,
      editable = command.editable,
      row = anchor.row,
      col = anchor.col - edge / 2,
      width = anchor.width,
      height = anchor.height,
      outer_width = anchor.width + edge,
      outer_height = anchor.height + edge,
      border = { top = edge / 2, right = edge / 2, bottom = edge / 2, left = edge / 2 },
      text = {
        row = anchor.row + edge / 2 + M.cursor.row - saved.topline,
        col = anchor.col + display_width(prefix[#prefix]) - saved.leftcol,
      },
      cursor = { row = cursor.row - 1, col = cursor.col - 1 },
    }
  end
  M.layout = layout
  local modal = package.loaded["input-tools.modal"]
  if layout or not (modal and modal.get_window()) then
    require("input-tools.events").set(layout)
  else
    modal.refresh()
  end
end
return M
