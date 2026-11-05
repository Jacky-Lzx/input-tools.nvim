#!/usr/bin/env python3
"""Native search colors must never replace input or completion popup colors."""
import os
import signal
from rpc import Capture


class SearchCapture(Capture):
    def __init__(self):
        super().__init__(os.environ.copy())
        self.source = None
        self.source_frames = 0
        self.source_bad = []
        self.checked = 0
        self.bad = []

    def redraw(self, events):
        for event in events:
            super().redraw([event])
            if event[0] != "flush":
                continue
            if self.source is not None:
                self.source_frames += 1
                for row in (15, 20):
                    char, attr = self.grid[row][0]
                    color = self.attrs.get(attr, {}).get("background")
                    expected = 0x00ff00 if row == self.source else 0xff0000
                    if char != "n" or color != expected:
                        self.source_bad.append((row, char, color))
            for row in self.grid[:13]:
                text = "".join(cell[0] for cell in row)
                start = text.lower().find("norm")
                if start < 0:
                    continue
                self.checked += 1
                for char, attr in row[start:start + 4]:
                    color = self.attrs.get(attr, {}).get("background")
                    if color in (0xff0000, 0x00ff00, 0x0000ff):
                        self.bad.append((text, char, color))


def main():
    def timeout(*_):
        raise TimeoutError("search highlight UI test timed out")

    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(20)
    ui = SearchCapture()

    def lua(code):
        return ui.request("nvim_exec_lua", [code, []])

    def keys(value):
        ui.request("nvim_input", [value])
        lua("vim.wait(35)")

    try:
        ui.request("nvim_ui_attach", [100, 36, {"rgb": True, "ext_linegrid": True}])
        lua("""
            vim.opt.rtp:prepend(vim.fn.getcwd())
            require('input-tools').setup({status=false,window={row=3,width=40}})
            vim.o.hlsearch,vim.o.incsearch,vim.o.ignorecase=true,true,true
            vim.o.laststatus=0
            vim.api.nvim_set_hl(0,'Search',{bg=0xff0000})
            vim.api.nvim_set_hl(0,'IncSearch',{bg=0x00ff00})
            vim.api.nvim_set_hl(0,'CurSearch',{bg=0x0000ff})
            local lines={}; for i=1,30 do lines[i]='' end
            lines[16],lines[21]='normalized','normalized'
            vim.api.nvim_buf_set_lines(0,0,-1,false,lines)
            vim.api.nvim_create_user_command('NormalAlpha',function() end,{})
            vim.api.nvim_create_user_command('NormalBeta',function() end,{})
            vim.o.wildmode,vim.o.wildoptions='full','pum'
        """)
        for kind in ("/", "?"):
            lua("vim.api.nvim_win_set_cursor(0,{1,0})")
            keys(kind + "norm")
            ui.source = 15 if kind == "/" else 20
            for key in ("a", "l", "i", "z", "<BS>", "zed"):
                keys(key)
            source_colors = [ui.attrs.get(ui.grid[row][0][1], {}).get("background") for row in (15, 20)]
            assert 0xff0000 in source_colors and 0x00ff00 in source_colors, source_colors
            ui.source = None
            assert ui.source_frames > 0 and not ui.source_bad, ui.source_bad[:6]
            at = lua("local c=require('input-tools.view').cursor; return vim.fn.screenpos(c.win,c.row,c.col+1)")
            assert ui.cursor == [1, at['row'] - 1, at['col'] - 1], (ui.cursor, at)
            keys("<CR>")
        lua("vim.fn.setreg('/','Normal'); vim.v.hlsearch=1")
        keys(":Normal<Tab>")
        assert lua("""for _,w in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(w)].filetype=='input-tools-menu' then return true end
            end return false"""), "native completion popup was not shown"
        lua("vim.cmd.redraw(); vim.wait(35)")
        assert ui.checked > 0, "no input or menu frames checked"
        assert not ui.bad, ui.bad[:5]
        keys("<Esc>")
        print(f"search UI: {ui.checked} input/menu frames preserve their colors during /, ?, completion and redraw")
    finally:
        signal.alarm(0)
        ui.close()


if __name__ == "__main__":
    main()
