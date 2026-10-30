#!/usr/bin/env python3
"""Isolated RPC-UI benchmark, using the same driver for old/new plugin roots."""
import argparse
import json
import math
import os
from pathlib import Path
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tests'))
import rpc

COUNTERS = ('redraw', 'nvim_buf_set_lines', 'nvim_buf_clear_namespace',
            'nvim_buf_set_extmark', 'nvim_win_set_config')


def trial(root, iterations):
    # Capture's clean --embed subprocess runs in the chosen source tree.
    rpc.ROOT = root
    with tempfile.TemporaryDirectory(prefix='input-tools-benchmark-') as temp:
        env = dict(os.environ, XDG_STATE_HOME=temp + '/state',
                   XDG_CACHE_HOME=temp + '/cache', XDG_DATA_HOME=temp + '/data',
                   NVIM_LOG_FILE=temp + '/nvim.log')
        ui = rpc.Capture(env)

        def lua(code):
            return ui.request('nvim_exec_lua', [code, []])

        def keys(value, settle=3):
            ui.request('nvim_input', [value])
            lua('vim.wait(' + str(settle) + ')')

        def until(expression):
            deadline = time.monotonic() + 2
            while not lua('return ' + expression):
                if time.monotonic() > deadline:
                    raise AssertionError('UI did not settle: ' + expression)
                lua('vim.wait(3)')

        def open_modal(default="'name'"):
            keys(":lua input.input({vim_mode=true,default=" + default + "},function()end)<CR>", 3)
            until("input.get_layout() and input.get_layout().vim_mode and vim.api.nvim_get_mode().mode:sub(1,1)=='i'")

        def close_modal():
            keys('<C-c>')
            until("input.get_window()==nil and vim.api.nvim_get_mode().mode=='n'")

        def phase(name, operations, action):
            lua('counts={}')
            started = time.perf_counter_ns()
            action()
            elapsed = (time.perf_counter_ns() - started) / 1e6
            counts = lua('return counts') or {}
            result[name] = {'ms': elapsed, 'operations': operations,
                            'counts': {key: counts.get(key, 0) for key in COUNTERS}}

        def repeat(count, fn):
            for i in range(count):
                fn(i)

        result = {}
        try:
            ui.request('nvim_ui_attach', [100, 32, {'rgb': True, 'ext_linegrid': True}])
            setup = lua("local clock=(vim.uv or vim.loop).hrtime; local t=clock(); "
                        "vim.opt.rtp:prepend(vim.fn.getcwd()); input=require('input-tools'); "
                        "local loaded=clock(); input.setup({window={row=3,width=32}}); "
                        "local done=clock(); local modules={}; for name in pairs(package.loaded) do "
                        "if name:match('^input%-tools') then modules[#modules+1]=name end end; table.sort(modules); "
                        "return {require_ms=(loaded-t)/1e6,setup_ms=(done-loaded)/1e6,modules=modules}")
            result['require'] = {'ms': setup['require_ms'], 'operations': 1}
            result['setup'] = {'ms': setup['setup_ms'], 'operations': 1}
            lua("counts={}; local redraw=vim.cmd.redraw; vim.cmd.redraw=function(...) counts.redraw=(counts.redraw or 0)+1; return redraw(...) end; "
                "for _,name in ipairs({'nvim_buf_set_lines','nvim_buf_clear_namespace','nvim_buf_set_extmark','nvim_win_set_config'}) do "
                "local original=vim.api[name]; vim.api[name]=function(...) counts[name]=(counts[name] or 0)+1; return original(...) end end")
            phase('native_first_open', 1, lambda: keys(":echo '" + '你好' * 40 + "'"))
            assert lua('return input.get_window() ~= nil')
            phase('native_cursor', iterations,
                  lambda: repeat(iterations, lambda i: keys('<Left>' if i % 2 == 0 else '<Right>')))
            phase('native_typing', iterations, lambda: repeat(iterations, lambda _: keys('a')))
            keys('<Esc>')
            phase('native_reopen_close', iterations,
                  lambda: repeat(iterations, lambda _: (keys(':echo 1'), keys('<Esc>'))))
            phase('vim_first_open', 1,
                  lambda: open_modal("string.rep('你好',40)"))
            assert lua("return vim.bo.filetype=='input-tools-input'")
            keys('<Esc>')
            phase('vim_cursor', iterations,
                  lambda: repeat(iterations, lambda i: keys('h' if i % 2 == 0 else 'l')))
            keys('A')
            phase('vim_typing', iterations, lambda: repeat(iterations, lambda _: keys('a')))
            close_modal()
            phase('vim_reopen_close', iterations,
                  lambda: repeat(iterations, lambda _: (open_modal(), close_modal())))
            assert lua('return input.get_window()==nil')
            return result, setup['modules']
        finally:
            ui.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT, help='Plugin root to load (may be an older checkout)')
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--iterations', type=int, default=20)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.runs < 1 or args.iterations < 2:
        parser.error('runs must be >=1 and iterations >=2')
    def timeout(*_):
        raise TimeoutError('benchmark timed out')
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(max(60, args.runs * args.iterations * 2))
    runs, modules = [], []
    for _ in range(args.runs):
        result, loaded = trial(args.root.resolve(), args.iterations)
        runs.append(result)
        modules.append(loaded)
    summary = {}
    for name in runs[0]:
        times = sorted(run[name]['ms'] for run in runs)
        record = {'operations_per_run': runs[0][name]['operations'],
                  'median_ms': statistics.median(times),
                  'p95_ms': times[math.ceil(len(times) * .95) - 1],
                  'samples_ms': times}
        if 'counts' in runs[0][name]:
            record['median_api_calls'] = {key: statistics.median(run[name]['counts'][key] for run in runs) for key in COUNTERS}
        summary[name] = record
    report = {'plugin_root': str(args.root.resolve()), 'nvim': shutil.which('nvim'),
              'version': subprocess.check_output(['nvim', '--version'], text=True).splitlines()[0],
              'runs': args.runs, 'screen': [100, 32], 'startup_modules': modules,
              'timing': 'require/setup: Lua hrtime; UI phases: total wall time including RPC, settle waits and callback delays. No Blink, LSP or user config. API wrappers add overhead.',
              'phases': summary}
    encoded = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.write_text(encoded)
    else:
        print(encoded, end='')


if __name__ == '__main__':
    main()
