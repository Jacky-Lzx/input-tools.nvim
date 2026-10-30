-- Per-call presentation is tied to the native input level, not global config.
local M = {}
local stack = {}

---Snapshot presentation only for this call's native input, not nested expressions.
function M.context(args)
  local request = stack[#stack]
  if
    request
    and args[3] == ""
    and (args[4] or "") == request.prompt
    and (request.level == nil or request.level == args[6])
  then
    request.level = args[6]
    return {
      width = request.width,
      position = request.position,
      anchor = request.anchor,
      title = request.title,
      title_pos = request.title_pos,
      hide_prompt = request.hide_prompt,
    }
  end
end

function M.input(opts, on_confirm, config)
  assert(opts == nil or type(opts) == "table", "input options must be a table")
  assert(type(on_confirm) == "function", "on_confirm must be a function")
  opts = opts or {}
  assert(
    opts.title == nil or opts.title == false or type(opts.title) == "string",
    "title must be a string or false"
  )
  assert(
    opts.title_pos == nil or vim.tbl_contains({ "left", "center", "right" }, opts.title_pos),
    "title_pos must be left, center or right"
  )
  assert(
    opts.position == nil or vim.tbl_contains({ "editor", "cursor" }, opts.position),
    "position must be editor or cursor"
  )
  local width = opts.width
  assert(
    width == nil
      or type(width) == "number"
        and width > 0
        and width < math.huge
        and (width <= 1 or width == math.floor(width)),
    "width must be a positive integer or a fraction in (0, 1]"
  )
  assert(opts.vim_mode == nil or type(opts.vim_mode) == "boolean", "vim_mode must be a boolean")
  if opts.vim_mode then
    return require("input-tools.modal").open(opts, on_confirm, config)
  end
  local native = { cancelreturn = vim.NIL }
  for _, key in ipairs({ "prompt", "default", "completion", "highlight" }) do
    if opts[key] ~= nil then
      native[key] = opts[key]
    end
  end
  local title_only = type(opts.title) == "string"
    and opts.title ~= ""
    and (native.prompt == nil or native.prompt == "")
  if title_only then
    native.prompt = opts.title .. ": " -- Readable if the renderer is disabled/fails.
  end
  local request = {
    width = width,
    position = opts.position,
    anchor = opts.position == "cursor" and require("input-tools.position").capture() or nil,
    title = opts.title,
    title_pos = opts.title_pos,
    prompt = native.prompt or "",
    hide_prompt = title_only,
  }
  stack[#stack + 1] = request
  local ok, value = pcall(vim.fn.input, native)
  table.remove(stack)
  if not ok or value == vim.NIL then
    on_confirm(nil)
  else
    on_confirm(value)
  end
end

return M
