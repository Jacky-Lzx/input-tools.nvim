#!/usr/bin/env python3
"""Drive native editing engines through an attached UI, with optional notifications."""
import os
from pathlib import Path
import signal
from rpc import Capture, unpack


def main():
    def timed_out(*_):
        raise TimeoutError("input-tools UI test timed out")

    signal.signal(signal.SIGALRM, timed_out)
    signal.alarm(40)
    ui = Capture(os.environ.copy())

    def lua(code):
        return ui.request("nvim_exec_lua", [code, []])

    def keys(value):
        ui.request("nvim_input", [value])
        lua("vim.wait(35)")

    def text():
        return "\n".join("".join(c[0] for c in row) for row in ui.grid)

    def command():
        return lua("return vim.fn.getcmdline()")

    def floats(kind):
        return lua("local r = {}; for _, w in ipairs(vim.api.nvim_list_wins()) do local b = vim.api.nvim_win_get_buf(w); "
                   "if vim.bo[b].filetype == 'input-tools-" + kind + "' then r[#r+1] = w end end; return r")

    def prompt(command_text, reply, expected):
        ui.notices.clear()
        ui.frames.clear()
        ui.request("nvim_input", [command_text])
        while not any(m[1] == "test-prompt" for m in ui.notices):
            message = unpack(ui.process.stdout)
            if message[0] == 2 and message[1] == "redraw":
                ui.redraw(message[2])
            elif message[0] == 2:
                ui.notices.append(message)
        keys(reply)
        if expected is not None:
            assert lua("return vim.g.prompt_result") == expected

    try:
        ui.request("nvim_ui_attach", [100, 32, {"rgb": True, "ext_linegrid": True}])
        lua("vim.opt.rtp:prepend(vim.fn.getcwd()); input = require('input-tools'); input.setup(); "
            "vim.o.wildmode = 'full'; vim.o.wildoptions = 'pum'; vim.o.wildmenu = true")
        assert lua("return input.is_enabled() and not package.loaded['notification-tools']")
        lua("layout_events={}; vim.api.nvim_create_autocmd('User',{pattern={'InputToolsOpen','InputToolsClose','InputToolsLayoutChanged'}, "
            "callback=function(e) layout_events[#layout_events+1]={event=e.match,layout=vim.deepcopy(e.data.layout)} end})")
        assert lua("return input.get_layout()") is None
        keys(":let g:unicode_result = '你好🙂'")
        assert "你好🙂" in text(), text()
        assert lua("return layout_events[1].event=='InputToolsOpen' and layout_events[1].layout.kind=='command'")
        assert lua("local l=input.get_layout(); local w=vim.api.nvim_win_get_config(l.win); "
                   "return l.row==w.row and l.col==w.col and l.outer_width==w.width+2 and l.outer_height==w.height+2 "
                   "and l.cursor.row>=l.row and l.cursor.col>=l.col")
        assert lua("local l=input.get_layout(); l.row=-100; return input.get_layout().row~=-100 and l.content==nil")
        keys("<Left>")
        assert lua("local w = require('input-tools.view').cursor.win; return vim.api.nvim_win_get_cursor(w)[2] == vim.fn.getcmdpos()")
        cursor = lua("local c = require('input-tools.view').cursor; return vim.fn.screenpos(c.win, c.row, c.col + 1)")
        assert ui.cursor == [1, cursor["row"] - 1, cursor["col"] - 1], (ui.cursor, cursor)
        keys("<End><CR>")
        assert lua("return vim.g.unicode_result") == "你好🙂"
        assert lua("return input.get_layout()") is None
        assert lua("return layout_events[#layout_events].event=='InputToolsClose'")
        keys(":<Up>")
        assert "unicode_result" in command()
        keys("<Esc>")

        keys(":let g:nested_result = <C-r>=2+3")
        assert "=2+3" in text(), text()
        keys("<CR><CR>")
        assert lua("return vim.g.nested_result") == 5
        keys(":lua vim.g.input_result = vim.fn.input('input-question: ')<CR>")
        assert "input-question:" in text(), text()
        keys("answer<CR>")
        assert lua("return vim.g.input_result") == "answer"
        # Native input() highlight callbacks must survive rendering, including
        # the legacy attribute-only protocol on Neovim 0.10.
        lua("vim.api.nvim_set_hl(0, 'InputToolsNativeColor', {fg='#ff1234', bold=true}); "
            "_G.InputToolsColor = function(s) return {{0, #s, 'InputToolsNativeColor'}} end")
        keys(":lua vim.g.colored_input = vim.fn.input({prompt='Color: ',highlight='v:lua.InputToolsColor'})<CR>")
        keys("你好")
        def colored_cells():
            return [cell for row in ui.grid for cell in row if cell[0] == '你' and ui.attrs.get(cell[1], {}).get('foreground') == 0xff1234]
        assert colored_cells(), "native highlighted Unicode input lost its colors"
        lua("vim.api.nvim_set_hl(0, 'InputToolsNativeColor', {fg='#12ff34'}); vim.cmd('doautocmd ColorScheme')")
        lua("vim.wait(35)")
        assert any(cell[0] == '你' and ui.attrs.get(cell[1], {}).get('foreground') == 0x12ff34 for row in ui.grid for cell in row)
        keys("<CR>")
        assert lua("return vim.g.colored_input") == "你好"

        # Explicit adapter remains available when another plugin owns vim.ui.input.
        lua("saved_input=vim.ui.input; vim.ui.input=function() error('global input owner used') end")
        keys(":lua input.input({prompt='Rename to: ',default='foo',scope='cursor'}, function(v) vim.g.adapter_value=v or '__cancel' end)<CR>")
        assert lua("return input.get_layout().kind") == "input"
        assert lua("return vim.fn.getcmdline()") == "foo"
        keys("<C-u>新名称<CR>")
        assert lua("return vim.g.adapter_value") == "新名称"
        keys(":lua input.input({prompt='Rename to: ',default='foo'}, function(v) vim.g.adapter_value=v or '__cancel' end)<CR>")
        keys("<Esc>")
        assert lua("return vim.g.adapter_value") == "__cancel"
        lua("vim.ui.input=saved_input")

        keys(":function! InputToolsExample()<CR>")
        assert "function! InputToolsExample()" in text(), text()
        keys("return 7<CR>endfunction<CR>")
        keys(":let g:block_result = InputToolsExample()<CR>")
        assert lua("return vim.g.block_result") == 7
        keys("q:")
        assert lua("return vim.fn.getcmdwintype()") == ":"
        keys("<C-c>")
        keys("<Esc>")

        lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'needle one', 'needle two'}); vim.o.inccommand = 'split'")
        keys("/needle")
        assert lua("return input.get_layout().kind") == "search", str(lua("return {layout=input.get_layout(),mode=vim.fn.mode(1),type=vim.fn.getcmdtype()}"))
        assert "/needle" in text(), text()
        keys("<CR>")
        keys(":%s/needle/replacement")
        assert command() == "%s/needle/replacement"
        assert "replacement" in text(), text()
        assert lua("return input.is_enabled()")
        keys("<Esc>")
        lua("vim.o.inccommand = ''")

        lua("vim.api.nvim_create_user_command('InputToolsAlpha', function() end, {}); "
            "vim.api.nvim_create_user_command('InputToolsBeta', function() end, {})")
        keys(":InputTools<Tab>")
        assert floats("menu"), text()
        assert "InputToolsAlpha" in text() and "InputToolsBeta" in text(), text()
        keys("<Tab>")
        keys("<Esc>")
        assert not floats("menu") and not floats("command")
        lua("input.setup({window={row=3}})")
        keys(":InputTools<Tab>")
        palette = lua("return vim.api.nvim_win_get_config(" + str(floats("command")[0]) + ")")
        menu = lua("return vim.api.nvim_win_get_config(" + str(floats("menu")[0]) + ")")
        assert palette["row"] == 3, palette
        assert palette["col"] == (100 - palette["width"] - 2) // 2, palette
        assert menu["row"] >= palette["row"] + palette["height"] + 2, (palette, menu)
        keys("<Esc>")
        # Borderless menus, Unicode clipping and scrolling stay within the
        # screen and keep the selected candidate visible.
        lua("input.setup({window={row=3,width=20,border='none'},popupmenu={border='none',max_height=3,max_width=18}}); "
            "vim.api.nvim_create_user_command('InputToolsList', function() end, {nargs='*',complete=function() "
            "local r={}; for i=1,15 do r[i]='候选项'..i..string.rep('长',20) end; return r end})")
        keys(":InputToolsList <Tab>")
        for _ in range(6):
            keys("<Tab>")
        menu_id = floats("menu")[0]
        menu = lua("return vim.api.nvim_win_get_config(" + str(menu_id) + ")")
        palette = lua("return vim.api.nvim_win_get_config(" + str(floats("command")[0]) + ")")
        assert menu['row'] >= palette['row'] + palette['height']
        assert menu['col'] == palette['col'] and menu['width'] <= 18 and menu['height'] == 3
        assert lua("local w=" + str(menu_id) + "; local b=vim.api.nvim_win_get_buf(w); "
                   "for _,l in ipairs(vim.api.nvim_buf_get_lines(b,0,-1,false)) do if vim.fn.strdisplaywidth(l)>18 then return false end end; "
                   "return #vim.api.nvim_buf_get_extmarks(b,vim.api.nvim_create_namespace('input-tools.view'),0,-1,{details=true})>=4")
        keys("<Esc>")
        lua("input.setup()")
        lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {''}); "
            "_G.InputToolsComplete = function(start) return start == 1 and 0 or {'apple', 'apricot'} end; "
            "vim.bo.omnifunc = 'v:lua.InputToolsComplete'")
        keys("i<C-x><C-o>")
        assert floats("menu") and lua("return vim.fn.pumvisible()") == 1
        keys("<C-n><C-y><Esc>")
        assert lua("return vim.api.nvim_get_current_line()") in ("apple", "apricot")

        keys(":echo 'small-你好'")
        ui.request("nvim_ui_try_resize", [22, 8])
        lua("vim.wait(35)")
        assert lua("return input.is_enabled()") and floats("command"), str(lua("return {status=input.status(), err=vim.v.errmsg}")) + text()
        keys("<Esc>")
        ui.request("nvim_ui_try_resize", [100, 32])
        keys(":InputTools disable<CR>")
        assert not lua("return input.is_enabled()")
        keys(":echo")
        assert ":echo" in text().splitlines()[-1], text()
        keys("<Esc>")
        keys(":InputTools enable<CR>")
        assert lua("return input.is_enabled()")
        keys(":echo")
        assert floats("command")
        keys("<Esc>")
        lua("input.teardown()")
        print("UI: native editing/search/history, Unicode cursor, nested input, substitute preview, command/insert completion, resize and native restoration passed")

        # Scheduled lifecycle handlers may disable the renderer safely. Their
        # errors are reported without losing input ownership or looping.
        lua("input.setup({window={row=3}}); layout_events={}; "
            "vim.api.nvim_create_autocmd('User',{pattern='InputToolsOpen',once=true,callback=function() input.disable() end})")
        keys(":echo")
        assert not lua("return input.is_enabled()")
        assert lua("return input.get_layout()") is None
        assert lua("return layout_events[1].event=='InputToolsOpen' and layout_events[#layout_events].event=='InputToolsClose'")
        keys("<Esc>")
        lua("input.enable(); observer_error=false; "
            "vim.api.nvim_create_autocmd('User',{pattern='InputToolsOpen',once=true,callback=function() observer_error=true; error('observer failure') end})")
        keys(":echo")
        assert lua("return input.is_enabled() and observer_error"), str(lua("return {enabled=input.is_enabled(),error=observer_error,mode=vim.fn.mode(1),cmd=vim.fn.getcmdline(),events=layout_events,errmsg=vim.v.errmsg}"))
        keys("<Esc>")
        lua("input.teardown()")

        notification_root = os.environ.get("NOTIFICATION_TOOLS_ROOT")
        if not notification_root:
            return
        lua("input.setup()")
        lua("vim.opt.rtp:append(" + repr(str(Path(notification_root).resolve())) + "); "
            "notifications = require('notification-tools'); notifications.setup({timeout=0});")
        lua("input.setup()")
        assert not lua("return input.status().notifications")
        lua("notifications.setup({timeout=0, messages={enabled=true}})")
        assert lua("return input.status().notifications")
        keys(":echo '**joint-capture**'<CR>")
        assert any(r["message"] == "**joint-capture**" and not r["markdown"] for r in lua("return notifications.history()"))
        lua("notifications.setup({timeout=0, messages={enabled=true}})")
        assert lua("return input.status().notifications")

        # Observe, without consuming, prompts generated by either UI protocol.
        lua("observer_ns = vim.api.nvim_create_namespace('input-tools.test-observer'); vim.ui_attach(observer_ns, {ext_cmdline=true}, function(e, ...) "
            "local a={...}; if e=='msg_show' and (a[1]=='confirm' or a[1]=='number_prompt' or a[1]=='confirm_sub' or a[1]=='return_prompt' and vim.g.await_return or a[1]=='' and require('input-tools.model').is_prompt(a[1])) "
            "or e=='cmdline_show' and (vim.fn.mode(1):sub(1,1)=='r' or (a[4] or ''):find('__confirm', 1, true) or (a[4] or ''):find('__pick', 1, true)) "
            "then vim.rpcnotify(1, 'test-prompt') end end)")
        lua("input.setup({profiles={confirm={title='Decision'}}})")
        prompt(":lua vim.g.prompt_result = vim.fn.confirm('__confirm-question', '&Yes\\n&No', 2)<CR>", "n", 2)
        assert any("__confirm-question" in frame for frame in ui.frames), "confirmation text was never drawn"
        assert any("Decision" in frame for frame in ui.frames), "confirm profile was not used by the native prompt"
        assert not any("__confirm-question" in r["message"] for r in lua("return notifications.history()"))
        prompt(":lua vim.g.prompt_result = vim.fn.inputlist({'__pick-question', '1. One', '2. Two'})<CR>", "2<CR>", 2)
        assert any("__pick-question" in frame for frame in ui.frames), "inputlist text was never drawn"
        assert not any("__pick-question" in r["message"] for r in lua("return notifications.history()"))
        lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, {'needle'}); vim.api.nvim_win_set_cursor(0, {1,0})")
        prompt(":s/needle/replacement/c<CR>", "n", None)
        assert lua("return vim.api.nvim_get_current_line()") == "needle"
        if lua("return vim.fn.has('nvim-0.11')") == 0:
            lua("input.setup({return_prompt='show'}); vim.g.await_return = true")
            prompt(":messages<CR>", "<CR>", None)
            assert lua("return vim.bo.filetype") == "notification-tools-history"
            keys("q")
            lua("vim.g.await_return = false; input.setup()")
        lua("vim.ui_detach(observer_ns)")

        lua("notifications.teardown()")
        assert lua("return input.is_enabled() and not input.status().notifications and vim.o.cmdheight == 1")
        lua("notifications.setup({timeout=0, messages={enabled=true}})")
        assert lua("return input.status().notifications")
        lua("input.teardown()")
        assert not lua("return require('notification-tools.messages').active()")
        keys(":echo")
        assert ":echo" in text().splitlines()[-1], text()
        keys("<Esc>")
        lua("input.setup(); notifications.setup({messages={enabled=false}})")
        assert lua("return input.is_enabled() and not input.status().notifications")
        lua("notifications.setup({timeout=0, messages={enabled=true}}); input.setup({window={max_width=50}})")
        assert lua("return input.status().notifications")
        lua("input.teardown(); notifications.teardown()")
        print("integration UI: load-order handoff, notifications, visible interactive confirms, reconfiguration and ordered teardown passed")
    finally:
        signal.alarm(0)
        if ui.process.poll() is not None and ui.process.returncode != 0:
            print("Neovim exited:", ui.process.returncode, ui.process.stderr.read().decode())
        ui.close()


if __name__ == "__main__":
    main()
