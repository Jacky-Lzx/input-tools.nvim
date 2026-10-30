# input-tools.nvim

A small command-line UI for Neovim. Native editing, history and completion stay
in Neovim; input-tools draws the command line, interactive prompts and menus.

Requires **Neovim 0.10+**. No runtime dependencies.

- A bottom command-line float for `:`, `/`, `?` and `input()`.
- Unicode byte-accurate cursors, horizontal scrolling, expression/register input,
  nested command lines, multiline definition context and command-line history.
- Native command-line and insert-mode completion menus with selection tracking.
- Confirmation, numbered-choice and substitution prompts when messages are externalized.
- Optional cooperation with notification-tools; ordinary messages stay out of this plugin.
- Resize/theme updates, repeated setup/teardown and restoration of the native UI.

## Install

With lazy.nvim:

```lua
{
  "Jacky-Lzx/input-tools.nvim",
  main = "input-tools",
  lazy = false,
  opts = {},
}
```

Or add this repository to `runtimepath` and call:

```lua
require("input-tools").setup()
```

`require()` alone does not attach UI or replace functions. Input-tools does not
replace `vim.ui.input`, `vim.ui.select`, `vim.notify`, editing keymaps or LSP handlers.
Neovim's default input/select implementations already use its native input engine.
Prompts go through that engine; the plugin draws them without answering confirmations.

Use `:checkhealth input-tools` to inspect the current owners.

### blink.cmp

Command-line completion menus follow the input window automatically. Input-tools
publishes the `vim.g.ui_cmdline_pos` screen-position convention consumed by
Blink's default `completion.menu.cmdline_position`; no Blink dependency, patch
or early loading is needed. Keep Blink's command-line menu enabled as usual.
Custom `cmdline_position` callbacks must honor this position to follow the UI.
The position updates with layout/scrolling and is released when input closes;
teardown restores the previous value only while input-tools still owns it.
When layout changes, an already-loaded Blink menu is repositioned on the next
event-loop turn. This guarded adapter uses Blink's internal menu positioning
function because it has no public reposition-only API; it never loads or patches
Blink and leaves completion sources, selection and keymaps with Blink.

## Pair with notification-tools

Enable native-message capture in notification-tools:

```lua
require("notification-tools").setup({
  messages = { enabled = true },
})
require("input-tools").setup()
```

The plugins have separate jobs:

- **input-tools** owns command-line input, prompts, completion and externalized status widgets.
- **notification-tools** owns notifications, non-interactive native messages, progress and history.

Input-tools calls `attach_messages()` only after its renderer is attached, then
releases that handle **before** detaching its renderer. Without notification-tools,
it works alone and native messages retain their original display. It never loads
notification-tools or changes that plugin's configuration. If `messages.enabled`
is false, there is no message handoff.

Both loading orders work with a notification-tools version providing the
`NotificationToolsReady` User event. Reconfiguring notification-tools triggers a
fresh handoff; reconfiguring input-tools releases and reacquires its handle. For
older notification-tools versions with `attach_messages()` but no ready event,
load notifications first, or call `require("input-tools").sync_notifications()`
after its setup. See [examples/lazy.lua](examples/lazy.lua).

Disable competing external UI owners, including Noice's command-line/messages/
popup-menu UI. A GUI already externalizing the command line or an enabled popup
menu is detected before setup changes the working instance. Lua UI subscriptions
cannot currently be enumerated, so other Lua owners must be disabled explicitly.

## Configuration

```lua
require("input-tools").setup({
  notifications = true, -- Join an already loaded, opted-in notification-tools.
  return_prompt = "auto", -- "show" preserves the native hit-enter interaction.
  status = true, -- Mode, showcmd and ruler widgets when messages are externalized.
  window = {
    border = "rounded", -- single, double, solid, none and "" also supported.
    max_width = 80,
    max_height = 8,
    bottom = 1,
    -- row = 3, -- Optional zero-based top offset; overrides bottom placement.
    winblend = 0,
    zindex = 250,
  },
  popupmenu = {
    enabled = true, -- Applies to native command-line AND insert-mode completion.
    max_height = 8,
    max_width = 60,
  },
})
```

The command line is centered near the bottom by default. Set `window.row = 3`
for a top-centered command palette like Noice's `command_palette` preset. The
position is clamped on small screens. Completion menus appear below a top input
or above a bottom input, falling back to available space without overlapping it.
Long input scrolls horizontally
with the cursor; multiline prompts/context use at most `max_height` rows. Menu
selection, acceptance and cancellation use Neovim's existing keys and settings.
Use `wildoptions=pum` and `wildmode=full` if you want the native command-line
completion engine to emit a popup menu. Input-tools does not change these options.
With popup-menu capture disabled, Neovim/another owner controls menu display.

Hit-enter prompts are acknowledged automatically by default; this avoids an
extra pause for messages already shown in notification-tools. Set
`return_prompt="show"` to wait for the user's Enter key. Confirmations, numbered
choices and substitution decisions always wait for the user's answer.
On older Neovim, unnamed messages emitted in a native `r`/`rm` prompt state are
treated as interactive too; this keeps `inputlist()` choices visible while the
editor waits for a number.

Float colors use `InputToolsNormal`, `InputToolsBorder`, `InputToolsPrompt`,
`InputToolsMenu`, `InputToolsSelection` and `InputToolsStatus`. They link to native
theme groups; override them with `nvim_set_hl`, including from a `ColorScheme`
autocmd. The UI uses plain text and prompt accents; it does not add a syntax
parser or a completion source. Its terminal cursor uses Neovim's experimental
`nvim__redraw` cursor support, available in the supported versions.

## API and lifecycle

```lua
local input = require("input-tools")
input.setup(opts)          -- Validate, replace the old instance, then attach.
input.is_enabled()         -- Whether our UI subscription is active.
input.status()             -- { enabled = boolean, notifications = boolean }
input.sync_notifications() -- Retry the optional handoff after producer setup.
input.teardown()           -- Release messages, UI subscription, floats/autocmds.
```

No idle timer runs. UI events update the native input state and redraw the
non-focusable floats; repeated identical events do not schedule redraw loops.
Fast-event work is deferred. Rendering failures disable the UI and release the
message handoff, restoring native input rather than leaving an invisible prompt.
Invalid configuration is rejected before replacing a working instance.

The UI subscription uses Neovim's experimental `vim.ui_attach` protocol. A
consumer that replaces input-tools should call `teardown()` first. This plugin
does not capture ordinary output, implement a message history, or manage LSP UI.

## Development

```sh
sh tests/run.sh
NOTIFICATION_TOOLS_ROOT=../notification-tools.nvim sh tests/run.sh
INPUT_TOOLS_BLINK_ROOT=/path/to/blink.cmp sh tests/run.sh
python3 scripts/check_types.py
```

Runtime tests require Neovim, Python 3 and StyLua. Optional type checks require
LuaLS. UI tests attach a real RPC UI, drive the native editing engine and inspect
rendered grid/cursor events. Integration tests cover native-message capture,
visible interactive prompts, both loading orders, reconfiguration and teardown.
They do not depend on an installed Neovim configuration.

## License

MIT
