# Never Press Start

A pomodoro timer for people who keep forgetting to press start.

A macOS menu-bar Pomodoro timer that starts itself. It runs a 20-minute work timer, and when the timer finishes it covers every display with a full-screen "Take a break" overlay, including full-screen apps and every Space. The overlay stays up until you dismiss it.

It needs no macOS permissions: no Accessibility, Input Monitoring, Screen Recording or notifications.

## Build and run

```sh
make          # swift build -c release, assemble build/NeverPressStart.app, ad-hoc codesign
make icon     # redraw Support/AppIcon.icns from Support/Icon/make-icon.swift
make run      # build, then launch build/NeverPressStart.app/Contents/MacOS/NeverPressStart
make clean
```

Copy `build/NeverPressStart.app` to /Applications to use it day to day; launch at login is only set up from there, never for `build/`.

## Behaviour

- The menu bar shows the time left as `mm:ss`. A pause glyph means paused, a moon means idle, "zzz" with a countdown means a long snooze, and a cup means you're on a break.
- The menu has Pause/Resume, Reset timer, Take break now, Snooze 1 hour, Settings… (⌘,) and Quit.
- The "Current focus" field at the top of the menu shows what you're working on next to the timer, cut to the first 10 characters (set "Characters shown in menu bar" in Settings), for example `12:08 Article`. It updates as you type. Return closes the menu, Esc closes it and discards the edit. It's kept across relaunches.
- Settings sets the work period, break snooze, idle threshold and long snooze (in minutes). Changes apply from the next period. The `FOCUS_*` variables below override them.
- Launch at login is on by default. It's turned on once, the first time the app runs from /Applications or ~/Applications; after that, the Settings toggle or System Settings > General > Login Items decides.
- Snooze 1 hour is for calls and presentations. The timer stops and nothing happens for an hour, then a fresh 20-minute period starts. Resume ends the snooze early. Idle, sleep and unlock don't cut it short.
- On the overlay, "Back to work" (or Return) and Esc start a fresh 20-minute period. "Snooze 5 min" starts a 5-minute one.
- The overlay covers the menu bar on purpose, so the menu isn't reachable while it's up. The only ways out are Back to work, Snooze, Esc or Return, or killing the process (for example `pkill NeverPressStart` over SSH).
- While the overlay is up, it comes back to the front every second, whenever the active Space changes (for example, when you switch into a full-screen app) and whenever displays change.
- If there's no keyboard or mouse input for 5 minutes, that counts as a break. The timer stops and restarts at 20 minutes when input resumes. Idle time never brings up the overlay.
- Waking from sleep, waking the screen, unlocking or switching back to the user session also restarts the timer at 20 minutes. A manual pause is kept.

### Why no permissions are needed

| Need | API | Permission |
| --- | --- | --- |
| Overlay above everything | non-activating `NSPanel` at `.screenSaver` level with `.canJoinAllSpaces`, `.fullScreenAuxiliary` and `.canJoinAllApplications`. It is brought to the front every second and when the Space or frontmost app changes. It never activates the app or uses native full screen. | none |
| Esc to dismiss | Carbon `RegisterEventHotKey`, registered only while the overlay is up | none |
| Idle detection | `CGEventSource.secondsSinceLastEventType(.hidSystemState, ...)` | none |
| Sleep/lock detection | `NSWorkspace` and `DistributedNotificationCenter` notifications | none |

## Testing overrides

Environment variables, in seconds:

```sh
FOCUS_WORK_SECONDS=5 FOCUS_SNOOZE_SECONDS=10 FOCUS_IDLE_SECONDS=30 FOCUS_LONG_SNOOZE_SECONDS=20 \
  build/NeverPressStart.app/Contents/MacOS/NeverPressStart
```

State transitions are logged to stderr with timestamps.

## Launch at login

`SMAppService.mainApp.register()` adds the app itself as a login item, no helper or LaunchAgent. The Settings toggle shows `SMAppService.mainApp.status`, so it always matches System Settings.
