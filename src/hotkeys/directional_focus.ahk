; Directional focus hotkey bindings.
global Config

if Config.Has("directional_focus") && Config["directional_focus"]["enabled"] {
    ; Register against each configured super key so LWin/RWin combinations
    ; override Windows' native shortcuts instead of depending on Alt.
    HotIf (*) => (
        !GetKeyState("Shift", "P")
        && !GetKeyState("Ctrl", "P")
        && !IsAltPressed()
    )
    RegisterSuperComboHotkey("n", (*) => DirectionalFocus("left"))
    RegisterSuperComboHotkey("e", (*) => DirectionalFocus("down"))
    RegisterSuperComboHotkey("i", (*) => DirectionalFocus("up"))
    RegisterSuperComboHotkey("o", (*) => DirectionalFocus("right"))
    RegisterSuperComboHotkey("Left", (*) => DirectionalFocus("left"))
    RegisterSuperComboHotkey("Down", (*) => DirectionalFocus("down"))
    RegisterSuperComboHotkey("Up", (*) => DirectionalFocus("up"))
    RegisterSuperComboHotkey("Right", (*) => DirectionalFocus("right"))
    HotIf

    HotIf (*) => !IsSuperKeyPressed()
    Hotkey("!+d", (*) => ToggleDirectionalFocusDebug())
    Hotkey("!+s", (*) => SetLastStackedFromActive())
    HotIf
}
