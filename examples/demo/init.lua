-- Run with scripts/record-demo.sh for an isolated real-terminal demonstration.
local plugin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
_G.demo = dofile(plugin .. "/examples/demo.lua").setup({
  plugin = plugin,
  root = assert(vim.env.INPUT_TOOLS_DEMO_ROOT),
  lsp = vim.env.INPUT_TOOLS_LUA_LS,
})
vim.api.nvim_create_user_command("DemoVerify", function()
  local text = table.concat(vim.api.nvim_buf_get_lines(demo.buf, 0, -1, false), "\n")
  assert(demo.export_answer == "Markdown" and demo.export_index == 2)
  assert(vim.fn.filereadable(demo.root .. "/notes/release notes.md") == 1)
  assert(demo.rename_answer == "request_timeout_ms")
  local _, count = text:gsub("request_timeout_ms", "")
  assert(count == 2, "LuaLS must rename both field occurrences")
  vim.fn.writefile({
    "Real terminal workflow passed: native search/substitute/select/input, LuaLS rename, quit/cancel.",
  }, assert(vim.env.INPUT_TOOLS_DEMO_RESULT))
end, {})
