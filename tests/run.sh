#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_root=$(mktemp -d "${TMPDIR:-/tmp}/input-tools-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
export XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" XDG_DATA_HOME="$test_root/data"
export NVIM_LOG_FILE="$test_root/nvim.log" PYTHONDONTWRITEBYTECODE=1
nvim --headless -n -u NONE -i NONE --noplugin -l tests/lazy.lua
nvim --headless -n -u NONE -i NONE --noplugin -l tests/core.lua
nvim --headless -n -u NONE -i NONE --noplugin -l tests/features.lua
nvim --headless -n -u NONE -i NONE --noplugin -l tests/events.lua
python3 tests/ui.py
python3 tests/confirm_ui.py
python3 tests/cursor_ui.py
python3 tests/modal_ui.py
python3 tests/buffer_ui.py
python3 tests/render_updates.py
if [ -n "${INPUT_TOOLS_BLINK_ROOT:-}" ]; then
  python3 tests/blink_ui.py
  python3 tests/blink_lazy_ui.py
fi
stylua --check lua tests examples
