local M = {}
local prompts = { confirm = true, confirm_sub = true, number_prompt = true, return_prompt = true }
local statuses = { msg_showmode = true, msg_showcmd = true, msg_ruler = true }

function M.is_prompt(kind)
  return prompts[kind]
    or (kind == "" and not vim.in_fast_event() and vim.fn.mode(1):sub(1, 1) == "r")
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
      pos = args[2],
      firstc = args[3],
      prompt = args[4],
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
    local text = M.text(args[2])
    if args[5] and s.prompt then
      text = s.prompt.text .. text
    end
    changed = put(s, "prompt", { kind = args[1], text = text })
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

function M.command(s)
  local current, highest
  for level, entry in pairs(s.levels) do
    if not highest or level > highest then
      current, highest = entry, level
    end
  end
  if not current and not s.prompt then
    return
  end
  local lines = {}
  for _, line in ipairs(s.block) do
    vim.list_extend(lines, vim.split(M.text(line), "\n", { plain = true }))
  end
  local prefix, content, pos = "", "", 0
  if current then
    prefix = current.firstc .. current.prompt .. string.rep(" ", current.indent)
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
    vim.list_extend(lines, vim.split(s.prompt.text, "\n", { plain = true }))
  end
  local before = prefix .. content:sub(1, pos)
  local cursor_lines = vim.split(before, "\n", { plain = true })
  local row = #lines + #cursor_lines
  local col = #cursor_lines[#cursor_lines]
  if current then
    vim.list_extend(lines, vim.split(prefix .. content .. " ", "\n", { plain = true }))
  else
    row, col = #lines, #lines[#lines]
    lines[#lines] = lines[#lines] .. " "
  end
  return {
    lines = lines,
    row = row,
    col = col,
    prefix = prefix,
    content = content,
    editable = current ~= nil,
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
