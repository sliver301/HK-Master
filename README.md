<p align="center">
  <img src="icons/app.svg" width="96" alt="HK-Master logo">
</p>

<h1 align="center">HK-Master</h1>
<p align="center"><b>Hot Keys Master: the MX Master experience, on any mouse.</b></p>

<p align="center">
Flick the wheel and pages glide as if it spins freely. Your side buttons become undo and redo.<br>
Free, lightweight, and no admin rights needed.
</p>

<p align="center">
  <a href="https://github.com/sliver301/HK-Master/releases/latest">
    <img src="https://img.shields.io/github/v/release/sliver301/HK-Master?label=Download&style=for-the-badge&color=0067C0" alt="Download the latest version">
  </a>
</p>

## ⬇️ Download

**[Get the latest HK-Master.exe →](https://github.com/sliver301/HK-Master/releases/latest)**

Run it, choose **Install** or **Portable**, and you're done. Windows 10 / 11.

> Windows may warn about an **unknown publisher**: the exe isn't code-signed yet. Click **More info → Run anyway**. Every release exe is built from this public source by [GitHub Actions](.github/workflows/build.yml).

[Privacy](#privacy)

---

## Features

| | |
|---|---|
| ⚡ **Fast scroll** | Hold **Shift** and flick the wheel: the page keeps gliding, just like the Logitech MX Master's free-spin wheel, but done in software so it works with any mouse. Revit and CAD drawing areas are skipped automatically. |
| ↔️ **Sideways scroll** | **Ctrl + Shift + wheel** scrolls left and right in any app. |
| 🖱️ **Side buttons** | **Back = Undo**, **Forward = Redo**, **both together = Enter**, per app (Revit, AutoCAD, Office, Adobe and more). Off in dialogs and File Explorer, so nothing gets undone by accident. |
| 📂 **Folders** | **Shift + Back** goes up one folder in File Explorer and in any app's Open/Save dialog. |
| 🔊 **Media control** | Hold **Caps Lock** (or Right Alt, Right Ctrl, Menu key, Scroll Lock) + **wheel** for volume, **+ middle click** for play/pause, **+ side buttons** for next/previous track. |
| 🔠 **Caps Lock guard** | Caps Lock alone does nothing; **Shift + Caps Lock** turns it on and off. No more ACCIDENTAL CAPS. |
| 🔄 **Auto-update** | Checks GitHub once a day and updates itself in one click. You can turn it off, or check by hand, in *General › Updates*. |
| ⌨️ **Text shortcuts** | Type a short code like `@@` and get your full email address, phone number or any text. |

Everything can be switched on/off and changed in the settings window (**Ctrl + Alt + H**, or double-click the tray icon). Light and dark themes included.

## Install

1. Download **HK-Master.exe** from the [latest release](https://github.com/sliver301/HK-Master/releases/latest).
2. Run it and choose:
   - **Install**: copies itself to your user folder, can start with Windows, and appears in *Settings › Apps* for uninstalling.
   - **Portable**: just runs from where it is.

No administrator rights are needed for either.

## Uninstall

- **Installed:** *Windows Settings › Apps › Installed apps › HK-Master › Uninstall*, or **Uninstall...** in the app's *General* tab. This removes the program, its start-with-Windows entry and its shortcuts.
- **Portable:** quit it from the tray icon and delete the exe.
- Uninstall asks whether to delete your settings too. Portable users can delete `%APPDATA%\HK Master\` by hand.

## Run from source

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Double-click `HK-Master.ahk`.

To build the exe yourself, open `HK-Master.ahk` with **Ahk2Exe** (comes with AutoHotkey). The icons are picked up from the `icons` folder.

Official release exes are built from this repository by [GitHub Actions](.github/workflows/build.yml), never on a personal PC.

## Settings

Your settings are stored in `%APPDATA%\HK Master\HK-Master.ini`. Use **Export / Import** in the General tab to back them up or move them to another PC.

## 🤖 Made with AI

This app is about 99% vibe-coded: I described what I wanted, tested it on my own PC, and an AI assistant (Claude) wrote the code. It works great for me every day, but it hasn't been through a formal code review. Bug reports and pull requests are very welcome.

## Privacy

HK-Master does not collect or send any personal data. Your settings and text shortcuts stay on your PC.

The only network access is the update check: once a day it asks GitHub (`api.github.com`) for the latest release number, and it downloads a new version only when you click **Update**. You can turn the automatic check off in *General › Updates*. Otherwise this program will not transfer any information to other networked systems unless specifically requested by the user. GitHub's own [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) applies to those requests.

## License

[GPL-3.0](LICENSE): free to use, change and share. Any copy or modified version you share must also be open source under GPL-3.0, keep the original credit, and say what you changed.

**Name and icon:** the "HK-Master" name and icon belong to Islam Abohadia. Forks are welcome, but please give yours a different name and icon. Contributions back to this repo are the best way to improve HK-Master itself.
