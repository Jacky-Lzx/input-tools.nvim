#!/usr/bin/env python3
"""Drive actual buffer-mode input, focus restoration and lifecycle cleanup."""
import os
import signal
from rpc import Capture


def main():
    def timeout(*_):
        raise TimeoutError('modal input UI test timed out')
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(30)
    ui = Capture(os.environ.copy())

    def lua(code):
        return ui.request('nvim_exec_lua', [code, []])

    def keys(value):
        ui.request('nvim_input', [value])
        lua('vim.wait(70)')

    def open_input(extra=''):
        keys(":lua handle=input.input({vim_mode=true,position='cursor',width=32,title='Name',title_pos='center',default='foo'" + extra + "},function(v) calls=calls+1; value=v or '__cancel'; callback_win=vim.api.nvim_get_current_win();callback_mode=vim.api.nvim_get_mode().mode end)<CR>")
        layout = lua('return input.get_layout()')
        assert layout and layout['vim_mode'] and layout['width'] == 32, layout
        assert lua("return vim.api.nvim_get_mode().mode:sub(1,1)") == 'i'
        assert lua("return vim.bo.filetype") == 'input-tools-input'
        assert lua('return vim.api.nvim_get_current_win()') == layout['win']
        return layout

    def line():
        return lua('return vim.api.nvim_get_current_line()')

    def closed(count, expected):
        lua('assert(vim.wait(500,function() return calls==' + str(count) + ' end,5), "input callback did not complete")')
        assert lua('return calls') == count, lua('return {calls,value}')
        assert lua('return value') == expected
        assert lua('return vim.api.nvim_get_current_win()==source_win and callback_win==source_win')
        assert lua('return input.get_layout()') is None
        assert lua('return callback_mode') == 'n'
        assert lua("for _,b in ipairs(vim.api.nvim_list_bufs()) do if vim.bo[b].filetype=='input-tools-input' then return false end end; return true")
        assert lua('return vim.deep_equal(vim.api.nvim_buf_get_lines(source_buf,0,-1,false),original)')

    try:
        ui.request('nvim_ui_attach', [100, 32, {'rgb': True, 'ext_linegrid': True}])
        lua("vim.opt.rtp:prepend(vim.fn.getcwd()); input=require('input-tools'); input.setup({window={row=3}}); "
            "original={string.rep('x',40),string.rep('x',40),string.rep('x',40)}; vim.api.nvim_buf_set_lines(0,0,-1,false,original); "
            "vim.api.nvim_win_set_cursor(0,{2,10}); source_win=vim.api.nvim_get_current_win(); source_buf=vim.api.nvim_get_current_buf(); calls=0")
        layout = open_input()
        keys('<Esc>')
        assert lua('return vim.api.nvim_get_mode().mode') == 'n'
        assert lua('return calls') == 0
        keys('ciwbar<Esc>')
        assert line() == 'bar'
        keys('u')
        assert line() == 'foo'
        keys('<C-r>')
        assert line() == 'bar'
        keys('<CR>')
        closed(1, 'bar')
        assert lua('return vim.api.nvim_buf_is_valid(' + str(layout['buf']) + ')') is False

        open_input()
        keys('<C-u>你好')
        keys('<CR>')
        closed(2, '你好')
        open_input()
        keys('<Esc>')
        assert lua('return calls') == 2
        keys('<Esc>')
        closed(3, '__cancel')
        open_input()
        keys('<C-c>')
        closed(4, '__cancel')

        open_input()
        lua('handle.cancel(); handle.cancel(); vim.wait(70)')
        closed(5, '__cancel')
        open_input()
        lua('input.disable(); vim.wait(70)')
        closed(6, '__cancel')
        assert not lua('return input.is_enabled()')
        # Explicit Vim-mode input also works without enabling external cmdline UI.
        open_input()
        keys('<Esc>ciwstandalone<CR>')
        closed(7, 'standalone')
        assert not lua('return input.is_enabled()')
        lua('input.enable()')

        open_input()
        ui.request('nvim_ui_try_resize', [24, 10])
        lua('vim.wait(80)')
        box = lua('return input.get_layout()')
        assert box and box['col'] + box['outer_width'] <= 24 and box['row'] + box['outer_height'] <= 10, box
        keys('<C-c>')
        closed(8, '__cancel')
        ui.request('nvim_ui_try_resize', [100, 32])

        open_input()
        keys('<Esc>:q<CR>')
        closed(9, '__cancel')
        open_input()
        keys('<Esc>dd<CR>')
        closed(10, '')
        open_input()
        lua("replacement=input.input({vim_mode=true,position='cursor',width=32,title='Next',default='next'},function(v) calls=calls+1;value=v or '__cancel';callback_win=vim.api.nvim_get_current_win() end); vim.wait(80)")
        lua('assert(vim.wait(500,function() return calls==11 end,5))')
        assert lua('return calls') == 11
        assert lua("return vim.api.nvim_get_mode().mode:sub(1,1)") == 'i'
        assert line() == 'next'
        keys('<C-c>')
        closed(12, '__cancel')
        open_input()
        lua('vim.api.nvim_win_close(input.get_window(),true); vim.wait(80)')
        closed(13, '__cancel')
        keys(":lua input.input({vim_mode=true,title='Project',prompt='Name: ',default='value'},function(v) inline_done=v end)<CR>")
        assert line() == 'value'
        inline = lua('return input.get_layout()')
        assert inline['text']['col'] >= inline['col'] + 7, inline
        keys('<CR>')
        lua('assert(vim.wait(500,function() return inline_done=="value" end,5))')
        # Native (vim_mode=false/default) input is still the command-line engine.
        keys(":lua input.input({vim_mode=false,default='native'},function(v) calls=calls+1; value=v or '__cancel' end)<CR>")
        assert lua('return vim.fn.getcmdline()') == 'native'
        assert lua('return vim.api.nvim_get_mode().mode') == 'c'
        keys('<Esc>')
        assert lua('return calls') == 14
        keys(":lua input.input({vim_mode=true,title='First',default='one'},function(v) input.input({vim_mode=true,title='Second',default='two'},function(r) chain_done=true end) end)<CR>")
        keys('<CR>')
        lua("assert(vim.wait(500,function() return input.get_window() and vim.api.nvim_get_current_line()=='two' end,5))")
        assert lua("return vim.api.nvim_get_mode().mode:sub(1,1)") == 'i', str(lua("return {mode=vim.api.nvim_get_mode().mode,line=vim.api.nvim_get_current_line(),layout=input.get_layout(),err=vim.v.errmsg,done=chain_done}"))
        assert line() == 'two'
        keys('<C-c>')
        lua('assert(vim.wait(500,function() return chain_done end,5))')
        assert lua('return chain_done')
        lua("immediate_calls=0; local h=input.input({vim_mode=true,title='Cancel'},function(v) immediate_calls=immediate_calls+1;immediate_value=v end); h.cancel(); vim.wait(40)")
        lua('assert(vim.wait(500,function() return immediate_calls==1 end,5))')
        assert lua('return immediate_value') is None
        assert lua('return vim.api.nvim_get_mode().mode') == 'n'
        assert lua('return vim.api.nvim_get_current_win()==source_win')
        print('modal UI: real Insert/Normal edits, undo/redo, Unicode, confirm/cancel, cancel handle, teardown, standalone, resize and native fallback passed')
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == '__main__':
    main()
