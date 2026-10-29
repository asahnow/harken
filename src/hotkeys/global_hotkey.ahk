; Global hotkey bindings (super + key combos).
global Config
global alt_menu_mask_pending := false
global suppressed_super_alt_keys := Map()

for _, hotkey_config in Config["global_hotkeys"] {
    if !hotkey_config["enabled"]
        continue

    send_keys := hotkey_config["send_keys"]
    hotkey_name := hotkey_config["hotkey"]
    ; Standalone Super+Alt is reserved as a no-op. Harken still reads Alt's
    ; physical state when it modifies a window-management shortcut.
    if StrLower(hotkey_name) = "alt"
        continue
    target_exes := hotkey_config["target_exes"]
    callback := SendConfiguredGlobalHotkey.Bind(send_keys)

    if (target_exes.Length > 0) {
        HotIf (*) => ScopedHotIf(target_exes)
        RegisterSuperComboHotkey(hotkey_name, callback)
        HotIf
    } else {
        RegisterSuperComboHotkey(hotkey_name, callback)
    }
}

SendConfiguredGlobalHotkey(send_keys, *) {
    Send(send_keys)
}

MarkSuperAltChordUsed() {
    global alt_menu_mask_pending, suppressed_super_alt_keys
    alt_menu_mask_pending := true
    ; When Super was held first, Alt-down was completely blocked and there is
    ; no application menu state to mask. The fallback is only for Alt-first
    ; ordering, where the application already received Alt-down.
    if suppressed_super_alt_keys.Count > 0
        return
    MaskAltMenuActivation()
    ; Run once more just after the window action. For monitor-follow actions,
    ; that places the mask on the moved/reactivated application frame.
    SetTimer(MaskAltMenuActivation, -10)
}

MaskAltMenuActivation() {
    if !GetKeyState("LAlt", "P") && !GetKeyState("RAlt", "P")
        return

    ; Super is implemented as a custom combination, so an Alt suffix does not
    ; receive AutoHotkey's normal Alt-menu masking. An otherwise unused virtual
    ; key makes the eventual physical Alt-up part of a chord without changing
    ; the user's modifier state or invoking an application command.
    SendEvent("{Blind}{vkE8}")
}

AltMenuMaskPending(*) {
    global alt_menu_mask_pending
    return alt_menu_mask_pending
}

SuppressSuperAltDown(alt_key, *) {
    global alt_menu_mask_pending, suppressed_super_alt_keys
    suppressed_super_alt_keys[alt_key] := true
    alt_menu_mask_pending := true
    ; Do not send anything: the application never receives this Alt-down.
}

CompleteAltMenuMask(alt_key, *) {
    global alt_menu_mask_pending, suppressed_super_alt_keys
    if !alt_menu_mask_pending
        return

    if suppressed_super_alt_keys.Has(alt_key) {
        suppressed_super_alt_keys.Delete(alt_key)
        alt_menu_mask_pending := suppressed_super_alt_keys.Count > 0
        ; Its down event was blocked, so block the matching up event too.
        QueueSuperAltMenuCancellation()
        return
    }
    alt_menu_mask_pending := false

    ; Consume the physical Alt-up and replace it with a complete masked
    ; sequence on whichever application owns the destination foreground by
    ; then. Some legacy menu implementations ignore vkE8, while the standard
    ; Ctrl mask reliably marks Alt as part of a chord. Never synthesize a Ctrl
    ; release over a physically held Ctrl key.
    mask_keys := (
        GetKeyState("LCtrl", "P") || GetKeyState("RCtrl", "P")
            ? "{vkE8}"
            : "{LCtrl Down}{LCtrl Up}"
    )
    SendEvent("{Blind}" mask_keys "{" alt_key " Up}")
    QueueSuperAltMenuCancellation()
}

QueueSuperAltMenuCancellation() {
    ; A few legacy applications poll physical modifier state and enter menu
    ; mode even though their Alt messages were blocked. Queue distinct one-shot
    ; callbacks across their release-processing window. WM_CANCELMODE is a
    ; no-op when no menu/tracking mode is active and is not a keystroke.
    SetTimer(CancelForegroundMenuMode.Bind(), -10)
    SetTimer(CancelForegroundMenuMode.Bind(), -100)
}

CancelForegroundMenuMode(*) {
    foreground_hwnd := DllCall("GetForegroundWindow", "Ptr")
    if !foreground_hwnd
        return false

    try {
        thread_id := DllCall(
            "GetWindowThreadProcessId",
            "Ptr", foreground_hwnd,
            "Ptr", 0,
            "UInt"
        )
        info_size := A_PtrSize = 8 ? 72 : 48
        menu_owner_offset := A_PtrSize = 8 ? 32 : 20
        thread_info := Buffer(info_size, 0)
        NumPut("UInt", info_size, thread_info, 0)
        has_thread_info := thread_id && DllCall(
            "GetGUIThreadInfo",
            "UInt", thread_id,
            "Ptr", thread_info.Ptr,
            "Int"
        )

        ; Native menus expose hwndMenuOwner; custom legacy menu bars often do
        ; not, so always include the foreground root. WM_CANCELMODE asks either
        ; implementation to leave tracking without delivering application
        ; input, and does nothing when there is no active mode to cancel.
        targets := Map(foreground_hwnd, true)
        menu_owner := has_thread_info
            ? NumGet(thread_info, menu_owner_offset, "Ptr")
            : 0
        if menu_owner
            targets[menu_owner] := true
        root_hwnd := DllCall(
            "GetAncestor",
            "Ptr", foreground_hwnd,
            "UInt", 2, ; GA_ROOT
            "Ptr"
        )
        if root_hwnd
            targets[root_hwnd] := true
        for target_hwnd in targets
            PostMessage(0x001F, 0, 0, , "ahk_id " target_hwnd) ; WM_CANCELMODE
        return true
    }
    catch {
        return false
    }
}

HotIf IsSuperKeyPressed
Hotkey("*LAlt", SuppressSuperAltDown.Bind("LAlt"))
Hotkey("*RAlt", SuppressSuperAltDown.Bind("RAlt"))
HotIf

HotIf AltMenuMaskPending
Hotkey("*LAlt Up", CompleteAltMenuMask.Bind("LAlt"))
Hotkey("*RAlt Up", CompleteAltMenuMask.Bind("RAlt"))
HotIf

ScopedHotIf(target_exes, *) {
    for _, exe in target_exes {
        if WinActive("ahk_exe " exe)
            return true
    }
    return false
}
