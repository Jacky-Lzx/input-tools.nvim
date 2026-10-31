#!/usr/bin/env python3
"""Edit and export a real temporary Lua configuration through everyday prompts."""
import os
from pathlib import Path
import signal
import tempfile
import time
from rpc import Capture, unpack

ROOT = Path(__file__).resolve().parent.parent


def main():
    def timeout(*_):
        raise TimeoutError('everyday input workflow timed out')
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(45)
    with tempfile.TemporaryDirectory(prefix='input-tools-workflow-') as temp:
        ui = Capture(os.environ.copy())

        def lua(code):
            return ui.request('nvim_exec_lua', [code, []])

        def keys(value):
            ui.request('nvim_input', [value])
            lua('vim.wait(45)')

        def lines():
            return lua('return vim.api.nvim_buf_get_lines(demo.buf,0,-1,false)')

        def prompt(command, expected):
            ui.notices.clear()
            ui.request('nvim_input', [command + '<CR>'])
            while not any(m[1] == 'workflow-view' and m[2][0]['kind'] == 'confirm' for m in ui.notices):
                message = unpack(ui.process.stdout)
                if message[0] == 2 and message[1] == 'redraw':
                    ui.redraw(message[2])
                elif message[0] == 2:
                    ui.notices.append(message)
            time.sleep(.12)
            ui.request('nvim_get_mode', [])  # Fast API also works inside blocking dialogs.
            snapshots = [m[2] for m in ui.notices if m[1] == 'workflow-view']
            assert snapshots, ui.notices
            box, body = snapshots[-1]
            content = '\n'.join(body)
            assert box['kind'] == 'confirm', (box, content)
            for fragment in expected:
                assert fragment in content, (fragment, content)
            visible = '\n'.join(''.join(cell[0] for cell in row) for row in ui.grid)
            for fragment in expected:
                assert fragment in visible, (fragment, visible)

        try:
            ui.request('nvim_ui_attach', [112, 36, {'rgb': True, 'ext_linegrid': True}])
            lua('demo=dofile(' + repr(str(ROOT / 'examples/demo.lua')) + ').setup({plugin=' + repr(str(ROOT)) + ',root=' + repr(temp) + '})')
            original = lines()
            lua("local v=require('input-tools.view'); local render=v.render;v.render=function(s,c) render(s,c);local b=require('input-tools').get_layout(); "
                "if b then vim.rpcnotify(1,'workflow-view',b,vim.api.nvim_buf_get_lines(b.buf,0,-1,false)) end end")
            # Native forward/backward search and a nested expression register.
            keys('/timeout_ms')
            assert lua("return require('input-tools').get_layout().kind") == 'search'
            keys('<CR>')
            assert lua('return vim.api.nvim_win_get_cursor(0)[1]') == 4
            keys('?project<CR>')
            assert lua('return vim.api.nvim_win_get_cursor(0)[1]') == 3
            assert lines() == original
            keys(':let g:workflow_budget = <C-r>=40*2<CR><CR>')
            assert lua('return vim.g.workflow_budget') == 80
            assert lua("return require('input-tools').get_layout()") is None

            # Per-match substitution: accept one occurrence, skip the next.
            prompt(':%s/timeout_ms/delay_ms/gc', ['replace with delay_ms'])
            ui.request('nvim_input', ['y'])
            time.sleep(.08)
            ui.request('nvim_get_mode', [])
            keys('n')
            changed = lines()
            assert 'delay_ms = 1200' in changed[3] and 'config.timeout_ms' in changed[8], changed
            keys('u')
            assert lines() == original

            # Default vim.ui.select -> inputlist must keep every option visible
            # after scheduled callbacks run, including after typing a number.
            prompt(':DemoExport', ['Export format', '1: PDF', '2: Markdown', '3: Plain text'])
            ui.request('nvim_input', ['2<BS>2'])
            time.sleep(.08)
            ui.request('nvim_get_mode', [])
            snapshots = [m[2] for m in ui.notices if m[1] == 'workflow-view']
            assert '2: Markdown' in '\n'.join(snapshots[-1][1]), snapshots[-1]
            keys('<CR>')
            assert lua('return {demo.export_answer,demo.export_index,demo.export_done}') == ['Markdown', 2, True]
            lua('demo.export_done=false')
            prompt(':DemoExport', ['Export format', '2: Markdown'])
            keys('<CR>')
            assert lua('return demo.export_done and demo.export_answer==nil and demo.export_index==nil')

            # Native input API: spaces in a path, cancel without side effects,
            # then create and inspect an actual file in the temporary project.
            keys(':DemoFile<CR>')
            assert lua('return vim.fn.getcmdline()') == 'notes/release notes.md'
            keys('<Esc>')
            assert not (Path(temp) / 'notes/release notes.md').exists()
            assert lua('return demo.file_done and demo.file_answer==nil')
            keys(':DemoFile<CR>')
            keys('<CR>')
            assert (Path(temp) / 'notes/release notes.md').read_text().startswith('# Release notes')

            # Secret entry is rendered as stars, and never added to input history.
            keys(":lua vim.g.workflow_secret=vim.fn.inputsecret('Access token: ')<CR>")
            ui.frames.clear()
            ui.notices.clear()
            keys('only-a-test-token')
            frame = '\n'.join(''.join(cell[0] for cell in row) for row in ui.grid)
            assert 'Access token:' in frame and '*****************' in frame
            assert not any('only-a-test-token' in frame for frame in ui.frames)
            assert 'only-a-test-token' not in str(ui.notices)
            keys('<CR>')
            assert lua('return vim.g.workflow_secret') == 'only-a-test-token'
            assert lua("for i=1,vim.fn.histnr('input') do if vim.fn.histget('input',i)=='only-a-test-token' then return false end end;return true")

            # Optional real LuaLS path: the input API supplies the name, while
            # native LSP performs the semantic edit. No rename response is mocked.
            executable = os.environ.get('INPUT_TOOLS_LUA_LS')
            if executable:
                lua('vim.cmd.enew({bang=true}); demo=dofile(' + repr(str(ROOT / 'examples/demo.lua')) + ').setup({plugin=' + repr(str(ROOT)) + ',root=' + repr(temp) + ',lsp=' + repr(executable) + '});vim.api.nvim_win_set_cursor(0,{4,4})')
                lua("assert(vim.wait(12000,function() local c=vim.lsp.get_client_by_id(demo.client);return c and c.initialized end,20),'LuaLS did not initialize')")
                lua("assert(vim.wait(12000,function() local r=vim.lsp.buf_request_sync(0,'textDocument/prepareRename',vim.lsp.util.make_position_params(0,'utf-16'),500);for _,v in pairs(r or {}) do if v.result then return true end end end,100),'LuaLS semantic analysis not ready')")
                keys(':DemoRename<CR>')
                box = lua("return require('input-tools').get_layout()")
                assert box['vim_mode'] and box['width'] == 32
                keys('<Esc>ciwrequest_timeout_ms<CR>')
                lua("assert(vim.wait(5000,function() return table.concat(vim.api.nvim_buf_get_lines(demo.buf,0,-1,false),'\\n'):find('config.request_timeout_ms',1,true)~=nil end,10),'real LSP rename did not apply')")
                assert lua('return demo.rename_answer') == 'request_timeout_ms'
                assert 'request_timeout_ms = 1200' in lines()[3]
                lua('vim.lsp.stop_client(demo.client,true)')
            # Source remains editable and no prompt/title/window survives.
            assert lua("return require('input-tools').get_layout()") is None
            assert lua("return vim.api.nvim_get_mode().mode") == 'n'
            print('workflow UI: search, expression, per-match substitute, persistent native select, file creation/cancel, secret masking' + (', real LuaLS rename' if executable else '') + ' passed')
        finally:
            signal.alarm(0)
            ui.close()


if __name__ == '__main__':
    main()
