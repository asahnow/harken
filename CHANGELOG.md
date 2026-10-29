# Changelog

All notable changes to this project are documented here. This changelog is human curated.

## [Unreleased]
### Added
- `super+shift+s` starts the classic Snipping Tool with `/clip` and explicitly selects rectangular capture mode for Windows Server 2019/Windows 10 version 1809 compatibility.
- Vendored AutoHotkey-WinMover and bound Super+left-drag/right-drag to its dynamic window move/resize methods.
- `super+ctrl+neio` and arrow aliases now invoke Geometry Mode's three-size left/down/up/right edge-snap cycles directly.
- Geometry Mode key `5` detects opposing edge windows and fills the middle gap horizontally on landscape monitors or vertically on portrait monitors.
- Added persistent Geometry Mode (`super+g`) with directional movement and edge resizing, centering, monocle/fullscreen controls, axis maximization, and numpad-style corner/edge snapping.
- Screen Search with clickable hints (like vimium/surfingkeys/homerow but jankier).
- UI Automation support via `src/lib/UIA.ahk` with licensing documentation.
- Command mode action to send windows to their assigned desktops.
- App matching enhancements: process-tree targeting and `ignore_classes` support.
- `docs/COMPILE.md` with build and packaging notes.
- Virtual desktop scroll navigation and move-window scroll support (`super+scroll` & `super+alt+shift+scroll`).
- Optional desktop switch curtain to mask brief background flashes.
- Project now uses CHANGELOG.md

### Changed
- Standalone Super+Alt is now reserved as a no-op. Alt is suppressed from applications while Super is physically held, while plain Alt remains native and Harken can still use the physical modifier for window actions; legacy `global_hotkeys` entries for Alt are ignored.
- `super+f` now opens Explorer, native app fullscreen moved to `super+ctrl+f`, and Super+wheel virtual-desktop switching is no longer registered.
- Numbered virtual desktops now use `super+1-9` to switch, Shift to send without following, and Alt to send and follow; Harken ensures nine desktops exist.
- Window-management outer margins remain 8 px, inner snap padding is 5 px, and colored focus borders are 3 px thick.
- Focus borders are square with a `#458588` normal color and a dedicated `#D79921` Geometry Mode color.
- Arrow keys now mirror `neio` directional actions: `super+arrows` focuses windows, and Geometry Mode arrows mirror its plain, Shift, and Ctrl movement/resize layers.
- Geometry Mode is now transactional: `Enter` accepts the session and `Esc` restores its starting geometry. Monitor-follow shortcuts and directional shrink/center-resize modifiers are available within the mode.
- Geometry Mode Shift resizing now anchors the top-left corner: `n/i` shrink the right/bottom edges and `o/e` expand them. Geometry Mode Alt bindings were removed; centered Ctrl resizing remains.
- Geometry corner/edge snaps now loop through half, third, and two-thirds sizes without an automatic restore step.
- Geometry Mode center and maximization actions remain toggleable within each session.
- `super+PageUp` now swaps the active window with its previous Harken-managed geometry, while retaining last-minimized restoration as a fallback.
- App hotkeys support `always_run`; the Firefox and PowerShell bindings use it to launch new instances instead of focusing existing windows.
- Added Super bindings for monitor-scoped window raise/lower (`]/[`), minimize/restore (`PageDown/PageUp`), native fullscreen (`ctrl+f`), and configurable 75 px coarse move/resize increments with `neio` or arrow keys.
- Added monitor navigation: `super+,/.` focuses the next/previous monitor; Shift sends the active window while keeping focus on the source monitor, and Alt sends while following it.
- `super+space` now opens compact Start search, and `super+w` closes the active window.
- Holding a configured Windows-key Super no longer passes through to native Start/Search; firmware-mapped `;`/`:` aliases support shifted monitor movement.
- Directional focus now uses `super+n/e/i/o` or arrow keys (left/down/up/right).
- Double-super now opens native Task View; move mode is entered from command mode, and h/j/k/l navigate Task View.
- Super+scroll switches virtual desktops (replacing the prior super+alt+scroll combo).
- Config flow favors `config_watch` instead of a dedicated reload section.
- Example config updates (apps list and focus border thickness).
- App matching now uses cached window metadata and PID-based lookups for off-desktop windows, with focus diagnostics logging.
- README adds a comparison section with similar tools.
- Config validation favors warnings over hard errors where possible.

### Fixed
- Super+,/. monitor navigation and its firmware-shifted scan-code alias now use configured-Super custom combinations instead of wildcard suffixes guarded by a physical-Super query, preventing Emacs from receiving `M-,`/`M-.` and invoking Xref when Harken should move or follow a window between monitors.
- Super+Alt/Shift/Ctrl directional layers now use configured-Super custom combinations rather than wildcard suffix hotkeys guarded by a second physical-Super query. Modified letters and arrows are therefore consumed reliably in Emacs instead of leaking through as Meta commands, text selection, word movement, or Ctrl actions.
- Super+Space and plain numbered-desktop custom combinations no longer repeat a physical `IsSuperKeyPressed()` check after AutoHotkey has already matched the configured Super prefix. This prevents foreground keyboard handlers such as Emacs from making the redundant check fail and leaking Space/numeric suffixes into the application. Super+Space opens compact Start/Search through Explorer's shell command rather than injecting Ctrl+Esc into the focused application.
- After Super+Alt release, Harken sends `WM_CANCELMODE` to the foreground frame and any native menu owner at two points in the release-processing window. This also covers custom legacy menu bars that show keytips without reporting native menu mode; the message is a no-op when no tracking mode exists and plain Alt remains unchanged.
- Super+Alt actions now consume the physical Alt release and deliver a Ctrl-masked synthetic Alt-up to the eventual destination window. This prevents legacy applications that ignore the prior unused-key mask from opening their Alt menu after monitor-follow shortcuts, without application-specific exceptions.
- Cross-desktop attention cleanup no longer invokes legacy `FlashWindow` or touches the foreground window during ordinary switching; it now applies `FLASHW_STOP` only to a matching root-owner/taskbar-group window confirmed on another desktop, preventing the cleanup itself from creating persistent orange taskbar buttons.
- Foreground changes now drive cross-desktop taskbar-attention cleanup through a Windows event hook with no launch timeout. Windows are matched by their taskbar AppUserModelID, with process path/PID fallbacks for legacy software, so delayed cross-process launchers can clear the exact older orange thumbnail without suppressing unrelated applications' notifications.
- Virtual-desktop switches and window send/follow operations now clear stale Windows taskbar-attention state only from the windows participating in the transition, with one delayed cleanup after the desktop animation. Restoring a remembered desktop window also avoids a redundant activation when it is already foreground.
- Taskbar application-button clicks now suspend all automatic focus activation from mouse-down through the shell's post-release settling period, preventing Harken from racing intermittent restore/minimize transitions even when the taskbar never becomes the foreground window.
- New-dialog activation now requires a captioned top-level window, preventing context menus and other transient popup surfaces carrying `WS_EX_DLGMODALFRAME` from being activated and immediately dismissed.
- Newly shown dialog windows are now activated once when they are owned by, share a root owner with, or belong to the same process as the foreground application. This brings enabled/modeless Properties sheets forward without repeatedly stealing focus after the user intentionally changes windows.
- Managed-focus maintenance now detects disabled foreground owners and activates their enabled visible owned popup, keeping Properties sheets and other modal dialogs above their application frame and ensuring subsequent keyboard accelerators target the dialog.
- WinMover's maximized-window move/resize paths now use `dMon`'s actual `LW/TW/WW/HW` work-area properties instead of nonexistent long-form names. Harken also contains transient drag errors and restores mouse-coordinate/DPI state so they cannot open modal AutoHotkey error dialogs.
- Focus-border polling now tolerates windows and transient menus disappearing between Win32 queries, hides and invalidates stale overlays on every failed sample, and revalidates the foreground HWND before drawing so timer errors cannot freeze a border across windows or desktops.
- Taskbar application-button clicks now receive a short, non-renewing focus grace period so Windows can restore and raise the selected app before Harken's managed-focus recovery runs; genuine lingering taskbar focus is still recovered afterward.
- Classic Snipping Tool capture now suspends Harken's periodic managed-focus recovery until `/clip` finishes, preventing the prior application from immediately cancelling the selection overlay; capture begins on the `S` press without waiting for the launch chord to be released.
- `super+alt+,/.` now masks the Alt release before and after moving/following a window, preventing application menu-key hints from remaining active on the destination monitor.
- Standalone `super+m` now uses Geometry Mode's monocle toggle consistently; the conflicting legacy wildcard binding that caused app- and monitor-dependent behavior was removed.
- Directional focus now normalizes enabled owned palettes and quick-action bars to their visible root application window, preventing Acrobat's auxiliary toolbar from being selected instead of its main frame while preserving modal-dialog focus.
- Windows-system launch commands now resolve through `%WINDIR%` before fuzzy Start Menu matching, preventing `explorer.exe` from being mistaken for Internet Explorer, and shortcut working directories expand environment variables. `always_run` launchers now wait for and focus the newly created app window.
- Virtual-desktop focus history now retains a preferred monitor per desktop and avoids recording a destination window against the desktop being left during transitions.
- Harken now restores focus to the most recent eligible window after virtual-desktop switches and when Windows leaves the desktop/taskbar focused, preserving directional navigation.
- Returning to a virtual desktop now restores that desktop's last focused eligible window when it is still available.
- Numbered desktop switching now uses explicit configured-Super combinations so native Windows taskbar shortcuts cannot intercept `super+1-9`.
- Raise/lower now changes z-order and subsequent focus only among windows on the active monitor; focus borders honor configured window exceptions and ignore oversized Windows 10/11 shell Search/Start host bounds.
- Increased AutoHotkey's hotkey-rate guard to accommodate fast Filter Keys repeat settings without showing the `A_MaxHotkeysPerInterval` warning.
- Window walker rendering issues when the resolution changes.
- Window cycling now includes more than two tiles reliably.
- Grid snapping edge cases.
- EnumWindows callback signature.

## [0.2.1] - 2026-02-07
### Added
- New entry point `harken.ahk` and TOML configuration support with a TOML example config.
- Virtual desktop integration via `VD.ahk` with licensing documentation.

### Changed
- Project rename to Harken and migration away from JSON config.
- Install, release, and build tooling updated for the new name/config.
- README refreshed to reflect the new app name and setup steps.

## [0.2.0] - 2026-02-03
### Added
- Directional focus hotkeys and supporting window focus helpers.
- Window switcher (window walker) UI and hotkeys.
- State store for persisted app state.
- Additional documentation assets for the overlay and switcher UI.

### Changed
- README updates with new features and sources.
- Config example refreshed for the new hotkeys.

## [0.0.1] - 2026-01-28
### Added
- Initial public release of the original script.
