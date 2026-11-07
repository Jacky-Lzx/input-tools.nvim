-- Explicit inspection does not configure or start the plugin.
require("input-tools.user_command").create("InputToolsInfo", function()
  vim.notify(
    vim.inspect(require("input-tools").status()),
    vim.log.levels.INFO,
    { title = "input-tools.nvim", filetype = "lua" }
  )
end, { desc = "Inspect configuration and current runtime state" })
