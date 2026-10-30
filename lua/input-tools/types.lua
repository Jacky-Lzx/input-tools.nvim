---@meta

---@class input_tools.WindowConfig
---@field border? 'rounded'|'single'|'double'|'solid'|'none'|''
---@field max_width? integer Maximum content width in display cells.
---@field max_height? integer Maximum context/prompt rows.
---@field bottom? integer Bottom margin in display rows.
---@field winblend? integer Transparency, 0..100.
---@field zindex? integer Float stacking priority.

---@class input_tools.PopupmenuConfig
---@field enabled? boolean Own the native command-line and insert-mode popup menus.
---@field max_height? integer Maximum visible completion items.
---@field max_width? integer Maximum menu content width in display cells.

---@class input_tools.Config
---@field notifications? boolean Join an already loaded notification-tools instance; defaults to true.
---@field return_prompt? 'auto'|'show' Acknowledge hit-enter automatically, or display it until answered.
---@field status? boolean Display externalized mode/showcmd/ruler status; defaults to true.
---@field window? input_tools.WindowConfig
---@field popupmenu? input_tools.PopupmenuConfig

---@class input_tools.Status
---@field enabled boolean Whether input-tools owns its UI subscription.
---@field notifications boolean Whether it has an active notification-tools message handle.
