-- A real scratch-buffer input for native Normal/Insert editing.
local M = {}
local api = vim.api
local active, waiting
local ns = api.nvim_create_namespace("input-tools.modal")
local refresh, finish, open_window, complete_close

function M.get_window()
  if
    active
    and not active.closed
    and active.win
    and api.nvim_win_is_valid(active.win)
    and api.nvim_buf_is_valid(active.buf)
    and api.nvim_win_get_buf(active.win) == active.buf
  then
    return active.win
  end
end

function M.get_layout()
  return M.get_window() and active.layout and vim.deepcopy(active.layout) or nil
end

local function signature(a)
  return {
    point = a.opts.position == "cursor" and require("input-tools.position").point(a.source) or nil,
    columns = vim.o.columns,
    rows = vim.o.lines - vim.o.cmdheight,
  }
end

local function geometry(a)
  local w = a.style
  local box, edge = require("input-tools.layout").input(
    w,
    api.nvim_buf_line_count(a.buf),
    a.opts.position == "cursor" and a.source or nil,
    true
  )
  return box, w, edge
end

local function update(a)
  if active ~= a or a.closed or not M.get_window() then
    return
  end
  local box, w, edge = geometry(a)
  if not vim.deep_equal(box, a.geometry) then
    local changed = vim.tbl_extend("force", {}, box)
    changed.noautocmd, changed.title = nil, box.title or ""
    api.nvim_win_set_config(a.win, changed)
    a.geometry = box
  end
  if a.winblend ~= w.winblend then
    vim.wo[a.win].winblend, a.winblend = w.winblend, w.winblend
  end
  a.signature = signature(a)
  -- Run only from scheduled work, never inside the decoration provider.
  local ok = api.nvim__redraw
    and pcall(api.nvim__redraw, { win = a.win, valid = true, flush = true })
  if not ok then
    vim.cmd.redraw()
  end
  if active ~= a or a.closed or not M.get_window() then
    return
  end
  local cursor = api.nvim_win_get_cursor(a.win)
  local screen = vim.fn.screenpos(a.win, cursor[1], cursor[2] + 1)
  local saved = api.nvim_win_call(a.win, vim.fn.winsaveview)
  a.layout = {
    win = a.win,
    buf = a.buf,
    kind = "input",
    editable = true,
    vim_mode = true,
    row = box.row,
    col = box.col,
    width = box.width,
    height = box.height,
    outer_width = box.width + edge,
    outer_height = box.height + edge,
    border = { top = edge / 2, right = edge / 2, bottom = edge / 2, left = edge / 2 },
    text = {
      row = box.row + edge / 2,
      col = box.col + edge / 2 + (a.prompt_width or 0) - saved.leftcol,
    },
    cursor = { row = screen.row - 1, col = (screen.curscol or screen.col) - 1 },
  }
  local view = package.loaded["input-tools.view"]
  if not (view and view.cursor and api.nvim_win_is_valid(view.cursor.win)) then
    require("input-tools.events").set(a.layout)
  end
end

refresh = function(a)
  if active ~= a or a.closed or a.closing or a.refresh_pending then
    return
  end
  a.refresh_pending = true
  vim.schedule(function()
    a.refresh_pending = false
    if active ~= a or a.closed then
      return
    end
    local ok, err = pcall(update, a)
    if not ok then
      finish(a, nil)
      vim.notify("input-tools input closed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

function M.refresh()
  if active then
    refresh(active)
  end
end

local function dispatch(a, value)
  vim.defer_fn(function()
    a.callback(value)
  end, 10)
end

complete_close = function(a, value)
  if a.closed then
    return
  end
  a.closed = true
  if active == a then
    active = nil
  end
  api.nvim_set_decoration_provider(ns, {})
  if a.group then
    pcall(api.nvim_del_augroup_by_id, a.group)
  end
  local focused = a.win and api.nvim_get_current_win() == a.win
  local externally_closed = a.win and not api.nvim_win_is_valid(a.win)
  if a.win and api.nvim_win_is_valid(a.win) then
    pcall(api.nvim_win_close, a.win, true)
  end
  if a.buf and api.nvim_buf_is_valid(a.buf) then
    pcall(api.nvim_buf_delete, a.buf, { force = true })
  end
  if
    (focused or externally_closed)
    and api.nvim_win_is_valid(a.source.win)
    and api.nvim_win_get_buf(a.source.win) == a.source.buf
    and api.nvim_win_get_tabpage(a.source.win) == api.nvim_get_current_tabpage()
  then
    api.nvim_set_current_win(a.source.win)
  end
  require("input-tools.events").set(nil)
  dispatch(a, value)
  local next_input = waiting
  if next_input then
    vim.schedule(function()
      if waiting == next_input and not active and not next_input.closed then
        waiting = nil
        next_input.queued = false
        open_window(next_input)
      end
    end)
  end
end

finish = function(a, value)
  if a.closed or a.closing then
    return
  end
  if a.queued then
    a.closed = true
    if waiting == a then
      waiting = nil
    end
    dispatch(a, value)
    return
  end
  a.closing = true
  -- Leave Insert while the input buffer still owns the cursor. Closing it first
  -- would let Neovim apply the Insert-exit cursor adjustment to the source file.
  local mode = api.nvim_get_mode().mode
  if
    a.win
    and (api.nvim_get_current_win() == a.win or not api.nvim_win_is_valid(a.win))
    and mode:sub(1, 1) == "i"
  then
    local returned = api.nvim_create_augroup("InputToolsModalReturn" .. a.buf, { clear = true })
    api.nvim_create_autocmd("ModeChanged", {
      group = returned,
      pattern = "*:n",
      once = true,
      callback = function()
        pcall(api.nvim_del_augroup_by_id, returned)
        vim.defer_fn(function()
          complete_close(a, value)
        end, 10)
      end,
    })
    vim.cmd.stopinsert()
  else
    if a.entering_insert then
      vim.cmd.stopinsert()
    end
    complete_close(a, value)
  end
end

function M.cancel()
  if waiting then
    finish(waiting, nil)
  end
  if active then
    finish(active, nil)
  end
end

open_window = function(a)
  local opts = a.opts
  active = a
  local ok, err = pcall(function()
    require("input-tools.highlights").setup()
    a.buf = api.nvim_create_buf(false, true)
    vim.bo[a.buf].buftype, vim.bo[a.buf].bufhidden = "nofile", "wipe"
    vim.bo[a.buf].swapfile, vim.bo[a.buf].undofile = false, false
    vim.bo[a.buf].filetype = "input-tools-input"
    vim.b[a.buf].completion = false -- Blink respects this buffer-local opt-out.
    api.nvim_buf_set_lines(
      a.buf,
      0,
      -1,
      false,
      vim.split(opts.default or "", "\n", { plain = true })
    )
    vim.bo[a.buf].modified = false
    local box, w = geometry(a)
    a.win = api.nvim_open_win(a.buf, true, box)
    a.geometry = box
    vim.wo[a.win].wrap, vim.wo[a.win].scrolloff, vim.wo[a.win].sidescrolloff = false, 0, 2
    vim.wo[a.win].winblend, a.winblend = w.winblend, w.winblend
    vim.wo[a.win].winhighlight =
      "Normal:InputToolsNormal,FloatBorder:InputToolsBorder,FloatTitle:InputToolsTitle"
    local prompt = opts.prompt or ""
    if (w.border == "none" or w.border == "") and prompt == "" and type(w.title) == "string" then
      prompt = w.title .. ": "
    end
    a.prompt_width = vim.fn.strdisplaywidth(prompt)
    if prompt ~= "" then
      api.nvim_buf_set_extmark(a.buf, ns, 0, 0, {
        virt_text = { { prompt:gsub("[\r\n]", " "), "InputToolsPrompt" } },
        virt_text_pos = "inline",
        right_gravity = false,
      })
    end
    local function later(value)
      vim.schedule(function()
        if active == a then
          finish(a, value)
        end
      end)
    end
    local function confirm()
      if vim.fn.pumvisible() == 1 then
        api.nvim_feedkeys(api.nvim_replace_termcodes("<C-y>", true, false, true), "n", false)
      else
        later(table.concat(api.nvim_buf_get_lines(a.buf, 0, -1, false), "\n"))
      end
    end
    vim.keymap.set({ "n", "i" }, "<CR>", confirm, { buffer = a.buf, silent = true })
    vim.keymap.set({ "n", "i" }, "<C-c>", function()
      later(nil)
    end, { buffer = a.buf, silent = true })
    vim.keymap.set("n", "<Esc>", function()
      later(nil)
    end, { buffer = a.buf, silent = true })
    vim.keymap.set("i", "<Esc>", "<Esc>", { buffer = a.buf, silent = true })
    a.group = api.nvim_create_augroup("InputToolsModal", { clear = true })
    api.nvim_create_autocmd(
      { "TextChanged", "TextChangedI", "CursorMoved", "CursorMovedI", "ModeChanged" },
      {
        group = a.group,
        buffer = a.buf,
        callback = function()
          if api.nvim_get_current_win() == a.win and api.nvim_get_mode().mode:sub(1, 1) == "i" then
            a.entering_insert = false
          end
          refresh(a)
        end,
      }
    )
    api.nvim_create_autocmd({ "WinLeave", "BufWipeout" }, {
      group = a.group,
      buffer = a.buf,
      callback = function()
        later(nil)
      end,
    })
    api.nvim_create_autocmd("WinClosed", {
      group = a.group,
      pattern = tostring(a.win),
      callback = function()
        later(nil)
      end,
    })
    api.nvim_create_autocmd({ "VimResized", "ColorScheme" }, {
      group = a.group,
      callback = function(e)
        if e.event == "ColorScheme" then
          require("input-tools.highlights").setup(true)
        end
        refresh(a)
      end,
    })
    api.nvim_set_decoration_provider(ns, {
      on_end = function()
        if
          active == a
          and not a.closed
          and not a.closing
          and not vim.deep_equal(signature(a), a.signature)
        then
          refresh(a)
        end
      end,
    })
    refresh(a)
    local lines = api.nvim_buf_get_lines(a.buf, 0, -1, false)
    api.nvim_win_set_cursor(a.win, { #lines, #lines[#lines] })
    a.entering_insert = api.nvim_get_mode().mode:sub(1, 1) ~= "i"
    vim.cmd("startinsert!")
  end)
  if not ok then
    finish(a, nil)
    error(err)
  end
end

function M.open(opts, callback, config)
  assert(opts.default == nil or type(opts.default) == "string", "default must be a string")
  assert(opts.prompt == nil or type(opts.prompt) == "string", "prompt must be a string")
  if waiting then
    finish(waiting, nil)
  end
  local a = {
    opts = vim.deepcopy(opts),
    callback = callback,
    config = config or require("input-tools.config").resolve(),
    source = active and active.source or require("input-tools.position").capture(),
    queued = active ~= nil,
  }
  a.style = require("input-tools.layout").style(a.config, "input", a.opts)
  if active then
    waiting = a
    finish(active, nil)
  else
    open_window(a)
  end
  return {
    cancel = function()
      finish(a, nil)
    end,
  }
end

return M
