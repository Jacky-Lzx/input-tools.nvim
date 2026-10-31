-- Standalone consumers of input-tools: files, choices and a real LSP rename.
-- The project and all generated files live in the supplied temporary directory.
local M = {}

function M.setup(opts)
  opts = opts or {}
  local root = assert(opts.root, "a temporary demo project is required")
  local plugin = assert(opts.plugin, "plugin runtimepath is required")
  vim.opt.runtimepath:prepend(plugin)
  vim.o.termguicolors, vim.o.number, vim.o.showmode = true, true, false
  vim.o.confirm, vim.o.hidden, vim.o.swapfile = true, false, false
  vim.o.incsearch, vim.o.hlsearch, vim.o.inccommand = true, true, "split"
  vim.o.signcolumn, vim.o.laststatus = "no", 2
  vim.o.statusline = " %f %m%=%{get(g:,'input_tools_demo_status','INPUT TOOLS')}  %l:%c "
  vim.opt.fillchars:append({ eob = " " })
  vim.cmd.colorscheme("habamax")
  -- Explicit demo highlights keep screenshots consistent across Nvim releases.
  -- The plugin itself uses the user's normal colorscheme links.
  vim.api.nvim_set_hl(0, "NormalFloat", { fg = "#d4d4d4", bg = "#242424" })
  vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#89b4fa", bg = "#242424" })
  vim.api.nvim_set_hl(0, "FloatTitle", { fg = "#89b4fa", bg = "#242424", bold = true })
  vim.api.nvim_set_hl(0, "PmenuSel", { fg = "#1c1c1c", bg = "#89b4fa" })
  require("input-tools").setup({
    window = { row = 3 },
    profiles = { search = { title = " Search ", title_pos = "left" } },
  })
  -- A message subscriber makes native interactive messages external. Ordinary
  -- messages are deliberately left to the terminal; production can use notifications.
  local messages = vim.api.nvim_create_namespace("input-tools.demo.messages")
  pcall(vim.ui_detach, messages)
  vim.ui_attach(messages, { ext_messages = true }, function() end)
  vim.fn.mkdir(root, "p")
  vim.cmd.cd(root)
  vim.fn.writefile(vim.fn.readfile(plugin .. "/examples/demo/settings.lua"), "settings.lua")
  vim.cmd.edit("settings.lua")
  vim.bo.filetype = "lua"
  vim.cmd.syntax("enable")
  M.buf, M.root = vim.api.nvim_get_current_buf(), root
  local input = require("input-tools")
  vim.api.nvim_create_user_command("DemoFile", function()
    input.input({
      title = "New file",
      title_pos = "left",
      default = "notes/release notes.md",
      completion = "file",
    }, function(value)
      M.file_answer = value
      if value and value ~= "" then
        assert(not value:match("^/") and not value:find("..", 1, true), "use a relative demo path")
        vim.fn.mkdir(vim.fn.fnamemodify(value, ":h"), "p")
        vim.fn.writefile({ "# Release notes", "", "Created through the native input API." }, value)
      end
      M.file_done = true
    end)
  end, {})
  vim.api.nvim_create_user_command("DemoExport", function()
    vim.ui.select(
      { "PDF", "Markdown", "Plain text" },
      { prompt = "Export format" },
      function(value, index)
        M.export_answer, M.export_index, M.export_done = value, index, true
      end
    )
  end, {})
  vim.api.nvim_create_user_command("DemoRename", function()
    assert(M.client, "DemoRename requires LuaLS; set INPUT_TOOLS_LUA_LS")
    input.input({
      vim_mode = true,
      position = "cursor",
      width = 32,
      title = "Rename",
      title_pos = "left",
      default = vim.fn.expand("<cword>"),
    }, function(value)
      if value and value ~= "" then
        vim.lsp.buf.rename(value)
      end
      M.rename_answer, M.rename_done = value, true
    end)
  end, {})
  if opts.lsp then
    local executable = type(opts.lsp) == "string" and opts.lsp or "lua-language-server"
    M.client = vim.lsp.start({
      name = "input-tools-demo-lua",
      cmd = { executable, "--logpath=" .. root .. "/lsp-log", "--metapath=" .. root .. "/lsp-meta" },
      root_dir = root,
      settings = {
        Lua = { workspace = { checkThirdParty = false }, telemetry = { enable = false } },
      },
      on_init = function()
        vim.g.input_tools_demo_status = "LuaLS ready"
        vim.cmd.redrawstatus()
      end,
    })
    vim.api.nvim_create_autocmd("TextChanged", {
      buffer = M.buf,
      callback = function()
        local text = table.concat(vim.api.nvim_buf_get_lines(M.buf, 0, -1, false), "\n")
        local _, count = text:gsub("request_timeout_ms", "")
        if count == 2 then
          vim.g.input_tools_demo_status = "Rename applied"
          vim.cmd.redrawstatus()
        end
      end,
    })
  end
  return M
end

return M
