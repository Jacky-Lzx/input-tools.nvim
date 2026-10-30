---@meta

---@class input_tools.WindowConfig
---@field border? 'rounded'|'single'|'double'|'solid'|'none'|''
---@field width? number Content width in cells, or fraction of editor columns in (0, 1].
---@field min_width? integer Minimum requested content width, limited by the screen.
---@field max_width? integer Maximum content width in display cells.
---@field col? integer Horizontal offset from center, clamped to the screen.
---@field title? string|false Optional centered border title.
---@field max_height? integer Maximum context/prompt rows.
---@field bottom? integer Bottom margin in display rows.
---@field row? integer Zero-based top offset; omit to use the bottom margin.
---@field winblend? integer Transparency, 0..100.
---@field zindex? integer Float stacking priority.

---@class input_tools.PopupmenuConfig
---@field enabled? boolean Own the native command-line and insert-mode popup menus.
---@field max_height? integer Maximum visible completion items.
---@field max_width? integer Maximum menu content width in display cells.

---@class input_tools.Profiles
---@field command? input_tools.WindowConfig Colon commands.
---@field search? input_tools.WindowConfig Forward and backward search.
---@field input? input_tools.WindowConfig Native input() prompts.
---@field expression? input_tools.WindowConfig Nested expression input.
---@field confirm? input_tools.WindowConfig Interactive confirmation prompts.

---@class input_tools.Config
---@field notifications? boolean Join an already loaded notification-tools instance; defaults to true.
---@field return_prompt? 'auto'|'show' Acknowledge hit-enter automatically, or display it until answered.
---@field status? boolean Display externalized mode/showcmd/ruler status; defaults to true.
---@field window? input_tools.WindowConfig
---@field profiles? input_tools.Profiles Overrides merged over window for each input kind.
---@field popupmenu? input_tools.PopupmenuConfig

---@class input_tools.Status
---@field enabled boolean Whether input-tools owns its UI subscription.
---@field notifications boolean Whether it has an active notification-tools message handle.
