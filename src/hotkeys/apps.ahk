; App hotkey bindings (launch or focus).
global Config

; App launchers are plain Super chords. Keeping modifier tiers separate lets
; window-management bindings such as Super+Ctrl+f coexist with Super+f.
HotIf (*) => (
    !GetKeyState("Shift", "P")
    && !GetKeyState("Ctrl", "P")
    && !IsAltPressed()
)
for _, app in Config["apps"] {
    if !app.Has("hotkey") || app["hotkey"] = ""
        continue
    hotkey_name := app["hotkey"]
    win_title := app.Has("win_title") ? app["win_title"] : ""
    run_cmd := app.Has("run") ? app["run"] : ""
    hotkey_id := app["id"]
    ; Explicit configured-Super combinations work reliably when Super itself
    ; is LWin/RWin, which AutoHotkey otherwise treats as extra modifiers.
    RegisterSuperComboHotkey(
        hotkey_name,
        FocusOrRun.Bind(win_title, run_cmd, hotkey_id, app)
    )
}
HotIf
