#!/usr/bin/env python3
"""Cursor-only editing must preserve content/marks without a whole-screen redraw."""
import os
import signal
from rpc import Capture


def main():
    def timeout(*_):
        raise TimeoutError("render update test timed out")
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(15)
    ui = Capture(os.environ.copy())

    def lua(code):
        return ui.request("nvim_exec_lua", [code, []])

    def keys(value):
        ui.request("nvim_input", [value])
        lua("vim.wait(15)")

    try:
        ui.request("nvim_ui_attach", [100, 32, {"rgb": True, "ext_linegrid": True}])
        lua("vim.opt.rtp:prepend(vim.fn.getcwd()); input=require('input-tools'); input.setup({window={row=3,width=32}}); "
            "counts={}; local redraw=vim.cmd.redraw; vim.cmd.redraw=function(...) counts.redraw=(counts.redraw or 0)+1; return redraw(...) end; "
            "for _,name in ipairs({'nvim_buf_set_lines','nvim_buf_clear_namespace','nvim_buf_set_extmark','nvim_win_set_config'}) do "
            "local f=vim.api[name]; vim.api[name]=function(...) counts[name]=(counts[name] or 0)+1; return f(...) end end")
        keys(":echo '" + "你好" * 40 + "'")
        lua("counts={}")
        for i in range(20):
            keys("<Left>" if i % 2 == 0 else "<Right>")
        assert lua("return vim.tbl_isempty(counts)"), lua("return counts")
        keys("<Esc>")
        keys(":lua input.input({vim_mode=true,default=string.rep('你好',40)},function()end)<CR>")
        keys("<Esc>")
        lua("counts={}")
        for i in range(20):
            keys("h" if i % 2 == 0 else "l")
        assert lua("return vim.tbl_isempty(counts)"), lua("return counts")
        keys("<Esc>")
        print("render updates: Unicode cursor moves preserve buffer, highlights and geometry without global redraw passed")
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == "__main__":
    main()
