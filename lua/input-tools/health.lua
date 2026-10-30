local M = {}
function M.check()
  vim.health.start("input-tools.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim >= 0.10 is required")
  end
  local status = require("input-tools").status()
  if status.enabled then
    vim.health.ok("Command-line renderer attached")
  else
    vim.health.info("Renderer is disabled; call require('input-tools').setup()")
  end
  if status.notifications then
    vim.health.ok("Native messages handed to notification-tools")
  else
    vim.health.info("No message handoff; native messages stay with their current owner")
  end
  if package.loaded["noice"] then
    vim.health.warn(
      "Noice is loaded; disable its command-line, message and popup-menu owners before enabling input-tools"
    )
  end
end
return M
