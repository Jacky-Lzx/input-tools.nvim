#!/bin/sh
# Capture an actual Neovim TUI with VHS/ttyd; never source the user's config.
set -eu
plugin_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for tool in nvim vhs ttyd ffmpeg python3 lua-language-server; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
demo_tmp=$(mktemp -d "${TMPDIR:-/tmp}/input-tools-record.XXXXXX")
trap 'rm -rf "$demo_tmp"' EXIT HUP INT TERM
export INPUT_TOOLS_DEMO_ROOT="$demo_tmp/project"
export INPUT_TOOLS_DEMO_RESULT="$demo_tmp/result.txt"
export INPUT_TOOLS_LUA_LS="${INPUT_TOOLS_LUA_LS:-$(command -v lua-language-server)}"
export XDG_CACHE_HOME="$demo_tmp/cache" XDG_STATE_HOME="$demo_tmp/state" XDG_DATA_HOME="$demo_tmp/data"
export NVIM_LOG_FILE="$demo_tmp/nvim.log" PYTHONDONTWRITEBYTECODE=1
python3 - "$plugin_root/docs/demo.tape" "$demo_tmp/workflow.tape" "$demo_tmp/workflow" <<'PY'
from pathlib import Path
import sys
source, target, recording = map(Path, sys.argv[1:])
target.write_text(source.read_text().replace('@RECORDING@', str(recording)))
PY
cd "$plugin_root"
mkdir -p docs/screenshots
vhs "$demo_tmp/workflow.tape"
test -f "$INPUT_TOOLS_DEMO_RESULT"
cat "$INPUT_TOOLS_DEMO_RESULT"
