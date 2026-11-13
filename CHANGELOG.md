# Changelog

## 2.1.6 (not released yet)

**Improvements**
- "What's New" in the update window shows the release notes right there (the window grows) instead of opening GitHub.
- Slider number boxes: typing a number above the maximum (like 2500, or 1111111) sets the maximum half a second after you stop typing.
- An unexpected error is shown once, saved to `error-log.txt` in the settings folder, and can be reported on GitHub in one click. It no longer opens a new error box over and over.

**Fixes**
- Windows 10: message windows had a thick white rim around them, and the title bar stayed light in the dark theme on older Windows 10.
- The slider track left stripes behind when the slider moved.

## 2.1.5

**Improvements**
- Fast scroll speeds: each slider has a number box to type a value, and a **Reset** button restores the default speeds (#4).

**Fixes**
- Lists in the light theme were missing the line at the end of the last column that the dark theme shows (#4).
- The slider track is drawn in the theme colours (accent up to the thumb), so it is clear in the light theme too.

## 2.1.4

**Improvements**
- Switching between light and dark now fades smoothly, like dimming a light.
- "Check now" says you're offline within seconds instead of waiting 20.
- Installing over an existing copy asks **Update / Re-install / Downgrade, Uninstall, Cancel** (and warns when the exe is older) and keeps your "Start with Windows" choice.
- The Desktop / Start menu shortcuts question is asked only once (with "Don't ask again"), never on updates.

**Fixes**
- Sliders kept the old theme's background after switching themes.
- A message that was open during a theme switch kept a mix of both themes.
- The frame around the chosen theme card was thicker on some sides.

## 2.1.3

**Improvements**
- Fast scroll now works in Foxit PDF.
- Apps that ignore smooth scrolling are found automatically and switched to real wheel scrolling.
- **Report a problem...** in *General › Help* and the tray menu: it tries the usual fixes first, then opens a ready-filled bug report on GitHub.

## 2.1.2

**New look for themes** 🎨
Pick **Auto**, **Light** or **Dark** from three picture cards in *General*. The window switches instantly, without closing.

**Improvements**
- When a new version is found: **Update**, **What's New**, **Not Now** or **Skip Version**, plus a switch for automatic checks.
- Messages from the app now match its look (theme colours, rounded corners).
- *General › Updates* shows the version and when it last checked.
- *General › Notifications*: turn the "still running in the tray" message back on.
- Fast-scroll settings: Shift + scroll makes a slider glide. Slider handles are rounded pills, white on hover in dark mode.
- Dark mode lists show a single line between columns.

**Fixes**
- Closing the settings window while something was still gliding showed an error.

## 2.1.1

**New: automatic updates** 🔄
HK-Master now checks GitHub once a day and offers to update itself in one click. You can also check by hand in *General › Updates* or from the tray menu.

**Improvements**
- **Apply** saves without closing the settings window. **Close** turns into **Cancel** when you have unsaved changes.
- Caps Lock options are separate: the *Shift + Caps Lock* guard and *Media Control*, with a choice of hold key (Caps Lock, Right Alt, Right Ctrl, Menu key, Scroll Lock).
- Fast scroll support for WhatsApp desktop and other new-style (WinUI 3) apps.
- Shift + scroll over a settings slider moves it the right way.
- Fast-scroll sliders move in steps of 5 when you scroll over them.
- Lists show lines between their columns.
- Shortcuts guide: icons and text sit on one line, and there's a new "General" group.
- The tray menu says "Restart app" instead of "Reload".
- Removed the old Revit 2022 "pk" shortcut.

**Download:** HK-Master.exe below. If you have 2.1.0, download this one by hand once. From now on, updates are automatic.

## 2.1.0

First public release.
