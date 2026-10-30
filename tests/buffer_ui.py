#!/usr/bin/env python3
"""Editable input completion/highlighting with real Insert-mode UI events."""
import os
from pathlib import Path
import signal
import tempfile
from rpc import Capture


def main():
    def timeout(*_):
        raise TimeoutError('buffer input UI test timed out')
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(25)
    ui = Capture(os.environ.copy())

    def lua(code):
        return ui.request('nvim_exec_lua', [code, []])

    def keys(value):
        ui.request('nvim_input', [value])
        lua('vim.wait(80)')

    def open_input(opts):
        lua('done=false; value=nil')
        keys(':lua handle=input.input({' + opts + ',vim_mode=true},function(v) done=true;value=v end)<CR>')
        assert lua("return vim.bo.filetype=='input-tools-input'")

    def close(expected):
        keys('<CR>')
        lua('assert(vim.wait(500,function() return done end,5))')
        assert lua('return value') == expected, lua('return value')
        assert lua('return input.get_window()') is None

    try:
        ui.request('nvim_ui_attach', [100, 32, {'rgb': True, 'ext_linegrid': True}])
        lua("vim.opt.rtp:prepend(vim.fn.getcwd()); input=require('input-tools'); input.setup(); "
            "vim.o.completeopt='menuone,noselect,noinsert'; hl_calls=0; "
            "vim.api.nvim_set_hl(0,'InputToolsBufferTest',{fg='#ff1234'}); "
            "_G.InputToolsHighlight=function(text) hl_calls=hl_calls+1; if text~='' then return {{0,#text,'InputToolsBufferTest'}} end; return {} end; "
            "_G.InputToolsComplete=function(lead,text,cursor) completion_args={lead,text,cursor}; return {'alpha','alpine'} end")
        open_input("default='你好',title='Color',highlight=InputToolsHighlight")
        assert lua('return hl_calls') == 1
        marks = lua("return vim.api.nvim_buf_get_extmarks(0,vim.api.nvim_create_namespace('input-tools.input-highlight'),0,-1,{details=true})")
        assert len(marks) == 1 and marks[0][3]['end_col'] == 6, marks
        keys('<Left><Right>')
        keys('<Esc>hlu<C-r>')
        assert lua('return hl_calls') == 1, lua('return hl_calls')
        keys('A!')
        assert lua('return hl_calls') == 2
        lua("vim.api.nvim_exec_autocmds('ColorScheme',{}); vim.wait(80)")
        assert lua('return hl_calls') == 3
        keys('<Esc>ddi')
        assert lua("return #vim.api.nvim_buf_get_extmarks(0,vim.api.nvim_create_namespace('input-tools.input-highlight'),0,-1,{})") == 0
        close('')

        open_input("default='prefix al',completion='customlist,v:lua.InputToolsComplete'")
        assert lua('return vim.b.completion') is False, 'Blink must remain opt-in'
        keys('<C-x><C-u>')
        assert lua('return vim.fn.pumvisible()') == 1, lua("return {errmsg=vim.v.errmsg,messages=vim.fn.execute('messages'),cf=vim.bo.completefunc,args=completion_args,mode=vim.api.nvim_get_mode().mode,result=require('input-tools.buffer').complete(0,'al')}")
        assert lua('return completion_args') == ['al', 'prefix al', 9], lua('return {completion_args,vim.api.nvim_win_get_cursor(0),vim.api.nvim_get_current_line()}')
        keys('<C-n><CR>')
        assert lua('return done') is False, 'Accepting a candidate must not confirm input'
        assert lua('return vim.api.nvim_get_current_line()') == 'prefix alpha'
        close('prefix alpha')

        with tempfile.TemporaryDirectory(prefix='input-tools-files-') as temp:
            (Path(temp) / 'alpha.txt').write_text('')
            (Path(temp) / 'alpine').mkdir()
            lua('vim.cmd.lcd(' + repr(temp) + ')')
            open_input("default='al',completion='file'")
            keys('<C-x><C-u>')
            assert lua('return vim.fn.pumvisible()') == 1, lua("return {errmsg=vim.v.errmsg,messages=vim.fn.execute('messages'),cf=vim.bo.completefunc,args=completion_args,mode=vim.api.nvim_get_mode().mode,result=require('input-tools.buffer').complete(0,'al')}")
            keys('<C-n><CR>')
            close('alpha.txt')
            (Path(temp) / 'space alpha.txt').write_text('')
            open_input("default='space\\\\ a',completion='file'")
            keys('<C-x><C-u>')
            assert lua('return vim.fn.pumvisible()') == 1
            keys('<C-n><CR>')
            close('space alpha.txt')

        lua("_G.InputToolsCustom=function() return 'alpha\\nalpine\\nbeta' end")
        open_input("default='al',completion='custom,v:lua.InputToolsCustom'")
        keys('<C-x><C-u>')
        assert lua('return vim.fn.pumvisible()') == 1
        assert lua("return #vim.fn.complete_info({'items'}).items") == 2
        keys('<C-e>')
        close('al')

        # Full text and byte offsets remain consistent for multiline highlights.
        open_input("default='你\\n好',highlight='v:lua.InputToolsHighlight'")
        marks = lua("return vim.api.nvim_buf_get_extmarks(0,vim.api.nvim_create_namespace('input-tools.input-highlight'),0,-1,{details=true})")
        assert marks[0][3]['end_row'] == 1 and marks[0][3]['end_col'] == 3, marks
        close('你\n好')
        # Bad callbacks do not leak stale marks or take away the editor UI.
        lua("vim.notify=function(message) warning=message end")
        open_input("default='safe',highlight=function() return {{1,2,'Error'}} end")
        # Invalid callback/error results leave the input usable and cancellable.
        keys('<Esc>cc你好')
        assert lua('return warning')
        keys('<C-c>')
        lua('assert(vim.wait(500,function() return done end,5))')
        assert lua('return value') is None
        assert lua("return vim.api.nvim_get_mode().mode") == 'n'
        print('buffer UI: highlight caching/theme/Unicode, custom and file completion, acceptance and callback failure passed')
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == '__main__':
    main()
