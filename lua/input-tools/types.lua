---@meta

---@class input_tools.WindowConfig
---@field border? 'rounded'|'single'|'double'|'solid'|'none'|''
---@field width? number Content width in cells, or fraction of editor columns in (0, 1].
---@field min_width? integer Minimum requested content width, limited by the screen.
---@field max_width? integer Maximum content width in display cells.
---@field col? integer Horizontal offset from center, clamped to the screen.
---@field title? string|false Optional upper border title.
---@field title_pos? 'left'|'center'|'right' Title alignment; defaults to center.
---@field max_height? integer Maximum context/prompt rows.
---@field bottom? integer Bottom margin in display rows.
---@field row? integer|false Zero-based top offset; false explicitly uses the bottom margin.
---@field winblend? integer Transparency, 0..100.
---@field zindex? integer Float stacking priority.

---@class input_tools.PopupmenuConfig
---@field border? 'rounded'|'single'|'double'|'solid'|'none'|''
---@field min_width? integer Minimum requested native menu width.
---@field align? 'frame'|'cursor' Command-line menu alignment; insert mode remains cursor-relative.
---@field scrollbar? boolean Show the visible range of a scrolling native menu.
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

---@class input_tools.InputOptions
---@field title? string|false Per-call upper border title; false suppresses the profile title.
---@field title_pos? 'left'|'center'|'right' Per-call alignment; defaults to the input profile's title_pos.
---@field prompt? string Inline input prompt; omit for a title-only input.
---@field default? string Initial value.
---@field completion? string Native input() completion specification.
---@field highlight? string|function Native input() highlight callback.
---@field scope? string Accepted for vim.ui.input provider compatibility; layout follows profiles.input.

---@class input_tools.ScreenPosition
---@field row integer Zero-based screen row.
---@field col integer Zero-based screen column; text origin can be negative while scrolling.

---@class input_tools.Layout
---@field win integer Visible input window ID.
---@field buf integer Input buffer ID.
---@field kind 'command'|'search'|'input'|'expression'|'confirm'
---@field editable boolean Native editing engine is awaiting input.
---@field row integer Zero-based outer frame row.
---@field col integer Zero-based outer frame column.
---@field width integer Content width in display cells.
---@field height integer Content height in display cells.
---@field outer_width integer Width including border.
---@field outer_height integer Height including border.
---@field border { top: integer, right: integer, bottom: integer, left: integer }
---@field text input_tools.ScreenPosition Native text origin, adjusted for scrolling.
---@field cursor input_tools.ScreenPosition Actual cursor position on screen.

---@class input_tools.BlinkStatus
---@field loaded boolean Whether Blink is already loaded.
---@field visible boolean Whether its completion menu is visible.
---@field adapter boolean Whether the outer-frame callback is active.

---@class input_tools.Status
---@field enabled boolean Whether input-tools owns its UI subscription.
---@field notifications boolean Whether it has an active notification-tools message handle.
---@field window? integer Visible input window.
---@field layout? input_tools.Layout Current layout snapshot.
---@field blink input_tools.BlinkStatus
---@field last_error? string Last renderer failure; cleared by successful setup.
