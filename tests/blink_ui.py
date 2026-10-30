#!/usr/bin/env python3
"""Optional UI regression against an actual installed blink.cmp checkout."""
import os
from pathlib import Path
import signal
from rpc import Capture


def main():
    def timeout(*_):
        raise TimeoutError("Blink UI test timed out")

    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(25)
    ui = Capture(os.environ.copy())

    def lua(code):
        return ui.request("nvim_exec_lua", [code, []])

    def keys(value):
        ui.request("nvim_input", [value])
        lua("vim.wait(120)")

    def window(kind):
        return lua("for _,w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == '" + kind + "' then return vim.api.nvim_win_get_config(w) end end")

    try:
        ui.request("nvim_ui_attach", [120, 40, {"rgb": True, "ext_linegrid": True}])
        lua("vim.opt.rtp:prepend(vim.fn.getcwd()); vim.opt.rtp:append(" + repr(str(Path(os.environ["INPUT_TOOLS_BLINK_ROOT"]).resolve())) + "); "
            "input=require('input-tools'); input.setup({window={row=3}}); "
            "require('blink.cmp').setup({fuzzy={implementation='lua'}, "
            "completion={menu=vim.tbl_deep_extend('force',{border='single'},require('input-tools.blink').menu_config())}, "
            "cmdline={completion={menu={auto_show=true},list={selection={preselect=true,auto_insert=false}}}, "
            "keymap={preset='none',['<Tab>']={'accept','fallback'},['<CR>']={'fallback'}}}})")
        keys(":")
        keys("he")
        palette, menu = window("input-tools-command"), window("blink-cmp-menu")
        assert palette and menu, (palette, menu)
        assert palette["row"] == 3
        assert menu["row"] == palette["row"] + palette["height"] + 2, (palette, menu)
        assert menu["col"] == palette["col"], (palette, menu)
        assert window("input-tools-menu") is None, "Native and Blink menus must not duplicate"
        selected = lua("return require('blink.cmp').get_selected_item().label")
        keys("<Tab>")
        assert lua("return vim.fn.getcmdline()").startswith(selected)
        keys("<Esc>")
        assert lua("return vim.g.ui_cmdline_pos") is None
        assert not lua("return require('blink.cmp').is_menu_visible()")

        # A long command scrolls horizontally; the candidate stays with its
        # visible query rather than the unscrolled byte offset off-screen.
        lua("input.setup({window={row=3,max_width=40}}); vim.api.nvim_create_user_command('InputToolsBlink', function() end, "
            "{nargs='*', complete=function() return {'alpha','alpine'} end})")
        keys(":")
        keys("InputToolsBlink " + "x" * 100 + " al")
        palette, menu = window("input-tools-command"), window("blink-cmp-menu")
        assert palette and menu and lua("return vim.g.ui_cmdline_pos[2]") < 0, (palette, menu)
        assert menu["col"] == palette["col"], (palette, menu)
        keys("<Esc>")
        lua("input.setup({window={row=3}})")

        # Input without a border and close to the right edge: Blink may shift
        # left to fit, but neither frame crosses the input vertically.
        lua("input.setup({window={row=3,width=20,border='none',col=100}})")
        keys(":he")
        palette, menu = window("input-tools-command"), window("blink-cmp-menu")
        assert palette and menu and menu['row'] >= palette['row'] + palette['height'], (palette, menu)
        assert menu['col'] >= 0 and menu['col'] + menu['width'] + 2 <= 120, menu
        keys("<Esc>")
        lua("input.setup({window={row=3}})")

        # Insert completion keeps Blink's native cursor-relative positioning.
        lua("vim.api.nvim_buf_set_lines(0,0,-1,false,{'alpha unique', ''}); vim.api.nvim_win_set_cursor(0,{2,0})")
        keys("ial")
        menu = window("blink-cmp-menu")
        assert menu and menu["relative"] != "editor", menu
        assert window("input-tools-command") is None
        assert lua("return vim.g.ui_cmdline_pos") is None
        keys("<Esc>")

        # Reconfigure and resize while a menu is active, then move the cursor.
        keys(":")
        keys("he")
        ui.request("nvim_ui_try_resize", [80, 24])
        lua("vim.wait(150)")
        palette, menu = window("input-tools-command"), window("blink-cmp-menu")
        assert palette and menu and menu["col"] == palette["col"], (palette, menu)
        keys("<Left>")
        assert lua("return vim.g.ui_cmdline_pos") is not None
        lua("input.setup()")
        keys("<End>l")
        palette, menu = window("input-tools-command"), window("blink-cmp-menu")
        assert palette and menu and menu["row"] + menu["height"] + 2 <= palette["row"], (palette, menu)
        keys("<Esc>")
        lua("input.setup({window={row=3}})")
        keys(":")
        keys("he")
        lua("input.teardown()")
        assert lua("return vim.g.ui_cmdline_pos") is None
        lua("vim.wait(150)")
        menu = window("blink-cmp-menu")
        assert menu and menu["row"] >= 12, menu
        keys("<Esc>")
        print("Blink UI: anchoring, selection/acceptance, scrolling, insert mode, resize and position cleanup passed")
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == "__main__":
    main()
