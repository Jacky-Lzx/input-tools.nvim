local M = {}
local prompts = { confirm = true, confirm_sub = true, number_prompt = true, return_prompt = true }
local statuses = { msg_showmode = true, msg_showcmd = true, msg_ruler = true }

function M.is_prompt(kind)
  return prompts[kind]
    or (kind == "" and not vim.in_fast_event() and vim.fn.mode(1):sub(1, 1) == "r")
end

-- Newer Neovim keeps an interactive cmdline active while waiting for a choice.
-- Its preceding msg_show body belongs to that same dialog until cmdline_hide.
function M.prompt_active(s)
  for _, entry in pairs(s.levels) do
    if entry.interactive then
      return true
    end
  end
  return false
end

function M.text(chunks)
  local parts = {}
  for _, chunk in ipairs(chunks or {}) do
    parts[#parts + 1] = chunk[2]
  end
  return table.concat(parts)
end

function M.new()
  return { levels = {}, block = {}, statuses = {} }
end

local function put(target, key, value)
  if vim.deep_equal(target[key], value) then
    return false
  end
  target[key] = value
  return true
end

-- Consume only our widgets. Ordinary messages belong to notification-tools.
function M.event(s, event, args, popupmenu)
  local changed = false
  if event == "cmdline_show" then
    changed = put(s.levels, args[6], {
      content = M.text(args[1]),
      chunks = vim.deepcopy(args[1]),
      prompt_hl = args[7],
      input = require("input-tools.input").context(args),
      interactive = not vim.in_fast_event() and vim.fn.mode(1):sub(1, 1) == "r",
      pos = args[2],
      firstc = args[3],
      prompt = args[4] or "",
      indent = args[5],
    })
  elseif event == "cmdline_pos" then
    if s.levels[args[2]] then
      changed = put(s.levels[args[2]], "pos", args[1])
    end
  elseif event == "cmdline_special_char" then
    if s.levels[args[3]] then
      changed = put(s.levels[args[3]], "special", { char = args[1], shift = args[2] })
    end
  elseif event == "cmdline_hide" then
    changed = s.levels[args[1]] ~= nil or s.menu ~= nil or s.prompt ~= nil
    s.levels[args[1]], s.menu, s.prompt = nil, nil, nil
  elseif event == "cmdline_block_show" then
    changed = put(s, "block", vim.deepcopy(args[1]))
  elseif event == "cmdline_block_append" then
    s.block[#s.block + 1] = vim.deepcopy(args[1])
    changed = true
  elseif event == "cmdline_block_hide" then
    changed = put(s, "block", {})
  elseif event == "msg_show" and M.is_prompt(args[1]) then
    local chunks = vim.deepcopy(args[2])
    local text = M.text(chunks)
    if args[5] and s.prompt then
      text = s.prompt.text .. text
      chunks = vim.list_extend(vim.deepcopy(s.prompt.chunks), chunks)
    end
    changed = put(s, "prompt", { kind = args[1], text = text, chunks = chunks })
  elseif statuses[event] then
    changed = put(s.statuses, event, M.text(args[1]))
  elseif popupmenu and event == "popupmenu_show" then
    changed = put(
      s,
      "menu",
      { items = args[1], selected = args[2], row = args[3], col = args[4], grid = args[5] }
    )
  elseif popupmenu and event == "popupmenu_select" then
    if s.menu then
      changed = put(s.menu, "selected", args[1])
    end
  elseif popupmenu and event == "popupmenu_hide" then
    changed = put(s, "menu", nil)
  else
    return false
  end
  return true, changed
end

function M.command(s, keep_prompt)
  local current, highest
  for level, entry in pairs(s.levels) do
    if not highest or level > highest then
      current, highest = entry, level
    end
  end
  if not current and not s.prompt then
    return
  end
  local lines, highlights = {}, {}
  local rich = require("input-tools.text")
  local function append(chunks)
    local added, marks = rich.lines(chunks)
    for _, mark in ipairs(marks) do
      mark.row = mark.row + #lines
      highlights[#highlights + 1] = mark
    end
    vim.list_extend(lines, added)
  end
  for _, line in ipairs(s.block) do
    append(line)
  end
  local prefix, content, pos = "", "", 0
  if current then
    local prompt = current.input and current.input.hide_prompt and not keep_prompt and ""
      or current.prompt
    prefix = current.firstc .. prompt .. string.rep(" ", current.indent)
    content, pos = current.content, current.pos
    if current.special then
      local tail = content:sub(pos + 1)
      if not current.special.shift and tail ~= "" then
        tail = vim.fn.strcharpart(tail, 1)
      end
      content = content:sub(1, pos) .. current.special.char .. tail
    end
  end
  if
    s.prompt and (not current or not (prefix .. content):find(vim.trim(s.prompt.text), 1, true))
  then
    append(s.prompt.chunks)
  end
  local before = prefix .. content:sub(1, pos)
  local cursor_lines = vim.split(before, "\n", { plain = true })
  local row = #lines + #cursor_lines
  local col = #cursor_lines[#cursor_lines]
  if current then
    local chunks = {
      {
        0,
        prefix,
        current.prompt_hl and current.prompt_hl > 0 and current.prompt_hl or "InputToolsPrompt",
      },
    }
    vim.list_extend(chunks, rich.special(current.chunks, current.pos, current.special))
    chunks[#chunks + 1] = { 0, " " }
    append(chunks)
  else
    row, col = #lines, #lines[#lines]
    lines[#lines] = lines[#lines] .. " "
  end
  return {
    lines = lines,
    highlights = highlights,
    row = row,
    col = col,
    prefix = prefix,
    content = content,
    editable = current ~= nil,
    input = current and current.input,
    kind = (not current or current.interactive or s.prompt ~= nil) and "confirm"
      or (current.firstc == "/" or current.firstc == "?") and "search"
      or current.firstc == "=" and "expression"
      or (current.input or current.prompt ~= "") and "input"
      or "command",
  }
end

function M.status(s)
  local parts = {}
  for _, name in ipairs({ "msg_showmode", "msg_showcmd", "msg_ruler" }) do
    local value = s.statuses[name]
    if value and value ~= "" then
      parts[#parts + 1] = value:gsub("\n", " ")
    end
  end
  return table.concat(parts, "  ")
end
return M
