#!/usr/bin/env python3
"""The first Vim input may itself lazy-load Blink on InsertEnter."""
import os
from pathlib import Path
import signal
from rpc import Capture


def main():
    def timeout(*_):
        raise TimeoutError('lazy Blink input test timed out')
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(15)
    ui = Capture(os.environ.copy())

    def lua(code):
        return ui.request('nvim_exec_lua', [code, []])

    def keys(value):
        ui.request('nvim_input', [value])
        lua('vim.wait(150)')

    try:
        ui.request('nvim_ui_attach', [100, 32, {'rgb': True, 'ext_linegrid': True}])
        lua("vim.opt.rtp:prepend(vim.fn.getcwd()); vim.opt.rtp:append(" + repr(str(Path(os.environ['INPUT_TOOLS_BLINK_ROOT']).resolve())) + "); "
            "input=require('input-tools'); input.setup(); _G.InputToolsLazyComplete=function() return {'alpha','alpine'} end; "
            "vim.api.nvim_create_autocmd('InsertEnter',{once=true,callback=function() "
            "require('blink.cmp').setup({fuzzy={implementation='lua'},sources=require('input-tools.blink').sources_config(),keymap={preset='default',['<CR>']={function(cmp) return cmp.accept() end,function() return '<CR>' end}}}) end})")
        assert not lua("return package.loaded['blink.cmp'] ~= nil")
        keys(":lua input.input({vim_mode=true,default='al',completion='customlist,v:lua.InputToolsLazyComplete'},function(v) done=true;value=v end)<CR>")
        assert lua("return package.loaded['blink.cmp'] ~= nil and vim.b.completion")
        keys('p')
        assert lua("return require('blink.cmp').is_menu_visible()"), lua("return {err=vim.v.errmsg,mode=vim.api.nvim_get_mode().mode}")
        lua("if not require('blink.cmp').get_selected_item() then require('blink.cmp').select_next() end")
        keys('<CR>')
        assert not lua('return done')
        keys('<CR>')
        lua('assert(vim.wait(500,function() return done end,5))')
        assert lua('return value') in ('alpha','alpine')
        assert not lua("return require('blink.cmp').is_menu_visible()")
        print('Blink lazy UI: first Vim input activates configured source, typing and Enter ownership passed')
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == '__main__':
    main()
