#!/usr/bin/env python3
"""Save/discard/cancel dialogs retain their body throughout the native wait."""
import os
from pathlib import Path
import signal
import tempfile
import time
from rpc import Capture, unpack


def main():
    def timeout(*_):
        raise TimeoutError('confirmation UI test timed out')
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(25)
    ui = Capture(os.environ.copy())

    def lua(code):
        return ui.request('nvim_exec_lua', [code, []])

    def keys(value):
        ui.request('nvim_input', [value])
        lua('vim.wait(60)')

    def question(command, fragment=None, cancel=True, resize=None, default_yes=True):
        nonlocal screen_rows
        if resize:
            ui.request('nvim_ui_try_resize', list(resize))
            screen_rows = lua('return vim.o.lines-vim.o.cmdheight')
        ui.notices.clear()
        ui.frames.clear()
        ui.request('nvim_input', [command + '<CR>'])
        while not any(m[1] == 'confirm-ready' for m in ui.notices):
            message = unpack(ui.process.stdout)
            if message[0] == 2 and message[1] == 'redraw':
                ui.redraw(message[2])
            elif message[0] == 2:
                ui.notices.append(message)
        # A confirmation can service fast API calls while ordinary Lua RPC is
        # blocked. Drain UI updates after pending cleanup has had time to run.
        time.sleep(.15)
        ui.request('nvim_get_mode', [])
        rendered = [m[2] for m in ui.notices if m[1] == 'confirm-drawn']
        assert rendered, ui.notices
        box, body, measured = rendered[-1]
        assert box and box['kind'] == 'confirm' and 36 <= box['width'] <= 64, box
        assert box['height'] >= 5, box
        assert box['row'] == (screen_rows - box['outer_height']) // 2, box
        assert body[0] == '' and body[-1] == '', body
        fragment = fragment or current.name
        assert any(fragment in line for line in body), body
        marker = '[Y]es' if default_yes else '[N]o'
        choice = next(line for line in body if marker in line)
        assert ',' not in choice and ':' not in choice, choice
        assert ('(N)o' if default_yes else '(Y)es') in choice and (not cancel or '(C)ancel' in choice), choice
        assert body[body.index(choice)-1] == '', body
        visible = ''.join(''.join(cell[0] for cell in row[box['col']+1:box['col']+1+box['width']]).rstrip()
                          for row in ui.grid[box['row']+1:box['row']+1+box['height']])
        normalize = lambda value: ''.join(value.split())
        assert normalize(fragment) in normalize(visible), visible
        assert marker in visible and (not cancel or '(C)ancel' in visible), visible
        assert 'Confirm' in ''.join(cell[0] for cell in ui.grid[box['row']]), box
        assert box['text']['row'] == box['cursor']['row'], box
        assert measured <= box['height'], (measured, box)
        return box

    try:
        ui.request('nvim_ui_attach', [100, 32, {'rgb': True, 'ext_linegrid': True}])
        lua("vim.opt.rtp:prepend(vim.fn.getcwd()); input=require('input-tools'); input.setup({window={row=3}}); "
            "vim.o.confirm=true;vim.o.hidden=false; vim.ui_attach(vim.api.nvim_create_namespace('input-tools.confirm-test'),{ext_cmdline=true},function(e,...) "
            "local a={...}; if e=='msg_show' and a[1]=='confirm' or e=='cmdline_show' and (a[4] or ''):find('(C)ancel',1,true) "
            "then vim.rpcnotify(1,'confirm-ready') end end)")
        # Add message ownership just as in the user's configuration.
        root = os.environ.get('NOTIFICATION_TOOLS_ROOT')
        if root:
            lua('vim.opt.rtp:prepend(' + repr(str(Path(root).resolve())) + "); require('notification-tools').setup({messages={enabled=true}});input.sync_notifications()")
        else:
            lua("vim.ui_attach(vim.api.nvim_create_namespace('input-tools.confirm-messages'),{ext_messages=true},function() end)")
        screen_rows = lua('return vim.o.lines-vim.o.cmdheight')
        lua("local view=require('input-tools.view');local render=view.render;view.render=function(s,c) render(s,c); "
            "local box=input.get_layout();if box and box.kind=='confirm' then "
            "vim.rpcnotify(1,'confirm-drawn',box,vim.api.nvim_buf_get_lines(box.buf,0,-1,false),vim.api.nvim_win_text_height(box.win,{}).all) end end")
        with tempfile.TemporaryDirectory(prefix='input-tools-confirm-') as temp:
            for index, reply in enumerate(('c', '<Esc>', 'n', '<CR>')):
                current = Path(temp) / (str(index) + '-未保存的文件名' * 5 + '.txt')
                lua('vim.cmd.enew({bang=true}); vim.api.nvim_buf_set_name(0,' + repr(str(current)) + "); vim.api.nvim_buf_set_lines(0,0,-1,false,{'keep these changes'}); original=vim.api.nvim_get_current_buf()")
                # Exercise the exact quit path for cancellation, and enew for
                # yes/no so that accepting a choice does not end the test editor.
                question(':q' if index < 2 else ':enew', resize=(48, 20) if index == 0 else None)
                keys(reply)
                if index == 0:
                    ui.request('nvim_ui_try_resize', [100, 32])
                    screen_rows = lua('return vim.o.lines-vim.o.cmdheight')
                assert lua('return input.get_layout()') is None
                assert lua("return vim.api.nvim_get_mode().mode") == 'n'
                if index < 2:
                    assert lua('return vim.api.nvim_get_current_buf()==original and vim.bo.modified')
                    assert not current.exists()
                elif reply == 'n':
                    assert not current.exists()
                    assert lua('return vim.api.nvim_get_current_buf()~=original')
                else:
                    assert current.read_text() == 'keep these changes\n'
                if root:
                    assert not any('Save changes to' in item['message'] for item in lua("return require('notification-tools').history()"))
            small = question(":lua vim.g.dialog_result=vim.fn.confirm('Continue?', '&Yes\\n&No',1)", 'Continue?', False)
            assert small['width'] == 36, small
            keys('n')
            assert lua('return vim.g.dialog_result') == 2
            question(":lua vim.g.dialog_result=vim.fn.confirm('Continue?', '&Yes\\n&No',2)", 'Continue?', False, default_yes=False)
            keys('<CR>')
            assert lua('return vim.g.dialog_result') == 2
            # The dialog title/width do not leak to subsequent normal commands.
            keys(':echo 1')
            box = lua('return input.get_layout()')
            assert box['kind'] == 'command' and box['width'] == 80
            assert lua('return vim.api.nvim_win_get_config(input.get_window()).title') is None
            keys('<Esc>')
        print('confirm UI: centered padded buttons, adaptive width, Unicode paths, quit cancel/discard/save and cleanup passed')
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == '__main__':
    main()
