# MacTabber

A private, native macOS menu-bar utility that makes Command–Tab show only apps
with a visible window on the current Desktop (Space).

## Install

```sh
./scripts/install.sh
```

On first launch, allow MacTabber in **System Settings → Privacy & Security →
Accessibility**. The menu-bar icon reports when the replacement switcher is active.
MacTabber registers itself in **System Settings → General → Login Items**.

## Behavior

- Hold Command and press Tab (or Shift–Tab) to cycle.
- Release Command to activate the selected app.
- Press Escape to cancel.
- Only regular applications with a layer-0 window currently onscreen are included.
  Minimized apps and apps whose windows exist only in other Spaces are excluded.

## Build requirements

macOS 14 or newer and Swift 6/Xcode 16 or newer. The app uses only public Apple
frameworks: AppKit, Core Graphics, Accessibility, and Service Management.
