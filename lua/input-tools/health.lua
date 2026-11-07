local M = {}

function M.check()
  vim.health.start("input-tools.nvim")
  if vim.fn.has("nvim-0.10") == 0 then
    vim.health.error("Neovim 0.10+ is required", { "Upgrade Neovim" })
    return
  end
  local issues = {}
  local function problem(level, message, advice)
    issues[#issues + 1] = { level = level, message = message, advice = advice }
  end
  local plugin = package.loaded["input-tools"]
  local status = plugin and plugin.status()
  if not status or not status.enabled and not status.last_error then
    vim.health.info("Renderer inactive; input checks skipped.")
    return
  end
  if status.last_error then
    problem("warn", "Renderer failed: " .. status.last_error, { "Inspect :InputToolsInfo" })
  end
  local noice = package.loaded["noice.config"]
  local other = noice and noice.options
  if status.enabled and other and (other.cmdline or {}).enabled then
    problem(
      "warn",
      "Noice cmdline is enabled; command-line renderers conflict.",
      { "Disable Noice cmdline while input-tools owns command-line rendering" }
    )
  end

  table.sort(issues, function(a, b)
    if a.level ~= b.level then
      return a.level == "error"
    end
    return a.message < b.message
  end)
  for _, issue in ipairs(issues) do
    vim.health[issue.level](issue.message, issue.advice)
  end
  if #issues == 0 then
    vim.health.ok("Command-line renderer is attached.")
  end
  vim.health.info("Details: :InputToolsInfo")
end

return M
