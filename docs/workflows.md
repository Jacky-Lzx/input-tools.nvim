# Everyday input workflows

`tests/workflow_ui.py` edits a real `settings.lua` in a temporary project. It
attaches a real Neovim RGB UI and types keys through the native editing engines.
It uses the same consumers as the terminal demonstration in `examples/demo.lua`.

| Workflow | Interaction and checks |
| --- | --- |
| Search | `/timeout_ms` and `?project`; cursor moves to the matches without editing the file. |
| Expression register | `<C-r>=40*2<CR>` inside an Ex command; the result is inserted and the outer command resumes. |
| Confirm replacements | `:%s/timeout_ms/delay_ms/gc`; accept the first match, skip the next, inspect the resulting file and undo. |
| Export selection | Default `vim.ui.select()` / `inputlist()`; title and all choices stay visible after waiting and after `2<BS>2`, selection returns Markdown, and empty input cancels. |
| File creation | Native input API with `completion='file'` and a space-containing path; cancellation creates nothing, confirmation creates the expected file. |
| Secret entry | Native `inputsecret()`; only stars reach the visible UI and captured redraw events, and the test token stays out of input history. |
| Semantic rename | Optional real LuaLS: the general Vim-mode input collects a name beside the cursor, then native LSP changes both field references. No LSP response or edit is mocked. |

Native editing/history/completion and generic Vim input lifecycle also have their
existing focused UI tests. `tests/confirm_ui.py` covers unsaved-file quit, cancel,
discard and default-save behavior. All fixtures and writes are temporary.

## Run the checks

```sh
sh tests/run.sh
# Optional real language-server workflow:
INPUT_TOOLS_LUA_LS="$(command -v lua-language-server)" python3 tests/workflow_ui.py
```

The default workflow has no external language-server or theme dependency. Test
both the minimum supported Neovim and the current release by changing `PATH`.

The workflow caught two selection-display issues: newer Neovim can use an ordinary
command-line mode for a numbered prompt, and Neovim 0.10 echoes digits/backspaces
as separate unnamed messages. The renderer now retains the preceding choices in
both cases. Assertions inspect the stable window after scheduled work, rather
than merely looking for a title that flashed in an earlier frame.

## Reproduce the README screenshots

```sh
sh scripts/record-demo.sh
```

Recording requires Neovim, LuaLS, VHS, ttyd, ffmpeg, Python 3 and an available
Chromium browser. The tape requests Cascadia Mono; install that font for the same
appearance. It launches an actual Neovim TUI in VHS's terminal renderer, using an
isolated startup file, temporary project and XDG directories. It does not load or
modify the user's Neovim configuration.

The six PNGs in `docs/screenshots` were recorded on Neovim 0.12.6 with the built-in
`habamax` colorscheme and explicit float highlights from `examples/demo.lua`.
They are terminal screenshots, not reconstructions of the RPC grid. Each capture
waits for its prompt and holds the state after taking the screenshot, so video
capture latency cannot select the already-closed window. The final command
checks the selected format, created file and both real LuaLS rename edits.
The intermediate GIF and project are removed after verification.

The demo uses Neovim's default `vim.ui.select`, the explicit input-tools API for
file/rename input, and the native LSP client for edits. It does not replace
`vim.ui.input` or register a production LSP integration inside the plugin.
