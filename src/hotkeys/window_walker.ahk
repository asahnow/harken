; Window walker hotkey binding.
global Config

if Config.Has("window_selector") && Config["window_selector"]["enabled"] {
    hotkey_name := Config["window_selector"]["hotkey"]
    ; Super+w is reserved for closing the active window.
    if (hotkey_name != "" && StrLower(hotkey_name) != "w")
        RegisterSuperComboHotkey(hotkey_name, (*) => WindowWalker.Toggle())
}
