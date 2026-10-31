# My Planner for Mac

A native macOS desktop widget for tasks, goals, habits, notes and focus sessions. It lives on your desktop like a built-in widget, so you never have to open an app window.

Part of the **My Planner** project (see the Android app in the main repo). Both apps read and write the same JSON backup format.

## Highlights
- Translucent frosted-glass panel pinned at desktop level, with a colour theme per tab
- Menu-bar item: show/hide, keep above windows, launch at login, backup/restore
- Today, Tasks, Goals, Habits, Notes and a Focus timer
- **Budget tracker:** log expenses by category, set a monthly budget, see today's spend, what's left and a daily allowance, plus a 7-day chart
- Universal binary (Apple Silicon + Intel), built with GitHub Actions

## Tech
SwiftUI, AppKit (`NSWindow`, `NSVisualEffectView`, `NSStatusItem`), `SMAppService`, `Codable` JSON, Swift Package Manager.

## Build
```
swift build -c release
```
Or push to GitHub and download the app from the Actions artifacts. On first launch, right-click the app and choose **Open** (it is ad-hoc signed).

## Author
Built by **[Md Shamoel Farooqui]**.
