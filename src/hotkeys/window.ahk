global Config

resize_step := Config["window"]["resize_step"]
move_step := Config["window"]["move_step"]
coarse_resize_step := Config["window"].Has("coarse_resize_step")
    ? Config["window"]["coarse_resize_step"]
    : 75
coarse_move_step := Config["window"].Has("coarse_move_step")
    ? Config["window"]["coarse_move_step"]
    : 75
super_double_tap_ms := Config["window"]["super_double_tap_ms"]
move_mode_enabled := Config["window"]["move_mode"]["enable"]
move_mode_cancel_key := Config["window"]["move_mode"]["cancel_key"]
; Window hotkeys (resize/move/cycle) and virtual desktop bindings.
cycle_app_windows_hotkey := Config["window"]["cycle_app_windows_hotkey"]
cycle_app_windows_current_hotkey := Config["window"]["cycle_app_windows_current_hotkey"]
vd_config := Config.Has("virtual_desktop") ? Config["virtual_desktop"] : Map()
vd_prev_hotkey := vd_config.Has("prev_hotkey") ? vd_config["prev_hotkey"] : ""
vd_next_hotkey := vd_config.Has("next_hotkey") ? vd_config["next_hotkey"] : ""
vd_move_prev_hotkey := vd_config.Has("move_prev_hotkey") ? vd_config["move_prev_hotkey"] : ""
vd_move_next_hotkey := vd_config.Has("move_next_hotkey") ? vd_config["move_next_hotkey"] : ""
vd_desktop_hotkeys := vd_config.Has("desktop_hotkeys") ? vd_config["desktop_hotkeys"] : []
vd_goto_hotkeys := vd_config.Has("goto_hotkeys") ? vd_config["goto_hotkeys"] : []
vd_move_hotkeys := vd_config.Has("move_hotkeys") ? vd_config["move_hotkeys"] : []
minimize_others_hotkey := ""
if Config["window"].Has("minimize_others_hotkey")
    minimize_others_hotkey := Config["window"]["minimize_others_hotkey"]

vd_prev_hotkey := NormalizeAltHotkey(vd_prev_hotkey)
vd_next_hotkey := NormalizeAltHotkey(vd_next_hotkey)
vd_move_prev_hotkey := NormalizeAltHotkey(vd_move_prev_hotkey, true)
vd_move_next_hotkey := NormalizeAltHotkey(vd_move_next_hotkey, true)

last_super_tap := 0
previous_window_geometry := Map()
geometry_restore_in_progress := false
geometry_mode_action_state := Map()
geometry_mode_session := Map()
minimized_window_history := []
last_managed_focus_monitor := MonitorGetPrimary()
desktop_focus_history := Map()
desktop_focus_last_desktop := VirtualDesktopEnabled() ? GetCurrentDesktopNumFresh() : 0
app_cycle_cache := Map()
cycle_hwnd_desktop := Map()
debug_logs_initialized := false
screen_capture_active := false
taskbar_focus_grace_hwnd := 0
taskbar_focus_grace_started_at := 0
taskbar_mouse_down := false
taskbar_mouse_down_at := 0
taskbar_mouse_released_at := 0
known_top_level_windows := Map()
for hwnd in WinGetList()
    known_top_level_windows[hwnd] := true
foreground_attention_callback := 0
foreground_attention_hook := 0
if VirtualDesktopEnabled() {
    foreground_attention_callback := CallbackCreate(
        OnForegroundAttentionEvent,
        ,
        7
    )
    foreground_attention_hook := DllCall(
        "SetWinEventHook",
        "UInt", 0x0003, ; EVENT_SYSTEM_FOREGROUND
        "UInt", 0x0003,
        "Ptr", 0,
        "Ptr", foreground_attention_callback,
        "UInt", 0,
        "UInt", 0,
        "UInt", 0x0002, ; WINEVENT_SKIPOWNPROCESS | OUTOFCONTEXT
        "Ptr"
    )
    OnExit(ReleaseForegroundAttentionHook)
}

IsEligibleManagedForeground(hwnd) {
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return false
    try {
        ; A disabled frame normally has an active modal popup. Never remember
        ; or recover to the owner while the user must interact with its dialog.
        if !DllCall("IsWindowEnabled", "Ptr", hwnd, "Int")
            return false
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            return false
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            return false
        ex_style := WinGetExStyle("ahk_id " hwnd)
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            return false
        if !IsWindowOnCurrentDesktop(hwnd)
            return false
        return true
    }
    catch {
        return false
    }
}

FindEnabledOwnedPopup(hwnd) {
    if !hwnd
        return 0
    try {
        if DllCall("IsWindowEnabled", "Ptr", hwnd, "Int")
            return 0

        root_owner := DllCall(
            "GetAncestor",
            "Ptr", hwnd,
            "UInt", 3, ; GA_ROOTOWNER
            "Ptr"
        )
        if !root_owner
            root_owner := hwnd

        ; GW_ENABLEDPOPUP returns the enabled popup owned by this frame, or the
        ; frame itself when no such popup exists.
        popup := DllCall(
            "GetWindow",
            "Ptr", root_owner,
            "UInt", 6, ; GW_ENABLEDPOPUP
            "Ptr"
        )
        if !popup || popup = root_owner
            return 0
        if !DllCall("IsWindow", "Ptr", popup, "Int")
            return 0
        if !DllCall("IsWindowVisible", "Ptr", popup, "Int")
            return 0
        if !DllCall("IsWindowEnabled", "Ptr", popup, "Int")
            return 0
        if !IsWindowOnCurrentDesktop(popup)
            return 0
        return popup
    }
    catch {
        ; Owned dialogs can close while the focus observer is inspecting them.
        return 0
    }
}

ActivateForegroundOwnedPopup(hwnd) {
    popup := FindEnabledOwnedPopup(hwnd)
    if !popup
        return false
    try {
        WinActivate("ahk_id " popup)
        return WinWaitActive("ahk_id " popup, , 0.15) != 0
    }
    catch {
        return false
    }
}

IsNewDialogForForeground(hwnd, foreground_hwnd) {
    if !hwnd || !foreground_hwnd || hwnd = foreground_hwnd
        return false
    try {
        if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
            return false
        if !DllCall("IsWindowEnabled", "Ptr", hwnd, "Int")
            return false
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            return false

        ex_style := WinGetExStyle("ahk_id " hwnd)
        if (ex_style & 0x8000000) ; WS_EX_NOACTIVATE
            return false

        style := WinGetStyle("ahk_id " hwnd)
        ; Context menus and dropdown surfaces can carry WS_EX_DLGMODALFRAME,
        ; but unlike a real top-level dialog they do not have a caption. Never
        ; call WinActivate on those transient HWNDs because doing so dismisses
        ; the menu that created them.
        if ((style & 0x00C00000) != 0x00C00000) ; WS_CAPTION
            return false

        class_name := WinGetClass("ahk_id " hwnd)
        ; #32770 is the system dialog class. WS_EX_DLGMODALFRAME also covers
        ; captioned application-defined dialogs which use another class name.
        if (class_name != "#32770" && !(ex_style & 0x1))
            return false

        owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr") ; GW_OWNER
        dialog_root := DllCall(
            "GetAncestor",
            "Ptr", hwnd,
            "UInt", 3, ; GA_ROOTOWNER
            "Ptr"
        )
        foreground_root := DllCall(
            "GetAncestor",
            "Ptr", foreground_hwnd,
            "UInt", 3, ; GA_ROOTOWNER
            "Ptr"
        )

        related_by_owner := (
            owner = foreground_hwnd
            || (dialog_root && dialog_root = foreground_root)
        )
        if !related_by_owner {
            dialog_pid := WinGetPID("ahk_id " hwnd)
            foreground_pid := WinGetPID("ahk_id " foreground_hwnd)
            if !dialog_pid || dialog_pid != foreground_pid
                return false
        }

        return IsWindowOnCurrentDesktop(hwnd)
    }
    catch {
        ; Dialogs can close between enumeration and relationship checks.
        return false
    }
}

ActivateNewDialogForForeground(*) {
    global known_top_level_windows

    foreground_hwnd := DllCall("GetForegroundWindow", "Ptr")
    current_windows := Map()
    candidate := 0
    for hwnd in WinGetList() {
        current_windows[hwnd] := true
        ; WinGetList is ordered front-to-back, so retain the first qualifying
        ; newly shown dialog if several appear in one observer interval.
        if (
            !candidate
            && !known_top_level_windows.Has(hwnd)
            && IsNewDialogForForeground(hwnd, foreground_hwnd)
        )
            candidate := hwnd
    }
    known_top_level_windows := current_windows

    if !candidate
        return false
    try {
        WinActivate("ahk_id " candidate)
        return WinWaitActive("ahk_id " candidate, , 0.15) != 0
    }
    catch {
        return false
    }
}

GetWindowTaskbarIdentity(hwnd) {
    identity := Map("app_id", "", "process_path", "", "pid", 0)
    if !hwnd
        return identity

    try identity["pid"] := WinGetPID("ahk_id " hwnd)
    try identity["process_path"] := StrLower(WinGetProcessPath("ahk_id " hwnd))

    ; The taskbar's explicit grouping identity is PKEY_AppUserModel_ID. Legacy
    ; applications often omit it, in which case Windows falls back to process
    ; identity and Harken does the same below.
    iid_store := Buffer(16, 0)
    property_key := Buffer(20, 0)
    property_value := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    store := 0
    try {
        DllCall(
            "ole32\CLSIDFromString",
            "WStr", "{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}",
            "Ptr", iid_store.Ptr,
            "HRESULT"
        )
        DllCall(
            "ole32\CLSIDFromString",
            "WStr", "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}",
            "Ptr", property_key.Ptr,
            "HRESULT"
        )
        NumPut("UInt", 5, property_key, 16) ; PKEY_AppUserModel_ID PID
        result := DllCall(
            "shell32\SHGetPropertyStoreForWindow",
            "Ptr", hwnd,
            "Ptr", iid_store.Ptr,
            "Ptr*", &store,
            "HRESULT"
        )
        if result >= 0 && store {
            result := ComCall(
                5,
                store,
                "Ptr", property_key.Ptr,
                "Ptr", property_value.Ptr,
                "HRESULT"
            )
            if result >= 0 && NumGet(property_value, 0, "UShort") = 31 {
                value_ptr := NumGet(property_value, 8, "Ptr")
                if value_ptr
                    identity["app_id"] := StrLower(StrGet(value_ptr, "UTF-16"))
            }
        }
    }
    catch {
        ; Explicit AppUserModelID is optional, especially for legacy windows.
    }
    finally {
        try DllCall(
            "ole32\PropVariantClear",
            "Ptr", property_value.Ptr,
            "HRESULT"
        )
        if store
            ObjRelease(store)
    }
    return identity
}

WindowSharesTaskbarIdentity(hwnd, identity) {
    if !hwnd
        return false
    peer := GetWindowTaskbarIdentity(hwnd)
    if (
        identity["app_id"] != ""
        && peer["app_id"] != ""
    )
        return identity["app_id"] = peer["app_id"]
    if (
        identity["process_path"] != ""
        && peer["process_path"] != ""
    )
        return identity["process_path"] = peer["process_path"]
    return identity["pid"] && identity["pid"] = peer["pid"]
}

ClearCrossDesktopAttentionForForegroundWindow(hwnd, retry := true) {
    if !WindowExistsAcrossDesktops(hwnd)
        return false

    try {
        if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
            return false
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            return false
        if !IsWindowOnCurrentDesktop(hwnd)
            return false

        foreground_hwnd := DllCall("GetForegroundWindow", "Ptr")
        if !foreground_hwnd
            return false
        window_root := DllCall(
            "GetAncestor",
            "Ptr", hwnd,
            "UInt", 2, ; GA_ROOT
            "Ptr"
        )
        foreground_root := DllCall(
            "GetAncestor",
            "Ptr", foreground_hwnd,
            "UInt", 2, ; GA_ROOT
            "Ptr"
        )
        if (foreground_hwnd != hwnd && foreground_root != window_root)
            return false

        current_desktop := GetCurrentDesktopNumFresh()
        taskbar_identity := GetWindowTaskbarIdentity(hwnd)
        cleared_related := false

        ; An owned window may live on the current desktop while its root-owner
        ; frame remains on the desktop where the launch originated.
        root_owner := DllCall(
            "GetAncestor",
            "Ptr", hwnd,
            "UInt", 3, ; GA_ROOTOWNER
            "Ptr"
        )
        if root_owner && root_owner != hwnd {
            owner_desktop := GetWindowDesktopNum(root_owner)
            if (
                current_desktop > 0
                && owner_desktop > 0
                && owner_desktop != current_desktop
            ) {
                ClearWindowAttention(root_owner)
                cleared_related := true
            }
        }

        ; Match the taskbar's AppUserModelID when present. Process path/PID are
        ; fallbacks for legacy software that relies on Windows' implicit group.
        if current_desktop > 0 {
            for peer_hwnd in GetWindowsAcrossDesktops() {
                if peer_hwnd = hwnd
                    continue
                try {
                    if !WindowSharesTaskbarIdentity(peer_hwnd, taskbar_identity)
                        continue
                    peer_desktop := GetWindowDesktopNum(peer_hwnd)
                    if (peer_desktop > 0 && peer_desktop != current_desktop) {
                        ClearWindowAttention(peer_hwnd)
                        cleared_related := true
                    }
                }
            }
        }

        ; Never apply attention APIs to the foreground window during ordinary
        ; same-desktop switching. Only confirmed related windows on another
        ; desktop are eligible for cleanup.
        if retry && cleared_related
            SetTimer(
                ClearCrossDesktopAttentionForForegroundWindow.Bind(hwnd, false),
                -500
            )
        return cleared_related
    }
    catch {
        ; Launch surfaces may disappear or change ownership while the queued
        ; foreground-event handler is inspecting them.
        return false
    }
}

OnForegroundAttentionEvent(
    hook,
    event,
    hwnd,
    object_id,
    child_id,
    event_thread,
    event_time
) {
    if event != 0x0003 || !hwnd
        return
    ; Leave the WinEvent callback immediately. The queued script timer runs in
    ; Harken's normal thread after Windows finishes assigning foreground state.
    SetTimer(ClearCrossDesktopAttentionForForegroundWindow.Bind(hwnd), -1)
}

ReleaseForegroundAttentionHook(*) {
    global foreground_attention_callback, foreground_attention_hook
    if foreground_attention_hook {
        DllCall("UnhookWinEvent", "Ptr", foreground_attention_hook, "Int")
        foreground_attention_hook := 0
    }
    if foreground_attention_callback {
        CallbackFree(foreground_attention_callback)
        foreground_attention_callback := 0
    }
}

ShouldRecoverManagedFocus(hwnd) {
    if !hwnd
        return true
    try {
        class_name := WinGetClass("ahk_id " hwnd)
        if (
            class_name = "Progman"
            || class_name = "WorkerW"
            || class_name = "Shell_TrayWnd"
            || class_name = "Shell_SecondaryTrayWnd"
        )
            return true
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            return true
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            return true
        if !IsWindowOnCurrentDesktop(hwnd)
            return true
    }
    catch {
        return true
    }

    ; Visible excluded/tool surfaces may be intentional (Search, menus,
    ; inspectors), so leave their focus alone.
    return false
}

IsTaskbarWindow(hwnd) {
    if !hwnd
        return false
    try {
        class_name := WinGetClass("ahk_id " hwnd)
        return (
            class_name = "Shell_TrayWnd"
            || class_name = "Shell_SecondaryTrayWnd"
        )
    }
    catch {
        return false
    }
}

IsPointerOverTaskbar(*) {
    try {
        MouseGetPos(, , &point_hwnd)
        if !point_hwnd
            return false
        root_hwnd := DllCall(
            "GetAncestor",
            "Ptr", point_hwnd,
            "UInt", 2, ; GA_ROOT
            "Ptr"
        )
        return IsTaskbarWindow(root_hwnd)
    }
    catch {
        return false
    }
}

BeginTaskbarFocusTransaction(*) {
    global taskbar_mouse_down, taskbar_mouse_down_at
    global taskbar_mouse_released_at

    ; The taskbar does not reliably become the foreground HWND during an app
    ; button click. Observe the passthrough mouse press itself so Harken cannot
    ; race the shell while it restores, raises, or minimizes the target window.
    taskbar_mouse_down := true
    taskbar_mouse_down_at := A_TickCount
    taskbar_mouse_released_at := 0
}

EndTaskbarFocusTransaction(*) {
    global taskbar_mouse_down, taskbar_mouse_down_at
    global taskbar_mouse_released_at
    if !taskbar_mouse_down
        return

    taskbar_mouse_down := false
    taskbar_mouse_down_at := 0
    taskbar_mouse_released_at := A_TickCount
}

IsTaskbarFocusTransactionActive(*) {
    global taskbar_mouse_down, taskbar_mouse_down_at
    global taskbar_mouse_released_at
    static settle_ms := 1250
    static stuck_press_ms := 10000

    if taskbar_mouse_down {
        ; Do not allow a lost mouse-up event to disable recovery indefinitely.
        if A_TickCount - taskbar_mouse_down_at < stuck_press_ms
            return true
        taskbar_mouse_down := false
        taskbar_mouse_down_at := 0
    }

    if !taskbar_mouse_released_at
        return false
    if A_TickCount - taskbar_mouse_released_at < settle_ms
        return true

    taskbar_mouse_released_at := 0
    return false
}

ShouldDeferTaskbarFocusRecovery(hwnd) {
    global taskbar_focus_grace_hwnd, taskbar_focus_grace_started_at
    static grace_ms := 1250

    if IsTaskbarFocusTransactionActive()
        return true

    if !IsTaskbarWindow(hwnd) {
        taskbar_focus_grace_hwnd := 0
        taskbar_focus_grace_started_at := 0
        return false
    }

    ; A taskbar button temporarily foregrounds Explorer while it restores and
    ; raises the selected application. Give that shell transaction one fixed
    ; grace period instead of racing it with Harken's 250 ms focus recovery.
    if (
        taskbar_focus_grace_hwnd != hwnd
        || taskbar_focus_grace_started_at = 0
    ) {
        taskbar_focus_grace_hwnd := hwnd
        taskbar_focus_grace_started_at := A_TickCount
    }

    return A_TickCount - taskbar_focus_grace_started_at < grace_ms
}

EnsureManagedWindowFocused(preferred_monitor := 0, force_preferred := false, *) {
    global last_managed_focus_monitor, screen_capture_active
    static recovering := false
    if recovering || ReloadModeActive() || screen_capture_active
        return false
    if (ScreenSearch.IsActive())
        return false

    monitor_count := MonitorGetCount()
    if (preferred_monitor < 1 || preferred_monitor > monitor_count)
        preferred_monitor := last_managed_focus_monitor
    if (preferred_monitor < 1 || preferred_monitor > monitor_count)
        preferred_monitor := MonitorGetPrimary()

    active_hwnd := DllCall("GetForegroundWindow", "ptr")
    if ActivateForegroundOwnedPopup(active_hwnd)
        return true
    if ShouldDeferTaskbarFocusRecovery(active_hwnd)
        return false

    if IsEligibleManagedForeground(active_hwnd) {
        active_monitor := Screen.FromWindow("ahk_id " active_hwnd)
        if (!force_preferred || active_monitor = preferred_monitor) {
            last_managed_focus_monitor := active_monitor
            return true
        }
    } else if !ShouldRecoverManagedFocus(active_hwnd) {
        return false
    }
    if IsOverviewActive()
        return false

    recovering := true
    try {
        if Window.ActivateMostRecentWindowOnMonitor(preferred_monitor) {
            last_managed_focus_monitor := preferred_monitor
            return true
        }

        loop monitor_count {
            monitor_number := A_Index
            if (monitor_number = preferred_monitor)
                continue
            if Window.ActivateMostRecentWindowOnMonitor(monitor_number) {
                last_managed_focus_monitor := monitor_number
                return true
            }
        }
    }
    finally {
        recovering := false
    }
    return false
}

RememberDesktopFocusedWindow(desktop_num := 0) {
    global desktop_focus_history, last_managed_focus_monitor
    if !VirtualDesktopEnabled()
        return false

    if (desktop_num <= 0)
        desktop_num := VD.getCurrentDesktopNum()
    hwnd := DllCall("GetForegroundWindow", "ptr")
    if (desktop_num <= 0 || !IsEligibleManagedForeground(hwnd))
        return false

    ; During the desktop transition Windows can expose the destination's
    ; foreground window before VD's cached current-desktop number changes.
    ; Do not accidentally record that window against the desktop being left.
    window_desktop := GetWindowDesktopNum(hwnd)
    if (window_desktop > 0 && window_desktop != desktop_num)
        return false

    monitor_number := Screen.FromWindow("ahk_id " hwnd)
    desktop_focus_history[desktop_num] := Map(
        "hwnd", hwnd,
        "monitor", monitor_number
    )
    last_managed_focus_monitor := monitor_number
    return true
}

ClearWindowAttention(hwnd, retry := true) {
    if !hwnd
        return false

    try {
        if !DllCall("IsWindow", "Ptr", hwnd, "Int")
            return false

        ; Taskbar attention belongs to the root-owner frame even when a child
        ; dialog currently has focus. Clear both handles defensively because
        ; applications differ in which one they pass to FlashWindowEx.
        targets := Map(hwnd, true)
        root_owner := DllCall(
            "GetAncestor",
            "Ptr", hwnd,
            "UInt", 3, ; GA_ROOTOWNER
            "Ptr"
        )
        if root_owner
            targets[root_owner] := true

        for target_hwnd in targets {
            if !DllCall("IsWindow", "Ptr", target_hwnd, "Int")
                continue

            ; FLASHWINFO is naturally aligned: HWND starts at byte 8 on x64
            ; and byte 4 on x86. FLASHW_STOP (zero) removes the taskbar's
            ; flashing and persistent orange attention state without focus.
            info_size := A_PtrSize = 8 ? 32 : 20
            hwnd_offset := A_PtrSize = 8 ? 8 : 4
            flags_offset := A_PtrSize = 8 ? 16 : 8
            flash_info := Buffer(info_size, 0)
            NumPut("UInt", info_size, flash_info, 0)
            NumPut("Ptr", target_hwnd, flash_info, hwnd_offset)
            NumPut("UInt", 0, flash_info, flags_offset) ; FLASHW_STOP
            DllCall("FlashWindowEx", "Ptr", flash_info.Ptr, "Int")
        }

        ; Some applications request attention during the tail end of the
        ; desktop animation. Repeat once after it settles, still scoped to the
        ; exact window participating in this transition.
        if retry
            SetTimer(ClearWindowAttention.Bind(hwnd, false), -350)
        return true
    }
    catch {
        return false
    }
}

RestoreDesktopFocusedWindow(desktop_num := 0) {
    global desktop_focus_history, desktop_focus_last_desktop
    global last_managed_focus_monitor
    if !VirtualDesktopEnabled()
        return EnsureManagedWindowFocused()

    current := GetCurrentDesktopNumFresh()
    if (current <= 0)
        current := VD.getCurrentDesktopNum()
    if (desktop_num <= 0)
        desktop_num := current
    ; A delayed observer must never activate a window after the user has
    ; already continued to another desktop.
    if (current <= 0 || desktop_num != current)
        return false

    desktop_focus_last_desktop := current
    preferred_monitor := 0
    if desktop_focus_history.Has(current) {
        entry := desktop_focus_history[current]
        ; Accept the older in-memory format during a live script update.
        hwnd := entry is Map ? entry["hwnd"] : entry
        if (entry is Map && entry.Has("monitor"))
            preferred_monitor := entry["monitor"]
        if IsEligibleManagedForeground(hwnd) {
            try {
                ; VD's arrival callback may already have selected this exact
                ; remembered window. Do not activate it a second time: rapid
                ; competing foreground requests can set taskbar attention.
                is_active := DllCall("GetForegroundWindow", "Ptr") = hwnd
                if !is_active {
                    WinActivate("ahk_id " hwnd)
                    is_active := WinWaitActive("ahk_id " hwnd, , 0.25) != 0
                }
                if is_active {
                    last_managed_focus_monitor := Screen.FromWindow("ahk_id " hwnd)
                    ClearWindowAttention(hwnd)
                    return true
                }
            }
        } else if !WindowExistsAcrossDesktops(hwnd) {
            desktop_focus_history.Delete(current)
        }
    }

    return EnsureManagedWindowFocused(
        preferred_monitor,
        preferred_monitor > 0
    )
}

MaintainManagedWindowFocus(*) {
    global desktop_focus_last_desktop
    ; Suspend every automatic activation path for the complete taskbar click,
    ; including the interval where Windows exposes no taskbar foreground HWND.
    if IsTaskbarFocusTransactionActive()
        return
    if ActivateNewDialogForForeground()
        return
    if VirtualDesktopEnabled() {
        current := VD.getCurrentDesktopNum()
        if (current > 0 && current != desktop_focus_last_desktop) {
            ; The periodic observer covers switches made by Windows itself,
            ; gestures, and other tools in addition to Harken hotkeys.
            desktop_focus_last_desktop := current
            RestoreDesktopFocusedWindow(current)
            return
        }
    }

    EnsureManagedWindowFocused()
    RememberDesktopFocusedWindow()
}

RememberWindowGeometry(target := "A") {
    global previous_window_geometry, geometry_restore_in_progress
    if geometry_restore_in_progress
        return false

    hwnd := IsInteger(target) ? target : WinExist(target)
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return false

    try {
        min_max := WinGetMinMax("ahk_id " hwnd)
        if (min_max = -1)
            return false
        WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)
        if (w <= 0 || h <= 0)
            return false
        previous_window_geometry[hwnd] := Map(
            "x", x,
            "y", y,
            "w", w,
            "h", h,
            "min_max", min_max
        )
        return true
    }
    catch {
        return false
    }
}

CaptureWindowGeometry(hwnd) {
    try {
        min_max := WinGetMinMax("ahk_id " hwnd)
        WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)
        return Map("x", x, "y", y, "w", w, "h", h, "min_max", min_max)
    }
    catch {
        return ""
    }
}

ApplyWindowGeometryState(hwnd, state, remember_current := true) {
    global geometry_restore_in_progress
    if !(state is Map) || !WinExist("ahk_id " hwnd)
        return false

    if remember_current
        RememberWindowGeometry(hwnd)

    geometry_restore_in_progress := true
    try {
        if (state["min_max"] = 1) {
            WinMaximize "ahk_id " hwnd
        } else {
            WinRestore "ahk_id " hwnd
            WinMoveEx(
                state["x"],
                state["y"],
                state["w"],
                state["h"],
                "ahk_id " hwnd
            )
        }
        return true
    }
    finally {
        geometry_restore_in_progress := false
    }
}

RestorePreviousWindowGeometry(*) {
    global previous_window_geometry, geometry_restore_in_progress
    hwnd := WinExist("A")

    if !hwnd || !previous_window_geometry.Has(hwnd) {
        RestoreLastMinimizedWindow()
        return
    }

    target := previous_window_geometry[hwnd]
    current := CaptureWindowGeometry(hwnd)
    ApplyWindowGeometryState(hwnd, target, false)
    if (current is Map)
        previous_window_geometry[hwnd] := current
}

ClearGeometryActionState(hwnd := 0) {
    global geometry_mode_action_state
    if !hwnd
        hwnd := WinExist("A")
    if hwnd && geometry_mode_action_state.Has(hwnd)
        geometry_mode_action_state.Delete(hwnd)
}

NextGeometryActionStep(hwnd, action, step_count, wrap := false) {
    global geometry_mode_action_state
    if !hwnd
        return 0

    if geometry_mode_action_state.Has(hwnd) {
        state := geometry_mode_action_state[hwnd]
        if (state["action"] = action) {
            if (state["index"] >= step_count) {
                if wrap {
                    state["index"] := 1
                    return 1
                }
                base := state["base"]
                geometry_mode_action_state.Delete(hwnd)
                ApplyWindowGeometryState(hwnd, base)
                return 0
            }
            state["index"] += 1
            return state["index"]
        }
    }

    base := CaptureWindowGeometry(hwnd)
    if !(base is Map)
        return 0
    geometry_mode_action_state[hwnd] := Map(
        "action", action,
        "index", 1,
        "base", base
    )
    return 1
}

ResizeActiveWindow(delta_w, delta_h, *) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    if IsAltPressed() || AltPressedSoon()
        return

    if Window.IsGeometryMode()
        ClearGeometryActionState(hwnd)
    RememberWindowGeometry(hwnd)
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd

    WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)

    new_w := w + delta_w
    new_h := h + delta_h

    if (new_w <= 0 || new_h <= 0)
        return

    if (x < Screen.left)
        x := Screen.left
    if (y < Screen.top)
        y := Screen.top

    max_w := Screen.right - x
    max_h := Screen.bottom - y
    new_w := Min(new_w, max_w)
    new_h := Min(new_h, max_h)

    WinMoveEx(x, y, new_w, new_h, "ahk_id " hwnd)
}

ResizeActiveWindowCentered(delta_w, delta_h, *) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    if IsAltPressed() || AltPressedSoon()
        return

    if Window.IsGeometryMode()
        ClearGeometryActionState(hwnd)
    RememberWindowGeometry(hwnd)
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd

    WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)

    new_w := w + (delta_w * 2)
    new_h := h + (delta_h * 2)
    new_x := x - delta_w
    new_y := y - delta_h

    if (new_w <= 0 || new_h <= 0)
        return

    if (new_x < Screen.left) {
        new_w -= (Screen.left - new_x)
        new_x := Screen.left
    }
    if (new_y < Screen.top) {
        new_h -= (Screen.top - new_y)
        new_y := Screen.top
    }

    max_w := Screen.right - new_x
    max_h := Screen.bottom - new_y
    new_w := Min(new_w, max_w)
    new_h := Min(new_h, max_h)

    if (new_w <= 0 || new_h <= 0)
        return

    WinMoveEx(new_x, new_y, new_w, new_h, "ahk_id " hwnd)
}

MoveGeometryWindowToAdjacentMonitor(direction, *) {
    hwnd := WinExist("A")
    if !hwnd
        return
    ClearGeometryActionState(hwnd)
    Window.SendActiveWindowToAdjacentMonitor(direction, true)
}

MoveGeometryHardwareShiftedMonitor(*) {
    ; Firmware semicolon is shifted comma (next), while colon is shifted
    ; period (previous).
    direction := GetKeyState("Shift", "P") ? -1 : 1
    MoveGeometryWindowToAdjacentMonitor(direction)
}

MoveActiveWindow(delta_x, delta_y, *) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    if Window.IsGeometryMode()
        ClearGeometryActionState(hwnd)
    RememberWindowGeometry(hwnd)
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd

    WinGetPosEx(&x, &y, &w, &h, "ahk_id " hwnd)

    new_x := x + delta_x
    new_y := y + delta_y

    min_x := Screen.left
    min_y := Screen.top
    max_x := Screen.right - w
    max_y := Screen.bottom - h

    new_x := Min(Max(new_x, min_x), max_x)
    new_y := Min(Max(new_y, min_y), max_y)

    WinMoveEx(new_x, new_y, w, h, "ahk_id " hwnd)
}

MoveActiveWindowCoarse(delta_x, delta_y, *) {
    ; Prevent the standalone Super+Alt action from firing after this chord.
    MarkSuperAltChordUsed()
    MoveActiveWindow(delta_x, delta_y)
}

SortWindowList(list) {
    sorted := []
    for _, id in list
        sorted.Push(id)

    count := sorted.Length
    loop count - 1 {
        i := A_Index
        loop count - i {
            j := A_Index
            if (sorted[j] > sorted[j + 1]) {
                temp := sorted[j]
                sorted[j] := sorted[j + 1]
                sorted[j + 1] := temp
            }
        }
    }

    return sorted
}

IsAltPressed() {
    return GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P")
}

AltPressedSoon() {
    if IsAltPressed()
        return true
    KeyWait "Alt", "D T0.05"
    return IsAltPressed()
}

NormalizeAltHotkey(hotkey_name, require_shift := false) {
    if !hotkey_name
        return ""
    normalized := hotkey_name
    if (SubStr(normalized, 1, 1) != "*")
        normalized := "*" normalized
    if !InStr(normalized, "!")
        normalized := "!" normalized
    if (require_shift && !InStr(normalized, "+"))
        normalized := "+" normalized
    return normalized
}


FilterWindowList(exe, list) {
    filtered := []
    for _, id in list {
        if !WindowExistsAcrossDesktops(id)
            continue
        try class_name := WinGetClass("ahk_id " id)
        catch
            continue
        if (exe = "explorer.exe") {
            if (class_name = "Progman" || class_name = "WorkerW" || class_name = "Shell_TrayWnd")
                continue
        }
        try ex_style := WinGetExStyle("ahk_id " id)
        catch
            continue
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        try style := WinGetStyle("ahk_id " id)
        catch
            continue
        allow_invisible := false
        if VirtualDesktopEnabled() {
            desktop_num := GetWindowDesktopNum(id)
            if (desktop_num <= 0)
                continue
            if (desktop_num > 0 && desktop_num != VD.getCurrentDesktopNum())
                allow_invisible := true
        }
        if (!allow_invisible && !(style & 0x10000000))
            continue
        filtered.Push(id)
    }
    return filtered
}

FilterExcludedCycleWindows(list, app_config := "") {
    if !(app_config is Map)
        return list
    if !app_config.Has("exclude_titles") || !(app_config["exclude_titles"] is Array)
        return list

    filtered := []
    for _, id in list {
        if !AppConfigExcludesTitle(app_config, id)
            filtered.Push(id)
    }
    return filtered
}

FilterAppConfigCycleWindows(list, app_config := "") {
    if !(app_config is Map)
        return list

    filtered := []
    for _, id in list {
        if AppConfigMatchesWindow(app_config, id)
            filtered.Push(id)
    }
    return filtered
}

ApplyDesktopCyclePreference(list, current_only := false) {
    if !VirtualDesktopEnabled()
        return list

    current := []
    other := []
    for _, id in list {
        desktop_num := GetWindowDesktopForCycle(id)
        is_current := (desktop_num > 0 && desktop_num = VD.getCurrentDesktopNum())
        if is_current
            current.Push(id)
        else if !current_only
            other.Push(id)
    }

    if current_only
        return current

    if !Config["virtual_desktop"]["cycle_prefer_current"]
        return list

    ordered := []
    for _, id in current
        ordered.Push(id)
    for _, id in other
        ordered.Push(id)
    return ordered
}

ApplyCurrentDesktopOrder(exe, win_list, active_hwnd, current_only := false) {
    if !VirtualDesktopEnabled()
        return win_list
    current_order := GetCurrentDesktopOrderedList(exe)
    current_set := Map()
    for _, id in current_order
        current_set[id] := true

    ; Current-desktop ordering uses visible windows to avoid skipping local tiles.
    if (current_order.Length = 0) {
        if (current_only && active_hwnd && WindowExistsAcrossDesktops(active_hwnd))
            return [active_hwnd]
        return win_list
    }

    if current_only {
        ; Keep stable ordering to avoid z-order oscillation while cycling.
        ordered := []
        for _, id in win_list {
            if current_set.Has(id)
                ordered.Push(id)
        }
        return ordered
    }

    if !Config["virtual_desktop"]["cycle_prefer_current"]
        return win_list

    ; Preserve win_list order while preferring current desktop windows first.
    ordered := []
    for _, id in win_list {
        if current_set.Has(id)
            ordered.Push(id)
    }
    for _, id in win_list {
        if !current_set.Has(id)
            ordered.Push(id)
    }
    return ordered
}

GetCurrentDesktopWindowSet(exe) {
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := false
    list := WinGetList("ahk_exe " exe)
    A_DetectHiddenWindows := bak_detect_hidden_windows

    list := FilterCurrentDesktopWindowList(exe, list)
    set := Map()
    for _, id in list
        set[id] := true
    return set
}

GetCurrentDesktopOrderedList(exe) {
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := false
    list := WinGetList("ahk_exe " exe)
    A_DetectHiddenWindows := bak_detect_hidden_windows

    return FilterCurrentDesktopWindowList(exe, list)
}

FilterCurrentDesktopWindowList(exe, list) {
    filtered := []
    for _, id in list {
        if !WinExist("ahk_id " id)
            continue
        try class_name := WinGetClass("ahk_id " id)
        catch
            continue
        if (exe = "explorer.exe") {
            if (class_name = "Progman" || class_name = "WorkerW" || class_name = "Shell_TrayWnd")
                continue
        }
        try ex_style := WinGetExStyle("ahk_id " id)
        catch
            continue
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        filtered.Push(id)
    }
    return filtered
}

GetWindowDesktopForCycle(hwnd) {
    desktop_num := GetWindowDesktopNum(hwnd)
    if (desktop_num > 0)
        return desktop_num
    if cycle_hwnd_desktop.Has(hwnd)
        return cycle_hwnd_desktop[hwnd]
    return 0
}

CycleDebugEnabled() {
    if !Config.Has("virtual_desktop")
        return false
    return Config["virtual_desktop"].Has("debug_cycle") && Config["virtual_desktop"]["debug_cycle"]
}

HotkeyDebugEnabled() {
    if !Config.Has("virtual_desktop")
        return false
    return Config["virtual_desktop"].Has("debug_hotkeys") && Config["virtual_desktop"]["debug_hotkeys"]
}

EnsureDebugLogInit() {
    global debug_logs_initialized
    if debug_logs_initialized
        return
    if !(CycleDebugEnabled() || HotkeyDebugEnabled())
        return
    log_dir := GetCycleDebugDir()
    DirCreate(log_dir)
    if CycleDebugEnabled() {
        TryResetLogFile(log_dir "\\cycle.debug.log")
    }
    if HotkeyDebugEnabled() {
        TryResetLogFile(log_dir "\\vd.hotkeys.log")
        TryResetLogFile(log_dir "\\vd.actions.log")
    }
    debug_logs_initialized := true
}

TryResetLogFile(path) {
    try {
        if FileExist(path)
            FileDelete(path)
        FileAppend("", path)
    }
}

LogCycleDebug(lines) {
    if !CycleDebugEnabled()
        return
    EnsureDebugLogInit()
    log_dir := GetCycleDebugDir()
    DirCreate(log_dir)
    log_path := log_dir "\\cycle.debug.log"
    header := "[" A_Now "] "
    if !(lines is Array)
        lines := [lines]
    for _, line in lines {
        FileAppend(header line "`n", log_path)
    }
}

LogVirtualDesktopHotkeys(lines) {
    if !HotkeyDebugEnabled()
        return
    EnsureDebugLogInit()
    log_dir := GetCycleDebugDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.hotkeys.log"
    header := "[" A_Now "] "
    if !(lines is Array)
        lines := [lines]
    for _, line in lines {
        FileAppend(header line "`n", log_path)
    }
}

LogVirtualDesktopAction(lines) {
    if !HotkeyDebugEnabled()
        return
    EnsureDebugLogInit()
    log_dir := GetCycleDebugDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.actions.log"
    header := "[" A_Now "] "
    if !(lines is Array)
        lines := [lines]
    for _, line in lines {
        FileAppend(header line "`n", log_path)
    }
}

RegisterDesktopHotkey(kind, hotkey_name, desktop_num, callback) {
    if (hotkey_name = "")
        return
    Hotkey(hotkey_name, (*) => (
        LogVirtualDesktopAction(kind " hotkey=" hotkey_name " desktop=" desktop_num " current=" GetCurrentDesktopNumFresh()),
        callback()
    ))
}

RegisterSuperDesktopHotkey(kind, hotkey_name, desktop_num, callback) {
    if (hotkey_name = "")
        return
    RegisterSuperComboHotkey(
        hotkey_name,
        RunDesktopHotkey.Bind(kind, hotkey_name, desktop_num, callback)
    )
}

RunDesktopHotkey(kind, hotkey_name, desktop_num, callback, *) {
    LogVirtualDesktopAction(
        kind
        " hotkey=" hotkey_name
        " desktop=" desktop_num
        " current=" GetCurrentDesktopNumFresh()
    )
    callback()
}

GetCycleDebugDir() {
    appdata := EnvGet("APPDATA")
    if appdata
        return appdata "\\harken"
    return GetConfigDir()
}

UpdateAppCycleCache(exe, win_list) {
    if !app_cycle_cache.Has(exe)
        app_cycle_cache[exe] := Map()

    cache := app_cycle_cache[exe]
    for _, hwnd in win_list {
        desktop_num := GetWindowDesktopNum(hwnd)
        if (desktop_num > 0)
            cache[hwnd] := desktop_num
        else if !cache.Has(hwnd)
            cache[hwnd] := 0
        if (desktop_num > 0)
            cycle_hwnd_desktop[hwnd] := desktop_num
    }

    for hwnd, _ in cache {
        if !WindowExistsAcrossDesktops(hwnd)
            cache.Delete(hwnd)
    }

    return cache
}

BuildCycleWindowList(exe, win_list) {
    if !VirtualDesktopEnabled()
        return win_list

    ; Cache app windows seen across desktops since WinGetList can hide off-desktop windows.
    cache := UpdateAppCycleCache(exe, win_list)
    if (cache.Count = 0)
        return win_list

    dedup := Map()
    merged := []
    for _, hwnd in win_list {
        dedup[hwnd] := true
        merged.Push(hwnd)
    }
    for hwnd, _ in cache {
        if !dedup.Has(hwnd) {
            merged.Push(hwnd)
            dedup[hwnd] := true
        }
    }
    return merged
}

HandleSuperTap() {
    global last_super_tap, super_double_tap_ms, screen_capture_active

    if screen_capture_active {
        ; Releasing Super during a screen capture is part of the launch chord,
        ; not a tap and must not open Task View over the capture overlay.
        last_super_tap := 0
        return
    }

    if Window.IsGeometryMode() {
        ; Releasing Super after Super+g must not immediately leave the mode.
        last_super_tap := 0
        return
    }

    if Window.IsMoveMode() {
        Window.SetMoveMode(false)
        UpdateCommandToastVisibility()
        return
    }

    if (A_TickCount - last_super_tap <= super_double_tap_ms) {
        ; Use native overview instead of move mode (heuristic detects Task View state).
        Send("#{Tab}")
        UpdateCommandToastVisibility()
        last_super_tap := 0
        return
    }

    last_super_tap := A_TickCount
}

OnSuperKeyUp() {
    HandleSuperTap()
    if ReloadModeActive() {
        global reload_mode_activated_at
        if (A_TickCount - reload_mode_activated_at < 500) {
            UpdateCommandToastVisibility()
            return
        }
        ClearReloadMode()
    }
    UpdateCommandToastVisibility()
}

RegisterSuperKeyHotkey("", " up", (*) => OnSuperKeyUp())

HotIf (*) => !Window.IsMoveMode() && !Window.IsGeometryMode()
RegisterSuperComboHotkey("LButton", BeginWinMoverDynamicMove)
RegisterSuperComboHotkey("RButton", BeginWinMoverDynamicResize)
HotIf

OpenWindowsSearch(*) {
    ; Ask Explorer to open Start/Search directly. Synthesizing Ctrl+Esc into
    ; the foreground window is unreliable when an editor such as Emacs owns
    ; that key sequence. SC_TASKLIST opens the compact Start surface on this
    ; Windows version and accepts immediate search input.
    taskbar_hwnd := WinExist("ahk_class Shell_TrayWnd")
    opened := taskbar_hwnd && DllCall(
        "PostMessage",
        "Ptr", taskbar_hwnd,
        "UInt", 0x0112, ; WM_SYSCOMMAND
        "Ptr", 0xF130, ; SC_TASKLIST
        "Ptr", 0,
        "Int"
    )
    if !opened
        Send("{LWin up}{RWin up}^{Esc}")
}

OpenRectangularScreenSnip(*) {
    global last_super_tap, screen_capture_active

    ; Snipping Tool temporarily leaves no conventional application foreground
    ; window. Suspend Harken's periodic focus recovery for the lifetime of the
    ; non-interactive /clip process or it will reactivate the prior app and
    ; cancel the selection overlay.
    last_super_tap := 0
    screen_capture_active := true
    HideCommandToast()

    ; Start capture on the S press. Keep the physical keys untouched while
    ; releasing their logical state so the overlay does not inherit the chord.
    Send("{Blind}{LWin up}{RWin up}{Shift up}")

    snipping_tool := A_WinDir "\System32\SnippingTool.exe"
    try {
        if !FileExist(snipping_tool)
            throw Error("Snipping Tool was not found at " snipping_tool)

        ; Server 2019's /clip switch uses the saved classic Snipping Tool mode.
        ; Force mode 2 so this shortcut always begins a rectangular selection.
        RegWrite(
            2,
            "REG_DWORD",
            "HKCU\SOFTWARE\Microsoft\Windows\TabletPC\Snipping Tool",
            "CaptureMode"
        )
        RunWait('"' snipping_tool '" /clip')
    }
    catch as err {
        MsgBox(
            "Failed to start a rectangular Snipping Tool capture.`n`n"
            err.Message,
            "harken"
        )
    }
    finally {
        screen_capture_active := false
    }
}

CloseWindow(*) {
    hwnd := WinExist("A")
    if !hwnd
        return
    WinClose "ahk_id " hwnd
}

CloseWindowOnce(key_name, *) {
    CloseWindow()
    ; Ignore Filter Keys repeats until the close key is physically released.
    KeyWait(key_name)
}

RaiseActiveWindow(*) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    monitor_number := Screen.FromWindow("ahk_id " hwnd)
    monitor_windows := GetMonitorZOrderWindows(monitor_number, hwnd)
    if (monitor_windows.Length = 0)
        return

    ; Place the active window directly above the top window from this monitor,
    ; preserving unrelated monitors' relative z-order as much as Windows allows.
    top_target := monitor_windows[1]
    z_list := WinGetList()
    insert_after := 0
    for index, candidate_hwnd in z_list {
        if (candidate_hwnd != top_target)
            continue
        if (index > 1)
            insert_after := z_list[index - 1]
        break
    }
    if (insert_after = hwnd)
        return
    DllCall(
        "SetWindowPos",
        "Ptr", hwnd,
        "Ptr", insert_after,
        "Int", 0,
        "Int", 0,
        "Int", 0,
        "Int", 0,
        "UInt", 0x0013
    )
}

LowerActiveWindow(*) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    monitor_number := Screen.FromWindow("ahk_id " hwnd)
    monitor_windows := GetMonitorZOrderWindows(monitor_number, hwnd)
    if (monitor_windows.Length = 0)
        return

    ; Move only below the bottom eligible window on this monitor rather than
    ; sending the window to the bottom of the global multi-monitor z-order.
    bottom_target := monitor_windows[monitor_windows.Length]
    DllCall(
        "SetWindowPos",
        "Ptr", hwnd,
        "Ptr", bottom_target,
        "Int", 0,
        "Int", 0,
        "Int", 0,
        "Int", 0,
        "UInt", 0x0013
    )
    Window.ActivateMostRecentWindowOnMonitor(monitor_number, hwnd)
}

GetMonitorZOrderWindows(monitor_number, exclude_hwnd := 0) {
    windows := []
    for _, hwnd in WinGetList() {
        try {
            if (hwnd = exclude_hwnd)
                continue
            if Window.IsException("ahk_id " hwnd)
                continue
            if (WinGetMinMax("ahk_id " hwnd) = -1)
                continue

            ex_style := WinGetExStyle("ahk_id " hwnd)
            if (ex_style & 0x80) || (ex_style & 0x8000000)
                continue
            if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
                continue
            if (Screen.FromWindow("ahk_id " hwnd) != monitor_number)
                continue

            windows.Push(hwnd)
        }
    }
    return windows
}

ToggleAppFullscreen(*) {
    ; Let the focused application own its fullscreen transition and restore.
    RememberWindowGeometry("A")
    Send("{F11}")
    KeyWait("f")
}

ToggleGeometryFullscreen(*) {
    global geometry_mode_session
    hwnd := WinExist("A")
    if (
        geometry_mode_session is Map
        && geometry_mode_session.Has("hwnd")
        && geometry_mode_session["hwnd"] = hwnd
    )
        geometry_mode_session["fullscreen_toggled"] :=
            !geometry_mode_session["fullscreen_toggled"]
    ClearGeometryActionState()
    ToggleAppFullscreen()
}

CenterActiveWindow(*) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    if !NextGeometryActionStep(hwnd, "center", 1)
        return
    RememberWindowGeometry(hwnd)
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd
    WinGetPosEx(, , &w, &h, "ahk_id " hwnd)
    x := Screen.left + Round((Screen.width - w) / 2)
    y := Screen.top + Round((Screen.height - h) / 2)
    WinMoveEx(x, y, w, h, "ahk_id " hwnd)
}

MaximizeActiveWindowVertically(*) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    if !NextGeometryActionStep(hwnd, "vertical", 1)
        return
    RememberWindowGeometry(hwnd)
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd
    WinGetPosEx(&x, , &w, , "ahk_id " hwnd)
    WinMoveEx(x, Screen.top, w, Screen.height, "ahk_id " hwnd)
}

MaximizeActiveWindowHorizontally(*) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    if !NextGeometryActionStep(hwnd, "horizontal", 1)
        return
    RememberWindowGeometry(hwnd)
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd
    WinGetPosEx(, &y, , &h, "ahk_id " hwnd)
    WinMoveEx(Screen.left, y, Screen.width, h, "ahk_id " hwnd)
}

SnapActiveWindow(coords, *) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return
    Window.Move(coords, "ahk_id " hwnd)
}

ToggleGeometryMonocle(*) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return
    if !NextGeometryActionStep(hwnd, "monocle", 1)
        return
    Window.Move({ x: 1, y: 1, width: 1, height: 1 }, "ahk_id " hwnd)
}

CycleGeometrySnap(position, *) {
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    ; Loop among three useful small/default/large fractions. Snap cycling no
    ; longer restores the pre-cycle geometry; PageUp remains the explicit undo.
    divisors := [2, 3, 1.5]
    index := NextGeometryActionStep(
        hwnd,
        "snap_" position,
        divisors.Length,
        true
    )
    if !index
        return
    divisor := divisors[index]

    if (position = "1")
        coords := { x: 1, y: divisor, width: divisor, height: divisor }
    else if (position = "2")
        coords := { x: 1, y: divisor, width: 1, height: divisor }
    else if (position = "3")
        coords := { x: divisor, y: divisor, width: divisor, height: divisor }
    else if (position = "4")
        coords := { x: 1, y: 1, width: divisor, height: 1 }
    else if (position = "6")
        coords := { x: divisor, y: 1, width: divisor, height: 1 }
    else if (position = "7")
        coords := { x: 1, y: 1, width: divisor, height: divisor }
    else if (position = "8")
        coords := { x: 1, y: 1, width: 1, height: divisor }
    else if (position = "9")
        coords := { x: divisor, y: 1, width: divisor, height: divisor }
    else
        return

    SnapActiveWindow(coords)
}

FillGeometryMiddleGap(*) {
    global Config
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return false

    monitor_number := Screen.FromWindow("ahk_id " hwnd)
    windows := GetMonitorZOrderWindows(monitor_number, hwnd)
    if (windows.Length < 2)
        return false

    gap_px := Config["window_manager"]["gap_px"]
    tolerance := Max(20, gap_px * 3)
    screen_center_x := Screen.left + Screen.width / 2
    screen_center_y := Screen.top + Screen.height / 2
    landscape := Screen.width >= Screen.height

    first_boundary := 0
    second_boundary := 0
    found_first := false
    found_second := false

    for _, candidate_hwnd in windows {
        try WinGetPosEx(&x, &y, &w, &h, "ahk_id " candidate_hwnd)
        catch
            continue
        if (w <= 0 || h <= 0)
            continue

        if landscape {
            candidate_center := x + w / 2
            if (
                x <= Screen.left + gap_px + tolerance
                && candidate_center < screen_center_x
            ) {
                boundary := x + w
                if !found_first || boundary > first_boundary
                    first_boundary := boundary
                found_first := true
            }
            if (
                x + w >= Screen.right - gap_px - tolerance
                && candidate_center > screen_center_x
            ) {
                if !found_second || x < second_boundary
                    second_boundary := x
                found_second := true
            }
        } else {
            candidate_center := y + h / 2
            if (
                y <= Screen.top + gap_px + tolerance
                && candidate_center < screen_center_y
            ) {
                boundary := y + h
                if !found_first || boundary > first_boundary
                    first_boundary := boundary
                found_first := true
            }
            if (
                y + h >= Screen.bottom - gap_px - tolerance
                && candidate_center > screen_center_y
            ) {
                if !found_second || y < second_boundary
                    second_boundary := y
                found_second := true
            }
        }
    }

    if !found_first || !found_second
        return false

    ; Adjacent snapped cells each carry their own inset, so offset by twice
    ; gap_px from the visible edge window bounds to preserve equal spacing.
    if landscape {
        target_x := first_boundary + (2 * gap_px)
        target_y := Screen.top + gap_px
        target_w := second_boundary - (2 * gap_px) - target_x
        target_h := Screen.height - (2 * gap_px)
    } else {
        target_x := Screen.left + gap_px
        target_y := first_boundary + (2 * gap_px)
        target_w := Screen.width - (2 * gap_px)
        target_h := second_boundary - (2 * gap_px) - target_y
    }

    if (target_w < 80 || target_h < 80)
        return false

    if !NextGeometryActionStep(hwnd, "middle_fill", 1)
        return true
    RememberWindowGeometry(hwnd)
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore "ahk_id " hwnd
    WinMoveEx(target_x, target_y, target_w, target_h, "ahk_id " hwnd)
    return true
}

MinimizeWindow(*) {
    global minimized_window_history
    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return

    ; Keep a most-recent-first restoration trail while avoiding duplicate
    ; handles when the same window is minimized repeatedly.
    index := minimized_window_history.Length
    while (index >= 1) {
        if (minimized_window_history[index] = hwnd)
            minimized_window_history.RemoveAt(index)
        index -= 1
    }
    minimized_window_history.Push(hwnd)

    WinMinimize "ahk_id " hwnd
    ActivateMostRecentWindow(hwnd)
}

RestoreLastMinimizedWindow(*) {
    global minimized_window_history

    ; Windows itself retains the normal placement, so WinRestore returns the
    ; window to the geometry it had before Super+PageDown minimized it.
    while (minimized_window_history.Length > 0) {
        hwnd := minimized_window_history.Pop()
        if !WinExist("ahk_id " hwnd)
            continue

        try {
            WinRestore "ahk_id " hwnd
            WinActivate "ahk_id " hwnd
            return
        }
    }
}

CycleAppWindows(*) {
    hwnd := WinExist("A")
    if !hwnd
        return

    exe := WinGetProcessName("ahk_id " hwnd)
    if !exe
        return

    app_config := FindAppConfigByWindow(hwnd)
    if (app_config is Map && AppConfigExcludesTitle(app_config, hwnd))
        return

    win_list := []
    if (app_config is Map) {
        win_title := app_config.Has("win_title") ? app_config["win_title"] : ""
        win_list := GetAppWindowList(win_title, app_config)
    } else {
        win_list := GetWindowsAcrossDesktops("ahk_exe " exe)
    }
    win_list := FilterWindowList(exe, win_list)
    win_list := BuildCycleWindowList(exe, win_list)
    win_list := FilterAppConfigCycleWindows(win_list, app_config)
    win_list := FilterExcludedCycleWindows(win_list, app_config)
    if (win_list.Length < 2)
        return

    if CycleDebugEnabled() {
        lines := []
        lines.Push("cycle_all exe=" exe " active=" Format("0x{:X}", hwnd) " current_desktop=" GetCurrentDesktopNumFresh() " cache_count=" (app_cycle_cache.Has(exe) ? app_cycle_cache[exe].Count : 0))
        for _, id in win_list {
            desktop_num := GetWindowDesktopNum(id)
            exists := WindowExistsAcrossDesktops(id) ? "1" : "0"
            lines.Push("  hwnd=" Format("0x{:X}", id) " desktop=" desktop_num " exists=" exists)
        }
        LogCycleDebug(lines)
    }

    found_current := false
    for _, id in win_list {
        if (id = hwnd) {
            found_current := true
            break
        }
    }
    if (!found_current && WindowExistsAcrossDesktops(hwnd))
        win_list.Push(hwnd)

    win_list := SortWindowList(win_list)
    win_list := ApplyDesktopCyclePreference(win_list, false)
    win_list := ApplyCurrentDesktopOrder(exe, win_list, hwnd, false)
    if (win_list.Length < 2)
        return

    current_index := 0
    for i, id in win_list {
        if (id = hwnd) {
            current_index := i
            break
        }
    }

    next_index := (current_index >= win_list.Length || current_index = 0) ? 1 : current_index + 1
    ActivateNextAvailableWindow(win_list, next_index)
}

CycleAppWindowsCurrent(*) {
    hwnd := WinExist("A")
    if !hwnd
        return

    exe := WinGetProcessName("ahk_id " hwnd)
    if !exe
        return

    app_config := FindAppConfigByWindow(hwnd)
    if (app_config is Map && AppConfigExcludesTitle(app_config, hwnd))
        return

    win_list := []
    if (app_config is Map) {
        win_title := app_config.Has("win_title") ? app_config["win_title"] : ""
        win_list := GetAppWindowList(win_title, app_config)
    } else {
        win_list := GetWindowsAcrossDesktops("ahk_exe " exe)
    }
    win_list := FilterWindowList(exe, win_list)
    win_list := BuildCycleWindowList(exe, win_list)
    win_list := FilterAppConfigCycleWindows(win_list, app_config)
    win_list := FilterExcludedCycleWindows(win_list, app_config)
    if (win_list.Length < 2)
        return

    if CycleDebugEnabled() {
        lines := []
        lines.Push("cycle_current exe=" exe " active=" Format("0x{:X}", hwnd) " current_desktop=" GetCurrentDesktopNumFresh() " cache_count=" (app_cycle_cache.Has(exe) ? app_cycle_cache[exe].Count : 0))
        for _, id in win_list {
            desktop_num := GetWindowDesktopNum(id)
            exists := WindowExistsAcrossDesktops(id) ? "1" : "0"
            lines.Push("  hwnd=" Format("0x{:X}", id) " desktop=" desktop_num " exists=" exists)
        }
        LogCycleDebug(lines)
    }

    found_current := false
    for _, id in win_list {
        if (id = hwnd) {
            found_current := true
            break
        }
    }
    if (!found_current && WindowExistsAcrossDesktops(hwnd))
        win_list.Push(hwnd)

    win_list := SortWindowList(win_list)
    win_list := ApplyDesktopCyclePreference(win_list, true)
    win_list := ApplyCurrentDesktopOrder(exe, win_list, hwnd, true)
    if (win_list.Length < 2)
        return

    current_index := 0
    for i, id in win_list {
        if (id = hwnd) {
            current_index := i
            break
        }
    }

    next_index := (current_index >= win_list.Length || current_index = 0) ? 1 : current_index + 1
    ActivateNextAvailableWindow(win_list, next_index)
}

ActivateNextAvailableWindow(win_list, start_index) {
    count := win_list.Length
    if (count = 0)
        return

    index := start_index
    loop count {
        if (index > count)
            index := 1
        hwnd := win_list[index]
        if WindowExistsAcrossDesktops(hwnd) {
            activated := ActivateWindowAcrossDesktops(hwnd)
            if CycleDebugEnabled()
                LogCycleDebug("  try hwnd=" Format("0x{:X}", hwnd) " activated=" activated)
            if activated
                return
        }
        index += 1
    }
}

GoToRelativeDesktop(delta) {
    if !VirtualDesktopEnabled()
        return
    RefreshVirtualDesktopState()
    current := GetCurrentDesktopNumFresh()
    if (current <= 0)
        current := VD.getCurrentDesktopNum()
    if (current <= 0)
        return
    target := VD.modulusResolveDesktopNum(current + delta)
    LogVirtualDesktopAction("goto_relative current=" current " delta=" delta " target=" target)
    RememberDesktopFocusedWindow(current)
    RefreshVirtualDesktopState()
    curtain_visible := BeginDesktopSwitchCurtain()
    try {
        VD.goToDesktopNum(target)
        VD.WaitDesktopSwitched(target)
        arrival_hwnd := DllCall("GetForegroundWindow", "Ptr")
    } finally {
        EndDesktopSwitchCurtain(curtain_visible)
    }
    RefreshVirtualDesktopState()
    RestoreDesktopFocusedWindow(target)
    ClearWindowAttention(arrival_hwnd)
    ClearWindowAttention(DllCall("GetForegroundWindow", "Ptr"))
}

GoToDesktopNumber(desktop_num) {
    if !VirtualDesktopEnabled()
        return
    if (desktop_num <= 0)
        return
    current := GetCurrentDesktopNumFresh()
    LogVirtualDesktopAction("goto_absolute target=" desktop_num " current=" current)
    RememberDesktopFocusedWindow(current)
    RefreshVirtualDesktopState()
    GetCurrentDesktopNumFresh()
    curtain_visible := BeginDesktopSwitchCurtain()
    try {
        VD.goToDesktopNum(desktop_num)
        VD.WaitDesktopSwitched(desktop_num)
        arrival_hwnd := DllCall("GetForegroundWindow", "Ptr")
    } finally {
        EndDesktopSwitchCurtain(curtain_visible)
    }
    RefreshVirtualDesktopState()
    RestoreDesktopFocusedWindow(desktop_num)
    ClearWindowAttention(arrival_hwnd)
    ClearWindowAttention(DllCall("GetForegroundWindow", "Ptr"))
}

MoveWindowToRelativeDesktop(delta) {
    if !VirtualDesktopEnabled()
        return
    RefreshVirtualDesktopState()
    current := GetCurrentDesktopNumFresh()
    if (current <= 0)
        current := VD.getCurrentDesktopNum()
    if (current <= 0)
        return
    target := VD.modulusResolveDesktopNum(current + delta)
    moved_hwnd := WinExist("A")
    LogVirtualDesktopAction("move_relative current=" current " delta=" delta " target=" target)
    RefreshVirtualDesktopState()
    curtain_visible := BeginDesktopSwitchCurtain()
    try {
        VD.MoveWindowToDesktopNum("A", target, true)
        VD.WaitDesktopSwitched(target)
    } finally {
        EndDesktopSwitchCurtain(curtain_visible)
    }
    RefreshVirtualDesktopState()
    ClearWindowAttention(moved_hwnd)
    ClearWindowAttention(DllCall("GetForegroundWindow", "Ptr"))
}

MoveWindowToDesktopNumber(desktop_num, follow_window := true) {
    if !VirtualDesktopEnabled()
        return
    if (desktop_num <= 0)
        return
    if follow_window
        MarkSuperAltChordUsed()
    moved_hwnd := WinExist("A")
    source_monitor := Screen.FromWindow("A")
    LogVirtualDesktopAction(
        "move_absolute target=" desktop_num
        " follow=" follow_window
        " current=" GetCurrentDesktopNumFresh()
    )
    RefreshVirtualDesktopState()
    GetCurrentDesktopNumFresh()
    curtain_visible := BeginDesktopSwitchCurtain()
    try {
        VD.MoveWindowToDesktopNum("A", desktop_num, follow_window)
        if follow_window
            VD.WaitDesktopSwitched(desktop_num)
    } finally {
        EndDesktopSwitchCurtain(curtain_visible)
    }
    if !follow_window
        Window.ActivateMostRecentWindowOnMonitor(source_monitor)
    RefreshVirtualDesktopState()
    ClearWindowAttention(moved_hwnd)
    ClearWindowAttention(DllCall("GetForegroundWindow", "Ptr"))
}

HotIf (*) => IsSuperKeyPressed() && !IsAltPressed()
Hotkey("+h", (*) => ResizeActiveWindowCentered(-resize_step, 0))
Hotkey("+l", (*) => ResizeActiveWindowCentered(resize_step, 0))
Hotkey("+j", (*) => ResizeActiveWindowCentered(0, -resize_step))
Hotkey("+k", (*) => ResizeActiveWindowCentered(0, resize_step))
Hotkey("^h", (*) => MoveActiveWindow(-move_step, 0))
Hotkey("^l", (*) => MoveActiveWindow(move_step, 0))
Hotkey("^j", (*) => MoveActiveWindow(0, move_step))
Hotkey("^k", (*) => MoveActiveWindow(0, -move_step))
HotIf IsSuperKeyPressed
Hotkey(cycle_app_windows_hotkey, CycleAppWindows)
if (cycle_app_windows_current_hotkey != "")
    Hotkey(cycle_app_windows_current_hotkey, CycleAppWindowsCurrent)
HotIf

; RegisterSuperComboHotkey already encodes the configured Super prefix. Do not
; re-check its physical state in HotIf: foreground keyboard handlers can make
; that redundant query transiently false after AutoHotkey has matched the
; custom combination, causing suffix keys such as Space to leak into the app.
RegisterSuperComboHotkey("Space", OpenWindowsSearch)
RegisterSuperComboHotkey("w", CloseWindowOnce.Bind("w"))
RegisterSuperComboHotkey("/", (*) => ShowCommandToastTemporary())
HotIf IsSuperKeyPressed
if (minimize_others_hotkey != "")
    Hotkey(minimize_others_hotkey, MinimizeOtherWindows)
HotIf

HotIf (*) => (
    !GetKeyState("Shift", "P")
    && !GetKeyState("Ctrl", "P")
    && !IsAltPressed()
)
RegisterSuperComboHotkey("]", RaiseActiveWindow)
RegisterSuperComboHotkey("[", LowerActiveWindow)
RegisterSuperComboHotkey("PgDn", MinimizeWindow)
RegisterSuperComboHotkey("PgUp", RestorePreviousWindowGeometry)
RegisterSuperComboHotkey("g", EnterGeometryMode)
; Use Geometry Mode's stateful action outside the mode too, making standalone
; Super+m an exact monocle toggle with a per-window geometry restore.
RegisterSuperComboHotkey("m", ToggleGeometryMonocle)
HotIf

HotIf (*) => (
    GetKeyState("Shift", "P")
    && !GetKeyState("Ctrl", "P")
    && !IsAltPressed()
    && !Window.IsMoveMode()
    && !Window.IsGeometryMode()
)
RegisterSuperComboHotkey("s", OpenRectangularScreenSnip)
HotIf

HotIf (*) => (
    IsAltPressed()
    && !GetKeyState("Shift", "P")
    && !GetKeyState("Ctrl", "P")
)
RegisterSuperComboHotkey("n", MoveActiveWindowCoarse.Bind(-coarse_move_step, 0))
RegisterSuperComboHotkey("e", MoveActiveWindowCoarse.Bind(0, coarse_move_step))
RegisterSuperComboHotkey("i", MoveActiveWindowCoarse.Bind(0, -coarse_move_step))
RegisterSuperComboHotkey("o", MoveActiveWindowCoarse.Bind(coarse_move_step, 0))
RegisterSuperComboHotkey("Left", MoveActiveWindowCoarse.Bind(-coarse_move_step, 0))
RegisterSuperComboHotkey("Down", MoveActiveWindowCoarse.Bind(0, coarse_move_step))
RegisterSuperComboHotkey("Up", MoveActiveWindowCoarse.Bind(0, -coarse_move_step))
RegisterSuperComboHotkey("Right", MoveActiveWindowCoarse.Bind(coarse_move_step, 0))
HotIf

HotIf (*) => (
    GetKeyState("Shift", "P")
    && !GetKeyState("Ctrl", "P")
    && !IsAltPressed()
)
RegisterSuperComboHotkey("n", ResizeActiveWindow.Bind(-coarse_resize_step, 0))
RegisterSuperComboHotkey("e", ResizeActiveWindow.Bind(0, coarse_resize_step))
RegisterSuperComboHotkey("i", ResizeActiveWindow.Bind(0, -coarse_resize_step))
RegisterSuperComboHotkey("o", ResizeActiveWindow.Bind(coarse_resize_step, 0))
RegisterSuperComboHotkey("Left", ResizeActiveWindow.Bind(-coarse_resize_step, 0))
RegisterSuperComboHotkey("Down", ResizeActiveWindow.Bind(0, coarse_resize_step))
RegisterSuperComboHotkey("Up", ResizeActiveWindow.Bind(0, -coarse_resize_step))
RegisterSuperComboHotkey("Right", ResizeActiveWindow.Bind(coarse_resize_step, 0))
HotIf

; Quick edge snapping uses geometry mode's same three-size cycle without
; requiring a modal geometry session. Geometry mode keeps Ctrl+direction for
; centered resizing.
HotIf (*) => (
    GetKeyState("Ctrl", "P")
    && !GetKeyState("Shift", "P")
    && !IsAltPressed()
    && !Window.IsGeometryMode()
)
RegisterSuperComboHotkey("n", CycleGeometrySnap.Bind("4"))
RegisterSuperComboHotkey("e", CycleGeometrySnap.Bind("2"))
RegisterSuperComboHotkey("i", CycleGeometrySnap.Bind("8"))
RegisterSuperComboHotkey("o", CycleGeometrySnap.Bind("6"))
RegisterSuperComboHotkey("Left", CycleGeometrySnap.Bind("4"))
RegisterSuperComboHotkey("Down", CycleGeometrySnap.Bind("2"))
RegisterSuperComboHotkey("Up", CycleGeometrySnap.Bind("8"))
RegisterSuperComboHotkey("Right", CycleGeometrySnap.Bind("6"))
HotIf

HotIf (*) => (
    GetKeyState("Ctrl", "P")
    && !GetKeyState("Shift", "P")
    && !IsAltPressed()
    && !Window.IsGeometryMode()
)
RegisterSuperComboHotkey("f", ToggleAppFullscreen)
HotIf

Hotkey("!q", CloseWindow)

HotIf (*) => IsSuperKeyPressed() && IsAltPressed() && !GetKeyState("Shift", "P")
if (vd_prev_hotkey != "")
    Hotkey(vd_prev_hotkey, (*) => (
        LogVirtualDesktopAction("goto_relative hotkey=" vd_prev_hotkey " delta=-1 current=" GetCurrentDesktopNumFresh()),
        GoToRelativeDesktop(-1)
    ))
if (vd_next_hotkey != "")
    Hotkey(vd_next_hotkey, (*) => (
        LogVirtualDesktopAction("goto_relative hotkey=" vd_next_hotkey " delta=1 current=" GetCurrentDesktopNumFresh()),
        GoToRelativeDesktop(1)
    ))
LogVirtualDesktopHotkeys("prev_hotkey=" vd_prev_hotkey " next_hotkey=" vd_next_hotkey)
for _, entry in vd_goto_hotkeys {
    if !(entry is Map)
        continue
    if !entry.Has("hotkey") || !entry.Has("desktop")
        continue
    hotkey_name := NormalizeAltHotkey(entry["hotkey"])
    desktop_num := entry["desktop"]
    key_copy := hotkey_name
    num_copy := desktop_num
    if (key_copy != "") {
        callback := GoToDesktopNumber.Bind(num_copy)
        RegisterDesktopHotkey("goto_absolute", key_copy, num_copy, callback)
    }
    LogVirtualDesktopHotkeys("map goto hotkey=" key_copy " desktop=" num_copy)
}
HotIf

HotIf (*) => IsSuperKeyPressed() && IsAltPressed() && GetKeyState("Shift", "P")
if (vd_move_prev_hotkey != "")
    Hotkey(vd_move_prev_hotkey, (*) => (
        LogVirtualDesktopAction("move_relative hotkey=" vd_move_prev_hotkey " delta=-1 current=" GetCurrentDesktopNumFresh()),
        MoveWindowToRelativeDesktop(-1)
    ))
if (vd_move_next_hotkey != "")
    Hotkey(vd_move_next_hotkey, (*) => (
        LogVirtualDesktopAction("move_relative hotkey=" vd_move_next_hotkey " delta=1 current=" GetCurrentDesktopNumFresh()),
        MoveWindowToRelativeDesktop(1)
    ))
LogVirtualDesktopHotkeys("move_prev_hotkey=" vd_move_prev_hotkey " move_next_hotkey=" vd_move_next_hotkey)
for _, entry in vd_move_hotkeys {
    if !(entry is Map)
        continue
    if !entry.Has("hotkey") || !entry.Has("desktop")
        continue
    hotkey_name := NormalizeAltHotkey(entry["hotkey"], true)
    desktop_num := entry["desktop"]
    key_copy := hotkey_name
    num_copy := desktop_num
    if (key_copy != "") {
        callback := MoveWindowToDesktopNumber.Bind(num_copy)
        RegisterDesktopHotkey("move_absolute", key_copy, num_copy, callback)
    }
    LogVirtualDesktopHotkeys("map move hotkey=" key_copy " desktop=" num_copy)
}
HotIf

; Numbered desktop mappings use three explicit Super modifier tiers.
if (vd_desktop_hotkeys is Array && vd_desktop_hotkeys.Length > 0) {
    LogVirtualDesktopHotkeys("desktop_hotkeys_count=" vd_desktop_hotkeys.Length)

    HotIf (*) => (
        !GetKeyState("Shift", "P")
        && !GetKeyState("Ctrl", "P")
        && !IsAltPressed()
    )
    for _, entry in vd_desktop_hotkeys {
        if !(entry is Map) || !entry.Has("hotkey") || !entry.Has("desktop")
            continue
        key_copy := entry["hotkey"]
        num_copy := entry["desktop"]
        RegisterSuperDesktopHotkey(
            "goto_absolute",
            key_copy,
            num_copy,
            GoToDesktopNumber.Bind(num_copy)
        )
    }
    HotIf

    HotIf (*) => (
        IsSuperKeyPressed()
        && GetKeyState("Shift", "P")
        && !GetKeyState("Ctrl", "P")
        && !IsAltPressed()
    )
    for _, entry in vd_desktop_hotkeys {
        if !(entry is Map) || !entry.Has("hotkey") || !entry.Has("desktop")
            continue
        key_copy := "*" entry["hotkey"]
        num_copy := entry["desktop"]
        RegisterDesktopHotkey(
            "move_absolute",
            key_copy,
            num_copy,
            MoveWindowToDesktopNumber.Bind(num_copy, false)
        )
    }
    HotIf

    HotIf (*) => (
        IsSuperKeyPressed()
        && IsAltPressed()
        && !GetKeyState("Shift", "P")
        && !GetKeyState("Ctrl", "P")
    )
    for _, entry in vd_desktop_hotkeys {
        if !(entry is Map) || !entry.Has("hotkey") || !entry.Has("desktop")
            continue
        key_copy := "*" entry["hotkey"]
        num_copy := entry["desktop"]
        RegisterDesktopHotkey(
            "move_follow_absolute",
            key_copy,
            num_copy,
            MoveWindowToDesktopNumber.Bind(num_copy, true)
        )
    }
    HotIf
}

Hotkey("!-", MinimizeWindow)

if move_mode_enabled {
    HotIf Window.IsMoveMode
    Hotkey("h", (*) => MoveActiveWindow(-move_step, 0))
    Hotkey("l", (*) => MoveActiveWindow(move_step, 0))
    Hotkey("j", (*) => MoveActiveWindow(0, move_step))
    Hotkey("k", (*) => MoveActiveWindow(0, -move_step))
    Hotkey(move_mode_cancel_key, (*) => ExitMoveMode())
    HotIf
}

HotIf (*) => (
    Window.IsGeometryMode()
    && !GetKeyState("Shift", "P")
    && !GetKeyState("Ctrl", "P")
    && !IsAltPressed()
)
Hotkey("n", MoveActiveWindow.Bind(-coarse_move_step, 0))
Hotkey("e", MoveActiveWindow.Bind(0, coarse_move_step))
Hotkey("i", MoveActiveWindow.Bind(0, -coarse_move_step))
Hotkey("o", MoveActiveWindow.Bind(coarse_move_step, 0))
Hotkey("Left", MoveActiveWindow.Bind(-coarse_move_step, 0))
Hotkey("Down", MoveActiveWindow.Bind(0, coarse_move_step))
Hotkey("Up", MoveActiveWindow.Bind(0, -coarse_move_step))
Hotkey("Right", MoveActiveWindow.Bind(coarse_move_step, 0))
Hotkey("c", CenterActiveWindow)
Hotkey("m", ToggleGeometryMonocle)
Hotkey("v", MaximizeActiveWindowVertically)
Hotkey("h", MaximizeActiveWindowHorizontally)
Hotkey("f", ToggleGeometryFullscreen)
Hotkey("1", CycleGeometrySnap.Bind("1"))
Hotkey("2", CycleGeometrySnap.Bind("2"))
Hotkey("3", CycleGeometrySnap.Bind("3"))
Hotkey("4", CycleGeometrySnap.Bind("4"))
Hotkey("5", FillGeometryMiddleGap)
Hotkey("6", CycleGeometrySnap.Bind("6"))
Hotkey("7", CycleGeometrySnap.Bind("7"))
Hotkey("8", CycleGeometrySnap.Bind("8"))
Hotkey("9", CycleGeometrySnap.Bind("9"))
Hotkey(",", MoveGeometryWindowToAdjacentMonitor.Bind(1))
Hotkey(".", MoveGeometryWindowToAdjacentMonitor.Bind(-1))
Hotkey("sc027", MoveGeometryHardwareShiftedMonitor)
Hotkey("Esc", CancelGeometryMode)
Hotkey("Enter", AcceptGeometryMode)
HotIf

HotIf (*) => (
    Window.IsGeometryMode()
    && GetKeyState("Shift", "P")
    && !GetKeyState("Ctrl", "P")
    && !IsAltPressed()
)
Hotkey("*n", ResizeActiveWindow.Bind(-coarse_resize_step, 0))
Hotkey("*e", ResizeActiveWindow.Bind(0, coarse_resize_step))
Hotkey("*i", ResizeActiveWindow.Bind(0, -coarse_resize_step))
Hotkey("*o", ResizeActiveWindow.Bind(coarse_resize_step, 0))
Hotkey("*Left", ResizeActiveWindow.Bind(-coarse_resize_step, 0))
Hotkey("*Down", ResizeActiveWindow.Bind(0, coarse_resize_step))
Hotkey("*Up", ResizeActiveWindow.Bind(0, -coarse_resize_step))
Hotkey("*Right", ResizeActiveWindow.Bind(coarse_resize_step, 0))
Hotkey("*sc027", MoveGeometryHardwareShiftedMonitor)
HotIf

HotIf (*) => (
    Window.IsGeometryMode()
    && GetKeyState("Ctrl", "P")
    && !GetKeyState("Shift", "P")
    && !IsAltPressed()
)
Hotkey("*n", ResizeActiveWindowCentered.Bind(-coarse_resize_step, 0))
Hotkey("*e", ResizeActiveWindowCentered.Bind(0, coarse_resize_step))
Hotkey("*i", ResizeActiveWindowCentered.Bind(0, -coarse_resize_step))
Hotkey("*o", ResizeActiveWindowCentered.Bind(coarse_resize_step, 0))
Hotkey("*Left", ResizeActiveWindowCentered.Bind(-coarse_resize_step, 0))
Hotkey("*Down", ResizeActiveWindowCentered.Bind(0, coarse_resize_step))
Hotkey("*Up", ResizeActiveWindowCentered.Bind(0, -coarse_resize_step))
Hotkey("*Right", ResizeActiveWindowCentered.Bind(coarse_resize_step, 0))
HotIf

HotIf IsOverviewActive
Hotkey("h", (*) => Send("{Left}"))
Hotkey("l", (*) => Send("{Right}"))
Hotkey("j", (*) => Send("{Down}"))
Hotkey("k", (*) => Send("{Up}"))
HotIf

HotIf IsPointerOverTaskbar
Hotkey("~*LButton", BeginTaskbarFocusTransaction)
HotIf
; Mouse-up must be observed even if the pointer leaves the taskbar while held.
Hotkey("~*LButton Up", EndTaskbarFocusTransaction)

; Windows occasionally leaves the desktop shell focused after transitions or
; shell events. Keep a managed window selected without stealing focus from
; visible Search/menu/tool surfaces, and restore per-desktop focus history.
SetTimer(MaintainManagedWindowFocus, 250)

EnterMoveMode(*) {
    global move_mode_enabled
    if !move_mode_enabled
        return
    Window.SetMoveMode(true)
    UpdateCommandToastVisibility()
}

EnterGeometryMode(*) {
    global geometry_mode_session, previous_window_geometry
    if Window.IsGeometryMode()
        return

    hwnd := WinExist("A")
    if !hwnd || Window.IsException("ahk_id " hwnd)
        return
    base := CaptureWindowGeometry(hwnd)
    if !(base is Map)
        return

    had_previous := previous_window_geometry.Has(hwnd)
    prior_history := had_previous ? previous_window_geometry[hwnd] : ""
    geometry_mode_session := Map(
        "hwnd", hwnd,
        "base", base,
        "fullscreen_toggled", false,
        "had_previous", had_previous,
        "prior_history", prior_history
    )
    Window.SetMoveMode(false)
    Window.SetGeometryMode(true)
    UpdateCommandToastVisibility()
}

AcceptGeometryMode(*) {
    global geometry_mode_session, previous_window_geometry
    if !(geometry_mode_session is Map) || !geometry_mode_session.Has("hwnd")
        return

    hwnd := geometry_mode_session["hwnd"]
    if WinExist("ahk_id " hwnd)
        previous_window_geometry[hwnd] := geometry_mode_session["base"]
    ClearGeometryActionState(hwnd)
    geometry_mode_session := Map()
    Window.SetGeometryMode(false)
    Gui_Guides.Destroy_Guis()
    UpdateCommandToastVisibility()
}

CancelGeometryMode(*) {
    global geometry_mode_session, previous_window_geometry
    if !(geometry_mode_session is Map) || !geometry_mode_session.Has("hwnd")
        return

    hwnd := geometry_mode_session["hwnd"]
    if WinExist("ahk_id " hwnd) {
        if geometry_mode_session["fullscreen_toggled"] {
            WinActivate "ahk_id " hwnd
            Send("{F11}")
            Sleep(100)
        }
        ApplyWindowGeometryState(hwnd, geometry_mode_session["base"], false)
        if geometry_mode_session["had_previous"]
            previous_window_geometry[hwnd] := geometry_mode_session["prior_history"]
        else if previous_window_geometry.Has(hwnd)
            previous_window_geometry.Delete(hwnd)
    }

    ClearGeometryActionState(hwnd)
    geometry_mode_session := Map()
    Window.SetGeometryMode(false)
    Gui_Guides.Destroy_Guis()
    UpdateCommandToastVisibility()
}

ExitMoveMode() {
    Window.SetMoveMode(false)
    UpdateCommandToastVisibility()
}

IsOverviewActive(*) {
    ; Heuristic: Task View classes vary by Windows build, so allow a broader list.
    static overview_classes := ["MultitaskingViewFrame", "TaskViewFrame", "XamlExplorerHostIslandWindow"]
    static allowed_processes := Map("explorer.exe", true, "ShellExperienceHost.exe", true)

    for _, class_name in overview_classes {
        hwnds := WinGetList("ahk_class " class_name)
        for _, hwnd in hwnds {
            if !hwnd
                continue
            process_name := ""
            try process_name := WinGetProcessName("ahk_id " hwnd)
            process_lower := StrLower(process_name)
            if (process_lower = "" || !allowed_processes.Has(process_lower))
                continue
            if (class_name = "XamlExplorerHostIslandWindow") {
                title := ""
                try title := WinGetTitle("ahk_id " hwnd)
                if (title != "" && !InStr(title, "Task View") && !InStr(title, "Multitasking"))
                    continue
            }
            return true
        }
    }
    return false
}

GetWinMoverTargetWindow() {
    try {
        MouseGetPos(, , &hwnd)
        if !hwnd
            return 0
        if Window.IsException("ahk_id " hwnd)
            return 0
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            return 0
        return hwnd
    }
    catch {
        ; The pointed-at window may disappear while a click is being routed.
        return 0
    }
}

RunWinMoverDrag(callback) {
    ; WinMover changes thread DPI awareness and mouse coordinate mode. Restore
    ; both even if the dragged window disappears or the vendored code throws,
    ; and keep an expected drag race from opening a modal AutoHotkey error.
    mouse_mode := CoordMode("Mouse", "Screen")
    dpi_awareness := DllCall(
        "SetThreadDpiAwarenessContext",
        "ptr",
        -4,
        "ptr"
    )
    try callback.Call()
    catch as err {
        OutputDebug("harken WinMover drag stopped: " err.Message)
    }
    finally {
        CoordMode("Mouse", mouse_mode)
        DllCall(
            "SetThreadDpiAwarenessContext",
            "ptr",
            dpi_awareness,
            "ptr"
        )
    }
}

BeginWinMoverDynamicMove(*) {
    global WinMoverObj
    hwnd := GetWinMoverTargetWindow()
    if !hwnd
        return
    RememberWindowGeometry(hwnd)
    WinActivate "ahk_id " hwnd
    RunWinMoverDrag(ObjBindMethod(WinMoverObj, "DynamicMove"))
}

BeginWinMoverDynamicResize(*) {
    global WinMoverObj
    hwnd := GetWinMoverTargetWindow()
    if !hwnd
        return
    RememberWindowGeometry(hwnd)
    WinActivate "ahk_id " hwnd
    RunWinMoverDrag(ObjBindMethod(WinMoverObj, "DynamicResize"))
}

MinimizeOtherWindows(*) {
    active_hwnd := WinGetID("A")
    if !active_hwnd
        return
    active_monitor := Screen.FromWindow("ahk_id " active_hwnd)
    for _, hwnd in WinGetList() {
        if (hwnd = active_hwnd)
            continue
        if Window.IsException("ahk_id " hwnd)
            continue
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            continue
        ex_style := WinGetExStyle("ahk_id " hwnd)
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        if (Screen.FromWindow("ahk_id " hwnd) != active_monitor)
            continue
        WinMinimize "ahk_id " hwnd
    }
}

ActivateMostRecentWindow(exclude_hwnd := 0) {
    z_list := WinGetList()
    for _, hwnd in z_list {
        if (hwnd = exclude_hwnd)
            continue
        if Window.IsException("ahk_id " hwnd)
            continue
        if (WinGetMinMax("ahk_id " hwnd) = -1)
            continue
        ex_style := WinGetExStyle("ahk_id " hwnd)
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        WinActivate "ahk_id " hwnd
        return
    }
}
