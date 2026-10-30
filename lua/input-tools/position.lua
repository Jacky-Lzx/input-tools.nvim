-- Keep the source buffer position separate from the floating input cursor.
local M = {}
local api = vim.api

function M.capture()
  local win = api.nvim_get_current_win()
  local cursor = api.nvim_win_get_cursor(win)
  return { win = win, buf = api.nvim_win_get_buf(win), line = cursor[1], col = cursor[2] }
end

function M.point(anchor)
  if
    not anchor
    or not api.nvim_win_is_valid(anchor.win)
    or api.nvim_win_get_buf(anchor.win) ~= anchor.buf
    or api.nvim_win_get_tabpage(anchor.win) ~= api.nvim_get_current_tabpage()
    or anchor.line > api.nvim_buf_line_count(anchor.buf)
  then
    return
  end
  local point = vim.fn.screenpos(anchor.win, anchor.line, anchor.col + 1)
  if point.row > 0 and point.col > 0 then
    return { row = point.row - 1, col = (point.curscol or point.col) - 1 }
  end
end

---Place an outer frame below the source cursor, flipping above if necessary.
function M.place(anchor, width, height, columns, rows)
  local point = M.point(anchor)
  if not point then
    return
  end
  local below = rows - point.row - 1
  local above = point.row
  local row
  if below >= height or below >= above then
    row = point.row + 1
  else
    row = point.row - height
  end
  return math.max(0, math.min(row, rows - height)),
    math.max(0, math.min(point.col, columns - width)),
    point
end

return M
