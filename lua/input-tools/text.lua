-- UI attribute IDs and highlight-group IDs are different namespaces.
local M = {}
local legacy, cache = nil, {}
local retained = setmetatable({}, { __mode = "k" })

function M.reset()
  cache = {}
end

local function group(chunk)
  if chunk[3] and chunk[3] ~= 0 then
    return chunk[3]
  end
  local attr = chunk[1]
  if not attr or attr == 0 then
    return
  end
  if legacy == nil then
    local ok, convert = pcall(function()
      local ffi = require("ffi")
      ffi.cdef("int syn_id2attr(int hl_id);")
      return ffi.C.syn_id2attr
    end)
    legacy = ok and convert or false
  end
  if not legacy then
    return
  end
  if cache[attr] and legacy(cache[attr]) == attr then
    return cache[attr]
  end
  -- Old UI events contain no group ID. Resolve exact existing groups through
  -- a guarded integer-only bridge; never read internal C structures.
  for name in pairs(vim.api.nvim_get_hl(0, {})) do
    local id = vim.api.nvim_get_hl_id_by_name(name)
    if legacy(id) == attr then
      cache[attr] = id
      return id
    end
  end
end

---Convert highlighted chunks to lines and byte-based, single-line ranges.
function M.lines(chunks)
  local lines, marks = { "" }, {}
  for _, chunk in ipairs(chunks) do
    local hl = retained[chunk] or group(chunk)
    retained[chunk] = hl
    for i, value in ipairs(vim.split(chunk[2], "\n", { plain = true })) do
      if i > 1 then
        lines[#lines + 1] = ""
      end
      local col = #lines[#lines]
      lines[#lines] = lines[#lines] .. value
      if hl and #value > 0 then
        marks[#marks + 1] = { row = #lines, col = col, stop = col + #value, hl = hl }
      end
    end
  end
  return lines, marks
end

---Insert/overwrite a pending native special character without shifting colors.
function M.special(chunks, pos, special)
  if not special then
    return chunks
  end
  local output, offset, emitted = {}, 0, false
  local text = require("input-tools.model").text(chunks)
  local removed = special.shift and 0 or #vim.fn.strcharpart(text:sub(pos + 1), 0, 1)
  for _, chunk in ipairs(chunks) do
    local stop = offset + #chunk[2]
    local before = math.min(#chunk[2], math.max(0, pos - offset))
    local after = math.min(#chunk[2], math.max(0, pos + removed - offset))
    if before > 0 then
      output[#output + 1] = { chunk[1], chunk[2]:sub(1, before), retained[chunk] or chunk[3] }
    end
    if not emitted and offset <= pos and pos <= stop then
      output[#output + 1] = { 0, special.char, "InputToolsPrompt" }
      emitted = true -- Emit only once, even at a chunk boundary.
    end
    if after < #chunk[2] then
      output[#output + 1] = { chunk[1], chunk[2]:sub(after + 1), retained[chunk] or chunk[3] }
    end
    offset = stop
  end
  if not emitted then
    output[#output + 1] = { 0, special.char, "InputToolsPrompt" }
  end
  return output
end
return M
