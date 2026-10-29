; ================================
; Active Window Rounded Border Overlay
; For Windows 10 and 11
; Runs continuously in the background.
; Adjust the border color, thickness, and corner roundness below.
; Why: give a visible focus cue, plus mode-specific colors.
; ================================

global Config

focus_config := Config["focus_border"]
global focus_border_enabled := focus_config["enabled"]
if focus_border_enabled {
    ; ------------- User Settings -------------
    base_border_color := ParseHexColor(focus_config["border_color"])   ; Hex color (#RRGGBB)
    base_move_mode_color := ParseHexColor(focus_config["move_mode_color"]) ; Hex color (#RRGGBB)
    base_geometry_mode_color := focus_config.Has("geometry_mode_color")
        ? ParseHexColor(focus_config["geometry_mode_color"])
        : base_move_mode_color
    base_command_mode_color := ParseHexColor(focus_config["command_mode_color"]) ; Hex color (#RRGGBB)
    base_border_thickness := Integer(focus_config["border_thickness"])      ; Border thickness in pixels
    base_corner_radius := Integer(focus_config["corner_radius"])        ; Corner roundness in pixels
    update_interval := Integer(focus_config["update_interval_ms"])      ; How often (ms) to check/update active window
    ; ------------- End Settings -------------

    ; --- Create one overlay GUI that will be re-shaped to form a hollow border ---
    overlay := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20", "ActiveWindowBorder")
    ; Set the background color of the overlay (it will only be visible in its "region")
    ; Convert the numeric color (0xRRGGBB) to a 6-digit hex string (without "0x")
    bg_color := Format("{:06X}", base_border_color & 0xFFFFFF)
    overlay.BackColor := bg_color
    overlay.Show("NoActivate")
    h_overlay := overlay.Hwnd
    ; Add layered style so that SetWindowRgn is applied smoothly.
    WinSetExStyle("+0x80000", "ahk_id " h_overlay)

    ; Global variables to track the last active window's position & size.
    global prev_hwnd := 0, prev_ax := 0, prev_ay := 0, prev_aw := 0, prev_ah := 0
    global current_color := base_border_color
    global flash_until := 0
    global flash_color := 0xB0B0B0

    ; Set up a timer to update the overlay border.
    SetTimer(UpdateBorder, update_interval)

    ; -------------------------------
    ; UpdateBorder: Positions/resizes and re-shapes the overlay border
    ; -------------------------------
    UpdateBorder(*) {
        ; Foreground windows and transient menus can disappear between any two
        ; Win32 queries. Never let that expected race terminate the timer and
        ; strand the last successfully drawn border on screen.
        try UpdateBorderSnapshot()
        catch {
            HideFocusBorderOverlay()
        }
    }

    HideFocusBorderOverlay() {
        global overlay
        global prev_hwnd, prev_ax, prev_ay, prev_aw, prev_ah

        try overlay.Hide()
        ; Reset the cache as well as hiding. If the same window and geometry
        ; become valid again, the next timer tick must redraw the border.
        prev_hwnd := 0
        prev_ax := 0
        prev_ay := 0
        prev_aw := 0
        prev_ah := 0
    }

    UpdateBorderSnapshot() {
        global overlay, h_overlay
        global base_border_thickness, base_corner_radius
        global base_border_color, base_move_mode_color, base_geometry_mode_color
        global base_command_mode_color, current_color
        global prev_hwnd, prev_ax, prev_ay, prev_aw, prev_ah

        ; Get the currently active window.
        active_hwnd := DllCall("GetForegroundWindow", "ptr")
        ; (Ignore the overlay itself if it somehow becomes active)
        if (active_hwnd = h_overlay) {
            active_hwnd := 0
        }
        ; If no active window found or it's gone, hide the overlay.
        if (!active_hwnd || !DllCall("IsWindow", "ptr", active_hwnd)) {
            HideFocusBorderOverlay()
            return
        }
        class_name := WinGetClass("ahk_id " active_hwnd)
        if (class_name = "Progman" || class_name = "WorkerW" || class_name = "Shell_TrayWnd" || class_name = "Shell_SecondaryTrayWnd") {
            HideFocusBorderOverlay()
            return
        }
        if Window.IsException("ahk_id " active_hwnd) {
            ; Use the same configured class exclusions as window movement.
            HideFocusBorderOverlay()
            return
        }
        process_name := ""
        try process_name := StrLower(WinGetProcessName("ahk_id " active_hwnd))
        if (
            process_name = "searchhost.exe"
            || process_name = "searchapp.exe"
            || process_name = "searchui.exe"
            || process_name = "cortana.exe"
            || process_name = "startmenuexperiencehost.exe"
            || process_name = "shellexperiencehost.exe"
        ) {
            ; Shell surfaces use a large mostly-transparent host window around
            ; their visible flyout. Border that host and the result looks like
            ; an erroneous half-screen focus rectangle.
            HideFocusBorderOverlay()
            return
        }
        style := WinGetStyle("ahk_id " active_hwnd)
        if (style & 0x20000000) {  ; WS_MINIMIZE flag
            HideFocusBorderOverlay()
            return
        }

        ; --- Get the window's true bounds using DWM ---
        rect := Buffer(16, 0)
        if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", active_hwnd, "uint", 9, "ptr", rect, "uint", 16) = 0) {
            ax := NumGet(rect, 0, "int")
            ay := NumGet(rect, 4, "int")
            right := NumGet(rect, 8, "int")
            bottom := NumGet(rect, 12, "int")
            aw := right - ax
            ah := bottom - ay
        } else {
            ; Fallback in case DWM fails.
            WinGetPos(&ax, &ay, &aw, &ah, "ahk_id " active_hwnd)
        }

        border_color := base_border_color
        move_mode_color := base_move_mode_color
        geometry_mode_color := base_geometry_mode_color
        command_mode_color := base_command_mode_color
        border_thickness := base_border_thickness
        corner_radius := base_corner_radius
        override := FindFocusBorderOverride(active_hwnd)
        if (override is Map) {
            if (override.Has("border_color") && override["border_color"] != "")
                border_color := ParseHexColor(override["border_color"])
            if (override.Has("move_mode_color") && override["move_mode_color"] != "")
                move_mode_color := ParseHexColor(override["move_mode_color"])
            if (override.Has("geometry_mode_color") && override["geometry_mode_color"] != "")
                geometry_mode_color := ParseHexColor(override["geometry_mode_color"])
            if (override.Has("command_mode_color") && override["command_mode_color"] != "")
                command_mode_color := ParseHexColor(override["command_mode_color"])
            if (override.Has("border_thickness"))
                border_thickness := Integer(override["border_thickness"])
            if (override.Has("corner_radius"))
                corner_radius := Integer(override["corner_radius"])
        }

        if (flash_until > A_TickCount)
            desired_color := flash_color
        else if ReloadModeActive()
            desired_color := command_mode_color
        else if Window.IsGeometryMode()
            desired_color := geometry_mode_color
        else if Window.IsMoveMode()
            desired_color := move_mode_color
        else
            desired_color := border_color
        if (desired_color != current_color) {
            overlay.BackColor := Format("{:06X}", desired_color & 0xFFFFFF)
            current_color := desired_color
        }

        ; Only update if something changed.
        if (active_hwnd = prev_hwnd && ax = prev_ax && ay = prev_ay && aw = prev_aw && ah = prev_ah) {
            return
        }
        prev_hwnd := active_hwnd, prev_ax := ax, prev_ay := ay, prev_aw := aw, prev_ah := ah

        ; Calculate overlay position and size.
        ; The overlay is expanded by border_thickness on all sides so that its inner edge aligns
        ; exactly with the active window's border.
        ox := ax - border_thickness
        oy := ay - border_thickness
        ow := aw + (2 * border_thickness)
        oh := ah + (2 * border_thickness)

        ; The foreground can change while its style, bounds, and per-app
        ; overrides are sampled. Draw only if this exact HWND still exists and
        ; remains foreground; otherwise clear the stale border for this tick.
        if (
            !DllCall("IsWindow", "ptr", active_hwnd)
            || DllCall("GetForegroundWindow", "ptr") != active_hwnd
        ) {
            HideFocusBorderOverlay()
            return
        }

        ; (Re)position the overlay window.
        overlay.Show("x" ox " y" oy " w" ow " h" oh " NoActivate")

        ; ----- Build a hollow (donut-shaped) border region. -----
        if (corner_radius <= 0) {
            h_rgn_outer := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", ow, "int", oh, "ptr")
            h_rgn_inner := DllCall("CreateRectRgn", "int", border_thickness, "int", border_thickness, "int", ow - border_thickness, "int", oh - border_thickness, "ptr")
        } else {
            h_rgn_outer := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", ow, "int", oh, "int", corner_radius * 2, "int", corner_radius * 2, "ptr")
            inner_corner := (corner_radius > border_thickness) ? (corner_radius - border_thickness) : 0
            h_rgn_inner := DllCall("CreateRoundRectRgn", "int", border_thickness, "int", border_thickness, "int", ow - border_thickness, "int", oh - border_thickness, "int", inner_corner * 2, "int", inner_corner * 2, "ptr")
        }
        ; Create a region for the border by subtracting the inner region from the outer.
        ; First, create an empty region.
        h_rgn_border := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", 0, "int", 0, "ptr")
        ; RGN_DIFF = 4: h_rgn_border = h_rgn_outer - h_rgn_inner.
        DllCall("CombineRgn", "ptr", h_rgn_border, "ptr", h_rgn_outer, "ptr", h_rgn_inner, "int", 4)
        ; Apply the computed region to the overlay window.
        ; (After calling SetWindowRgn, the system owns h_rgn_border, so DO NOT free it.)
        DllCall("SetWindowRgn", "ptr", h_overlay, "ptr", h_rgn_border, "int", True)
        ; Clean up the temporary region handles.
        DllCall("DeleteObject", "ptr", h_rgn_outer)
        DllCall("DeleteObject", "ptr", h_rgn_inner)
    }
}

FindFocusBorderOverride(active_hwnd) {
    global Config
    if !Config.Has("apps")
        return ""

    for _, app in Config["apps"] {
        if !(app is Map)
            continue
        if !app.Has("focus_border") || !(app["focus_border"] is Map)
            continue
        if MatchAppWindow(app, active_hwnd)
            return app["focus_border"]
    }

    return ""
}

FlashFocusBorder(color := 0xB0B0B0, duration_ms := 130) {
    global focus_border_enabled, flash_until, flash_color, overlay, current_color
    if !focus_border_enabled
        return
    flash_color := color
    flash_until := A_TickCount + duration_ms
    if overlay {
        overlay.BackColor := Format("{:06X}", flash_color & 0xFFFFFF)
        current_color := flash_color
    }
}

ParseHexColor(value) {
    if (value is Integer)
        return value
    if !(value is String)
        return 0
    trimmed := Trim(value)
    if (SubStr(trimmed, 1, 1) = "#")
        trimmed := SubStr(trimmed, 2)
    if (StrLen(trimmed) = 8 && RegExMatch(trimmed, "i)^0x[0-9a-f]{6}$"))
        return Integer(trimmed)
    if (StrLen(trimmed) = 6 && RegExMatch(trimmed, "i)^[0-9a-f]{6}$"))
        return Integer("0x" trimmed)
    return 0
}
