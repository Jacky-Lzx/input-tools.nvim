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
  if status.blink.loaded then
    if status.blink.adapter then
      vim.health.ok("Blink outer-frame adapter configured")
    else
      vim.health.info("Blink loaded; default/shared command-line position is used")
    end
  else
    vim.health.info("Blink is not loaded (no completion dependency is required)")
  end
  if status.last_error then
    vim.health.warn("Last renderer error: " .. status.last_error)
  end
  if status.window then
    vim.health.info("Visible input window: " .. status.window)
    if status.layout then
      local box = status.layout
      vim.health.info(
        ("Layout: %s at row=%d col=%d, frame=%dx%d"):format(
          box.kind,
          box.row,
          box.col,
          box.outer_width,
          box.outer_height
        )
      )
    end
  end
  if package.loaded["noice"] then
    vim.health.warn(
      "Noice is loaded; disable its command-line, message and popup-menu owners before enabling input-tools"
    )
  end
end
return M
