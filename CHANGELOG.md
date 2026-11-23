# Changelog

## 2.2.1 (not released yet)

**New**
- Media Control: more keys to hold, now Left Alt, Left Ctrl, Insert and Pause as well as Caps Lock, Right Alt, Right Ctrl, the Menu key and Scroll Lock. Alt and Ctrl keep working as usual (Alt + Tab, Ctrl + C...); only their combinations with the mouse buttons you set are taken.
- A little surprise on the General page, for those who make the window really wide.

**Changed**
- Mouse & keys: the Media Control boxes now reach the right edge of the page and move with it when the window is made wider, with a thin line joining each label to its box (shown only once the window is wider than its original size). Their menus open below the box instead of beside it.
- Shortcuts and General: when the window is made wider, the right-hand column moves to the right edge.
- Fast scroll: the speed sliders fill the row, with the numbers and Reset at the right edge. When the window is made wider, the sliders and the Excluded apps list get longer, while the list's buttons and notes keep their size at the right edge.

## 2.2.0

**New**
- Accent colour (Settings > General > Look, next to Frosted glass): a colour button opens a swatch picker with 33 colours (11 hues in light, normal and deep), Windows' own accent colour, or any colour from Windows' colour dialog. The one colour is used for the tabs, buttons, switches, check boxes, sliders and the chosen theme card, in every look. Check boxes are now rounded, in the same style as the switches.

**Fixed**
- Windows 10: light frosted glass was almost clear, so text was hard to read and had light edges around the letters. It is now a frosted light grey, like on Windows 11.

## 2.1.9

**New**
- Frosted glass for the light look too (Settings > General > Look). Text, check boxes and sliders sit right on the glass; text boxes and lists are solid white.

**Improvements**
- The update check now runs twice a day, at 9 AM and 9 PM. If the PC was off, asleep or hibernating at that time, it checks once soon after it's back on, however many times it missed. If you're offline it doesn't keep retrying; it waits for the next 9 AM or 9 PM. (Before, it only checked at most once a day, which a PC that sleeps instead of shutting down could miss for days.)

**Fixed**
- With frosted glass on, the window no longer turns see-through for a moment when you minimize it.

## 2.1.8

**New**
- Frosted glass for the dark look, on by default: a tinted, blurred see-through background with soft panels and outlined buttons. Turn it off with the switch under the theme cards (Settings > General > Look).
- Our own title bar on the settings window and the app's message boxes, in the same style as the rest (drag, double-click to maximise, snap and resize still work).
- "Release notes" opens the notes right in the app, over the settings window (Close or Esc).
- "GitHub repo" button (Settings > General > Updates) opens the project page.

**Improvements**
- Buttons, cards and the mouse picture have smooth see-through corners; lists and text boxes have rounded corners and our own thin rounded scroll bars in the theme colours; the Caps Lock "Hold" choice is a drop-down drawn like the other buttons; sliders are a thin line like the separators, without tick marks.
- Drop-down and key menus are our own rounded menus in the app's colours, opening to the side; the slider number boxes are pills; the wheel over our scroll bars scrolls; Mouse & keys has a new layout (Caps Lock, Side scroll and Media Control on top, Side buttons below a line); the Side scroll switch moved there from Fast scroll. Each section's switch sits beside its header, and switching it off greys the section out.

**Fixes**
- Sideways scroll works again where 2.1.7 broke it: classic lists and text boxes get their own scroll-bar steps, other apps get real sideways-wheel input, and over Remote Desktop the other PC gets real sideways-wheel input.
- Adding Ctrl while Shift is still held from a fast scroll now scrolls sideways (it zoomed before), and stops the glide.

**Coming soon**
- Frosted glass for the light look.

## 2.1.7

**Improvements**
- Sideways scroll (Ctrl + Shift + wheel) now sends real sideways-wheel input, so it works in every app that can scroll sideways.

## 2.1.6

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
