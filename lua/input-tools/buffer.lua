-- Per-buffer completion/highlighting for editable Vim-mode inputs.
local M = {}
local api = vim.api
local inputs = {}
local ns = api.nvim_create_namespace("input-tools.input-highlight")
local completefunc = "v:lua.require'input-tools.buffer'.complete"

local function warn(input, message)
  if input.warned then
    return
  end
  input.warned = true
  vim.schedule(function()
    if inputs[input.buf] == input then
      vim.notify("input-tools: " .. tostring(message), vim.log.levels.WARN)
    end
  end)
end

local function invoke(callback, ...)
  if type(callback) == "function" then
    return callback(...)
  end
  local name = callback:match("^v:lua%.(.+)$")
  if name then
    return vim.fn.luaeval(name .. "(unpack(_A))", { ... })
  end
  return vim.fn.call(callback, { ... })
end

local function offset(lines, row, col)
  local result = col
  for i = 1, row - 1 do
    result = result + #lines[i] + 1
  end
  return result
end

local function point(lines, byte)
  for row, line in ipairs(lines) do
    if byte <= #line then
      return row - 1, byte
    end
    byte = byte - #line - 1
  end
end

local function boundary(text, byte)
  local char = text:byte(byte + 1)
  return not char or char < 128 or char >= 192
end

function M.refresh(buf, force)
  local input = inputs[buf]
  if not input or not input.opts.highlight or not api.nvim_buf_is_valid(buf) then
    return
  end
  local tick = api.nvim_buf_get_changedtick(buf)
  if not force and tick == input.tick then
    return
  end
  input.tick = tick
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  if not force and input.text == text then
    return
  end
  input.text = text
  local ok, marks = pcall(function()
    local result = invoke(input.opts.highlight, text)
    assert(type(result) == "table", "highlight callback must return a list")
    local previous = 0
    for _, span in ipairs(result) do
      local first, last, group = unpack(span)
      assert(
        type(first) == "number"
          and type(last) == "number"
          and first == math.floor(first)
          and last == math.floor(last)
          and first >= previous
          and last > first
          and last <= #text
          and boundary(text, first)
          and boundary(text, last)
          and type(group) == "string"
          and group ~= "",
        "invalid highlight byte range or group"
      )
      previous = last
    end
    return result
  end)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not ok then
    warn(input, marks)
    return
  end
  for _, span in ipairs(marks) do
    local row, col = point(lines, span[1])
    local end_row, end_col = point(lines, span[2])
    api.nvim_buf_set_extmark(
      buf,
      ns,
      row,
      col,
      { end_row = end_row, end_col = end_col, hl_group = span[3] }
    )
  end
end

local function query(input)
  local cursor = api.nvim_win_get_cursor(0)
  local lines = api.nvim_buf_get_lines(input.buf, 0, -1, false)
  local before = lines[cursor[1]]:sub(1, cursor[2])
  local start = 0
  -- Separate arguments at unescaped whitespace; keep paths containing '\ '.
  for i = 1, #before do
    if before:sub(i, i):match("%s") then
      local slash, j = 0, i - 1
      while j > 0 and before:sub(j, j) == "\\" do
        slash, j = slash + 1, j - 1
      end
      if slash % 2 == 0 then
        start = i
      end
    end
  end
  return start,
    before:sub(start + 1),
    table.concat(lines, "\n"),
    offset(lines, cursor[1], cursor[2])
end

function M.complete(findstart, base)
  local input = inputs[api.nvim_get_current_buf()]
  if not input or not input.opts.completion then
    return findstart == 1 and -3 or {}
  end
  local start, lead, text, cursor = query(input)
  if findstart == 1 then
    input.query = { start = start, lead = lead, text = text, cursor = cursor }
    return start
  end
  -- Vim removes the typed base while invoking the second completefunc phase;
  -- Blink leaves it in place. Preserve the original full input for both callers.
  if input.query then
    local saved = input.query
    start, lead = saved.start, base
    cursor = saved.cursor - #saved.lead + #base
    text = saved.text:sub(1, saved.cursor - #saved.lead) .. base .. saved.text:sub(saved.cursor + 1)
  end
  local ok, matches = pcall(function()
    local kind, callback = input.opts.completion:match("^(custom[^,]*),(.+)$")
    if kind == "custom" or kind == "customlist" then
      local result = invoke(callback, lead, text, cursor)
      if kind == "custom" then
        assert(type(result) == "string", "custom completion must return a string")
        result = vim.split(result, "\n", { trimempty = true })
        result = vim.tbl_filter(function(value)
          return value:sub(1, #lead) == lead
        end, result)
      end
      return result
    end
    local pattern = input.opts.completion == "cmdline" and text:sub(1, cursor) or lead
    return vim.fn.getcompletion(pattern, input.opts.completion, 1)
  end)
  if not ok or type(matches) ~= "table" then
    warn(input, ok and "completion must return a list" or matches)
    return {}
  end
  local words = {}
  for _, value in ipairs(matches) do
    if type(value) == "string" and value ~= "" then
      words[#words + 1] = { word = value, equal = 1 }
    end
  end
  return words
end

function M.attach(buf, opts)
  inputs[buf] = { buf = buf, opts = opts }
  if opts.completion and opts.completion ~= "" then
    vim.bo[buf].completefunc = completefunc
    vim.b[buf].input_tools_completion = true
    local blink = package.loaded["input-tools.blink"]
    vim.b[buf].completion = blink and blink.buffer_enabled() or false
  end
  M.refresh(buf)
end

function M.detach(buf)
  inputs[buf] = nil
end

return M
