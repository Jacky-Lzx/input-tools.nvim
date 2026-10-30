---@class input_tools.API
local M = {}
local config = require("input-tools.config")
local model = require("input-tools.model")
local session
local last_config, last_error
local ns = vim.api.nvim_create_namespace("input-tools")

---@return boolean
function M.is_enabled()
  return session ~= nil
end

---Return the visible input window without loading the renderer.
---@return integer? win
function M.get_window()
  local view = package.loaded["input-tools.view"]
  local win = session and view and view.cursor and view.cursor.win
  if win and vim.api.nvim_win_is_valid(win) then
    return win
  end
end

---Return a copy of the current layout. Coordinates are zero-based screen cells.
---@return input_tools.Layout? layout
function M.get_layout()
  if session then
    local events = package.loaded["input-tools.events"]
    return events and events.get() or nil
  end
end

---General input API for consumers, independent of the action using the result.
---Use native input explicitly, even when another plugin owns vim.ui.input.
---The active input-tools renderer draws it; disabled instances use native UI.
---@param opts? input_tools.InputOptions
---@param on_confirm fun(value: string?)
function M.input(opts, on_confirm)
  return require("input-tools.input").input(opts, on_confirm)
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
    window = M.get_window(),
    layout = M.get_layout(),
    blink = require("input-tools.blink").status(),
    last_error = last_error,
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
    last_error = tostring(err)
    M.teardown()
    vim.schedule(function()
      vim.notify("input-tools disabled: " .. tostring(err), vim.log.levels.ERROR)
    end)
  end
end

---Enable using the last successful configuration (or defaults).
function M.enable()
  if not session then
    M.setup(last_config)
  end
  return M
end

---Release UI ownership while retaining configuration for enable().
function M.disable()
  M.teardown()
end

function M.toggle()
  if session then
    M.disable()
  else
    M.enable()
  end
end

local function commands()
  local actions = { "enable", "disable", "toggle", "status" }
  vim.api.nvim_create_user_command("InputTools", function(command)
    if command.args == "status" then
      vim.api.nvim_echo({ { vim.inspect(M.status()) } }, false, {})
    elseif vim.tbl_contains(actions, command.args) then
      M[command.args]()
    else
      error("InputTools: expected enable, disable, toggle or status")
    end
  end, {
    nargs = 1,
    desc = "Control input-tools and inspect its UI ownership",
    complete = function(lead)
      return vim.tbl_filter(function(action)
        return action:sub(1, #lead) == lead
      end, actions)
    end,
  })
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
  last_config, last_error = vim.deepcopy(resolved), nil
  commands()
  return M
end
return M
