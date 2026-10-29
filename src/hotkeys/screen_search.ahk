; Screen search hotkey binding.
global Config

if Config.Has("screen_search") && Config["screen_search"]["enabled"] {
    hotkey_name := Config["screen_search"]["hotkey"]
    ; Comma and period are reserved for monitor navigation.
    if (hotkey_name != "" && hotkey_name != "," && hotkey_name != ".")
        RegisterSuperComboHotkey(hotkey_name, (*) => ScreenSearch.Toggle())
}
