# Performance measurements

Run the same driver against either the current plugin or a separate, unmodified
checkout. The benchmark starts clean Neovim processes with isolated XDG state,
attaches a 100×32 RGB UI and uses no user configuration, LSP or Blink.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/benchmark.py --runs 5 --iterations 20 --output /tmp/input-current.json
PYTHONDONTWRITEBYTECODE=1 python3 scripts/benchmark.py --root /path/to/baseline --runs 5 --iterations 20 --output /tmp/input-baseline.json
```

Select another Neovim release by changing `PATH`. The JSON records the executable,
version, module set after setup, median/p95 samples and API counts per phase.
Require/setup use Lua's monotonic clock. Other times measure the **whole phase**,
including RPC round trips, short settle waits and asynchronous close callbacks.
They are not isolated render times or a typing latency guarantee. API wrappers
also add overhead. Run on the same otherwise-idle machine; compare several runs,
not a single small timing difference. The initial Vim open occurs after native
input, so it is not a separate cold-process measurement.

Phases cover native/Vim first open, cursor-only movement, continuous typing and
repeated open/close. The operation count identifies keys or open/close cycles.
Counters distinguish buffer writes, highlight replacement, geometry changes and
explicit global redraw. A zero count means that operation was unnecessary for
that phase, not that Neovim did no rendering internally. No timing thresholds run
in CI; `tests/render_updates.py` checks the cursor-only work invariant, while the
UI tests verify visible editing, horizontal scrolling and completion behavior.

The lightweight command-line owner remains enabled at startup when paired with
notification-tools: message ownership needs a functioning command-line consumer.
Rendering, decoding, Vim input and optional Blink integration load on demand.
