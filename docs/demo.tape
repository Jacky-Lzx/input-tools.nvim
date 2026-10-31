# Real Neovim screenshots: scripts/record-demo.sh resolves @RECORDING@.
Output "@RECORDING@.gif"
Require nvim
Require lua-language-server
Set Shell "bash"
Set Width 1120
Set Height 680
Set FontFamily "Cascadia Mono"
Set FontSize 20
Set Padding 20
Set CursorBlink false
Set TypingSpeed 25ms
Set Theme "Catppuccin Mocha"
Hide
Type "nvim -n -i NONE --noplugin -u examples/demo/init.lua"
Enter
Wait+Screen /LuaLS ready/
Sleep 2s
Show
Type "/timeout_ms"
Wait+Screen /\/timeout_ms/
Sleep 300ms
Screenshot "docs/screenshots/search.png"
Sleep 600ms
Enter
Escape
Type ":%s/timeout_ms/delay_ms/gc"
Enter
Wait+Screen /replace with delay_ms/
Sleep 300ms
Screenshot "docs/screenshots/replace-confirm.png"
Sleep 600ms
Type "q"
Sleep 150ms
Type ":DemoExport"
Enter
Wait+Screen /3: Plain text/
Sleep 350ms
Screenshot "docs/screenshots/select.png"
Sleep 600ms
Type "2"
Enter
Sleep 150ms
Type ":DemoFile"
Enter
Wait+Screen /notes\/release notes.md/
Sleep 300ms
Screenshot "docs/screenshots/file-input.png"
Sleep 600ms
Enter
Sleep 150ms
Type "4G0w"
Type ":DemoRename"
Enter
Sleep 350ms
Escape
Type "ciwrequest_timeout_ms"
Wait+Screen /request_timeout_ms/
Sleep 200ms
Screenshot "docs/screenshots/rename.png"
Sleep 600ms
Enter
Wait+Screen /Rename applied/
Sleep 300ms
Type ":q"
Enter
Wait+Screen /Save changes to/
Sleep 300ms
Screenshot "docs/screenshots/quit-confirm.png"
Sleep 600ms
Type "c"
Sleep 150ms
Hide
Type ":DemoVerify"
Enter
Sleep 200ms
Type ":qa!"
Enter
