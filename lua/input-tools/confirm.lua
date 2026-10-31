-- Presentation only. Neovim still owns the question, accelerators and answer.
local M = {}

local function choices(line)
  local label = line:match("^(.-):%s*$")
  if not label then
    return
  end
  local parts, has_default = {}, false
  for part in label:gmatch("[^,]+") do
    part = vim.trim(part)
    local first, last = part:find("%[[^%]]+%]")
    local default = first ~= nil
    if not first then
      first, last = part:find("%([^%)]+%)")
    end
    if not first then
      return -- Unknown/localized layout: display it verbatim.
    end
    parts[#parts + 1] = { text = part, first = first, last = last, default = default }
    has_default = has_default or default
  end
  if #parts < 2 or not has_default then
    return
  end
  local text, marks, cursor = "", {}, nil
  for index, part in ipairs(parts) do
    if index > 1 then
      text = text .. "  "
    end
    local start = #text
    text = text .. " " .. part.text .. " "
    marks[#marks + 1] = {
      col = start,
      stop = #text,
      hl = part.default and "InputToolsConfirmDefault" or "InputToolsConfirmChoice",
    }
    if part.default then
      cursor = start + 1 + part.first
    else
      marks[#marks + 1] =
        { col = start + part.first, stop = start + 1 + part.last, hl = "InputToolsConfirmKey" }
    end
  end
  return { text = text, marks = marks, cursor = cursor }
end

function M.format(command, window)
  local output = vim.tbl_extend("force", {}, command)
  output.lines, output.highlights = {}, {}
  local columns, rows = require("input-tools.layout").screen()
  local padding = columns >= 20 and 2 or 1
  local vertical = rows >= 10 and window.max_height >= 6 and 1 or 0
  local pad, mapped = string.rep(" ", padding), {}
  local buttons = command.content == "" and choices(command.lines[command.row])
  local first = 1
  while first < command.row and vim.trim(command.lines[first]) == "" do
    first = first + 1
  end
  if vertical > 0 then
    output.lines[1] = ""
  end
  for row = first, #command.lines do
    if
      buttons
      and row == command.row
      and row > first
      and vim.trim(command.lines[row - 1]) ~= ""
    then
      output.lines[#output.lines + 1] = ""
    end
    mapped[row] = #output.lines + 1
    output.lines[#output.lines + 1] = pad
      .. (buttons and row == command.row and buttons.text or command.lines[row])
      .. pad
  end
  if vertical > 0 then
    output.lines[#output.lines + 1] = ""
  end
  local question = vim.api.nvim_get_hl_id_by_name("Question")
  for _, mark in ipairs(command.highlights) do
    if mapped[mark.row] and not (buttons and mark.row == command.row) then
      output.highlights[#output.highlights + 1] = {
        row = mapped[mark.row],
        col = mark.col + padding,
        stop = mark.stop + padding,
        hl = (mark.hl == question or mark.hl == "InputToolsPrompt") and "InputToolsConfirmText"
          or mark.hl,
      }
    end
  end
  output.row = mapped[command.row]
  output.col = padding + (buttons and buttons.cursor or command.col)
  output.prefix = pad .. command.prefix:gsub("\n", "\n" .. pad)
  if buttons then
    output.prefix = pad .. buttons.text
    for _, mark in ipairs(buttons.marks) do
      output.highlights[#output.highlights + 1] =
        { row = output.row, col = padding + mark.col, stop = padding + mark.stop, hl = mark.hl }
    end
  end
  return output
end

function M.width(command, window)
  if window.width then
    return window -- Explicit profile/base widths retain their meaning.
  end
  local natural = 1
  for _, line in ipairs(command.lines) do
    natural = math.max(natural, vim.fn.strdisplaywidth(line))
  end
  return vim.tbl_extend("force", {}, window, { width = math.max(window.min_width, natural) })
end

return M
