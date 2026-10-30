---@class input_tools.API
local M = {}
local config = require("input-tools.config")
local model = require("input-tools.model")
local session
local ns = vim.api.nvim_create_namespace("input-tools")

---@return boolean
function M.is_enabled()
  return session ~= nil
end

---Join only an installed, configured notification-tools instance; never load it.
function M.sync_notifications()
  local s = session
  if not s or not s.config.notifications or s.syncing then
    return
  end
  if s.messages and s.messages:is_active() then
    return
  end
  s.messages = nil
  local tools = package.loaded["notification-tools"]
  if type(tools) ~= "table" or type(tools.attach_messages) ~= "function" then
    return
  end
  s.syncing = true
  local ok, result = pcall(tools.attach_messages)
  s.syncing = false
  if not ok then
    error(result)
  end
  if session == s then
    s.messages = result
  elseif result then
    result:detach()
  end
end

---@return input_tools.Status
function M.status()
  return {
    enabled = session ~= nil,
    notifications = session ~= nil and session.messages ~= nil and session.messages:is_active(),
  }
end

function M.teardown()
  local s = session
  if not s then
    return
  end
  session = nil
  if s.messages then
    s.messages:detach()
  end -- Release messages before our renderer.
  vim.ui_detach(ns)
  pcall(vim.api.nvim_del_augroup_by_id, s.group)
  if package.loaded["input-tools.view"] then
    require("input-tools.view").close()
  end
end

local function render(s, defer)
  if session ~= s then
    return
  end
  if defer or vim.in_fast_event() or s.rendering then
    if not s.pending then
      s.pending = true
      vim.schedule(function()
        s.pending = false
        render(s)
      end)
    end
    return
  end
  s.rendering = true
  local ok, err = pcall(function()
    local view = require("input-tools.view")
    if not s.highlights then
      view.highlights()
      s.highlights = true
    end
    view.render(s.model, s.config)
  end)
  s.rendering = false
  if not ok then
    -- A broken renderer must never leave the editor with an invisible cmdline.
    M.teardown()
    vim.schedule(function()
      vim.notify("input-tools disabled: " .. tostring(err), vim.log.levels.ERROR)
    end)
  end
end

---Attach command-line, prompt and optional completion UI without changing keymaps.
---@param opts? input_tools.Config
---@return input_tools.API
function M.setup(opts)
  local resolved = config.resolve(opts)
  assert(vim.fn.has("nvim-0.10") == 1, "input-tools requires Neovim >= 0.10")
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    assert(
      not ui.ext_cmdline and not (resolved.popupmenu.enabled and ui.ext_popupmenu),
      "a connected GUI already externalizes cmdline/popupmenu"
    )
  end
  M.teardown()
  local s = { config = resolved, model = model.new() }
  s.group = vim.api.nvim_create_augroup("InputTools", { clear = true })
  session = s
  local ok, err = pcall(
    vim.ui_attach,
    ns,
    { ext_cmdline = true, ext_popupmenu = resolved.popupmenu.enabled },
    function(event, ...)
      if session ~= s then
        return
      end
      local args = { ... }
      local handled, changed = model.event(s.model, event, args, resolved.popupmenu.enabled)
      if not handled then
        return
      end
      if not changed then
        return true
      end
      if event == "msg_show" then
        local prompt = s.model.prompt
        if args[1] == "return_prompt" and resolved.return_prompt == "auto" then
          s.model.prompt = nil
          vim.api.nvim_input("<CR>")
        else
          -- In old Nvim the prompt runs a blocking getchar loop, not cmdline_*.
          vim.schedule(function()
            if session == s and s.model.prompt == prompt then
              s.model.prompt = nil
              render(s)
            end
          end)
        end
      end
      -- Status events can originate inside Neovim's screen update. Defer them
      -- so creating/closing floats never re-enters the native status renderer.
      render(s, event == "msg_showmode" or event == "msg_showcmd" or event == "msg_ruler")
      return true
    end
  )
  if not ok then
    M.teardown()
    error(err)
  end
  vim.api.nvim_create_autocmd({ "VimResized", "TabEnter", "ColorScheme" }, {
    group = s.group,
    callback = function(event)
      if event.event == "ColorScheme" then
        s.highlights = false
      end
      render(s)
    end,
  })
  vim.api.nvim_create_autocmd(
    "User",
    { group = s.group, pattern = "NotificationToolsReady", callback = M.sync_notifications }
  )
  vim.api.nvim_create_autocmd("VimLeavePre", { group = s.group, callback = M.teardown })
  local synced, sync_err = pcall(M.sync_notifications)
  if not synced then
    M.teardown()
    error(sync_err)
  end
  return M
end
return M
