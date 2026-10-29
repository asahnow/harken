# Harken
A window manager written in AutoHotkey v2.

Harken allows a keyboard-centered workflow on Windows: a single super modifier, mnemonic app keys, and fast window actions. Alt+Tab and Win+Tab still work, but you will hardly use them.

## Contents
- [Overview](#overview)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Default Config Keys](#default-config-keys)
- [Window Matching](#window-matching)
- [Path Expansion](#path-expansion)
- [Window Manager Exceptions](#window-manager-exceptions)
- [Helper Utility](#helper-utility)
- [Command Overlay](#command-overlay)
- [Known Limitations](#known-limitations)
- [Layout](#layout)
- [Third-Party](#third-party)

## Overview

> [!NOTE]
> CapsLock is the default super key, because who needs it?

### Features

- Launch-or-focus your most common programs with the hotkeys you assign in your config file.
- Focused tile includes border highlight that can be customized, including per app, window class, or window title.
- Snap tiles to grid and cycle through various positions with subsequent key presses.
- Freely move tiles with your keyboard.
- Resize tiles and their edges with your keyboard.
- Directional focus changes with vim-like motions.
- Cycle focus between tiles of the same program with `super + c`.
- Show a hotkey menu with `super + /`.
- Configurable Screen Search hints.
- Virtual desktops (native)
  - Navigate between desktops with better hotkeys
  - Assign custom hotkeys for the index-based virtual desktops.



Launch-or-focus a program with `super + [letter]`, or directionally change window focus with `super + n/e/i/o` or the arrow keys (left, down, up, right).
![Alt text](docs/assets/focus.gif)

Open the compact Start search surface with `super + spacebar`.

Toggles monocle mode with `super + m`.
![Alt text](docs/assets/maximize.gif)

Move a window with `super + h/j/k/l`.
![Alt text](docs/assets/move.gif)

Freely move a window with double tap super + h/j/k/l
![Alt text](docs/assets/free-move.gif)

Resize edges with `super + shift + h/j/k/l`.
![Alt text](docs/assets/resize.gif)

Show the [Command Overlay](#command-overlay) when the super key is held. Disable through command mode.
![Alt text](docs/assets/command_overlay.png)

The configurable Window Selector provides a fuzzy finder for open windows.
![Alt text](docs/assets/window_switcher.png)

Other
- `super + alt` alone does nothing; Alt is consumed only while Super is held so application menu keytips do not open
- `super + c` cycle through windows of the same app
- `super + shift + c` cycle through windows of the same app on the current desktop
- Screen Search click hints can be assigned a non-reserved hotkey in the config.
- `super + alt + h/l` switch to previous/next virtual desktop
- `super + alt + shift + h/l` move the active window to previous/next desktop (follow)
- `super + w` close the current window
- `super + n/o` move window focus left/right
- `super + e/i` move window focus down/up (non-stacked)
- `super + alt + h/l` to move between desktops
- `super + shift + alt + h/l` send current tile to adjacent desktop

Enter Command Mode with `super + '`.
- `r` to reload program/config
- `e` to open config file
- `w` opens a new window for the active program, if the program supports it
- `g` reapply app desktop assignments
- `n` toggles the command overlay on or off
- `i` opens the [Helper Utility](#helper-utility)

## TODO

- Clarify and work on areas of state
  - saving layouts
  - per app configs determining where things go (virtual desktop destination is supported now)
- Possibly rework the config schema. It's hectic.


## Configuration

### Quick start

- If not using the binary, make sure to install AutoHotKey 2.1-alpha18 or newer.
- Start the program and enter command mode with `super + '`. The binary is not currently signed and you will be warned by Windows. Clone and use `harken.ahk` directly as an alternative.
- The program might fail on first run? Probably something to do with the config. For now you can create the config first to _maybe_ avoid the initial-crash scenario.
- Press `e` to open the config file. You can also find it manually in `~/.config/harken/harken.toml` as it will be created on first run.
- After making changes to your config you can reload (the entire program) with `r` while in command mode.

## Window Matching

App entries under `apps` can match windows via `win_title` or a `match` map. The `match` map accepts
`exe`, `class`, and `title`, plus `*_regex = true` to treat the value as a regex. You can also match
by process tree with `match.process_tree`, which checks for ancestor/descendant executables.

Use `exclude_titles` to ignore specific window titles for a given app. Each entry is a regex pattern
and the match is case-insensitive unless you include your own `(?i)` prefix.

Set `always_run = true` when an app hotkey should launch a new instance instead
of focusing an existing matching window.

```toml
[apps.editor]
hotkey = "v"
match = { exe = "Code.exe", title = " - Visual Studio Code$", title_regex = true }
exclude_titles = ["^Settings$", "^Welcome$"]
```

Process tree matching can split apps that share the same window executable:

```toml
[[apps]]
id = "terminal"
hotkey = "s"
match = { exe = "alacritty.exe", process_tree = { mode = "descendant", exe = ["yazi.exe"], negate = true } }

[[apps]]
id = "yazi"
hotkey = "y"
match = { exe = "alacritty.exe", process_tree = { mode = "descendant", exe = ["yazi.exe"] } }
```

Add `debug = true` under `match.process_tree` to log process tree details to
`%APPDATA%\harken\process_tree.debug.log`.

### All default keybindings

#### Window management (Super)

| Shortcut | Action |
| --- | --- |
| `super + /` | Show command overlay (temporary) |
| `super + w` | Close current window |
| `super + c` | Cycle app windows across desktops |
| `super + shift + c` | Cycle app windows on current desktop |
| `super + space` | Open compact Start search |
| `super + m` | Toggle monocle (padded work area) |
| `super + shift + s` | Open rectangular screenshot selection |
| `alt + q` | Close window |
| `super + n/e/i/o` or arrows | Focus the window left/down/up/right |
| `super + ,/.` | Focus next/previous monitor |
| `super + shift + ,/.` | Send window to next/previous monitor; keep focus here |
| `super + ;/:` | Firmware aliases for shifted `,/.`; keep focus here |
| `super + alt + ,/.` | Send window to next/previous monitor and follow it |
| `super + ]/[` | Raise/lower current window within its monitor |
| `super + PageDown` | Minimize/hide current window |
| `super + PageUp` | Undo/toggle the active window's most recent Harken geometry change; otherwise restore the last Harken-minimized window |
| `super + g` | Enter Geometry Mode |
| `super + LButton` drag | Move the window under the pointer with WinMover |
| `super + RButton` drag | Resize the window under the pointer with WinMover |
| `super + ctrl + f` | Toggle the current app's native fullscreen mode |
| `super + alt + neio` or arrows | Move window by `coarse_move_step` |
| `super + shift + neio` or arrows | Resize window by `coarse_resize_step` |
| `super + ctrl + neio` or arrows | Cycle half/third/two-thirds snaps at the left/down/up/right edge |
| `super + shift + h/j/k/l` | Resize centered |
| `super + ctrl + h/j/k/l` | Move window |
| `super` (double tap) | Toggle move mode |

#### Window management (Move mode)

| Shortcut | Action |
| --- | --- |
| `h/j/k/l` | Move window |
| `Esc` or `super` | Exit move mode |

#### Geometry Mode

Enter with `super + g`. Press `5` to fill the space between suitable opposing
edge windows—left/right on landscape monitors or top/bottom on portrait
monitors. Press `Enter` to accept the resulting layout or `Esc` to cancel the
entire session and restore its starting geometry.

| Shortcut | Action |
| --- | --- |
| `n/e/i/o` or arrows | Move left/down/up/right by `coarse_move_step` |
| `shift + n/o` or `Left/Right` | Shrink/expand from the right edge by `coarse_resize_step` |
| `shift + i/e` or `Up/Down` | Shrink upward/expand downward from the bottom edge |
| `ctrl + n/e/i/o` or arrows | Shrink/expand symmetrically around the center |
| `,/.` | Move the window to the next/previous monitor and follow |
| `;/:` | Firmware aliases for `,/.`; move and follow |
| `c` | Toggle centered position while preserving size |
| `m` | Toggle monocle (maximized work area) |
| `v` | Toggle vertical maximize |
| `h` | Toggle horizontal maximize |
| `f` | Toggle the app's native fullscreen mode |
| `1/3/7/9` | Continuously cycle half/third/two-thirds sizes at the selected corner |
| `2/4/6/8` | Continuously cycle half/third/two-thirds sizes at the selected edge |
| `5` | Fill the detected middle gap again, or toggle that fill off |
| `Enter` | Accept changes and exit |
| `Esc` | Cancel all Geometry Mode changes and restore the starting geometry |

Changing actions uses the current layout as the next toggle action's local
restore point, but `Esc` still restores the geometry from when the mode began.
Directional move and resize actions remain incremental.

#### Focus navigation

| Shortcut | Action |
| --- | --- |
| `super + n/o` | Focus left/right |
| `super + e/i` | Focus down/up |
| `super + arrows` | Arrow-key aliases for directional focus |

#### Virtual desktops

| Shortcut | Action |
| --- | --- |
| `super + alt + h/l` | Previous/next desktop |
| `super + alt + shift + h/l` | Move window to previous/next desktop (follow) |
| `super + 1-9` | Switch to numbered desktop |
| `super + shift + 1-9` | Send the current window to the numbered desktop; stay here |
| `super + alt + 1-9` | Send the current window to the numbered desktop and follow |
| `super + alt + shift + <key>` | Move window to mapped desktop (follow) |
| `virtual_desktop.auto_assign` | Move newly created windows that match `apps[]` with `desktop` set |
| `virtual_desktop.debug_focus` | Log cross-desktop focus attempts to `%APPDATA%\harken\vd.focus.debug.log` |
| `virtual_desktop.switch_curtain` | Dim overlay during desktop switches to reduce flicker |

#### Apps (defaults)

These are examples for the launch-or-focus keybindings.

| Shortcut | Action |
| --- | --- |
| `super + b` | Browser (`firefox.exe`) |
| `super + f` | Files (`explorer.exe`) |
| `super + v` | Editor (`Code.exe`) |
| `super + Return` | PowerShell (`pwsh.exe -NoLogo`) |
| `super + n` | Notes (`notepad++.exe`) |

#### Command mode

| Shortcut | Action |
| --- | --- |
| `super + '` | Enter command mode |
| `r` | Reload program/config |
| `e` | Open config file |
| `w` | Open a new window for the active app |
| `n` | Toggle command overlay |
| `i` | Open window inspector |
| `m` | Enter move mode |
| `Esc` | Exit command mode |


### Helper Utility
- `tools/window_inspector.ahk` lists active window titles, exe names, classes, and PIDs.
- Use it to identify values for `apps[].win_title` in your config.
- In Command Mode, press `i` to launch the window inspector.
- Use Refresh to update the list; Copy Selected/All or Export to save results.

### Config watcher

Optional config file watcher that reloads the program when your config changes.

```toml
[config_watch]
enabled = false
interval_ms = 2500
```

### Screen search

```toml
[screen_search]
enabled = true
# Super+, and Super+. are reserved for monitor focus.
hotkey = ""
hint_chars = "asdfghjklqwertyuiopzxcvbnm"
max_results = 200
min_size_px = 12
min_distance_px = 40
hint_opacity = 235
debug_log = false
```

## Limitations
- This has not been tested with multi-monitor setups or much outside of ultra-wide monitors.
- Virtual desktop integration requires AutoHotkey v2.1-alpha-18 or later.
- Some apps (e.g., Discord) launch via `Update.exe` and keep versioned subfolders, which makes auto-resolution unreliable for launching or focusing more challenging.
- For some apps that minimize or close to the system tray, it's recommended you disable that in the program. Otherwise you can try to set `apps[].run` to a stable full path (or use `run_paths`) in your config.
- Windows with elevated permissions may ignore Harken hotkeys unless Harken is run as Administrator.

## Third-Party
- JXON (AHK v2 JSON serializer) from https://github.com/TheArkive/JXON_ahk2
  - License: `LICENSES/JXON_ahk2-LICENSE.md`
- VD.ahk from https://github.com/FuPeiJiang/VD.ahk
  - License: `LICENSES/VD.ahk-LICENSE.md`
- UIA.ahk v1.1.2 from https://github.com/Descolada/UIA-v2
  - License: `LICENSES/UIA.ahk-LICENSE.md`
- AutoHotkey-WinMover from https://github.com/Nich-Cebolla/AutoHotkey-WinMover
  - Vendored from commit `3fdf77304a4c75f626e6e63ce98383b2552ea989`
  - Local patch corrects the maximized-window work-area property names used by dynamic move/resize.
  - License: `LICENSES/AutoHotkey-WinMover-LICENSE.md`

## Similar tools and inspirations

For this project I was primarily inspired by what I was able to accomplish with [Raycast](https://www.raycast.com/) on macOS. Between [Karabiner](https://karabiner-elements.pqrs.org/), Raycast, and [HammerSpoon](https://www.hammerspoon.org/) one could achieve all of Harken and more on macOS. I needed to move back to windows for work, and I wanted a way to use the same flow on Windows that I had become accustomed to on macOS.

Other macOS tools that I tried for more than five minutes were [AeroSpace](https://github.com/nikitabobko/AeroSpace) and [Loop](https://github.com/MrKai77/Loop).

The foundation of Harken was built upon [this reddit post](https://old.reddit.com/r/AutoHotkey/comments/17qv594/window_management_tool/), shared by u/CrashKZ -- Thanks to [/u/plankoe](https://old.reddit.com/user/plankoe) for their initial contributions, too.

### [FancyZones](https://learn.microsoft.com/en-us/windows/powertoys/fancyzones)

FancyZones is okay, but it doesn't remove the need to know where things are in order to focus on them, and its features are insufficient for a truly keyboard-centered workflow.

### [Komorebi](https://github.com/LGUG2Z/komorebi)

I really like komorebi--though I didn't use it for long and I have never been able to stick with tiling in the long run--but for those who prefer the tiling approach this might be the best option on Windows.

### [GlazeWM](https://github.com/glzr-io/glazewm)

GlazeWM is another popular tiling window manager for Windows operating systems.


### Feature comparison (Harken vs similar Windows tools)

| Feature | Harken | [FancyZones](https://learn.microsoft.com/en-us/windows/powertoys/fancyzones) | [komorebi](https://github.com/LGUG2Z/komorebi) | [GlazeWM](https://github.com/glzr-io/glazewm) |
| --- | --- | --- | --- | --- |
| Primary interaction model | Keyboard-first hotkeys and commands | Zone-based snapping (mouse + keyboard) | Dynamic tiling WM | Dynamic tiling WM |
| Launch-or-focus app hotkeys | Yes (configurable per app) | No (outside scope) | Possible via external tooling/scripts | Possible via external tooling/scripts |
| Directional focus movement | Yes (`super + n/e/i/o` or arrows) | No | Yes | Yes |
| App-window cycling | Yes (`super + c`) | Mostly | Yes (tiling containers/workspaces) | Yes (tiling containers/workspaces) |
| Virtual desktop hotkeys | Yes (native desktop integration) | Indirect (PowerToys + Windows shortcuts) | Yes | Yes |
| Freeform floating adjustments | Yes (move mode + resize controls) | Primarily zone snapping | Primarily tiling; floating is secondary | Primarily tiling; floating is secondary |
| Built-in command/help overlay | Yes (`super + /`, command mode) | No | No built-in overlay | No built-in overlay |
| Config format | TOML | GUI + JSON settings | JSON/YAML-style config | YAML |
| Best fit | Users who want keyboard speed without fully committing to tiling | Users who want quick snap layouts | Users who want full tiling workflows | Users who want full tiling workflows |

