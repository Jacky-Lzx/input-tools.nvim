#!/usr/bin/env python3
"""Cursor-anchored input against actual source windows, grids and native menus."""
import os
import signal
from rpc import Capture


def main():
    def timeout(*_):
        raise TimeoutError('cursor input UI test timed out')
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(25)
    ui = Capture(os.environ.copy())

    def lua(code):
        return ui.request('nvim_exec_lua', [code, []])

    def keys(value):
        ui.request('nvim_input', [value])
        lua('vim.wait(50)')

    def source_point():
        return lua('local c=vim.api.nvim_win_get_cursor(source_win); return vim.fn.screenpos(source_win,c[1],c[2]+1)')

    def open_input(extra=''):
        keys(":lua input.input({position='cursor',title='Value',title_pos='center',default='old'" + extra + "},function(v) vim.g.cursor_value=v or '__cancel' end)<CR>")
        return lua('return input.get_layout()')

    def check_near(point):
        box = lua('return input.get_layout()')
        assert box, lua('return input.status()')
        cursor_row, cursor_col = point['row'] - 1, point['curscol'] - 1
        assert box['row'] == cursor_row + 1 or box['row'] + box['outer_height'] == cursor_row, (point, box)
        assert box['col'] == max(0, min(cursor_col, lua('return vim.o.columns') - box['outer_width'])), (point, box)
        assert lua('return vim.api.nvim_get_current_win()==source_win')
        return box

    try:
        ui.request('nvim_ui_attach', [100, 32, {'rgb': True, 'ext_linegrid': True}])
        lua("vim.opt.rtp:prepend(vim.fn.getcwd()); input=require('input-tools'); input.setup({window={row=3,width=30}}); "
            "vim.api.nvim_buf_set_lines(0,0,-1,false,vim.fn['repeat']({string.rep('x',100)},60)); "
            "vim.api.nvim_win_set_cursor(0,{8,20}); vim.fn.winrestview({topline=1,leftcol=0}); source_win=vim.api.nvim_get_current_win(); vim.cmd.redraw()")
        point = source_point()
        open_input()
        before = check_near(point)
        keys('<C-u>新名称')
        after = check_near(point)
        assert [before['row'], before['col']] == [after['row'], after['col']], (before, after)
        keys('<CR>')
        assert lua('return vim.g.cursor_value') == '新名称'
        keys(':echo')
        assert lua('return input.get_layout().row') == 3, 'cursor option leaked to the command line'
        keys('<Esc>')

        # A split, tabs and wide characters must use screen cells rather than
        # window-local coordinates or the source cursor's byte column.
        lua("vim.cmd('vsplit'); vim.cmd('wincmd L'); source_win=vim.api.nvim_get_current_win(); "
            "vim.wo.number=true; vim.wo.signcolumn='yes'; "
            "vim.api.nvim_buf_set_lines(0,7,8,false,{'\\t你好 target'}); "
            "vim.api.nvim_win_set_cursor(0,{8,8}); vim.fn.winrestview({topline=1,leftcol=0}); vim.cmd.redraw()")
        point = source_point()
        open_input()
        check_near(point)
        lua("vim.api.nvim_win_call(source_win,function() local v=vim.fn.winsaveview(); v.topline=3; vim.fn.winrestview(v) end); vim.cmd.redraw(); vim.wait(80)")
        moved = source_point()
        assert moved['row'] != point['row'], (point, moved)
        check_near(moved)
        # Resizing a source split without resizing the whole editor also moves it.
        lua("vim.api.nvim_win_set_width(source_win,60); vim.cmd.redraw(); vim.wait(80)")
        check_near(source_point())
        keys('<Esc>')
        assert lua('return vim.g.cursor_value') == '__cancel'

        # Bottom/right screen edges force north placement and horizontal clamping.
        lua("vim.cmd('only'); source_win=vim.api.nvim_get_current_win(); vim.wo.wrap=false; "
            "vim.api.nvim_win_set_cursor(0,{60,85}); vim.cmd('normal! zb'); vim.cmd.redraw()")
        point = source_point()
        box = open_input()
        check_near(point)
        assert box['row'] + box['outer_height'] <= point['row'] - 1, (point, box)
        ui.request('nvim_ui_try_resize', [24, 10])
        lua('vim.wait(80)')
        box = lua('return input.get_layout()')
        assert box and box['row'] >= 0 and box['col'] >= 0
        assert box['col'] + box['outer_width'] <= 24 and box['row'] + box['outer_height'] <= 10, box
        assert lua('return input.is_enabled() and vim.fn.getcmdline()=="old"')
        keys('<Esc>')
        ui.request('nvim_ui_try_resize', [100, 32])

        # Native command-line completion uses the same final screen geometry.
        lua("vim.api.nvim_win_set_cursor(0,{8,10}); vim.fn.winrestview({topline=1,leftcol=0}); vim.cmd.redraw(); "
            "vim.o.wildmode='full'; vim.o.wildoptions='pum'; vim.o.wildmenu=true; "
            "_G.CursorInputComplete=function() return {'alpha','alpine','alps'} end")
        point = source_point()
        open_input(",completion='customlist,v:lua.CursorInputComplete'")
        keys('<C-u>al<Tab>')
        box = check_near(point)
        menu = lua("for _,w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype=='input-tools-menu' then return vim.api.nvim_win_get_config(w) end end")
        assert menu, 'cursor-anchored completion menu is missing'
        assert menu['row'] >= box['row'] + box['outer_height'] or menu['row'] + menu['height'] + 2 <= box['row'], (box, menu)
        keys('<CR>')
        assert lua('return vim.g.cursor_value') in ('alpha', 'alpine', 'alps')
        print('cursor UI: stable source anchor, split/tab/Unicode offsets, scrolling, split/screen resize, edges, native completion and cleanup passed')
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == '__main__':
    main()
