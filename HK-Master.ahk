; =============================================================================
;  HK-Master  -  AutoHotkey v2
;  Settings window: Ctrl+Alt+H, or double-click the tray icon.
;  All edits are saved to %APPDATA%\HK Master\HK-Master.ini.
;  The compiled exe, run from anywhere else, offers to install itself into %APPDATA%\HK Master.
; =============================================================================
#Requires AutoHotkey v2.0
; Icons for the compiled exe: the app icon, plus both tray icons embedded as resources 300/301.
;@Ahk2Exe-SetName HK-Master
;@Ahk2Exe-SetDescription HK-Master
;@Ahk2Exe-SetVersion 2.2.1
;@Ahk2Exe-ExeName HK-Master
;@Ahk2Exe-SetMainIcon icons\app.ico
;@Ahk2Exe-AddResource icons\tray-white.ico, 300
;@Ahk2Exe-AddResource icons\tray-black.ico, 301
; The release notes, shown in the app (Settings > General > Release notes).
;@Ahk2Exe-AddResource CHANGELOG.md, CHANGELOG
#SingleInstance Force
SendMode "Input"
SetWorkingDir A_ScriptDir
; Wheel hotkeys fire very fast (free-spin wheels); turn off AHK's "too many hotkeys" warning.
A_HotkeyInterval := 0
A_MaxHotkeysPerInterval := 99000000

; Settings (and the installed exe) live in the user's AppData, so nothing needs admin rights.
; Settings from the old names (KS-Master, My Collective HotKeys) are copied over once.
global APP_NAME := "HK-Master"
global INSTALL_DIR := A_AppData "\HK Master"
global INSTALL_EXE := INSTALL_DIR "\HK-Master.exe"
global DATA_DIR := INSTALL_DIR
global INI := DATA_DIR "\HK-Master.ini"
global RUN_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global UNINSTALL_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\" APP_NAME
global APP_VERSION := "2.2.1"                 ; keep equal to ;@Ahk2Exe-SetVersion and the GitHub release tag
; Updates come from the GitHub releases of the public repo (the release needs an attached HK-Master*.exe).
global REPO_URL := "https://github.com/sliver301/HK-Master"
global RELEASES_URL := "https://github.com/sliver301/HK-Master/releases/latest"
global UPDATE_API := "https://api.github.com/repos/sliver301/HK-Master/releases/latest"
global UPD_BUSY := false
global UPD_TRIED := ""                         ; the 9:00 / 21:00 time the last automatic check was made for
global UPD_WAKE := 0                           ; A_TickCount when the PC last woke from sleep / hibernation
OnMessage(0x218, PowerWake)                    ; WM_POWERBROADCAST: the PC woke up -> check if a check was missed
global SLGLIDE := {h: 0, v: 0.0, pos: 0.0}  ; settings slider glide (SliderGlide)
global UPD_LABEL := 0                          ; the "Version / last checked" text in Settings
; Second step of an update: the new exe (downloaded to Temp) was started as
;   new.exe /update "<path of the old exe>"
; It waits until the old one has exited, copies itself over it, starts it and quits.
if A_IsCompiled && A_Args.Length >= 2 && A_Args[1] = "/update" {
    ok := false
    Loop 50 {                                  ; up to 10 s for the old copy to close
        try {
            FileCopy(A_ScriptFullPath, A_Args[2], 1)
            ok := true
            break
        }
        Sleep 200
    }
    if ok
        Run('"' A_Args[2] '" /updated')
    else
        MsgBox("Could not update " A_Args[2] ".`nPlease download it again from GitHub.", "HK-Master", "Icon!")
    ExitApp
}
global UPDATED := false                        ; just updated: tray only, say so
; Started by Windows at logon (the Run entry adds /startup): stay in the tray, no window.
global STARTUP_MODE := false
for arg in A_Args {
    if arg = "/startup"
        STARTUP_MODE := true
    if arg = "/updated"
        UPDATED := true
}
Loop Files A_Temp "\HK-Master-*.exe"            ; leftover update downloads
    try FileDelete(A_LoopFileFullPath)
; "Uninstall" in Windows Settings > Apps starts the installed exe with /uninstall.
if A_IsCompiled && A_Args.Length && A_Args[1] = "/uninstall" {
    UninstallApp(true)
    ExitApp
}
DirCreate(DATA_DIR)
OnError(AppError)
if !FileExist(INI) {
    for old in [A_AppData "\KS Master\KS-Master.ini", A_AppData "\My Collective HotKeys\My Collective HotKeys.ini"
              , A_ScriptDir "\My Collective HotKeys.ini"]
        if FileExist(old) {
            try FileCopy(old, INI)
            break
        }
}
try RegDelete(RUN_KEY, "KS-Master")        ; the previous name's startup entry
try {                                       ; an older startup entry without /startup would open the window at logon
    startVal := RegRead(RUN_KEY, APP_NAME)
    if startVal != "" && !InStr(startVal, "/startup")
        RegWrite(startVal " /startup", "REG_SZ", RUN_KEY, APP_NAME)
}
global cfg := LoadConfig()
global fs := {v: 0, acc: 0, last: 0, running: false, t0: 0, gen: 0, lastFwd: 0, real: false, probe: 0}   ; fast-scroll state
global FS_LASTUNDER := Map()        ; exe -> window class last fast-scrolled over (for bug reports)
FS_LASTUNDER.CaseSense := false
global PICBMP := Map()              ; our drawn pictures (buttons, cards...): control hwnd -> 32-bit bitmap with alpha
global PICFIELD := Map()     ; drawn pictures that sit on a text box's colour, not the window's
OnMessage(0x2B, PicDrawItem)        ; WM_DRAWITEM: paints them. Set before any window opens (install / update box)
global SCROLLS := Map()             ; our scroll bars (ScrollOverlay): hwnd -> control
OnMessage(0x201, ScrollDown)        ; WM_LBUTTONDOWN on one of them: drag / jump
OnMessage(0x201, LayeredClick)      ; light glass: a click through a label's see-through part still clicks it
OnMessage(0x231, GlassMoveStart)     ; WM_ENTERSIZEMOVE: light glass goes plain while the window is dragged
OnMessage(0x232, GlassMoveEnd)       ; WM_EXITSIZEMOVE: and frosted again when it is let go
OnMessage(0x47, GlassShown)          ; WM_WINDOWPOSCHANGED: light glass labels paint at once when a window opens
OnMessage(0x20A, ScrollWheel)       ; WM_MOUSEWHEEL over one of them: scroll its box
global POPUPS := Map()              ; our frameless pop-ups (release notes): hwnd -> 1
global TITLED := Map()              ; windows with our own title bar (TitleBar): hwnd -> {resize, btns, text, icon}
global TB_H := 32                   ; its height (96-dpi units)
OnMessage(0x83, TitledNcCalc)       ; WM_NCCALCSIZE: no Windows frame on those windows
OnMessage(0x84, TitledHitTest)      ; WM_NCHITTEST: our title bar drags, the edges resize
global GLASS_WINS := Map()          ; windows that have the frosted-glass backdrop on (hwnd -> 1)
global CHECKS := Map()              ; check boxes we draw ourselves in the accent colour (hwnd -> 1), see CheckDraw
OnMessage(0x4E, CheckDraw)          ; WM_NOTIFY: NM_CUSTOMDRAW from those check boxes
global LAYERED := Map()             ; light glass: controls made layered (hwnd -> 1), see GlassLayer
global APPDLGS := Map()             ; open AppDialog windows (hwnd -> Gui), recoloured on a theme switch
; Debug (set in the .ini under [General]): Debug=1 writes fastscroll-log.txt,
; DebugHoldMs=2000 pretends Shift is held that long after a glide starts (for testing).
global FS_DEBUG := IniRead(INI, "General", "Debug", 0) = 1
global FS_HOLDMS := NumOr(IniRead(INI, "General", "DebugHoldMs", 0), 0)
global FS_LOGBUF := []
global chordTick := 0                                    ; side-button chord
global sbCur := 0                                        ; side-button keys for the app under the mouse
global KEYBOX_VALUES := Map()                            ; settings window: key box hwnd -> keys
global SettingsGui := 0
global ANCH := Map()          ; settings window: control hwnd -> how it follows a resize
global BTN := Map()          ; hwnd -> button control
global BTN_HOT := 0          ; the button currently highlighted
global SLIDERS := Map()      ; settings window: slider hwnd -> {slider, value text, range}
global SLIDER_OF := Map()    ; a slider's number box and its pill -> the slider hwnd (wheel over them)
global PENDING := 0          ; settings kept while the window is rebuilt for a new theme
global REOPEN := 0           ; page / position / size to restore after that
global BASE_SIG := ""        ; settings window: the saved settings, to tell when something changed
global GUIDE := {hwnd: 0, pos: 0, total: 0, page: 0}     ; settings window: scrollable Shortcuts page
; Remote desktop / VM windows: a scroll message sent to them never reaches the remote PC
; (they only forward real input), so Shift + wheel is passed through untouched. Run the
; script on the remote PC as well to get fast scroll there.
global REMOTE_APPS := Map()
REMOTE_APPS.CaseSense := false
for remoteExe in ["mstsc.exe", "msrdc.exe", "vmconnect.exe", "AnyDesk.exe", "TeamViewer.exe"
          , "vncviewer.exe", "parsecd.exe", "RDCMan.exe"]
    REMOTE_APPS[remoteExe] := true

if !FileExist(INI) || IniRead(INI, "General", "ConfigVersion", 1) < 3
    SaveConfig(cfg)

; A reload (after Save, Import or tray Reload) must not ask to install again.
global RELOADED := UPDATED || IniRead(INI, "State", "Reloaded", 0) = 1 || IniRead(INI, "State", "JustSaved", 0) = 1
if RELOADED
    try IniDelete(INI, "State", "Reloaded")
try IniDelete(INI, "State", "Reopen")       ; left by an older version
if InstalledHere()
    RegisterUninstall()                      ; (re)create the Windows Settings > Apps entry
if A_IsCompiled && !InstalledHere() && !RELOADED && !STARTUP_MODE
    OfferInstall()
ApplyAppMode()

SetupCapsLock()
SetupTray()
OnMessage(0x20A, SliderWheel)          ; WM_MOUSEWHEEL
RegisterHotstrings()

if IniRead(INI, "State", "JustSaved", 0) = 1 {
    try IniDelete(INI, "State", "JustSaved")
    TrayTip("Settings saved and applied.", APP_NAME, "Iconi Mute")
}

if UPDATED
    TrayTip("Updated to version " APP_VERSION ".", APP_NAME, "Iconi Mute")
; Look for a new version at 9 AM and 9 PM. A check missed while the PC was off, asleep or
; hibernating is done soon after it is back on (see AutoUpdateCheck). Quiet unless there is
; a new version.
SetTimer(AutoUpdateCheck, -30000)
SetTimer(AutoUpdateCheck, 60000)

; Opened by the user: show the settings window. Opened by Windows at logon (or restarted): tray only.
if !STARTUP_MODE && !RELOADED
    SetTimer(ShowSettings, -100)

; =============================================================================
;  Hotkeys
; =============================================================================
#SuspendExempt
^!h::ShowSettings()
#SuspendExempt False

; ---- CapsLock layer: registered in SetupCapsLock() only when enabled ---------

; ---- Mouse side buttons (undo / redo in the listed apps) ---------------------
; Off in any dialog / file browser, so Back/Forward keep their normal meaning there
; and Ctrl+Z can never undo a file move or delete in an embedded Explorer view.
#HotIf SideButtonsActive()
XButton2::SideButton("XButton2", "XButton1", "fwd")
XButton1::SideButton("XButton1", "XButton2", "back")
; In a file dialog (Open, Save, Link, Browse...) of a listed app, the side buttons navigate the folders.
#HotIf SideFileDialogActive()
XButton1::FileDlgNav(-1)      ; Back
XButton2::FileDlgNav(1)       ; Forward
; Shift + Back = up one folder, in any app's file dialog and in File Explorer windows.
#HotIf FolderUpTarget()
+XButton1::FolderUp()
#HotIf

; ---- Fast scroll (Shift + wheel) --------------------------------------------
; Ctrl + Shift + wheel = horizontal scroll at normal speed, in any app. Checked first and on the
; keys really held, so adding Ctrl while Shift is still down from a fast scroll (even mid-glide)
; always scrolls sideways instead of letting the app see Ctrl + wheel (zoom).
#HotIf cfg.fs.hscroll && GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P")
*WheelUp::HScroll(-1)
*WheelDown::HScroll(1)
; Shift + wheel over a slider in the settings window: the slider glides, like fast scroll.
#HotIf OverSlider()
+WheelUp::SliderGlide(1)
+WheelDown::SliderGlide(-1)
#HotIf !fs.running && FastScrollAllowed()
+WheelUp::FS_Start(1)
+WheelDown::FS_Start(-1)
#HotIf fs.running
*WheelUp::FS_Notch(1)
*WheelDown::FS_Notch(-1)
*LShift::return          ; swallow Shift auto-repeat so the app keeps seeing plain vertical scrolling
*RShift::return
~*LButton::
~*RButton::
~*MButton::FS_Stop()
#HotIf

; =============================================================================
;  Text shortcuts
; =============================================================================
RegisterHotstrings() {
    for s in cfg.snippets
        try Hotstring(":*TC1:" s.trigger, s.text, "On")
}

; Apply: switch off what the old settings registered, then register the new ones.
; Side buttons and fast scroll read cfg each time, so they follow on their own.
ReapplySettings(old) {
    for s in old.snippets
        try Hotstring(":*TC1:" s.trigger, , "Off")
    if old.caps.shiftToggle {
        try Hotkey("+CapsLock", "Off")
        SetCapsLockState "Off"                   ; also lifts AlwaysOff
    }
    if old.caps.enabled
        for key in ["WheelUp", "WheelDown", "MButton", "XButton2", "XButton1"]
            try Hotkey(old.caps.trigger " & " key, "Off")
    SetupCapsLock()
    RegisterHotstrings()
}

; =============================================================================
;  CapsLock layer
; =============================================================================
; Two separate options:
;  - Shift toggle: Caps Lock alone does nothing, Shift + Caps Lock turns it on / off.
;  - Media Control: hold the trigger key (Caps Lock, Right Alt...) + a mouse button.
; With both off nothing is registered, so Caps Lock works normally.
SetupCapsLock() {
    if cfg.caps.shiftToggle {
        SetCapsLockState "AlwaysOff"
        Hotkey("+CapsLock", (*) => SetCapsLockState(GetKeyState("CapsLock", "T") ? "AlwaysOff" : "AlwaysOn"), "On")
    }
    if !cfg.caps.enabled
        return
    for k, key in Map("wheelUp", "WheelUp", "wheelDown", "WheelDown", "mButton", "MButton"
                    , "xButton2", "XButton2", "xButton1", "XButton1")
        if cfg.caps.%k% != ""
            try Hotkey(cfg.caps.trigger " & " key, SendCaps.Bind(cfg.caps.%k%), "On")
}

; Keys that can hold the Media Control layer: [AutoHotkey name, shown name].
; Alt and Ctrl keep their normal use (Alt + Tab, Ctrl + C...) when held as the trigger; only
; their combinations with the mouse buttons below are taken. No Shift (Shift + wheel is
; fast scroll) and no Win key (releasing it could open the Start menu). With Left Ctrl as the
; trigger, Ctrl + wheel (zoom) and Ctrl + Shift + wheel (side scroll) may be taken by the Media Control
; layer while the left Ctrl is held; the right Ctrl still does them.
TRIGGERS() => [["CapsLock", "Caps Lock"], ["LAlt", "Left Alt"], ["RAlt", "Right Alt"]
             , ["LCtrl", "Left Ctrl"], ["RCtrl", "Right Ctrl"], ["AppsKey", "Menu key"]
             , ["ScrollLock", "Scroll Lock"], ["Insert", "Insert"], ["Pause", "Pause"]]

TriggerName(key) {
    for t in TRIGGERS()
        if t[1] = key
            return t[2]
    return key
}

SendCaps(keys, *) => Send(keys)

; =============================================================================
;  Mouse side buttons
; =============================================================================
; Active when the active window AND the window under the mouse belong to a listed app,
; and neither is a dialog or contains a file browser.
SideButtonsActive() {
    global sbCur
    if !cfg.side.enabled
        return false
    try {
        active := WinExist("A")
        if !active || IsDialogOrBrowser(active)
            return false
        exe := WinGetProcessName(active)
        if exe = "explorer.exe" || !cfg.side.apps.Has(exe)
            return false
        MouseGetPos(, , &under)
        if !under || WinGetProcessName(under) != exe || IsDialogOrBrowser(under)
            return false
        sbCur := cfg.side.apps[exe]
        return true
    }
    return false
}

IsDialogOrBrowser(hwnd) {
    if WinGetClass(hwnd) = "#32770"            ; Open / Save / Browse / any standard dialog
        return true
    return HasExplorerView(hwnd)
}

HasExplorerView(hwnd) {
    for cls in ["SHELLDLL_DefView1", "Breadcrumb Parent1", "DirectUIHWND1"] {   ; embedded Explorer view
        try {
            ControlGetHwnd(cls, hwnd)
            return true
        }
    }
    return false
}

SideFileDialogActive() {
    if !cfg.side.enabled
        return false
    try {
        active := WinExist("A")
        if !active || !cfg.side.apps.Has(WinGetProcessName(active))
            return false
        return HasExplorerView(active)
    }
    return false
}

; Modern (Vista+) file dialogs have Back / Forward / Up on Alt+Left / Alt+Right / Alt+Up.
; Old-style ones (Revit's and AutoCAD's Open dialogs: SHELLDLL_DefView but no DirectUIHWND)
; have Autodesk toolbar buttons instead: Back = Alt+1, Up one level = Alt+2, and no Forward.
IsOldFileDlg(hwnd) {
    try {
        ControlGetHwnd("DirectUIHWND1", hwnd)
        return false
    }
    return true
}

FileDlgNav(dir) {
    active := WinExist("A")
    if !IsOldFileDlg(active) {
        SideLog("dialog: modern, " (dir < 0 ? "Alt+Left" : "Alt+Right"))
        Send(dir < 0 ? "!{Left}" : "!{Right}")
    } else if dir < 0 {
        SideLog("dialog: old-style, Back (Alt+1)")
        Send("!1")
    }                                          ; old-style dialogs have no Forward
}

FolderUpTarget() {
    try {
        active := WinExist("A")
        cls := WinGetClass(active)
        if cls = "CabinetWClass" || cls = "ExploreWClass"     ; File Explorer window
            return true
        return cls = "#32770" && HasExplorerView(active)       ; a file dialog in any app
    }
    return false
}

FolderUp() {
    active := WinExist("A")
    cls := WinGetClass(active)
    if cls = "#32770" && IsOldFileDlg(active) {
        ; Alt+2 is "Up one level" only on Autodesk's toolbar; other old dialogs are left alone.
        exe := WinGetProcessName(active)
        if exe = "Revit.exe" || exe = "acad.exe" || exe = "acadlt.exe" {
            SideLog("up: old-style dialog, Alt+2")
            Send("!2")
        }
        return
    }
    SideLog("up: Alt+Up")
    Send("!{Up}")
}

; Debug only (Debug=1): writes sidebuttons-log.txt in the settings folder, with the
; dialog's window class and its controls, to see why a file dialog is not recognised.
SideLog(msg) {
    if FS_DEBUG
        try FileAppend(FormatTime(, "HH:mm:ss") "  " msg "`n", DATA_DIR "\sidebuttons-log.txt", "UTF-8")
}


; Fires on release; pressing both buttons sends the "both" action instead.
SideButton(thisBtn, otherBtn, key) {
    global chordTick
    keys := sbCur
    pressTick := A_TickCount
    if GetKeyState(otherBtn, "P") {
        chordTick := A_TickCount
        if keys.both != ""
            Send keys.both
        KeyWait thisBtn
        return
    }
    KeyWait thisBtn
    if chordTick >= pressTick
        return
    if keys.%key% != ""
        Send keys.%key%
}

; =============================================================================
;  Fast scroll
; =============================================================================
; Fast scroll works everywhere except over a drawing canvas: the drawing area of Revit,
; AutoCAD and similar CAD apps (detected, so their panels and dialogs still glide), and
; apps listed as canvas apps (Photoshop, Blender...), where Shift + wheel is left alone.
; Only IsCadApp() apps get the drawing-area check: other MFC apps (Foxit PDF...) use the same
; window classes for normal documents, which then could not fast scroll.
IsCadApp(exe) {
    static apps := ""
    if !apps {
        apps := Map(), apps.CaseSense := "Off"
        for e in ["Revit.exe", "acad.exe", "bricscad.exe", "zwcad.exe", "gcad.exe", "DraftSight.exe", "ARCHICAD.exe"]
            apps[e] := 1
    }
    return apps.Has(exe)
}

FastScrollAllowed() {
    if !cfg.fs.enabled
        return false
    try {
        MouseGetPos(, , &win, &ctl, 2)
        if ctl && SliderAt(ctl)         ; our own sliders: Shift + wheel moves them like the plain wheel (SliderWheel)
            return false
        return !OverCanvas(win, ctl)
    }
    return false
}

OverCanvas(win, ctl) {
    exe := WinGetProcessName(win)
    return cfg.fs.canvasMap.Has(exe) || REMOTE_APPS.Has(exe)
        || (IsCadApp(exe) && IsCadCanvas(ctl ? ctl : win))
}

; The window that should get scroll messages. Chromium/Electron apps (Chrome, Edge, VS Code,
; Teams, Claude...) put a transparent "Intermediate D3D Window" over their content that
; ignores them; their "Chrome_WidgetWin" window handles the wheel instead. In Chrome that is the
; top-level window; in WebView2 apps (WhatsApp, new Outlook...) it is a child inside the app.
WheelTarget(win, ctl) {
    if !ctl
        return win
    buf := Buffer(512)
    h := ctl
    while h {
        DllCall("GetClassName", "Ptr", h, "Ptr", buf, "Int", 256)
        if InStr(StrGet(buf), "Chrome_WidgetWin") = 1
            return h
        if h = win
            break
        h := DllCall("GetParent", "Ptr", h, "Ptr")
    }
    DllCall("GetClassName", "Ptr", ctl, "Ptr", buf, "Int", 256)    ; never throws (the window may be gone)
    if StrGet(buf) = "Intermediate D3D Window"
        return win
    return ctl
}

; A CAD drawing area is an MFC view window (class "AfxFrameOrView140u" in Revit 2024, seen in
; the debug log), or anything inside an MDIClient area (AutoCAD's drawing tabs).
; Uses raw API calls because #HotIf runs this on every Shift+wheel event.
IsCadCanvas(hwnd) {
    buf := Buffer(512)
    while hwnd {
        DllCall("GetClassName", "Ptr", hwnd, "Ptr", buf, "Int", 256)
        cls := StrGet(buf)
        if cls = "MDIClient" || InStr(cls, "AfxFrameOrView") = 1
            return true
        hwnd := DllCall("GetParent", "Ptr", hwnd, "Ptr")
    }
    return false
}

; Scrolls by posting a wheel message straight to the window under the mouse.
; It never passes through the mouse input stream, so it can't re-trigger this script's
; own wheel hotkeys (the earlier input-injection version did, which flooded the mouse
; queue: frozen cursor, no scrolling). Sub-notch steps keep it smooth.
FS_Wheel(delta) {
    CoordMode "Mouse", "Screen"
    MouseGetPos(&x, &y, &win, &ctl, 2)
    target := WheelTarget(win, ctl)
    if !target || !DllCall("IsWindow", "ptr", target) {     ; window closed mid-glide
        FS_Stop()
        return
    }
    ; A glide that started over a panel stops when the mouse moves onto a canvas.
    try {
        if OverCanvas(win, ctl) {
            FS_Log("stop: mouse moved onto a canvas")
            FS_Stop()
            return
        }
    }
    if fs.real || NeedsRealWheel(ctl ? ctl : win) {
        RealWheel(delta, "WheelUp", "WheelDown")
        if fs.real
            FS_Probe(Abs(delta))
        return
    }
    wp := (delta & 0xFFFF) << 16              ; high word = wheel delta, low word = no Shift/Ctrl
    lp := ((y & 0xFFFF) << 16) | (x & 0xFFFF)
    ; Wait (max 60 ms) for the app to finish this step before the next one, so a slow app is
    ; never buried under queued scroll messages. If it can't keep up, stop gliding.
    r := 0
    ok := DllCall("SendMessageTimeout", "Ptr", target, "UInt", 0x020A, "UPtr", wp, "Ptr", lp
        , "UInt", 0x2, "UInt", 60, "UPtr*", &r)   ; 0x2 = SMTO_ABORTIFHUNG
    if !ok
        FS_Stop()
    else
        FS_Probe(Abs(delta))
}

; WinUI 3 apps (WhatsApp desktop, seen in the debug log as WhatsApp.Root.exe with
; "Microsoft.UI.Content.DesktopChildSiteBridge" under the mouse) read the wheel from the real
; input stream, so a posted wheel message does nothing there. They get real wheel input instead.
; Foxit PDF (BCGSoft toolkit, "BCGPTabWnd" under the mouse in the debug log) also ignores posted
; wheel messages: the glide ran but the page never moved.
NeedsRealWheel(hwnd) {
    try {
        if InStr(WinGetClass(hwnd), "Microsoft.UI.Content.") = 1
            return true
        exe := WinGetProcessName(hwnd)
        return InStr(exe, "Foxit") = 1 || cfg.fs.realMap.Has(exe)
    }
    return false
}

; ---- Apps that ignore posted wheel messages are found automatically ------------
; At the start of a glide, a small strip of the screen around the mouse is fingerprinted.
; If ~3 notches later nothing there has changed, the rest of the glide switches to real wheel
; input. If the strip then moves, the app is remembered in [FastScroll] realWheelApps.
; If neither moves (end of the page, a blank area), nothing is remembered.
FS_ProbeStart() {
    fs.real := false
    fs.probe := 0
    try {
        MouseGetPos(&x, &y, &win, &ctl, 2)
        exe := WinGetProcessName(win)
        FS_LASTUNDER[exe] := ctl ? WinGetClass(ctl) : WinGetClass(win)
        if NeedsRealWheel(ctl ? ctl : win)
            return
        fs.probe := {x: x, y: y, exe: exe, crc: RegionCrc(x, y), sent: 0, t: FS_Now(), stage: 1}
    }
}

FS_Probe(sent) {
    p := fs.probe
    if !p
        return
    p.sent += sent
    if p.sent < 360 || FS_Now() - p.t < 0.15        ; give the app ~3 notches and time to repaint
        return
    c := RegionCrc(p.x, p.y)
    if p.stage = 1 {
        if c != p.crc {                              ; it scrolls: all good
            fs.probe := 0
            return
        }
        FS_Log("probe: nothing moved, trying real wheel")
        fs.real := true
        p.stage := 2, p.crc := c, p.sent := 0, p.t := FS_Now()
        return
    }
    fs.probe := 0
    if c != p.crc {
        FS_Log("probe: real wheel works, remembering " p.exe)
        AddRealWheelApp(p.exe)
    } else
        FS_Log("probe: nothing moved either way")
}

; CRC of a 160 x 300 px screen area centred on (x, y).
RegionCrc(x, y) {
    w := 160, h := 300
    sdc := DllCall("GetDC", "ptr", 0, "ptr")
    mdc := DllCall("CreateCompatibleDC", "ptr", sdc, "ptr")
    bmp := DllCall("CreateCompatibleBitmap", "ptr", sdc, "int", w, "int", h, "ptr")
    old := DllCall("SelectObject", "ptr", mdc, "ptr", bmp, "ptr")
    DllCall("BitBlt", "ptr", mdc, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", sdc, "int", x - w // 2, "int", y - h // 2, "uint", 0x00CC0020)   ; SRCCOPY
    DllCall("SelectObject", "ptr", mdc, "ptr", old, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", w, bi, 4), NumPut("int", -h, bi, 8)
    NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    px := Buffer(w * h * 4, 0)
    DllCall("GetDIBits", "ptr", mdc, "ptr", bmp, "uint", 0, "uint", h, "ptr", px, "ptr", bi, "uint", 0)
    crc := DllCall("ntdll\RtlComputeCrc32", "uint", 0, "ptr", px, "uint", px.Size, "uint")
    DllCall("DeleteObject", "ptr", bmp)
    DllCall("DeleteDC", "ptr", mdc)
    DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
    return crc
}

; The real-wheel list is written straight to the .ini (never by SaveConfig), so an open
; settings window can't overwrite what was learned while it was open.
AddRealWheelApp(exe) {
    if exe = "" || cfg.fs.realMap.Has(exe)
        return
    cfg.fs.real.Push(exe), cfg.fs.realMap[exe] := true
    SaveRealWheelApps()
}

RemoveRealWheelApp(exe) {
    for i, e in cfg.fs.real
        if e = exe {
            cfg.fs.real.RemoveAt(i)
            break
        }
    try cfg.fs.realMap.Delete(exe)
    SaveRealWheelApps()
}

SaveRealWheelApps() {
    list := ""
    for e in cfg.fs.real
        list .= (list = "" ? "" : ",") e
    IniWrite(list, INI, "FastScroll", "realWheelApps")
}

; Real wheel input, whole notches only (sub-notch steps are saved up until they make a notch).
; AutoHotkey's own Send is used on purpose: its input is ignored by this script's hotkeys (so the
; glide can't feed itself, the old freeze), and it lifts the held Shift around the wheel so the
; app scrolls vertically instead of sideways.
RealWheel(delta, upKey, downKey) {
    static acc := 0
    acc += delta
    n := Integer(acc / 120)
    if !n
        return
    acc -= n * 120
    SendLevel 0
    Send "{" (n > 0 ? upKey : downKey) " " Abs(n) "}"
}

; Horizontal scroll by one notch (Ctrl + Shift + wheel).
; - Classic controls with their own horizontal scroll bar (lists, text boxes, a parent panel):
;   3 "line left / right" steps (WM_HSCROLL). Many of them ignore sideways-wheel input.
; - Everything else: real sideways-wheel input (like a tilt wheel / touchpad), which works in
;   apps that ignore posted messages. Send (not {Blind}) lifts the held Ctrl and Shift around it,
;   so the app sees a plain sideways scroll, not a zoom.
HScroll(dir) {
    if fs.running
        FS_Stop()                                 ; Ctrl added during a fast scroll: stop the glide
    CoordMode "Mouse", "Screen"
    MouseGetPos(, , &win, &ctl, 2)
    remote := false
    try remote := REMOTE_APPS.Has(WinGetProcessName(win))
    h := remote ? 0 : (ctl ? ctl : win)            ; remote desktop: only real input reaches the other PC
    while h {
        if DllCall("GetWindowLong", "Ptr", h, "Int", -16, "Int") & 0x100000 {   ; WS_HSCROLL
            Loop 3
                PostMessage(0x114, dir > 0 ? 1 : 0, 0, h)    ; WM_HSCROLL: SB_LINERIGHT / SB_LINELEFT
            return
        }
        if h = win
            break
        h := DllCall("GetParent", "Ptr", h, "Ptr")
    }
    SendLevel 0
    Send "{" (dir > 0 ? "WheelRight" : "WheelLeft") "}"
}

FS_Now() {
    static freq := 0
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    t := 0
    DllCall("QueryPerformanceCounter", "Int64*", &t)
    return t / freq
}

FS_ShiftHeld() => GetKeyState("Shift", "P") || (FS_HOLDMS && (FS_Now() - fs.t0) * 1000 < FS_HOLDMS)

FS_UnderMouse() {
    MouseGetPos(, , &win, &ctl, 2)
    try return WinGetProcessName(win) " " (ctl ? WinGetClass(ctl) : WinGetClass(win))
    return "?"
}

FS_Log(msg) {
    if FS_DEBUG
        FS_LOGBUF.Push(Format("{:.4f}`t{}", FS_Now() - fs.t0, msg))
}

FS_Start(dir) {
    fs.t0 := FS_Now()
    FS_LOGBUF.Length := 0
    FS_Log("start dir=" dir " shiftP=" GetKeyState("Shift", "P") " under=" FS_UnderMouse())
    fs.gen += 1
    fs.v := dir * cfg.fs.boost
    fs.acc := 0
    fs.lastFwd := fs.t0
    fs.running := true
    FS_ProbeStart()
    Send "{Blind}{LShift up}{RShift up}"     ; app sees plain vertical wheel while gliding
    FS_Wheel(dir * 120)                       ; first notch lands immediately
    SetTimer FS_Loop, -1                      ; start the glide loop in its own thread
}

FS_Notch(dir) {
    now := FS_Now()
    if (fs.v > 0) != (dir > 0) {
        ; Free-spin / high-res wheels "bounce" backwards for a moment when they slow down.
        ; Only a reverse that comes clearly after the last forward movement stops the glide.
        FS_Log("reverse gap=" Round((now - fs.lastFwd) * 1000) "ms")
        if now - fs.lastFwd > 0.15
            FS_Stop()
        return
    }
    gap := now - fs.lastFwd
    fs.lastFwd := now
    if FS_ShiftHeld() {
        ; High-res wheels send many tiny events per notch: weight each by the time since the
        ; previous one, so speed follows how hard you flick, not how many events the mouse sends.
        w := Max(0.15, Min(1, gap / 0.03))
        fs.v += dir * cfg.fs.boost * w
        if Abs(fs.v) > cfg.fs.max
            fs.v := dir * cfg.fs.max
        FS_Log("boost w=" Round(w, 2) " v=" Round(fs.v, 1))
    } else
        FS_Wheel(dir * 120)
}

; Runs the glide at ~120 Hz. AHK's Sleep only manages ~15.6 ms steps (seen in the log),
; so each frame waits with 1 ms system sleeps until 8 ms have passed, and Sleep -1 lets
; the wheel/click hotkeys interrupt between frames.
; Each frame sends whatever has built up in small sub-notch amounts (12 = 1/10 notch), so
; apps with smooth/high-res scrolling (browsers, Office, WPF) glide instead of jumping by lines.
; Classic list/tree controls still move whole lines; that is how those controls scroll.
FS_Loop() {
    myGen := fs.gen
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    fs.last := FS_Now()
    while fs.running && fs.gen = myGen {
        while FS_Now() - fs.last < 0.008
            DllCall("Sleep", "UInt", 1)
        Sleep -1
        if !fs.running || fs.gen != myGen
            break
        if FS_Now() - fs.t0 > 8 {             ; safety: no glide lasts more than 8 s
            FS_Stop()
            break
        }
        now := FS_Now()
        dt := Min(now - fs.last, 0.1)
        fs.last := now
        keep := FS_ShiftHeld() ? cfg.fs.glideHeld : cfg.fs.glideRelease
        fs.v *= (keep / 100) ** dt
        if Abs(fs.v) < 1 {
            FS_Stop()
            break
        }
        fs.acc += fs.v * 120 * dt             ; 120 = one wheel notch
        if Abs(fs.acc) >= 12 {
            d := Integer(fs.acc / 12) * 12
            fs.acc -= d
            FS_Wheel(Max(-4800, Min(4800, d)))
            FS_Log("tick dt=" Round(dt * 1000, 1) "ms v=" Round(fs.v, 1) " send=" d)
        }
    }
    DllCall("winmm\timeEndPeriod", "UInt", 1)
}

FS_Stop(*) {
    if !fs.running
        return
    fs.v := 0, fs.acc := 0, fs.running := false
    ; Never press Shift for you: if you're still holding it, its own auto-repeat brings it
    ; back. If you're not, make sure it isn't left stuck down.
    if !GetKeyState("LShift", "P")
        Send "{Blind}{LShift up}"
    if !GetKeyState("RShift", "P")
        Send "{Blind}{RShift up}"
    FS_Log("stop")
    if FS_DEBUG {
        out := ""
        for line in FS_LOGBUF
            out .= line "`n"
        try FileDelete(DATA_DIR "\fastscroll-log.txt")
        FileAppend(out, DATA_DIR "\fastscroll-log.txt", "UTF-8")
    }
}

; =============================================================================
;  Config (INI)
; =============================================================================
Rd(sec, key, def) => IniRead(INI, sec, key, def)
NumOr(v, def) => IsNumber(v) ? Number(v) : def
Esc(s) => StrReplace(StrReplace(StrReplace(StrReplace(s, "\", "\\"), "`r`n", "`n"), "`r", "`n"), "`n", "\n")
Unesc(s) => StrReplace(StrReplace(StrReplace(s, "\\", Chr(1)), "\n", "`n"), Chr(1), "\")

LoadConfig() {
    c := {snippets: [], caps: {}, side: {}, fs: {}}

    n := Rd("Snippets", "Count", "")
    if IsInteger(n) {
        Loop Integer(n) {
            t := Unesc(Rd("Snippets", A_Index "_Trigger", ""))
            if t != ""
                c.snippets.Push({trigger: t, text: Unesc(Rd("Snippets", A_Index "_Text", ""))})
        }
    } else {
        ; First run: two examples to edit in Settings.
        c.snippets.Push({trigger: "@@", text: "your.email@mail.com"})
        c.snippets.Push({trigger: "!!", text: "010xxxxxxxxxx"})
    }

    c.theme := Rd("General", "Theme", "auto")        ; auto / light / dark
    c.glass := Rd("General", "Glass", 1) = 1           ; frosted glass background, light or dark (on unless turned off)
    if c.theme = "glass"                               ; a short-lived test build had Glass as a 4th theme
        c.theme := "dark"
    c.accent := StrUpper(Rd("General", "Accent", "0090FF"))   ; accent colour: RRGGBB, or "windows" = Windows' own
    if c.accent = "WINDOWS"
        c.accent := "windows"
    else if !RegExMatch(c.accent, "^[0-9A-F]{6}$")             ; (also the colour names of a 2.2.0 test build)
        c.accent := "0090FF"
    c.caps.enabled   := Rd("CapsLock", "Enabled", 1) = 1
    c.caps.shiftToggle := Rd("CapsLock", "ShiftToggle", 1) = 1
    c.caps.trigger   := "CapsLock"
    tr := Rd("CapsLock", "Trigger", "CapsLock")
    for t in TRIGGERS()
        if t[1] = tr
            c.caps.trigger := t[1]
    c.caps.wheelUp   := Rd("CapsLock", "wheelUp", "{Volume_Up}")
    c.caps.wheelDown := Rd("CapsLock", "wheelDown", "{Volume_Down}")
    c.caps.mButton   := Rd("CapsLock", "mButton", "{Media_Play_Pause}")
    c.caps.xButton2  := Rd("CapsLock", "xButton2", "{Media_Next}")
    c.caps.xButton1  := Rd("CapsLock", "xButton1", "{Media_Prev}")

    ; Side buttons: one row per app (back = undo, forward = redo, both = extra key).
    c.side.enabled := Rd("SideButtons", "Enabled", Rd("RevitButtons", "Enabled", 1)) = 1
    c.side.list := []
    n := Rd("SideButtons", "Count", "")
    if IsInteger(n) {
        Loop Integer(n) {
            a := Trim(Rd("SideButtons", A_Index "_App", ""))
            if a != ""
                c.side.list.Push({app: a, back: Rd("SideButtons", A_Index "_Back", "")
                    , fwd: Rd("SideButtons", A_Index "_Fwd", ""), both: Rd("SideButtons", A_Index "_Both", "")})
        }
    } else {
        for d in DefaultSideApps() {
            if d.app = "Revit.exe" {        ; keep keys set in the old Revit-only settings
                d.back := Rd("RevitButtons", "back", d.back)
                d.fwd  := Rd("RevitButtons", "fwd", d.fwd)
                d.both := Rd("RevitButtons", "both", d.both)
            }
            c.side.list.Push(d)
        }
    }
    c.side.apps := SideAppMap(c.side.list)

    c.fs.enabled      := Rd("FastScroll", "Enabled", 1) = 1
    fresh := Rd("General", "ConfigVersion", 1) < 3     ; older file -> take the new speed defaults
    c.fs.boost        := fresh ? 30  : NumOr(Rd("FastScroll", "boost", 30), 30)
    c.fs.max          := fresh ? 400 : NumOr(Rd("FastScroll", "max", 400), 400)
    c.fs.glideHeld    := fresh ? 60  : NumOr(Rd("FastScroll", "glideHeld", 60), 60)
    c.fs.glideRelease := fresh ? 3   : NumOr(Rd("FastScroll", "glideRelease", 3), 3)
    c.fs.hscroll      := Rd("FastScroll", "hscroll", 1) = 1
    ; Apps that are all canvas: fast scroll is off anywhere in them. (Replaces the old
    ; "exclude" list of apps where Shift + wheel scrolled sideways; Ctrl + Shift + wheel does that now.)
    defCanvas := "Photoshop.exe,Illustrator.exe,InDesign.exe,AfterFX.exe,Adobe Premiere Pro.exe,"
               . "blender.exe,3dsmax.exe,SketchUp.exe,Rhino.exe,Roamer.exe,Lumion.exe,Twinmotion.exe"
    c.fs.canvas := []
    c.fs.canvasMap := Map()
    c.fs.canvasMap.CaseSense := false
    for e in StrSplit(Rd("FastScroll", "canvasApps", defCanvas), ",") {
        e := Trim(e)
        if e != "" && !c.fs.canvasMap.Has(e) {
            c.fs.canvas.Push(e)
            c.fs.canvasMap[e] := true
        }
    }
    ; Apps that only scroll with real wheel input (learned automatically, see FS_Probe).
    c.fs.real := []
    c.fs.realMap := Map()
    c.fs.realMap.CaseSense := false
    for e in StrSplit(Rd("FastScroll", "realWheelApps", ""), ",") {
        e := Trim(e)
        if e != "" && !c.fs.realMap.Has(e) {
            c.fs.real.Push(e)
            c.fs.realMap[e] := true
        }
    }
    return c
}

; Apps where undo / redo on the side buttons is useful. Adobe apps redo with Ctrl+Shift+Z
; (Ctrl+Y does something else there).
DefaultSideApps() {
    list := []
    for row in [["Revit.exe", "^{z}", "^{y}", "{Enter}"], ["acad.exe", "^{z}", "^{y}", "{Enter}"]
              , ["acadlt.exe", "^{z}", "^{y}", "{Enter}"], ["Rhino.exe", "^{z}", "^{y}", "{Enter}"]
              , ["SketchUp.exe", "^{z}", "^{y}", ""], ["3dsmax.exe", "^{z}", "^{y}", ""]
              , ["Roamer.exe", "^{z}", "^{y}", ""], ["Revu.exe", "^{z}", "^{y}", ""]
              , ["EXCEL.EXE", "^{z}", "^{y}", ""], ["WINWORD.EXE", "^{z}", "^{y}", ""]
              , ["POWERPNT.EXE", "^{z}", "^{y}", ""], ["ONENOTE.EXE", "^{z}", "^{y}", ""]
              , ["Photoshop.exe", "^{z}", "^+{z}", ""], ["Illustrator.exe", "^{z}", "^+{z}", ""]
              , ["InDesign.exe", "^{z}", "^+{z}", ""], ["mspaint.exe", "^{z}", "^{y}", ""]]
        list.Push({app: row[1], back: row[2], fwd: row[3], both: row[4]})
    return list
}

SideAppMap(list) {
    m := Map()
    m.CaseSense := false
    for e in list
        if e.app != "explorer.exe"         ; never in Explorer: Ctrl+Z there can undo file moves / deletes
            m[e.app] := e
    return m
}

SaveConfig(c) {
    if !FileExist(INI)
        FileAppend("[General]`n", INI, "UTF-16")   ; UTF-16 so any language saves correctly

    IniWrite(3, INI, "General", "ConfigVersion")
    IniWrite(c.theme, INI, "General", "Theme")
    IniWrite(c.glass ? 1 : 0, INI, "General", "Glass")
    IniWrite(c.accent, INI, "General", "Accent")
    try IniDelete(INI, "Snippets")
    IniWrite(c.snippets.Length, INI, "Snippets", "Count")
    for i, s in c.snippets {
        IniWrite(Esc(s.trigger), INI, "Snippets", i "_Trigger")
        IniWrite(Esc(s.text), INI, "Snippets", i "_Text")
    }

    IniWrite(c.caps.enabled ? 1 : 0, INI, "CapsLock", "Enabled")
    IniWrite(c.caps.shiftToggle ? 1 : 0, INI, "CapsLock", "ShiftToggle")
    IniWrite(c.caps.trigger, INI, "CapsLock", "Trigger")
    for k in ["wheelUp", "wheelDown", "mButton", "xButton2", "xButton1"]
        IniWrite(c.caps.%k%, INI, "CapsLock", k)

    try IniDelete(INI, "RevitButtons")      ; replaced by [SideButtons]
    try IniDelete(INI, "RevitCommand")      ; old setting (the Revit pk command was removed)
    try IniDelete(INI, "SideButtons")
    IniWrite(c.side.enabled ? 1 : 0, INI, "SideButtons", "Enabled")
    IniWrite(c.side.list.Length, INI, "SideButtons", "Count")
    for i, e in c.side.list {
        IniWrite(e.app, INI, "SideButtons", i "_App")
        IniWrite(e.back, INI, "SideButtons", i "_Back")
        IniWrite(e.fwd, INI, "SideButtons", i "_Fwd")
        IniWrite(e.both, INI, "SideButtons", i "_Both")
    }

    IniWrite(c.fs.enabled ? 1 : 0, INI, "FastScroll", "Enabled")
    for k in ["boost", "max", "glideHeld", "glideRelease"]
        IniWrite(c.fs.%k%, INI, "FastScroll", k)
    IniWrite(c.fs.hscroll ? 1 : 0, INI, "FastScroll", "hscroll")
    list := ""
    for e in c.fs.canvas
        list .= (list = "" ? "" : ",") e
    IniWrite(list, INI, "FastScroll", "canvasApps")
    try IniDelete(INI, "FastScroll", "exclude")
}

; =============================================================================
;  Tray
; =============================================================================
SetupTray() {
    A_IconTip := APP_NAME
    m := A_TrayMenu
    m.Delete()
    m.Add("Settings...`tCtrl+Alt+H", ShowSettings)
    m.Add("Pause all shortcuts", TogglePause)
    m.Add("Check for updates", (*) => CheckForUpdates(true))
    m.Add("Report a problem...", (*) => ReportProblem())
    m.Add()
    m.Add("Restart app", AppReload)
    m.Add("Exit", (*) => ExitApp())
    m.Default := "Settings...`tCtrl+Alt+H"
    m.ClickCount := 2
    UpdateTrayIcon()
    OnMessage(0x1A, (*) => (SetTimer(UpdateTrayIcon, -500), SetTimer(ApplyAppMode, -500)))   ; WM_SETTINGCHANGE: Windows theme may have changed
}

; White icon on a dark taskbar, black icon on a light one.
UpdateTrayIcon() {
    light := 0
    try light := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme")
    ; Braces needed: a "try" without them would swallow the "else" (v2's try has its own else).
    if A_IsCompiled {
        try TraySetIcon(A_ScriptFullPath, light ? -301 : -300)
    } else {
        try TraySetIcon(A_ScriptDir "\icons\tray-" (light ? "black" : "white") ".ico")
    }
}

TogglePause(name, pos, menu) {
    Suspend -1
    menu.ToggleCheck(name)
    FS_Stop()
}

; =============================================================================
;  Settings window
; =============================================================================
ShowSettings(*) {
    global SettingsGui, PENDING, REOPEN, BTN, BTN_HOT, SLIDERS, SLIDER_OF, UPD_LABEL
    if SettingsGui {                                   ; already open: bring it back (not Show(): it would re-size it)
        if DllCall("IsIconic", "ptr", SettingsGui.Hwnd)
            DllCall("ShowWindow", "ptr", SettingsGui.Hwnd, "int", 9)    ; SW_RESTORE
        try WinActivate("ahk_id " SettingsGui.Hwnd)
        return
    }
    u := PENDING ? PENDING : cfg          ; unsaved choices survive a theme change (see ThemeChanged)
    rebuilt := PENDING ? true : false
    PENDING := 0
    ro := REOPEN
    REOPEN := 0
    BTN := Map(), BTN_HOT := 0, SLIDERS := Map(), SLIDER_OF := Map()

    snips := []
    for s in u.snippets
        snips.Push({trigger: s.trigger, text: s.text})
    excl := []
    for e in u.fs.canvas
        excl.Push(e)

    global ANCH := Map()
    g := Gui("+MinimizeBox +Resize", AppTitle())
    SettingsGui := g
    g.SetFont("s9", "Segoe UI")
    SetWindowIcons(g)

    ; ---- Tab bar ----------------------------------------------------------------
    ; Our own tabs (plain text + an accent bar) instead of a Windows tab control, because
    ; the Windows one can't be drawn dark. Each page's controls are shown / hidden by ShowPage.
    tabs := [], pages := [], known := Map(), curPage := 1
    g.SetFont("s10")
    for i, name in ["Shortcuts", "Text shortcuts", "Mouse && keys", "Fast scroll", "General"] {
        t := g.AddText("x" (10 + (i - 1) * 134) " y10 w130 h28 Center +0x200", name)   ; 0x200 = centred vertically
        t.role := "tab"
        t.OnEvent("Click", ShowPage.Bind(i))
        tabs.Push(t), pages.Push([])
    }
    g.SetFont("s9")
    bar := g.AddText("x10 y38 w130 h3"), bar.role := "bar"
    sep := Anchor(g.AddText("x10 y41 w830 h1"), "w"), sep.role := "line"
    for hwnd, ctrl in g
        known[hwnd] := true

    ; ---- Page 1: the illustrated guide (its own scrollable child window) --------
    guideWin := ShortcutGuide(g)
    guideSb := ScrollOverlay(g, "guide")                      ; our scroll bar, shown with page 1
    pages[1].Push(guideSb), known[guideSb.Hwnd] := true

    ; ---- Page 2: text shortcuts -------------------------------------------------
    SecHeader(g, "x20 y56 w810", "Type a short code, get the full text")
    LvHeader(g, 20, 86, 810, [["You type", 160], ["You get", 600]])
    lv := NewList(g, "x20 y112 w810 h388", ["You type", "You get"], "wh")
    tBtn1 := AddBtn(g, "x20 y510 w90", "Add...")
    tBtn2 := AddBtn(g, "x+8 w90", "Edit...")
    tBtn3 := AddBtn(g, "x+8 w90", "Delete")
    tBtn1.OnEvent("Click", (*) => AddSnip()), tBtn2.OnEvent("Click", (*) => EditSnip()), tBtn3.OnEvent("Click", (*) => DelSnip())
    Anchor(tBtn1, "y"), Anchor(tBtn2, "y"), Anchor(tBtn3, "y")
    lv.OnEvent("DoubleClick", (ctrl, row) => (row ? EditSnip() : 0))
    RefreshLV()
    EndPage(2)

    ; ---- Page 3: mouse & keys ---------------------------------------------------
    mk := PanelMark(g)
    SecHeader(g, "x20 y58 w110", "Caps Lock")
    ; Each section's switch sits beside its header; unticked, the section (its header too) is
    ; greyed out and doesn't respond (PanelState). PanelMark / PanelSince collect its controls;
    ; the switch itself stays as it is.
    shiftEn := AddCheck(g, 135, 59, u.caps.shiftToggle, "", 1, () => PanelState(pShift, shiftEn.Value))
    Muted(g.AddText("x20 y88 w300", "Shift + Caps Lock turns it on / off."))
    Muted(g.AddText("x20 y110 w300", "Caps Lock alone does nothing."))
    pShift := PanelSince(g, mk)

    mk := PanelMark(g)
    SecHeader(g, "x20 y170 w110", "Side scroll")              ; (its own switch; saved with fast scroll)
    fsH := AddCheck(g, 135, 171, u.fs.hscroll, "", 1, () => PanelState(pSideScroll, fsH.Value))
    Muted(g.AddText("x20 y196 w300", "Ctrl + Shift + wheel scrolls sideways."))
    pSideScroll := PanelSince(g, mk)

    ; Media Control on the right. Its boxes sit at the page's right edge and follow it when the
    ; window is made wider; a thin line joins each label to its box (its menus open below the boxes).
    mk := PanelMark(g)
    SecHeader(g, "x345 y58 w110", "Media Control")
    capsEn := AddCheck(g, 460, 59, u.caps.enabled, "", 1, () => PanelState(pMedia, capsEn.Value))
    holdLbl := g.AddText("x345 y88", "Hold")
    trigNames := []
    for t in TRIGGERS()
        trigNames.Push(t[2])
    trigSel := 1
    for i, t in TRIGGERS()
        if t[1] = u.caps.trigger
            trigSel := i
    trigDd := Anchor(DropBtn(g, "x460 y82 w370", trigNames, trigSel), "x")
    LeaderLine(g, holdLbl, 460)
    capsEd := Map()
    for i, row in [["wheelUp", "Wheel up"], ["wheelDown", "Wheel down"], ["mButton", "Middle click"]
                 , ["xButton2", "Forward button"], ["xButton1", "Back button"]] {
        y := 116 + (i - 1) * 32
        rowLbl := g.AddText("x345 y" (y + 4), row[2])
        kb := capsEd[row[1]] := KeyBox(g, "x460 y" y " w342", u.caps.%row[1]%, true)   ; × ends at 830
        Anchor(kb, "x"), Anchor(kb.clr, "x")
        LeaderLine(g, rowLbl, 460)
    }
    pMedia := PanelSince(g, mk)

    ; A line across the page; Side buttons below it: the mouse on the left, the apps on the right.
    sepMk := Anchor(g.AddText("x20 y280 w810 h1"), "w"), sepMk.role := "line"
    mk := PanelMark(g)
    SecHeader(g, "x20 y292 w110", "Side buttons")
    sideEn := AddCheck(g, 135, 293, u.side.enabled, "", 1, () => PanelState(pSide, sideEn.Value))
    Muted(g.AddText("x20 y318 w300", "Not in dialogs or File Explorer."))
    MouseArt(g, 20, 338)

    sides := []
    for e in u.side.list
        sides.Push({app: e.app, back: e.back, fwd: e.fwd, both: e.both})
    LvHeader(g, 345, 292, 485, [["App", 150], ["Back", 110], ["Forward", 120], ["Both", 100]])
    sideLv := NewList(g, "x345 y318 w485 h172", ["App", "Back", "Forward", "Both"], "wh")
    sideLv.off := false                                        ; true while Side buttons is switched off
    sBtn1 := AddBtn(g, "x345 y500 w90", "Add...")
    sBtn2 := AddBtn(g, "x+8 w90", "Edit...")
    sBtn3 := AddBtn(g, "x+8 w90", "Delete")
    sBtn1.OnEvent("Click", (*) => AddSide()), sBtn2.OnEvent("Click", (*) => EditSide()), sBtn3.OnEvent("Click", (*) => DelSide())
    Anchor(sBtn1, "y"), Anchor(sBtn2, "y"), Anchor(sBtn3, "y")
    sideLv.OnEvent("DoubleClick", (ctrl, row) => (row && !ctrl.off ? EditSide() : 0))
    RefreshSides()
    pSide := PanelSince(g, mk)
    EndPage(3)

    ; ---- Page 4: fast scroll ----------------------------------------------------
    mk := PanelMark(g)
    fsEn := AddCheck(g, 20, 58, u.fs.enabled, "Fast scroll  (Shift + wheel)", 360, () => PanelState(pFast, fsEn.Value))
    SecHeader(g, "x20 y102 w400", "Speed")
    fsBoost := AddSlideRow("Kick per flick",        136, u.fs.boost, 5, 100)
    fsMax   := AddSlideRow("Top speed",             168, u.fs.max, 50, 800)
    fsHeld  := AddSlideRow("Glide: Shift held",     200, u.fs.glideHeld, 0, 100)
    fsRel   := AddSlideRow("Glide: Shift released", 232, u.fs.glideRelease, 0, 100)
    fsReset := Anchor(AddBtn(g, "x740 y96 w90", "Reset"), "x")   ; back to the default speeds
    fsReset.OnEvent("Click", (*) => (SetSlide(fsBoost, 30), SetSlide(fsMax, 400), SetSlide(fsHeld, 60), SetSlide(fsRel, 3)))
    SecHeader(g, "x20 y288 w400", "Excluded apps")
    ; The list takes the extra width when the window is made wider; the buttons and notes keep
    ; their size and stay at the right edge.
    exLv := NewList(g, "x20 y318 w470 h210", ["App"], "wh")
    aBtn1 := Anchor(AddBtn(g, "x506 y318 w130", "Add app..."), "x")
    aBtn2 := Anchor(AddBtn(g, "x506 y354 w130", "Remove"), "x")
    aBtn1.OnEvent("Click", (*) => ChooseApp(g, AddExclude)), aBtn2.OnEvent("Click", (*) => DelExclude())
    Anchor(Muted(g.AddText("x506 y398 w300", "No fast scroll in these apps.")), "x")
    Anchor(Muted(g.AddText("x506 y420 w300", "Revit and CAD canvases are skipped automatically.")), "x")
    RefreshEx()
    pFast := PanelSince(g, mk)
    EndPage(4)

    ; ---- Page 5: general --------------------------------------------------------
    SecHeader(g, "x20 y58 w400", "Look")
    themeCards := []
    for i, tc in [["auto", "Auto"], ["light", "Light"], ["dark", "Dark"]]
        themeCards.Push(ThemeCard(g, 20 + (i - 1) * 108, 88, tc[1], tc[2], PickTheme))
    glassSw := ToggleSwitch(g, 20, 198, () => cfg.glass, () => GlassSupported()
        , "Frosted glass", "Frosted glass (needs newer Windows)", PickGlass)
    glassSw.lbl.Move(, , 200)                            ; room for the accent colour on the same line
    ; Accent colour, at the end of the Frosted glass line: a button with the colour and its name
    ; that opens the swatch picker (AccentPicker).
    Muted(g.AddText("x226 y200 w58 Right", "Accent"))
    AccentButton(g, 292, 194, 128, PickAccent)

    SecHeader(g, "x20 y232 w400", "Startup")
    startEn := AddCheck(g, 20, 262, InstalledHere() ? (u.HasOwnProp("start") ? u.start : StartupOn()) : false
        , "Start with Windows", 400, (*) => SetStartup(startEn.Value))   ; takes effect at once
    if !InstalledHere() {                                ; a portable copy can't start with Windows
        startEn.Enabled := false
        Muted(g.AddText("x42 y285 w380", "Install the app to use this."))
    }

    SecHeader(g, "x20 y310 w400", "Install")
    g.AddText("x20 y342 w400", InstalledHere() ? "✔  Installed" : (A_IsCompiled ? "Portable copy (not installed)" : "Running as a script"))
    instBtn := AddBtn(g, "x20 y368 w150", InstalledHere() ? "Uninstall..." : (FileExist(INSTALL_EXE) ? "Update..." : "Install..."))
    instBtn.OnEvent("Click", (*) => (InstalledHere() ? UninstallApp() : InstallFlow()))
    if !A_IsCompiled
        BtnDisable(instBtn)
    Muted(g.AddText("x182 y374 w250", InstalledHere() ? "Also in Windows Settings > Apps." : "Copies to AppData, starts with Windows."))

    SecHeader(g, "x20 y430 w400", "Backup")
    AddBtn(g, "x20 y460 w120", "Export...").OnEvent("Click", (*) => ExportSettings(g))
    AddBtn(g, "x+8 w120", "Import...").OnEvent("Click", (*) => ImportSettings(g))
    Muted(g.AddText("x272 y466 w170", "All your settings."))

    ; The right column (Updates ... Help) keeps its size and stays at the right edge when the
    ; window is made wider (all its controls are anchored "x" below).
    rightMk := PanelMark(g)
    SecHeader(g, "x460 y58 w370", "Updates")
    UPD_LABEL := g.AddText("x460 y92 w370", UpdateStatusText())
    autoUpd := AddCheck(g, 460, 120, IniRead(INI, "General", "AutoUpdate", 1) = 1, "Check for updates automatically", 340
        , (*) => IniWrite(autoUpd.Value ? 1 : 0, INI, "General", "AutoUpdate"))      ; takes effect at once
    updBtn := AddBtn(g, "x460 y152 w116", "Check now")
    updBtn.OnEvent("Click", (*) => CheckForUpdates(true))
    AddBtn(g, "x+8 w116", "Release notes").OnEvent("Click", (*) => ShowNotes(g))
    AddBtn(g, "x+8 w116", "GitHub repo").OnEvent("Click", (*) => Run(REPO_URL))

    SecHeader(g, "x460 y220 w370", "Notifications")
    trayNote := AddCheck(g, 460, 250, IniRead(INI, "General", "HideTrayNotice", 0) != 1
        , "Tell me when the app keeps running in the tray", 360
        , (*) => IniWrite(trayNote.Value ? 0 : 1, INI, "General", "HideTrayNotice"))   ; takes effect at once

    SecHeader(g, "x460 y310 w370", "Settings file")
    Muted(g.AddText("x460 y342 w370 h34", INI))
    AddBtn(g, "x460 y380 w140", "Open folder").OnEvent("Click", (*) => Run('"' DATA_DIR '"'))

    SecHeader(g, "x460 y430 w370", "Help")
    AddBtn(g, "x460 y460 w170", "Report a problem...").OnEvent("Click", (*) => ReportProblem(DropExclude))
    Muted(g.AddText("x642 y466 w190", "Fixes it or tells us."))
    for rcol in PanelSince(g, rightMk)
        Anchor(rcol, "x")
    EndPage(5)

    ; ---- Bottom buttons (all pages) ---------------------------------------------
    sep2 := Anchor(g.AddText("x10 y550 w830 h1"), "wy"), sep2.role := "line"
    applyBtn := Anchor(AddBtn(g, "x636 y562 w100", "Apply", true), "xy")
    applyBtn.OnEvent("Click", ApplyClick)
    closeBtn := Anchor(AddBtn(g, "x+8 w100", "Close"), "xy")
    closeBtn.danger := true                        ; red, both as Close and as Cancel
    BtnRender(closeBtn, false)
    closeBtn.OnEvent("Click", CloseGui)
    g.OnEvent("Close", CloseGui)
    g.OnEvent("Escape", CloseGui)
    TitleBar(g, AppTitle(), ["min", "max", "close"], 850)    ; 850 = the width the page layout is made for
    ApplyTheme(g)
    if !InstalledHere()
        startEn.lbl.SetFont("c" ThemeColors().muted)          ; greyed out
    Panels()
    ShowPage(ro ? ro.page : 1)
    ShowTitled(g, ro ? "x" ro.x " y" ro.y : "", ro ? ro.w : 850, ro ? ro.h : 600 + TB_H)
    sc := A_ScreenDPI / 96
    g.Opt("+MinSize" Round(850 * sc) "x" Round((600 + TB_H) * sc))
    g.OnEvent("Size", GuiSize)
    g.GetClientPos(, , &cw, &ch)
    GuiSize(g, 0, cw, ch)

    ; Apply is greyed out and the button says Close until something is changed;
    ; then Apply lights up and Close becomes Cancel (closes without saving).
    global BASE_SIG
    if !rebuilt
        BASE_SIG := ConfigSig(BuildConfig())
    dirty := -1
    SetTimer(DirtyTick, 250)
    DirtyTick()

    ; ---- helpers -----------------------------------------------------------
    ; Window resized: stretch / move the anchored controls, the guide and the list columns.
    GuiSize(gg, minMax, w, h) {
        if minMax = -1
            return
        k := A_ScreenDPI / 96
        dw := Round(w / k) - 850, dh := Round(h / k) - 600 - TB_H     ; (TB_H: our title bar)
        SendMessage(0x0B, 0, 0, gg)                     ; WM_SETREDRAW off: move everything, then paint once (no flashing)
        for hw, a in ANCH {
            if !DllCall("IsWindow", "ptr", hw)
                continue
            DllCall("SetWindowPos", "ptr", hw, "ptr", 0
                , "int", Round((a.x + (InStr(a.f, "x") ? dw : 0)) * k), "int", Round((a.y + (InStr(a.f, "y") ? dh : 0)) * k)
                , "int", InStr(a.f, "g") && dw <= 0 ? 0 : Round((a.w + (InStr(a.f, "w") ? dw : 0)) * k)   ; g: only once wider
                , "int", Round((a.h + (InStr(a.f, "h") ? dh : 0)) * k)
                , "uint", 0x14)                         ; NOZORDER | NOACTIVATE
        }
        PlaceGuide(guideWin, 10, 48 + TB_H, 830 + dw, 498 + dh)
        ScrollPlace(guideSb)
        if TITLED.Has(gg.Hwnd)                          ; maximise / restore picture
            for tbtn in TITLED[gg.Hwnd].btns
                TitleBtnDraw(tbtn)
        if curPage != 1
            DllCall("ShowWindow", "ptr", guideWin.Hwnd, "int", 0)
        GuideScroll(0)
        FitList(lv, [160])
        FitList(sideLv, [150, 110, 120])
        FitList(exLv, [])
        SendMessage(0x0B, 1, 0, gg)                     ; WM_SETREDRAW on
        DllCall("RedrawWindow", "ptr", gg.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x185)   ; repaint everything
    }

    ; Give the last column all the width that is left.
    FitList(list, fixed) {
        k := A_ScreenDPI / 96
        list.GetPos(, , &lw)
        used := 0
        for i, f in fixed {
            list.ModifyCol(i, Round(f * k))
            used += Round(f * k)
        }
        last := Max(60, lw - used - Round(24 * k))
        list.ModifyCol(fixed.Length + 1, last)
        ; Round corners, like the buttons (a window region: Windows owns it once set).
        wr := Buffer(16)
        DllCall("GetWindowRect", "ptr", list.Hwnd, "ptr", wr)
        rw := NumGet(wr, 8, "int") - NumGet(wr, 0, "int"), rh := NumGet(wr, 12, "int") - NumGet(wr, 4, "int")
        d := Round(14 * k)
        DllCall("SetWindowRgn", "ptr", list.Hwnd, "ptr", DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", rw + 1, "int", rh + 1, "int", d, "int", d, "ptr"), "int", 1)
        if list.HasOwnProp("sb")
            ScrollPlace(list.sb)                               ; (narrows that region by the scroll bar)
        ; Column separators: a 1 px line at each column edge, the list's full height, on top.
        if !list.HasOwnProp("seps") || !list.seps.Length
            return
        rc := Buffer(16)
        DllCall("GetWindowRect", "ptr", list.Hwnd, "ptr", rc)
        DllCall("MapWindowPoints", "ptr", 0, "ptr", g.Hwnd, "ptr", rc, "uint", 2)
        lx := NumGet(rc, 0, "int"), ly := NumGet(rc, 4, "int"), lh := NumGet(rc, 12, "int") - ly
        x := 0
        dark := ThemeColors().dark            ; the dark list theme draws its own column lines: ours get 0 width
        for i, sp in list.seps {
            endLine := i > fixed.Length                ; the line after the last column
            x += endLine ? last : Round(fixed[i] * k)
            DllCall("SetWindowPos", "ptr", sp.Hwnd, "ptr", 0, "int", lx + x - Round((endLine ? 1 : 4) * k), "int", ly
                , "int", dark ? 0 : Max(1, Round(k)), "int", lh, "uint", 0x10)     ; HWND_TOP, NOACTIVATE
        }
    }

    ; Every control created since the last call belongs to page n.
    EndPage(n) {
        for hwnd, ctrl in g
            if !known.Has(hwnd) {
                pages[n].Push(ctrl)
                known[hwnd] := true
            }
    }

    ShowPage(n, *) {
        curPage := n
        for i, list in pages
            for ctrl in list
                if i != n
                    ctrl.Visible := false
        for ctrl in pages[n] {                          ; light glass: a layered control shown for the first
            ctrl.Visible := true                        ; time is black until it paints, so paint it right away
            if LAYERED.Has(ctrl.Hwnd)
                DllCall("RedrawWindow", "ptr", ctrl.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x0585)
        }
        if GUIDE.page                                   ; the guide is placed once the window is shown
            DllCall("ShowWindow", "ptr", guideWin.Hwnd, "int", n = 1 ? 8 : 0)
        t := ThemeColors()
        for i, tc in tabs
            tc.SetFont(i = n ? "bold c" t.fg : "norm c" t.muted)
        bar.Move(10 + (n - 1) * 134)
        if t.HasOwnProp("key")                          ; light glass: controls just shown paint again
            SetTimer(RepaintLayered.Bind(g.Hwnd), -30)
    }

    ; A slider with its number: label, bar, value. The bar fills the row; the number sits at the
    ; right edge, and both follow the window when it is made wider.
    AddSlideRow(label, y, value, lo, hi) {
        g.AddText("x20 y" (y + 4) " w200", label)
        sl := Anchor(g.AddSlider("x225 y" y " w535 h28 Range" lo "-" hi " ToolTip NoTicks", Min(hi, Max(lo, Round(value)))), "w")
        vt := PillBox(g, 770, y + 2, 60, 24, sl.Value)            ; type a value
        Anchor(vt.pill, "x"), Anchor(vt, "x")
        sl.OnEvent("Change", (c, *) => (vt.Text != c.Value ? vt.Text := c.Value : 0))
        vt.OnEvent("Change", (e, *) => SlideTyped(sl, e, lo, hi, false))
        vt.OnEvent("LoseFocus", (e, *) => SlideTyped(sl, e, lo, hi, true))
        SLIDERS[sl.Hwnd] := {sl: sl, vt: vt, lo: lo, hi: hi}
        SLIDER_OF[vt.Hwnd] := sl.Hwnd, SLIDER_OF[vt.pill.Hwnd] := sl.Hwnd   ; the wheel over the box moves it too
        sl.OnNotify(-12, SliderThumbDraw)              ; NM_CUSTOMDRAW: our own pill-shaped thumb
        return sl
    }

    ; The theme is applied the moment it is picked: save it, then rebuild this window in the
    ; new colours with everything the user has typed so far kept.
    DirtyTick() {
        if !DllCall("IsWindow", "ptr", g.Hwnd) {
            SetTimer(DirtyTick, 0)
            return
        }
        d := ConfigSig(BuildConfig()) != BASE_SIG
        if d = dirty
            return
        dirty := d
        applyBtn.Enabled := d, applyBtn.dis := !d
        BtnRender(applyBtn, false)
        closeBtn.Text := d ? "Cancel" : "Close"
    }

    ; Where the window is, to rebuild it in the same place.
    WinState() {
        WinGetPos(&wx, &wy, , , g.Hwnd)
        g.GetClientPos(, , &cw2, &ch2)
        k2 := A_ScreenDPI / 96
        return {page: curPage, x: wx, y: wy, w: Round(cw2 / k2), h: Round(ch2 / k2)}
    }

    ; A theme card was clicked: switch at once, recolouring this window in place.
    PickTheme(key) {
        if cfg.theme = key
            return
        cfg.theme := key
        IniWrite(key, INI, "General", "Theme")
        FadeRetheme()
    }

    ; An accent colour was picked: same in-place recolour as a theme change.
    PickAccent(v) {
        if cfg.accent = v
            return
        cfg.accent := v
        IniWrite(v, INI, "General", "Accent")
        FadeRetheme()
    }

    ; The frosted-glass switch was flipped: same in-place recolour as a theme change.
    PickGlass(on) {
        cfg.glass := on
        IniWrite(on ? 1 : 0, INI, "General", "Glass")
        FadeRetheme()
    }

    FadeRetheme() {
        covers := [FadeCover(g)]                      ; the old look stays on top while we recolour
        for hd, dlg in APPDLGS
            covers.Push(FadeCover(dlg))
        ApplyAppMode()
        Retheme()
        FadeAway(covers)
    }

    ; Each section greyed out or not, by its switch.
    Panels() {
        PanelState(pShift, shiftEn.Value), PanelState(pSideScroll, fsH.Value), PanelState(pMedia, capsEn.Value)
        PanelState(pSide, sideEn.Value), PanelState(pFast, fsEn.Value)
    }

    Retheme() {
        t := ThemeColors()
        ApplyTheme(g)
        SetWindowIcons(g)
        for hd, dlg in APPDLGS {                          ; open messages follow the theme too
            try {
                ApplyTheme(dlg)
                for hc, c in dlg
                    if c.HasOwnProp("drawFn") && !BTN.Has(hc)
                        c.drawFn.Call(c, false)
                DllCall("SetWindowPos", "ptr", hd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37)
                DllCall("RedrawWindow", "ptr", hd, "ptr", 0, "ptr", 0, "uint", 0x0185)
            }
        }
        for hw, b in BTN
            try BtnRender(b, false)
        for hw, ctrl in g
            if ctrl.HasOwnProp("drawFn") && !BTN.Has(hw)
                try ctrl.drawFn.Call(ctrl, false)
        for hs in SLIDERS
            RefreshSlider(hs)
        ApplyTheme(guideWin)
        DllCall("uxtheme\SetWindowTheme", "ptr", guideWin.Hwnd, t.dark ? "str" : "ptr", t.dark ? "DarkMode_Explorer" : 0, "ptr", 0)
        if !InstalledHere()
            startEn.lbl.SetFont("c" t.muted)
        Panels()                                          ; greyed-out sections stay greyed out
        ShowPage(curPage)                                 ; tab colours
        DllCall("SetWindowPos", "ptr", g.Hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37)  ; repaint the title bar
        g.GetClientPos(, , &cw4, &ch4)
        GuiSize(g, 0, cw4, ch4)                           ; repaints everything
        ; Finish all painting now (under the fade cover), so the fade never shows half-drawn frames.
        for wh in [g.Hwnd, guideWin.Hwnd]
            DllCall("RedrawWindow", "ptr", wh, "ptr", 0, "ptr", 0, "uint", 0x0185)   ; INVALIDATE|ERASE|ALLCHILDREN|UPDATENOW
    }

    RefreshSides() {
        sideLv.Delete()
        for e in sides
            sideLv.Add(, e.app, PrettyKeys(e.back), PrettyKeys(e.fwd), PrettyKeys(e.both))
    }

    AddSide() {
        r := SideAppDialog(g)
        if !r
            return
        for i, e in sides
            if e.app = r.app {
                sides[i] := r
                RefreshSides()
                return
            }
        sides.Push(r)
        RefreshSides()
    }

    EditSide() {
        row := sideLv.GetNext()
        if !row
            return
        r := SideAppDialog(g, sides[row])
        if !r
            return
        sides[row] := r
        RefreshSides()
        sideLv.Modify(row, "Select Focus")
    }

    DelSide() {
        row := sideLv.GetNext()
        if !row
            return
        sides.RemoveAt(row)
        RefreshSides()
    }

    RefreshLV() {
        lv.Delete()
        for s in snips
            lv.Add(, s.trigger, StrReplace(s.text, "`n", "  |  "))
    }

    FindSnip(t, skip := 0) {
        for i, s in snips
            if i != skip && s.trigger = t
                return i
        return 0
    }

    AddSnip() {
        r := SnippetDialog(g)
        if !r
            return
        if FindSnip(r.trigger) {
            MsgBox("The trigger '" r.trigger "' already exists.", "Text shortcut", "Icon! Owner" g.Hwnd)
            return
        }
        snips.Push(r)
        RefreshLV()
    }

    EditSnip() {
        row := lv.GetNext()
        if !row
            return
        r := SnippetDialog(g, snips[row].trigger, snips[row].text)
        if !r
            return
        if FindSnip(r.trigger, row) {
            MsgBox("The trigger '" r.trigger "' already exists.", "Text shortcut", "Icon! Owner" g.Hwnd)
            return
        }
        snips[row] := r
        RefreshLV()
        lv.Modify(row, "Select Focus")
    }

    DelSnip() {
        row := lv.GetNext()
        if !row
            return
        snips.RemoveAt(row)
        RefreshLV()
    }

    RefreshEx() {
        exLv.Delete()
        for e in excl
            exLv.Add(, e)
    }

    AddExclude(exe) {
        for e in excl
            if e = exe
                return
        excl.Push(exe)
        RefreshEx()
    }

    DropExclude(exe) {                     ; the report flow removed exe from the canvas list
        for i, e in excl
            if e = exe {
                excl.RemoveAt(i)
                break
            }
        RefreshEx()
    }

    DelExclude() {
        row := exLv.GetNext()
        if !row
            return
        excl.RemoveAt(row)
        RefreshEx()
    }

    ; Everything currently shown in the window, as a settings object (nothing is saved here).
    BuildConfig() {
        c := {snippets: snips, caps: {}, side: {}, fs: {}}
        c.theme := cfg.theme
        c.glass := cfg.glass
        c.accent := cfg.accent
        c.start := startEn.Value
        c.caps.enabled := capsEn.Value
        c.caps.shiftToggle := shiftEn.Value
        c.caps.trigger := TRIGGERS()[Max(1, trigDd.sel)][1]
        for k, b in capsEd
            c.caps.%k% := KeyBoxValue(b)
        c.side.enabled := sideEn.Value
        c.side.list := sides
        c.fs.enabled      := fsEn.Value
        c.fs.boost        := Max(1, NumOr(fsBoost.Value, 30))
        c.fs.max          := Max(1, NumOr(fsMax.Value, 400))
        c.fs.glideHeld    := Min(100, Max(0, NumOr(fsHeld.Value, 60)))
        c.fs.glideRelease := Min(100, Max(0, NumOr(fsRel.Value, 3)))
        c.fs.hscroll      := fsH.Value
        c.fs.canvas := excl
        return c
    }

    ; Save and switch the new settings on right away; the window stays open.
    ApplyClick(*) {
        global cfg, BASE_SIG
        if dirty != 1
            return
        SaveConfig(BuildConfig())
        old := cfg
        cfg := LoadConfig()
        ReapplySettings(old)
        BASE_SIG := ConfigSig(BuildConfig())
        ; The Shortcuts page shows the new settings.
        guideWin.Destroy()
        guideWin := ShortcutGuide(g)
        g.GetClientPos(, , &cw3, &ch3)
        GuiSize(g, 0, cw3, ch3)
        DirtyTick()
    }

    CloseGui(*) {
        global SettingsGui
        SetTimer(DirtyTick, 0)
        FS_Stop()                                  ; no glide may outlive the window it scrolls
        SetTimer(SliderGlideTick, 0), SLIDERS.Clear(), SLIDER_OF.Clear()
        SettingsGui := 0
        GUIDE.hwnd := 0
        g.Destroy()
        ShowTrayNotice()
    }
}

; Everything Apply saves, as one string (theme and Start with Windows apply at once, so they
; are left out). Two equal strings = nothing changed.
ConfigSig(c) {
    s := c.caps.enabled "|" c.caps.shiftToggle "|" c.caps.trigger
    for k in ["wheelUp", "wheelDown", "mButton", "xButton2", "xButton1"]
        s .= "|" c.caps.%k%
    for x in c.snippets
        s .= "`nS" x.trigger "`t" x.text
    s .= "`nside" c.side.enabled
    for e in c.side.list
        s .= "`n" e.app "`t" e.back "`t" e.fwd "`t" e.both
    s .= "`nfs" c.fs.enabled "|" c.fs.hscroll "|" Round(c.fs.boost) "|" Round(c.fs.max) "|" Round(c.fs.glideHeld) "|" Round(c.fs.glideRelease)
    for e in c.fs.canvas
        s .= "|" e
    return s
}

; The Shortcuts page: a plain guide for everyday users, two columns of "icon  keys  what it
; does" lines. Only features that are switched on are shown. It is built in a child window
; with its own scrollbar, so it scrolls when there are more lines than fit.
ShortcutGuide(g) {
    sg := Gui("-Caption +Parent" g.Hwnd " +0x200000")   ; 0x200000 = WS_VSCROLL
    sg.MarginX := 0, sg.MarginY := 0
    col := [{x: 15, y: 12}, {x: 415, y: 12}]
    c := col[1]
    if cfg.side.enabled {
        Header(c, "Mouse side buttons")
        Tip(c, "🖱️", "Back button", "Undo")
        Tip(c, "🖱️", "Forward button", "Redo")
        Tip(c, "🖱️", "Both buttons", "Enter")
    }
    Header(c, "Folders")
    Tip(c, "📂", "Shift + Back button", "Up one folder")
    if cfg.fs.enabled || cfg.fs.hscroll
        Header(c, "Scrolling")
    if cfg.fs.enabled
        Tip(c, "⚡", "Shift + wheel", "Fast scroll")
    if cfg.fs.hscroll
        Tip(c, "↔️", "Ctrl + Shift + wheel", "Scroll sideways")
    Header(c, "General")
    if cfg.caps.shiftToggle
        Tip(c, "🔠", "Shift + Caps Lock", "Caps Lock on / off")
    Tip(c, "⚙️", "Ctrl + Alt + H", "Open settings")

    c := col[2]
    rightMk := PanelMark(sg)                           ; the right column follows the right edge (PlaceGuide)
    if cfg.caps.enabled {
        Header(c, "Media Control")
        tn := TriggerName(cfg.caps.trigger)
        Tip(c, "🔊", tn " + wheel", PrettyKeys(cfg.caps.wheelUp) " / " PrettyKeys(cfg.caps.wheelDown))
        Tip(c, "⏯️", tn " + middle click", PrettyKeys(cfg.caps.mButton))
        Tip(c, "⏭️", tn " + side buttons", PrettyKeys(cfg.caps.xButton2) " / " PrettyKeys(cfg.caps.xButton1))
    }
    Header(c, "Text shortcuts")
    for snip in cfg.snippets    ; one line each: "@@   your.email@mail.com"
        Tip(c, "⌨️", snip.trigger, StrReplace(StrReplace(snip.text, "`r"), "`n", " "))
    GUIDE.right := []                                  ; [hwnd, x in pixels at the original width]
    for gctl in PanelSince(sg, rightMk) {
        gctl.GetPos(&gx)
        GUIDE.right.Push([gctl.Hwnd, gx])
    }

    ; Content height in screen pixels (controls are placed in 96-dpi units and scaled).
    GUIDE.total := Round((Max(col[1].y, col[2].y) + 4) * A_ScreenDPI / 96)
    GUIDE.pos := 0, GUIDE.page := 0
    GUIDE.hwnd := sg.Hwnd
    ApplyTheme(sg)
    if ThemeColors().dark
        DllCall("uxtheme\SetWindowTheme", "ptr", sg.Hwnd, "str", "DarkMode_Explorer", "ptr", 0)  ; dark scrollbar
    return sg

    Header(c, title) {
        sg.SetFont("s10 bold", "Segoe UI")
        sg.AddText("x" c.x " y" c.y " w380 BackgroundTrans", title)
        sg.SetFont("s9 norm", "Segoe UI")
        c.y += 26
    }

    ; One row: icon, keys, what it does. Each piece is placed so the middle of what is actually
    ; drawn (measured with InkMid, not the font's line box) sits on the row's centre line.
    ; Never wraps; text that does not fit ends with "..." (0x4000); & is shown as is (0x80).
    Tip(c, icon, keys, what) {
        k := 96 / A_ScreenDPI
        mid := c.y + 14
        sg.SetFont("s14", "Segoe UI Emoji")
        sg.AddText("x" (c.x + 2) " y" Round(mid - InkMid("Segoe UI Emoji", 14, false, icon) * k) " w32 h40 BackgroundTrans Center", icon)
        sg.SetFont("s9 bold", "Segoe UI")
        sg.AddText("x" (c.x + 40) " y" Round(mid - InkMid("Segoe UI", 9, true, "H") * k) " w170 h22 BackgroundTrans +0x4000 +0x80", keys)
        sg.SetFont("s9 norm", "Segoe UI")
        sg.AddText("x" (c.x + 214) " y" Round(mid - InkMid("Segoe UI", 9, false, "H") * k) " w170 h22 BackgroundTrans +0x4000 +0x80", what)
        c.y += 30
    }
}

; How far down (in pixels, from the top of a text control) the middle of the drawn glyphs is.
; "H" gives the middle of capital letters for normal text; an emoji is measured as itself.
; Draws the sample once in black on white in memory and finds the first and last inked rows.
InkMid(font, size, bold, sample) {
    static cache := Map()
    key := font "|" size "|" bold "|" sample
    if cache.Has(key)
        return cache[key]
    W := 80, H := 120
    hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", W, bi, 4), NumPut("int", -H, bi, 8)
    NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    DllCall("PatBlt", "ptr", hdc, "int", 0, "int", 0, "int", W, "int", H, "uint", 0x00FF0062)   ; WHITENESS
    hf := DllCall("CreateFont", "int", -Round(size * A_ScreenDPI / 72), "int", 0, "int", 0, "int", 0
        , "int", bold ? 700 : 400, "uint", 0, "uint", 0, "uint", 0, "uint", 1, "uint", 0, "uint", 0
        , "uint", 3, "uint", 0, "str", font, "ptr")              ; 3 = no anti-aliasing: clean edges
    ofn := DllCall("SelectObject", "ptr", hdc, "ptr", hf, "ptr")
    DllCall("SetBkMode", "ptr", hdc, "int", 1)
    DllCall("SetTextColor", "ptr", hdc, "uint", 0)
    DllCall("TextOut", "ptr", hdc, "int", 4, "int", 0, "str", sample, "int", StrLen(sample))
    DllCall("GdiFlush")
    top := -1, bot := -1
    Loop H {
        y := A_Index - 1, row := bits + y * W * 4
        Loop W
            if (NumGet(row, (A_Index - 1) * 4, "uint") & 0xFFFFFF) != 0xFFFFFF {
                if top < 0
                    top := y
                bot := y
                break
            }
    }
    DllCall("SelectObject", "ptr", hdc, "ptr", ofn), DllCall("DeleteObject", "ptr", hf)
    DllCall("SelectObject", "ptr", hdc, "ptr", obm), DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdc)
    m := top < 0 ? size * A_ScreenDPI / 72 * 0.7 : (top + bot + 1) / 2
    cache[key] := m
    return m
}

; Put the guide window at x, y, w, h (96-dpi units, inside the settings window) and set up its scrollbar.
PlaceGuide(sg, x, y, w, h) {
    s := A_ScreenDPI / 96
    DllCall("SetWindowPos", "ptr", sg.Hwnd, "ptr", 0, "int", Round(x * s), "int", Round(y * s)
        , "int", Round(w * s), "int", Round(h * s), "uint", 0x10)   ; on top, NOACTIVATE
    DllCall("ShowWindow", "ptr", sg.Hwnd, "int", 8)    ; SW_SHOWNA
    GUIDE.page := Round(h * s)
    ; The right column moves right by however much wider than 830 the guide is (kept at its
    ; scrolled height).
    if GUIDE.HasOwnProp("right") {
        dx := Round(Max(0, w - 830) * s)
        rc := Buffer(16)
        for r in GUIDE.right {
            DllCall("GetWindowRect", "ptr", r[1], "ptr", rc)
            DllCall("MapWindowPoints", "ptr", 0, "ptr", sg.Hwnd, "ptr", rc, "uint", 2)
            DllCall("SetWindowPos", "ptr", r[1], "ptr", 0, "int", r[2] + dx, "int", NumGet(rc, 4, "int")
                , "int", 0, "int", 0, "uint", 0x15)    ; NOSIZE | NOZORDER | NOACTIVATE
        }
    }
    GuideScrollBar()
    static hooked := false
    if !hooked {
        OnMessage(0x115, GuideMsg)                     ; WM_VSCROLL
        OnMessage(0x20A, GuideMsg)                     ; WM_MOUSEWHEEL
        hooked := true
    }
}

; Mouse wheel over a slider: wheel up = more (Windows does the opposite by default).
SliderWheel(wParam, lParam, msg, hwnd) {
    if !OverSlider()
        return
    delta := (wParam >> 16) & 0xFFFF
    delta := delta >= 0x8000 ? delta - 0x10000 : delta
    SliderStep(delta > 0 ? 1 : -1)
    return 0
}

; The slider a control belongs to (the slider itself, its number box or the box's pill), or 0.
SliderAt(h) {
    s := !h ? 0 : SLIDERS.Has(h) ? h : SLIDER_OF.Has(h) ? SLIDER_OF[h] : 0
    return s && DllCall("IsWindowEnabled", "ptr", s) ? s : 0      ; a greyed-out slider doesn't move
}

; The mouse is over one of the settings window's sliders (or its number box).
OverSlider() {
    if !SLIDERS.Count
        return false
    try {
        MouseGetPos(, , , &h, 2)
        h := SliderAt(h)
        return h && DllCall("IsWindowVisible", "ptr", h)
    }
    return false
}

; Fast scroll for the settings sliders: each Shift + wheel notch pushes the slider, it keeps
; gliding and slows down (faster when Shift is let go), then lands on a multiple of 5.
SliderGlide(dir) {
    MouseGetPos(, , , &h, 2)
    if !(h := SliderAt(h))
        return
    e := SLIDERS[h]
    if SLGLIDE.h != h || SLGLIDE.v * dir < 0                 ; new slider or reversed: start fresh
        SLGLIDE.h := h, SLGLIDE.v := 0.0, SLGLIDE.pos := e.sl.Value
    SLGLIDE.v += dir * (e.hi - e.lo) / 40               ; one notch glides about a quarter of the range
    SetTimer(SliderGlideTick, 16)
}

SliderGlideTick() {
    if !SLGLIDE.h || !SLIDERS.Has(SLGLIDE.h) || !DllCall("IsWindow", "ptr", SLGLIDE.h) {
        SetTimer(SliderGlideTick, 0)
        SLGLIDE.h := 0
        return
    }
    e := SLIDERS[SLGLIDE.h]
    SLGLIDE.pos := Min(e.hi, Max(e.lo, SLGLIDE.pos + SLGLIDE.v))
    e.sl.Value := Round(SLGLIDE.pos)
    e.vt.Text := Round(SLGLIDE.pos)
    SLGLIDE.v *= GetKeyState("Shift", "P") ? 0.9 : 0.75
    if Abs(SLGLIDE.v) < 0.3 || SLGLIDE.pos <= e.lo || SLGLIDE.pos >= e.hi {
        SetTimer(SliderGlideTick, 0)
        v := Min(e.hi, Max(e.lo, Round(SLGLIDE.pos / 5) * 5))
        e.sl.Value := v
        e.vt.Text := v
        SLGLIDE.h := 0
    }
}

; The slider thumb is drawn by us as a smooth vertical pill: accent colour, and under the
; mouse (or while dragged) black in the light theme, white in the dark one (Windows' own
; hover thumb is black, invisible on a dark window).
; A slider keeps its old background after a theme change (it caches the parent's brush and only
; reloads it when resized), so nudge its size and redraw it.
RefreshSlider(h) {
    try {
        ctrl := GuiCtrlFromHwnd(h)
        ctrl.GetPos(, , &w)
        ctrl.Move(, , w + 1), ctrl.Move(, , w)
        SendMessage(0x408, 1, SendMessage(0x402, 0, 0, h), h)       ; TBM_SETRANGEMAX (same max), redraw
        DllCall("RedrawWindow", "ptr", h, "ptr", 0, "ptr", 0, "uint", 0x0505)  ; INVALIDATE | ERASE | UPDATENOW | FRAME
    }
}

; Theme switch cross-fade: a screenshot of the window covers it while it is recoloured
; underneath, then fades away. Click-through, so it never gets in the way.
FadeCover(win) {
    try {
        if WinGetMinMax(win.Hwnd) = -1 || !DllCall("IsWindowVisible", "ptr", win.Hwnd)
            return 0
        WinGetPos(&x, &y, &w, &h, win.Hwnd)
        ; WinGetPos includes the invisible resize border (and the shadow under it) on Windows 10/11.
        ; Copy only the visible frame, or that strip shows up as a grey box while fading.
        rc := Buffer(16, 0)
        if !DllCall("dwmapi\DwmGetWindowAttribute", "ptr", win.Hwnd, "uint", 9, "ptr", rc, "uint", 16) {   ; DWMWA_EXTENDED_FRAME_BOUNDS
            vx := NumGet(rc, 0, "int"), vy := NumGet(rc, 4, "int")
            vw := NumGet(rc, 8, "int") - vx, vh := NumGet(rc, 12, "int") - vy
            if vx >= x && vy >= y && vw > 0 && vh > 0 && vx + vw <= x + w && vy + vh <= y + h
                x := vx, y := vy, w := vw, h := vh
        }
        sdc := DllCall("GetDC", "ptr", 0, "ptr")
        mdc := DllCall("CreateCompatibleDC", "ptr", sdc, "ptr")
        bmp := DllCall("CreateCompatibleBitmap", "ptr", sdc, "int", w, "int", h, "ptr")
        old := DllCall("SelectObject", "ptr", mdc, "ptr", bmp, "ptr")
        DllCall("BitBlt", "ptr", mdc, "int", 0, "int", 0, "int", w, "int", h
            , "ptr", sdc, "int", x, "int", y, "uint", 0x00CC0020)            ; SRCCOPY
        DllCall("SelectObject", "ptr", mdc, "ptr", old, "ptr")
        DllCall("DeleteDC", "ptr", mdc)
        DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
        c := Gui("-Caption +ToolWindow -DPIScale +E0x20 +Owner" win.Hwnd)   ; E0x20 = clicks pass through
        c.MarginX := 0, c.MarginY := 0
        c.AddPicture("x0 y0 w" w " h" h, "HBITMAP:" bmp)
        WinSetTransparent(255, c.Hwnd)
        pref := 2                                      ; Windows 11: same rounded corners as the window
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", c.Hwnd, "uint", 33, "int*", &pref, "uint", 4)
        c.Show("x" x " y" y " w" w " h" h " NA")
        DllCall("UpdateWindow", "ptr", c.Hwnd)
        DllCall("dwmapi\DwmFlush")                     ; the cover is really on screen before anything changes
        return c
    }
    return 0
}

; Fades the covers out like a dimmer: one step per screen refresh (DwmFlush waits for the next
; frame), eased in and out (smoothstep) so it starts and ends gently.
FadeAway(covers, ms := 450) {
    list := []
    for c in covers
        if c
            list.Push(c)
    if !list.Length
        return
    DllCall("dwmapi\DwmFlush")
    t0 := A_TickCount
    loop {
        f := Min(1, (A_TickCount - t0) / ms)
        a := Round(255 * (1 - f * f * (3 - 2 * f)))
        for c in list
            try WinSetTransparent(Max(a, 1), c.Hwnd)
        if f >= 1
            break
        if DllCall("dwmapi\DwmFlush") != 0                  ; composition off: fall back to a short sleep
            Sleep(10)
    }
    for c in list
        try c.Destroy()
}

SliderThumbDraw(ctrl, lp) {
    P := A_PtrSize
    stage := NumGet(lp, 3 * P, "uint")
    if stage = 1                                   ; CDDS_PREPAINT
        return 0x20                                ; CDRF_NOTIFYITEMDRAW
    part := NumGet(lp, 5 * P + 16, "uptr")
    if stage != 0x10001 || (part != 2 && part != 3)    ; only the thumb (TBCD_THUMB) and the track (TBCD_CHANNEL)
        return 0
    hdc := NumGet(lp, 4 * P, "ptr")
    l := NumGet(lp, 5 * P, "int"), t := NumGet(lp, 5 * P + 4, "int")
    r := NumGet(lp, 5 * P + 8, "int"), b := NumGet(lp, 5 * P + 12, "int")
    if part = 3
        return SliderTrackDraw(ctrl, hdc, l, t, r, b)
    state := NumGet(lp, 6 * P + 16, "uint")
    pt := Buffer(8)
    DllCall("GetCursorPos", "ptr", pt)
    DllCall("ScreenToClient", "ptr", ctrl.Hwnd, "ptr", pt)
    mx := NumGet(pt, 0, "int"), my := NumGet(pt, 4, "int")
    hot := (mx >= l && mx < r && my >= t && my < b) || (state & 0x41)    ; under the mouse / pressed / hot
    th := ThemeColors()
    c := hot ? (th.dark ? "FFFFFF" : "1B1B1B") : th.accent
    if !DllCall("IsWindowEnabled", "ptr", ctrl.Hwnd)              ; greyed-out section
        c := th.dark ? "4A4D58" : "C2C2C2"
    ; Smooth (anti-aliased) pill with GDI+, straight onto the slider's drawing surface.
    Gp_Start()
    w := r - l, h := b - t
    pw := Max(6, Round(w * 0.8)), x := l + (w - pw) / 2      ; a little slimmer than Windows' thumb
    gr := 0, path := 0, brush := 0
    DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc, "ptr*", &gr)
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gr, "int", 4)            ; anti-alias
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &path)
    d := pw                                                                  ; round ends = full width
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", t, "float", d, "float", d, "float", 180, "float", 180)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", b - d - 1, "float", d, "float", d, "float", 0, "float", 180)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", path)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", 0xFF000000 | Integer("0x" c), "ptr*", &brush)
    DllCall("gdiplus\GdipFillPath", "ptr", gr, "ptr", brush, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
    DllCall("gdiplus\GdipDeletePath", "ptr", path)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    return 4                                       ; CDRF_SKIPDEFAULT
}

; The slider's track, drawn by us: Windows' own track is almost white, so it vanished on the
; light theme. One plain colour on purpose: Windows repaints only the strips around the old and
; new thumb, so a track filled up to the thumb left stripes.
SliderTrackDraw(ctrl, hdc, l, t, r, b) {
    ; A thin line in the separator colour, painted the same way as the separators (plain GDI),
    ; so it looks just like the line under the tabs.
    c := Integer("0x" ThemeColors().line)
    h := Max(1, Round(A_ScreenDPI / 96)), y := (t + b) // 2
    rc := Buffer(16)
    NumPut("int", l, "int", y, "int", r, "int", y + h, rc)
    br := DllCall("CreateSolidBrush", "uint", ((c & 0xFF) << 16) | (c & 0xFF00) | (c >> 16), "ptr")
    DllCall("FillRect", "ptr", hdc, "ptr", rc, "ptr", br)
    DllCall("DeleteObject", "ptr", br)
    return 4                                       ; CDRF_SKIPDEFAULT
}

; A horizontal bar with round ends, filled with one colour.
GpPill(gr, x, y, w, h, hex) {
    d := Min(h, w), path := 0, br := 0
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &path)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", y, "float", d, "float", h, "float", 90, "float", 180)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x + w - d, "float", y, "float", d, "float", h, "float", 270, "float", 180)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", path)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", Gp_Argb(hex), "ptr*", &br)
    DllCall("gdiplus\GdipFillPath", "ptr", gr, "ptr", br, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
    DllCall("gdiplus\GdipDeletePath", "ptr", path)
}

; A value typed in a slider's number box moves the slider. A number above the maximum
; (typing 2500 or 1111 for a slider that ends at 800) moves the slider to the end at once and,
; half a second after the last key, turns the box into the maximum too. Leaving the box puts
; the real value back in it.
SlideTyped(sl, e, lo, hi, final) {
    if e.HasOwnProp("capFn")
        SetTimer(e.capFn, 0)                      ; a new key press restarts the wait
    txt := Trim(e.Text)
    if !IsInteger(txt) {
        if final
            e.Text := sl.Value
        return
    }
    n := Integer(txt)
    v := Min(hi, Max(lo, n))
    if sl.Value != v
        sl.Value := v
    if !final && n > hi {
        h := e.Hwnd
        e.capFn := () => DllCall("IsWindow", "ptr", h) ? SlideTyped(sl, e, lo, hi, true) : 0
        SetTimer(e.capFn, -500)
    }
    if final && txt !== String(v) {
        e.Text := v
        SendMessage(0xB1, StrLen(v), StrLen(v), e)   ; EM_SETSEL: cursor after the number
    }
}

; Sets a slider and its number box.
SetSlide(sl, v) {
    sl.Value := v
    if SLIDERS.Has(sl.Hwnd)
        SLIDERS[sl.Hwnd].vt.Text := v
}

; Move the slider under the mouse to the next multiple of 5 up (dir 1) or down (-1): 33 -> 35 / 30.
SliderStep(dir) {
    MouseGetPos(, , , &h, 2)
    if !(h := SliderAt(h))
        return
    e := SLIDERS[h]
    cur := e.sl.Value
    v := dir > 0 ? (Floor(cur / 5) + 1) * 5 : (Ceil(cur / 5) - 1) * 5
    v := Min(e.hi, Max(e.lo, v))
    e.sl.Value := v
    e.vt.Text := v
}

GuideScrollBar() {
    si := Buffer(28, 0)
    NumPut("uint", 28, "uint", 0x7, "int", 0, "int", GUIDE.total - 1, "uint", GUIDE.page, "int", GUIDE.pos, si)
    DllCall("SetScrollInfo", "ptr", GUIDE.hwnd, "int", 1, "ptr", si, "int", 1)  ; SB_VERT; hides itself when all fits
}

GuideScroll(dy) {
    newPos := Round(Min(Max(GUIDE.pos + dy, 0), Max(0, GUIDE.total - GUIDE.page)))
    if newPos = GUIDE.pos
        return
    DllCall("ScrollWindow", "ptr", GUIDE.hwnd, "int", 0, "int", GUIDE.pos - newPos, "ptr", 0, "ptr", 0)
    GUIDE.pos := newPos
    GuideScrollBar()
    DllCall("UpdateWindow", "ptr", GUIDE.hwnd)
}

; Scrollbar clicks/drags and the mouse wheel over the guide.
GuideMsg(wParam, lParam, msg, hwnd) {
    if !GUIDE.hwnd || !DllCall("IsWindowVisible", "ptr", GUIDE.hwnd)
        return
    line := Round(20 * A_ScreenDPI / 96)
    if msg = 0x20A {
        ; The wheel message goes to the focused or hovered window, so check what is under the mouse.
        x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
        x := x >= 0x8000 ? x - 0x10000 : x, y := y >= 0x8000 ? y - 0x10000 : y
        over := DllCall("WindowFromPoint", "int64", (y << 32) | (x & 0xFFFFFFFF), "ptr")
        if over != GUIDE.hwnd && !DllCall("IsChild", "ptr", GUIDE.hwnd, "ptr", over)
            return
        delta := (wParam >> 16) & 0xFFFF
        delta := delta >= 0x8000 ? delta - 0x10000 : delta
        GuideScroll(-delta / 120 * line * 3)
        return 0
    }
    if hwnd != GUIDE.hwnd
        return
    switch wParam & 0xFFFF {
        case 0: GuideScroll(-line)                      ; arrow up
        case 1: GuideScroll(line)                       ; arrow down
        case 2: GuideScroll(-GUIDE.page)                ; page up
        case 3: GuideScroll(GUIDE.page)                 ; page down
        case 6: GuideScroll(-GUIDE.total)               ; top
        case 7: GuideScroll(GUIDE.total)                ; bottom
        case 4, 5:                                      ; dragging the thumb
            si := Buffer(28, 0)
            NumPut("uint", 28, "uint", 0x10, si)        ; SIF_TRACKPOS
            DllCall("GetScrollInfo", "ptr", hwnd, "int", 1, "ptr", si)
            GuideScroll(NumGet(si, 24, "int") - GUIDE.pos)
    }
    return 0
}

; Export copies the saved settings file (unsaved changes in the window are not included).
ExportSettings(owner) {
    owner.Opt("+OwnDialogs")
    path := FileSelect("S16", A_MyDocuments "\HK-Master settings.ini", "Export settings", "Settings (*.ini)")
    if path = ""
        return
    if !RegExMatch(path, "i)\.ini$")
        path .= ".ini"
    try {
        FileCopy(INI, path, 1)
        MsgBox("Settings exported to:`n" path, "Export settings", "Iconi Owner" owner.Hwnd)
    } catch as e
        MsgBox("Could not export:`n" e.Message, "Export settings", "Icon! Owner" owner.Hwnd)
}

; Import replaces the current settings with the chosen file, then reloads.
ImportSettings(owner) {
    owner.Opt("+OwnDialogs")
    path := FileSelect(1, A_MyDocuments, "Import settings", "Settings (*.ini)")
    if path = ""
        return
    if IniRead(path, "Snippets", "Count", "") = "" && IniRead(path, "General", "ConfigVersion", "") = "" {
        MsgBox("That file doesn't look like " APP_NAME " settings.", "Import settings", "Icon! Owner" owner.Hwnd)
        return
    }
    if MsgBox("Replace your current settings with this file?", "Import settings", "YesNo Icon? Owner" owner.Hwnd) != "Yes"
        return
    try {
        FileCopy(path, INI, 1)
    } catch as e {
        MsgBox("Could not import:`n" e.Message, "Import settings", "Icon! Owner" owner.Hwnd)
        return
    }
    IniWrite(1, INI, "State", "JustSaved")
    AppReload()
}

; =============================================================================
;  Theme (Settings > General > Theme: Auto / Light / Dark)
; =============================================================================
IsDarkTheme() {
    if cfg.theme = "dark"
        return true
    if cfg.theme = "light"
        return false
    light := 1
    try light := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme")
    return !light
}

; The colours of the current look, with the chosen accent colour (AccentOver) on top.
ThemeColors() => AccentOver(BaseColors())

BaseColors() {
    ; Light frosted glass. Windows' own controls are made "layered" here (GlassLayer), so they
    ; show as solid pixels instead of being added to the glass: text and check boxes sit on
    ; key, a colour that turns see-through; text boxes and lists are solid white.
    if GlassOn() && !IsDarkTheme()
        return {dark: false, glass: true, bg: "000000", key: "E9EAEE", fg: "1B1B1B", muted: "5F6270", field: "FFFFFF", line: "C9CBD3"
            , btn: "F7F7F9", btnHot: "FFFFFF", edge: "CDD0D8", track: "E3E4E9", accent: "0067C0"
            , pri: "0067C0", priHot: "1A7FD0", priEdge: "0A5BAA", priText: "FFFFFF"
            , danger: "C42B1C", dangerHot: "D63A2B", dangerEdge: "A82618", dis: "ECEDF1"}
    ; Frosted glass, dark: the same recipe as Islam's "Claude Dual Logins" app.
    ; Windows ADDS every colour we paint to the tinted blur behind the window: pure black (bg)
    ; is clear glass, very dark colours are soft tints, and text has to be light. So these are
    ; much darker than the solid Dark colours on purpose. edge = outline of drawn buttons.
    if GlassOn()
        return {dark: true, glass: true, bg: "000000", fg: "F3F4F8", muted: "A3A6B2", field: "101116", line: "2C2E38"
            , btn: "1E1F27", btnHot: "30323D", edge: "424450", track: "16171C", accent: "4CC2FF"
            , pri: "2254C4", priHot: "3865CB", priEdge: "4972CE", priText: "F3F4F8"
            , danger: "C83C34", dangerHot: "CD4F48", dangerEdge: "D15F58", dis: "24252D"}
    return IsDarkTheme()
        ? {dark: true,  bg: "202020", fg: "E8E8E8", muted: "A0A0A0", field: "2B2B2B", line: "3C3C3C", btn: "3A3A3A", btnHot: "505050", accent: "4CC2FF", pri: "4CC2FF", priHot: "7AD3FF", priText: "00131F"}
        : {dark: false, bg: "F9F9F9", fg: "1B1B1B", muted: "6B6B6B", field: "FFFFFF", line: "D5D5D5", btn: "E3E3E3", btnHot: "CFCFCF", accent: "0067C0", pri: "0067C0", priHot: "1A7FD0", priText: "FFFFFF"}
}

; ---- Accent colour (Settings > General > Look) ----
; One colour for everything that shows the accent: tabs, buttons, switches, check boxes, sliders,
; the chosen theme card. cfg.accent is RRGGBB, or "windows" = the accent colour set in Windows
; (Settings > Personalization > Colors).

; The picker's colours: 11 hues (the solid colours of the Radix palette, made to work on light
; and dark backgrounds) in three rows: light, as is, deep.
ACCENT_HUES() => [["Red", "E5484D"], ["Orange", "F76B15"], ["Amber", "FFC53D"], ["Green", "30A46C"]
    , ["Teal", "12A594"], ["Cyan", "00A2C7"], ["Blue", "0090FF"], ["Indigo", "3E63DD"]
    , ["Violet", "6E56CF"], ["Pink", "D6409F"], ["Grey", "8B8D98"]]

AccentPalette() {                                              ; [[RRGGBB, name], ...] row by row
    static pal := 0
    if pal
        return pal
    pal := []
    for tone in [["Light ", "FFFFFF", 0.35], ["", "", 0], ["Deep ", "000000", 0.3]]
        for hu in ACCENT_HUES()
            pal.Push([tone[3] ? MixHex(hu[2], tone[2], tone[3]) : hu[2], tone[1] = "" ? hu[1] : (tone[1] StrLower(hu[1]))])
    return pal
}

; The accent colour now in use, as RRGGBB.
AccentHex() {
    a := cfg.HasOwnProp("accent") ? cfg.accent : "0090FF"
    if a != "windows"
        return a
    try {
        c := RegRead("HKCU\Software\Microsoft\Windows\DWM", "AccentColor")     ; 0xAABBGGRR
        return Format("{:02X}{:02X}{:02X}", c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF)
    }
    return "0078D4"                                            ; not set: Windows' default blue
}

AccentName() {
    if cfg.accent = "windows"
        return "Windows"
    for p in AccentPalette()
        if p[1] = cfg.accent
            return p[2]
    return "Custom"
}

; Two colours mixed: f = 0 gives a, 1 gives b (RRGGBB each).
MixHex(a, b, f) {
    a := Integer("0x" a), b := Integer("0x" b), out := 0
    for s in [16, 8, 0] {
        ca := (a >> s) & 0xFF, cb := (b >> s) & 0xFF
        out |= Round(ca + (cb - ca) * f) << s
    }
    return Format("{:06X}", out)
}

; How light a colour looks, 0 (black) to 1 (white).
Luma(hex) {
    v := Integer("0x" hex)
    return (0.2126 * ((v >> 16) & 0xFF) + 0.7152 * ((v >> 8) & 0xFF) + 0.0722 * (v & 0xFF)) / 255
}

; Puts the accent colour into a look's colours: the same colour for lines, text and filled
; buttons, in every look. Text on it is dark for light colours (amber, light tones), else white.
AccentOver(t) {
    c := AccentHex()
    light := Luma(c) > 0.6
    t.accent := t.pri := c
    t.priText := light ? "1B1B1B" : "FFFFFF"
    t.priHot := light ? MixHex(c, "000000", 0.08) : MixHex(c, "FFFFFF", 0.14)
    if t.HasOwnProp("priEdge")                                 ; glass: the outline of filled buttons
        t.priEdge := MixHex(c, t.dark ? "FFFFFF" : "000000", 0.22)
    return t
}

; The accent button (General page): like a drop-down, the colour as a dot, its name and a ˅.
AccentButton(win, x, y, w, onPick) {
    b := win.AddText("x" x " y" y " w" w " h28 +0xD +0x100", "")
    b.GetPos(, , &pw, &ph)
    b.px := pw, b.py := ph, b.dis := false
    b.drawFn := AccentButtonDraw
    BTN[b.Hwnd] := b                                           ; lighter under the mouse
    SetTimer(BtnHoverTick, 40)
    b.OnEvent("Click", (*) => AccentPicker(b, onPick))
    AccentButtonDraw(b)
    return b
}

AccentButtonDraw(b, hot := false) {
    t := ThemeColors()
    k := A_ScreenDPI / 96
    w := b.px / k, h := b.py / k
    fill := hot ? t.btnHot : t.btn
    cv := Gp_Canvas(b.px, b.py, t.bg, true)
    if t.HasOwnProp("glass") {                                 ; glass: a 1-pixel outline, like the buttons
        bw := Round(cv.k) / cv.k
        Gp_Round(cv, 0, 0, w, h, 8, t.edge)
        Gp_Round(cv, bw, bw, w - 2 * bw, h - 2 * bw, 8 - bw, fill)
    } else
        Gp_Round(cv, 0, 0, w, h, 8, fill)
    Gp_Round(cv, 10, h / 2 - 7, 14, 14, 7, t.line)              ; a thin ring, so any colour shows
    Gp_Round(cv, 11, h / 2 - 6, 12, 12, 6, AccentHex())
    Gp_Text(cv, AccentName(), 32, 0, w - 58, h, t.fg, 12, false, 0, 5)
    Gp_Line(cv, w - 22, h / 2 - 2, w - 18, h / 2 + 2, t.fg, 1.5)
    Gp_Line(cv, w - 18, h / 2 + 2, w - 14, h / 2 - 2, t.fg, 1.5)
    SetBitmap(b, Gp_Done(cv))
}

; The swatch picker: a pop-up under the accent button (like our menus) with the palette, then
; "Windows accent" and "Custom colour..." (Windows' colour dialog, any colour).
AccentPicker(anchor, onPick) {   ; (not "btn": names ignore case, and BTN is our buttons map)
    k := A_ScreenDPI / 96
    owner := DllCall("GetAncestor", "ptr", anchor.Hwnd, "uint", 2, "ptr")       ; GA_ROOT
    m := Gui("-Caption +ToolWindow +AlwaysOnTop +Owner" owner (VerCompare(A_OSVersion, "10.0.22000") < 0 ? " +Border" : ""))
    m.MarginX := 0, m.MarginY := 0
    mh := m.Hwnd                                                ; kept: m.Hwnd can't be read once it's closed
    POPUPS[mh] := 1
    cols := ACCENT_HUES().Length, S := 22, G := 6, PAD := 14
    W := PAD * 2 + cols * (S + G) - G
    Muted(m.AddText("x" PAD " y12 w" (W - 2 * PAD) " h18", "Accent colour"))
    pal := AccentPalette()
    Loop pal.Length {
        n := A_Index - 1
        sw := m.AddText("x" (PAD + Mod(n, cols) * (S + G)) " y" (38 + (n // cols) * (S + G)) " w" S " h" S " +0xD +0x100", "")
        sw.GetPos(, , &sx, &sy)
        sw.px := sx, sw.py := sy, sw.dis := false, sw.col := pal[A_Index][1]
        sw.drawFn := SwatchDraw
        BTN[sw.Hwnd] := sw                                      ; ring under the mouse
        sw.OnEvent("Click", SwatchClick)
        SwatchDraw(sw)
    }
    y := 38 + 3 * (S + G) + 4
    sp := m.AddText("x" PAD " y" y " w" (W - 2 * PAD) " h1"), sp.role := "line"
    y += 12
    bw := (W - 2 * PAD - 8) // 2
    isCustom := cfg.accent != "windows" && AccentName() = "Custom"
    AddBtn(m, "x" PAD " y" y " w" bw, "Windows accent", cfg.accent = "windows").OnEvent("Click", (*) => Pick("windows"))
    AddBtn(m, "x" (PAD + bw + 8) " y" y " w" bw, "Custom colour...", isCustom).OnEvent("Click", Custom)
    H := y + 28 + PAD
    m.OnEvent("Escape", (*) => Close())
    ApplyTheme(m)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", m.Hwnd, "int", 33, "int*", 2, "int", 4)   ; Windows 11: round corners
    rc := Buffer(16)
    DllCall("GetWindowRect", "ptr", anchor.Hwnd, "ptr", rc)
    x := NumGet(rc, 0, "int"), y := NumGet(rc, 12, "int") + Round(4 * k)                  ; under the button
    MonitorGetWorkArea(MonitorFromPt(x, y), &ml, &mt, &mr, &mb)  ; stay on the screen
    if y + Round(H * k) > mb
        y := NumGet(rc, 4, "int") - Round((H + 4) * k)          ; no room below: above it
    x := Max(ml, Min(x, mr - Round(W * k))), y := Max(mt, y)
    m.Show("x" x " y" y " w" W " h" H)
    SetTimer(BtnHoverTick, 40)
    SetTimer(Watch, 60)

    Watch() {                                                   ; another window took over: close
        if !DllCall("IsWindow", "ptr", mh) {
            SetTimer(Watch, 0)
            return
        }
        if DllCall("GetForegroundWindow", "ptr") != mh
            Close()
    }
    SwatchClick(ctrl, *) {
        Pick(ctrl.col)
    }
    Pick(v) {
        Close()
        onPick(v)
    }
    Custom(*) {
        Close()
        c := PickCustomColour(owner)
        if c != ""
            onPick(c)
    }
    Close() {                                                   ; forget its controls, then close
        SetTimer(Watch, 0)
        if !DllCall("IsWindow", "ptr", mh)
            return
        for hw, c in m
            try BTN.Delete(hw)
        try POPUPS.Delete(mh)
        try m.Destroy()
    }
}

; One round swatch of the picker: a ring in the text colour (with a tick) when it is the colour
; in use, a muted ring under the mouse.
SwatchDraw(b, hot := false) {
    t := ThemeColors()
    k := A_ScreenDPI / 96
    w := b.px / k, h := b.py / k, cx := w / 2, cy := h / 2
    sel := cfg.accent = b.col
    cv := Gp_Canvas(b.px, b.py, t.bg, true)
    if sel || hot
        Gp_Round(cv, 0, 0, w, h, w / 2, sel ? t.fg : t.muted)
    Gp_Round(cv, 2.5, 2.5, w - 5, h - 5, (w - 5) / 2, b.col)
    if sel {
        tc := Luma(b.col) > 0.6 ? "1B1B1B" : "FFFFFF"
        Gp_Line(cv, cx - 4.5, cy + 0.5, cx - 1.5, cy + 3.5, tc, 1.8)
        Gp_Line(cv, cx - 1.5, cy + 3.5, cx + 4.5, cy - 3, tc, 1.8)
    }
    SetBitmap(b, Gp_Done(cv))
}

; Windows' colour dialog, opened on the accent colour now in use. Returns RRGGBB, or "" if
; cancelled. The 16 "custom colours" boxes are kept while the app runs.
PickCustomColour(owner) {
    static cust := 0
    if !cust {
        cust := Buffer(64)
        Loop 16
            NumPut("uint", 0xFFFFFF, cust, (A_Index - 1) * 4)
    }
    P := A_PtrSize
    cc := Buffer(9 * P, 0)                                      ; CHOOSECOLOR
    NumPut("uint", 9 * P, cc, 0)
    NumPut("ptr", owner, cc, P)
    cur := Integer("0x" AccentHex())
    NumPut("uint", ((cur & 0xFF) << 16) | (cur & 0xFF00) | (cur >> 16), cc, 3 * P)   ; COLORREF 0x00BBGGRR
    NumPut("ptr", cust.Ptr, cc, 4 * P)
    NumPut("uint", 0x103, cc, 5 * P)                            ; CC_RGBINIT | CC_FULLOPEN | CC_ANYCOLOR
    if !DllCall("comdlg32\ChooseColorW", "ptr", cc)
        return ""
    c := NumGet(cc, 3 * P, "uint")
    return Format("{:02X}{:02X}{:02X}", c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF)
}

; Frosted glass (Settings > General > Look, on by default), dark or light. On glass every
; colour Windows' controls paint is added to the blur, so on light glass the controls are made
; layered (GlassLayer) to show as solid pixels. Needs Windows 10 1803 or newer.
GlassOn() => cfg.glass && GlassSupported()
GlassSupported() => VerCompare(A_OSVersion, "10.0.17134") >= 0

; Turns the frosted backdrop on or off for a top-level window (child windows, like the
; Shortcuts page, are part of their parent's picture and follow it). An unnamed Windows
; function (SetWindowCompositionAttribute, WCA_ACCENT_POLICY = 19) puts a blur behind the
; window with our tint over it (flag 2). Windows 11: acrylic (4), tint 0xD8140F0C (AABBGGRR,
; a blue-black at 85%), exactly as in the Claude Dual Logins app. Windows 10: the plain blur
; (3) with the same tint, because acrylic lags there when the window is dragged.
SetGlass(win, on) {
    h := win.Hwnd
    if !on && !GLASS_WINS.Has(h)                       ; never had it: leave Windows' default alone
        return
    if DllCall("GetWindowLong", "ptr", h, "int", -16, "int") & 0x40000000   ; WS_CHILD
        return
    ap := Buffer(16, 0)
    ; Acrylic on Windows 11, blur on 10. (Plain blur on Windows 11 showed solid black, tested
    ; 2026-11-17; acrylic keeps a milky layer of its own, so light uses almost no tint.)
    NumPut("int", on ? (VerCompare(A_OSVersion, "10.0.22000") >= 0 ? 4 : 3) : 0, ap, 0)
    NumPut("int", on ? 2 : 0, ap, 4)
    NumPut("uint", on ? GlassTint() : 0, ap, 8)                                     ; tint AABBGGRR
    wd := Buffer(A_PtrSize * 3, 0)
    NumPut("int", 19, wd, 0)
    NumPut("ptr", ap.Ptr, wd, A_PtrSize)
    NumPut("uptr", ap.Size, wd, A_PtrSize * 2)
    try DllCall("user32\SetWindowCompositionAttribute", "ptr", h, "ptr", wd)
    ; Windows drops the frosted backdrop during the minimize / restore animation, so the window
    ; showed see-through for a moment. With glass on, those animations are turned off
    ; (DWMWA_TRANSITIONS_FORCEDISABLED = 3): it just disappears and comes back.
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", h, "int", 3, "int*", on ? 1 : 0, "int", 4)
    if on
        GLASS_WINS[h] := 1
    else
        GLASS_WINS.Delete(h)
}

; Light glass: dragging the window lagged behind the mouse (many layered labels on acrylic are
; heavy for Windows to redraw on every step). While it is dragged or resized the glass is a
; plain light colour; let go, it is frosted again. Dark glass doesn't need it.
GlassMoveStart(wParam, lParam, msg, hwnd) {
    if !GLASS_WINS.Has(hwnd) || IsDarkTheme()
        return
    SetAccent(hwnd, 1, 2, 0xFFF0EFEE)                          ; ACCENT_ENABLE_GRADIENT: plain colour
}

GlassMoveEnd(wParam, lParam, msg, hwnd) {
    if !GLASS_WINS.Has(hwnd) || IsDarkTheme()
        return
    SetAccent(hwnd, VerCompare(A_OSVersion, "10.0.22000") >= 0 ? 4 : 3, 2, GlassTint())
}

; The glass tint (AABBGGRR). Dark: a blue-black at 85%. Light on Windows 11: almost none, as
; acrylic brings a milky layer of its own. Light on Windows 10: its plain blur has no such layer,
; so the same tint left the glass nearly clear (dark wallpaper behind dark text, with light
; fringes around the letters); a 75% light grey stands in for the acrylic layer.
GlassTint() {
    if IsDarkTheme()
        return 0xD8140F0C
    return VerCompare(A_OSVersion, "10.0.22000") >= 0 ? 0x10F3F3F3 : 0xC0F3F3F3
}

SetAccent(h, state, flags, tint) {
    ap := Buffer(16, 0)
    NumPut("int", state, ap, 0), NumPut("int", flags, ap, 4), NumPut("uint", tint, ap, 8)
    wd := Buffer(A_PtrSize * 3, 0)
    NumPut("int", 19, wd, 0), NumPut("ptr", ap.Ptr, wd, A_PtrSize), NumPut("uptr", ap.Size, wd, A_PtrSize * 2)
    try DllCall("user32\SetWindowCompositionAttribute", "ptr", h, "ptr", wd)
}

; Dark or light menus (tray menu, pop-up menus) for the whole app. Uses two unnamed Windows
; functions (uxtheme #135 SetPreferredAppMode, #136 FlushMenuThemes); ignored on old Windows.
ApplyAppMode() {
    try {
        ux := DllCall("LoadLibrary", "str", "uxtheme", "ptr")
        DllCall(DllCall("GetProcAddress", "ptr", ux, "ptr", 135, "ptr"), "int", IsDarkTheme() ? 2 : 3)
        DllCall(DllCall("GetProcAddress", "ptr", ux, "ptr", 136, "ptr"))
    }
}

; Colours a window and its controls. Controls can carry a "role": muted (grey hint text),
; tab, bar (accent line), line (separator).
ApplyTheme(win) {
    t := ThemeColors()
    win.BackColor := t.bg
    SetGlass(win, t.HasOwnProp("glass"))
    if TITLED.Has(win.Hwnd) || POPUPS.Has(win.Hwnd) {
        ; Windows 11: the thin window border in our outline colour (34 = DWMWA_BORDER_COLOR, BBGGRR).
        c := Integer("0x" (t.HasOwnProp("edge") ? t.edge : t.line))
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", win.Hwnd, "int", 34, "uint*", ((c & 0xFF) << 16) | (c & 0xFF00) | (c >> 16), "int", 4)
    }
    if TITLED.Has(win.Hwnd) && TITLED[win.Hwnd].icon {          ; the title bar icon follows the theme
        hi := LoadAppIcon(t.dark ? "white" : "black", Round(16 * A_ScreenDPI / 96))
        if hi
            try TITLED[win.Hwnd].icon.Value := "HICON:" hi
    }
    try {                                                                       ; dark or light title bar
        if DllCall("dwmapi\DwmSetWindowAttribute", "ptr", win.Hwnd, "int", 20, "int*", t.dark ? 1 : 0, "int", 4) != 0
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", win.Hwnd, "int", 19, "int*", t.dark ? 1 : 0, "int", 4)  ; Windows 10 before 20H1
    }
    lg := t.HasOwnProp("key")                                   ; light glass
    for hwnd, ctrl in win {
        role := ctrl.HasOwnProp("role") ? ctrl.role : ""
        try {
          ; Light glass: text-like controls on the see-through key colour, boxes solid.
          ; Our drawn pictures (SS_OWNERDRAW) stay as they are: their pixels carry their own alpha.
          pic := ctrl.Type = "Text" && (DllCall("GetWindowLong", "ptr", hwnd, "int", -16, "int") & 0x1F) = 0xD
          pic := pic || CHECKS.Has(hwnd)                ; our drawn check boxes are pictures too
          if !pic {
              switch ctrl.Type {
                case "Text", "Pic", "Checkbox", "Radio", "Slider":
                    own := role != "bar" && role != "line" && ctrl.Type != "Slider"   ; (those set their own colour below)
                    if lg {
                        if own
                            ctrl.Opt("+Background" t.key), ctrl.glassBg := true
                        GlassLayer(hwnd, "key", t.key)
                    } else {
                        ; Once light glass gave it its own background, it follows the window colour
                        ; from then on, in every look ("Default" would be Windows' grey, not ours).
                        if own && ctrl.HasOwnProp("glassBg")
                            ctrl.Opt("+Background" t.bg)
                        if LAYERED.Has(hwnd)
                            GlassLayer(hwnd, "")
                    }
                case "Edit", "DDL", "ComboBox", "ListBox", "ListView", "Button":
                    GlassLayer(hwnd, lg ? "solid" : "")
              }
          }
          switch ctrl.Type {
            case "Text":
                if role = "bar"
                    ctrl.Opt("+Background" t.accent)
                else if role = "head" {
                    ctrl.SetFont("bold c" t.muted)
                }
                else if role = "line"
                    ctrl.Opt("+Background" t.line)
                else
                    ctrl.SetFont("c" (role = "muted" ? t.muted : t.fg))
            case "Edit", "DDL", "ComboBox", "ListBox":
                ctrl.Opt("+Background" t.field)
                ctrl.SetFont("c" t.fg)
                SetTheme(hwnd, t.dark ? "DarkMode_CFD" : "")
            case "ListView":
                ctrl.Opt("+Background" t.field)
                ctrl.SetFont("c" t.fg)
                SetTheme(hwnd, t.dark ? "DarkMode_Explorer" : "")
            case "Slider":
                ctrl.Opt("+Background" (lg ? t.key : t.bg))
            case "Checkbox", "Radio":
                SetTheme(hwnd, t.dark ? "DarkMode_Explorer" : "")
          }
        }
    }
    if lg {                                                     ; layered controls paint again once shown
        SetTimer(RepaintLayered.Bind(win.Hwnd), -60)
        SetTimer(RepaintLayered.Bind(win.Hwnd), -400)
    }
    ; "" = back to the normal Windows look (used when switching from dark to light).
    SetTheme(h, name) => name = "" ? DllCall("uxtheme\SetWindowTheme", "ptr", h, "ptr", 0, "ptr", 0)
                                   : DllCall("uxtheme\SetWindowTheme", "ptr", h, "str", name, "ptr", 0)
}

; Light glass: a control made a "layered" child window, which Windows draws as solid pixels on
; the glass instead of adding its colours to it (dark text would vanish). mode: "key" = the
; key colour (the control's background) turns see-through, the rest is solid (text, check
; boxes, sliders); "solid" = the whole control (text boxes, lists); "" = back to normal.
GlassLayer(h, mode, key := "") {
    ex := DllCall("GetWindowLong", "ptr", h, "int", -20, "int")
    if mode = "" {
        if ex & 0x80000 {
            DllCall("SetWindowLong", "ptr", h, "int", -20, "int", ex & ~0x80000)
            DllCall("RedrawWindow", "ptr", h, "ptr", 0, "ptr", 0, "uint", 0x0585)
        }
        if LAYERED.Has(h)                                       ; (Delete throws for a missing key)
            LAYERED.Delete(h)
        return
    }
    fresh := !(ex & 0x80000)
    if fresh
        DllCall("SetWindowLong", "ptr", h, "int", -20, "int", ex | 0x80000)                       ; WS_EX_LAYERED
    if mode = "key" {
        c := Integer("0x" key)
        DllCall("SetLayeredWindowAttributes", "ptr", h, "uint", ((c & 0xFF) << 16) | (c & 0xFF00) | (c >> 16), "uchar", 0, "uint", 1)   ; LWA_COLORKEY
    } else
        DllCall("SetLayeredWindowAttributes", "ptr", h, "uint", 0, "uchar", 255, "uint", 2)    ; LWA_ALPHA, fully solid
    LAYERED[h] := 1
    ; A control already on screen when it becomes layered (switching to light glass) could stay
    ; black (a list did): hiding and showing it again gives it a fresh surface.
    if fresh && DllCall("IsWindowVisible", "ptr", h) {
        DllCall("ShowWindow", "ptr", h, "int", 0)
        DllCall("ShowWindow", "ptr", h, "int", 8)                                               ; SW_SHOWNA
        DllCall("RedrawWindow", "ptr", h, "ptr", 0, "ptr", 0, "uint", 0x0585)
    }
}

; Light glass: Windows lets clicks on a label's see-through (key colour) part fall through to
; the window behind it, so tabs and labels needed several clicks. The window gets that click
; here and passes it on to the label (or check box) under the mouse.
LayeredClick(wParam, lParam, msg, hwnd) {
    if !LAYERED.Count || LAYERED.Has(hwnd)
        return
    pt := Buffer(8)
    DllCall("GetCursorPos", "ptr", pt)
    px := NumGet(pt, 0, "int"), py := NumGet(pt, 4, "int")
    rc := Buffer(16), cls := Buffer(64)
    for h in LAYERED {
        if DllCall("GetParent", "ptr", h, "ptr") != hwnd || !DllCall("IsWindowVisible", "ptr", h) || !DllCall("IsWindowEnabled", "ptr", h)
            continue
        DllCall("GetWindowRect", "ptr", h, "ptr", rc)
        if px < NumGet(rc, 0, "int") || px >= NumGet(rc, 8, "int") || py < NumGet(rc, 4, "int") || py >= NumGet(rc, 12, "int")
            continue
        DllCall("GetClassName", "ptr", h, "ptr", cls, "int", 32)
        c := StrGet(cls)
        if c = "Static" && (DllCall("GetWindowLong", "ptr", h, "int", -16, "int") & 0x100) {       ; SS_NOTIFY: has a Click
            PostMessage(0x111, DllCall("GetDlgCtrlID", "ptr", h, "int"), h, , "ahk_id " hwnd)   ; WM_COMMAND, STN_CLICKED
            return 0
        }
        if c = "Button" {
            PostMessage(0xF5, 0, 0, , "ahk_id " h)                                              ; BM_CLICK
            return 0
        }
    }
}

; Layered controls stay black until they paint again after being shown (tested 2026-11-17),
; so every layered control in that window repaints.
; A window with light glass labels was just shown (SWP_SHOWWINDOW): paint them before Windows
; puts the window on screen, so they don't flash black (the install prompt did).
GlassShown(wParam, lParam, msg, hwnd) {
    if !LAYERED.Count || !(NumGet(lParam, 2 * A_PtrSize + 16, "uint") & 0x40)
        return
    RepaintLayered(hwnd)
}

RepaintLayered(winHwnd) {
    root := DllCall("GetAncestor", "ptr", winHwnd, "uint", 2, "ptr")                          ; GA_ROOT
    for h in LAYERED.Clone() {
        if !DllCall("IsWindow", "ptr", h) {
            LAYERED.Delete(h)
            continue
        }
        if DllCall("GetAncestor", "ptr", h, "uint", 2, "ptr") = root && DllCall("IsWindowVisible", "ptr", h)
            DllCall("RedrawWindow", "ptr", h, "ptr", 0, "ptr", 0, "uint", 0x0585)
    }
}

; A thin line from the end of a label's text to the box it belongs to (x2: the box's left edge,
; 96-dpi units). Only shown once the window is made wider than its original size ("g": no width
; until then); it grows as the box moves right.
LeaderLine(win, lbl, x2) {
    k := A_ScreenDPI / 96
    lbl.GetPos(&lx, &ly, &lw, &lh)
    x1 := Round((lx + lw) / k) + 8, y := Round((ly + lh / 2) / k)
    ln := Anchor(win.AddText("x" x1 " y" y " w" Max(1, x2 - 8 - x1) " h1"), "wg")
    ln.role := "line"
    return ln
}

; Remember a control's start position and how it follows a window resize
; (flags: x / y = move, w / h = grow, g = no width until the window is wider than at the start).
Anchor(ctrl, flags) {
    ctrl.GetPos(&x, &y, &w, &h)
    k := A_ScreenDPI / 96
    ANCH[ctrl.Hwnd] := {x: x / k, y: y / k, w: w / k, h: h / k, f: flags}
    return ctrl
}

; =============================================================================
;  Drawing (GDI+): smooth rounded buttons and the mouse picture
; =============================================================================
; A canvas is a bitmap we draw on; Gp_Done turns it into an HBITMAP for a picture control.
; Coordinates are in 96-dpi units; the canvas scales them to the screen.
Gp_Start() {
    static token := 0
    if token
        return
    DllCall("LoadLibrary", "str", "gdiplus")
    si := Buffer(24, 0)
    NumPut("uint", 1, si)                                   ; GdiplusVersion = 1
    DllCall("gdiplus\GdiplusStartup", "ptr*", &token, "ptr", si, "ptr", 0)
}

Gp_Argb(hex) => 0xFF000000 | Integer("0x" hex)

; px = true: w and h are already screen pixels (drawing coordinates stay in 96-dpi units).
Gp_Canvas(w, h, bgHex, px := false) {
    Gp_Start()
    k := A_ScreenDPI / 96
    bmp := 0, gr := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", px ? w : Round(w * k), "int", px ? h : Round(h * k), "int", 0
        , "int", 0x26200A, "ptr", 0, "ptr*", &bmp)         ; 32-bit ARGB
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &gr)
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gr, "int", 4)        ; anti-aliased edges
    DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", gr, "int", 4)      ; Half: shapes sit on the pixel grid, edges even on all sides
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", gr, "int", 4)    ; anti-aliased text
    DllCall("gdiplus\GdipGraphicsClear", "ptr", gr, "uint", 0)  ; transparent: PicDrawItem paints bgHex under it
    return {bmp: bmp, gr: gr, k: k, w: px ? w : Round(w * k), h: px ? h : Round(h * k)}
}

; The canvas as a 32-bit bitmap with premultiplied alpha (what AlphaBlend wants): see-through
; around the shapes, so on glass the corners are clear glass instead of black.
; additive: on glass, the picture is mixed into the glass the way Windows paints text boxes and
; lists (colour added, alpha 0) instead of covering it, so the two look the same.
Gp_Done(cv, additive := false) {
    w := cv.w, h := cv.h
    bi := Buffer(40, 0)                                      ; BITMAPINFOHEADER, 32 bits, top-down
    NumPut("uint", 40, bi, 0), NumPut("int", w, bi, 4), NumPut("int", -h, bi, 8)
    NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "ptr", 0, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    if hbm {
        rc := Buffer(16, 0), NumPut("int", w, rc, 8), NumPut("int", h, rc, 12)
        bd := Buffer(16 + 2 * A_PtrSize, 0)                  ; BitmapData
        if DllCall("gdiplus\GdipBitmapLockBits", "ptr", cv.bmp, "ptr", rc, "uint", 1, "int", 0xE200B, "ptr", bd) = 0 {   ; read, 32bppPARGB
            stride := NumGet(bd, 8, "int"), scan := NumGet(bd, 16, "ptr")
            if stride = w * 4
                DllCall("RtlMoveMemory", "ptr", bits, "ptr", scan, "uptr", w * 4 * h)
            else
                Loop h
                    DllCall("RtlMoveMemory", "ptr", bits + (A_Index - 1) * w * 4, "ptr", scan + (A_Index - 1) * stride, "uptr", w * 4)
            DllCall("gdiplus\GdipBitmapUnlockBits", "ptr", cv.bmp, "ptr", bd)
            if additive
                Loop w * h
                    NumPut("uchar", 0, bits, A_Index * 4 - 1)
        }
    }
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", cv.gr)
    DllCall("gdiplus\GdipDisposeImage", "ptr", cv.bmp)
    return hbm
}

; Filled rectangle.
Gp_Rect(cv, x, y, w, h, hex) {
    k := cv.k, br := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", Gp_Argb(hex), "ptr*", &br)
    DllCall("gdiplus\GdipFillRectangle", "ptr", cv.gr, "ptr", br, "float", x * k, "float", y * k, "float", w * k, "float", h * k)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
}

; Filled rounded rectangle (r = corner radius).
Gp_Round(cv, x, y, w, h, r, hex) {
    k := cv.k
    x *= k, y *= k, w *= k, h *= k
    r := Min(r * k, w / 2, h / 2), d := r * 2
    path := 0, br := 0
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &path)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", y, "float", d, "float", d, "float", 180, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x + w - d, "float", y, "float", d, "float", d, "float", 270, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x + w - d, "float", y + h - d, "float", d, "float", d, "float", 0, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", y + h - d, "float", d, "float", d, "float", 90, "float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", path)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", Gp_Argb(hex), "ptr*", &br)
    DllCall("gdiplus\GdipFillPath", "ptr", cv.gr, "ptr", br, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
    DllCall("gdiplus\GdipDeletePath", "ptr", path)
}

Gp_Line(cv, x1, y1, x2, y2, hex, width := 1) {
    k := cv.k
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", Gp_Argb(hex), "float", width * k, "int", 2, "ptr*", &pen)
    DllCall("gdiplus\GdipDrawLine", "ptr", cv.gr, "ptr", pen, "float", x1 * k, "float", y1 * k, "float", x2 * k, "float", y2 * k)
    DllCall("gdiplus\GdipDeletePen", "ptr", pen)
}

; Text inside the box x, y, w, h, centred vertically. align: 0 left, 1 centre, 2 right. px = text height in pixels.
; hint: 3 = smoothed and snapped to the pixel grid (any background), 5 = ClearType (only on a
; solid fill, like a button's).
Gp_Text(cv, text, x, y, w, h, hex, px := 12, bold := false, align := 1, hint := 3) {
    k := cv.k
    fam := 0, font := 0, fmt := 0, br := 0
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "str", "Segoe UI", "ptr", 0, "ptr*", &fam)
    DllCall("gdiplus\GdipCreateFont", "ptr", fam, "float", px * k, "int", bold ? 1 : 0, "int", 2, "ptr*", &font)
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr*", &fmt)
    DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", fmt, "int", align)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", fmt, "int", 1)
    DllCall("gdiplus\GdipSetStringFormatFlags", "ptr", fmt, "int", 0x1000)       ; no wrapping
    DllCall("gdiplus\GdipSetStringFormatTrimming", "ptr", fmt, "int", 3)         ; "..." when too long
    DllCall("gdiplus\GdipCreateSolidFill", "uint", Gp_Argb(hex), "ptr*", &br)
    rc := Buffer(16, 0)                                        ; whole pixels: no half-pixel blur
    NumPut("float", Round(x * k), "float", Round(y * k), "float", Round(w * k), "float", Round(h * k), rc)
    ; Text was soft: the canvas draws shapes half a pixel offset (PixelOffsetMode Half) and with
    ; plain smoothing, which blurs small letters. Text gets no offset and a grid-fitted hint.
    DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", cv.gr, "int", 0)
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", cv.gr, "int", hint)
    DllCall("gdiplus\GdipDrawString", "ptr", cv.gr, "str", text, "int", -1, "ptr", font, "ptr", rc, "ptr", fmt, "ptr", br)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", cv.gr, "int", 4)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
    DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
    DllCall("gdiplus\GdipDeleteFont", "ptr", font)
    DllCall("gdiplus\GdipDeleteFontFamily", "ptr", fam)
}

; ---- Buttons ---------------------------------------------------------------------
; A button is a picture we redraw: smooth rounded corners, lighter when the mouse is over it.
; primary = the main action (accent colour). Its text can be changed with .Text like a normal button.
AddBtn(win, opts, text, primary := false) {
    w := RegExMatch(opts, "i)(?:^|\s)w(\d+)", &mw) ? Integer(mw[1]) : 90
    h := RegExMatch(opts, "i)(?:^|\s)h(\d+)", &mh) ? Integer(mh[1]) : 28
    opts := RegExReplace(opts, "i)(^|\s)[wh]\d+", "")          ; the size is passed separately
    ; A text control we paint ourselves (SS_OWNERDRAW, see PicDrawItem): the bitmap 1:1.
    b := win.AddText(opts " w" w " h" h " +0xD +0x100", "")
    b.GetPos(, , &pw, &ph)                                     ; real size in pixels
    b.role := "btn", b.btnText := text, b.px := pw, b.py := ph, b.primary := primary, b.dis := false
    b.DefineProp("Text", {get: (self) => self.btnText, set: (self, v) => (self.btnText := v, BtnRender(self, false))})
    BTN[b.Hwnd] := b
    BtnRender(b, false)
    SetTimer(BtnHoverTick, 40)
    return b
}

; Show a bitmap in one of our drawn pictures (an owner-drawn text control, SS_OWNERDRAW) and
; free the one it showed before. It is painted at once by PicDrawItem.
SetBitmap(ctrl, hbm) {
    h := ctrl.Hwnd
    if PICBMP.Has(h)
        DllCall("DeleteObject", "ptr", PICBMP[h])
    PICBMP[h] := hbm
    if PICBMP.Count > 300                                      ; forget pictures of closed windows
        for hw, bm in PICBMP.Clone()
            if !DllCall("IsWindow", "ptr", hw)
                DllCall("DeleteObject", "ptr", bm), PICBMP.Delete(hw)
    DllCall("RedrawWindow", "ptr", h, "ptr", 0, "ptr", 0, "uint", 0x101)   ; INVALIDATE | UPDATENOW
}

; WM_DRAWITEM for our drawn pictures: the window colour first (black = clear glass), then the
; picture blended on top with its own transparency (AlphaBlend), so round corners and soft
; edges sit on whatever is behind them.
PicDrawItem(wParam, lParam, msg, hwnd) {
    P := A_PtrSize
    if NumGet(lParam, 0, "uint") != 5                         ; ODT_STATIC
        return
    h := NumGet(lParam, P = 8 ? 24 : 20, "ptr")
    if !PICBMP.Has(h)
        return
    hdc := NumGet(lParam, P = 8 ? 32 : 24, "ptr")
    rc := lParam + (P = 8 ? 40 : 28)
    t := ThemeColors()
    c := Integer("0x" (PICFIELD.Has(h) ? t.field : t.bg))
    br := DllCall("CreateSolidBrush", "uint", ((c & 0xFF) << 16) | (c & 0xFF00) | (c >> 16), "ptr")
    DllCall("FillRect", "ptr", hdc, "ptr", rc, "ptr", br)
    DllCall("DeleteObject", "ptr", br)
    bm := Buffer(P = 8 ? 32 : 24, 0)
    DllCall("GetObject", "ptr", PICBMP[h], "int", bm.Size, "ptr", bm)
    bw := NumGet(bm, 4, "int"), bh := NumGet(bm, 8, "int")
    mdc := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    old := DllCall("SelectObject", "ptr", mdc, "ptr", PICBMP[h], "ptr")
    DllCall("msimg32\AlphaBlend", "ptr", hdc, "int", NumGet(rc, 0, "int"), "int", NumGet(rc, 4, "int"), "int", bw, "int", bh
        , "ptr", mdc, "int", 0, "int", 0, "int", bw, "int", bh, "uint", 0x01FF0000)   ; AC_SRC_ALPHA, opacity 255
    DllCall("SelectObject", "ptr", mdc, "ptr", old)
    DllCall("DeleteDC", "ptr", mdc)
    return 1
}

; Our check boxes (AddCheck): Windows still runs them (click, keyboard, .Value), but we paint
; them, so the tick box takes the accent colour like the switches. NM_CUSTOMDRAW, before Windows
; paints: window colour, then our picture blended on top (as PicDrawItem), and tell Windows to
; skip its own drawing (CDRF_SKIPDEFAULT).
CheckDraw(wParam, lParam, msg, hwnd) {
    P := A_PtrSize
    if NumGet(lParam, 2 * P, "int") != -12                     ; NM_CUSTOMDRAW
        return
    h := NumGet(lParam, 0, "ptr")
    if !CHECKS.Has(h) || NumGet(lParam, 3 * P, "uint") != 1    ; only ours, at CDDS_PREPAINT
        return
    hdc := NumGet(lParam, 4 * P, "ptr")
    rc := lParam + 5 * P
    state := NumGet(lParam, 6 * P + 16, "uint")                ; uItemState
    w := NumGet(rc, 8, "int") - NumGet(rc, 0, "int"), hh := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
    on := SendMessage(0xF0, 0, 0, h) = 1                       ; BM_GETCHECK
    dis := (state & 4) || !DllCall("IsWindowEnabled", "ptr", h)
    bmp := CheckBitmap(w, hh, on, state & 0x40, dis)          ; 0x40 = CDIS_HOT
    t := ThemeColors()
    c := Integer("0x" t.bg)
    br := DllCall("CreateSolidBrush", "uint", ((c & 0xFF) << 16) | (c & 0xFF00) | (c >> 16), "ptr")
    DllCall("FillRect", "ptr", hdc, "ptr", rc, "ptr", br)
    DllCall("DeleteObject", "ptr", br)
    mdc := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    old := DllCall("SelectObject", "ptr", mdc, "ptr", bmp, "ptr")
    DllCall("msimg32\AlphaBlend", "ptr", hdc, "int", NumGet(rc, 0, "int"), "int", NumGet(rc, 4, "int"), "int", w, "int", hh
        , "ptr", mdc, "int", 0, "int", 0, "int", w, "int", hh, "uint", 0x01FF0000)   ; AC_SRC_ALPHA, opacity 255
    DllCall("SelectObject", "ptr", mdc, "ptr", old)
    DllCall("DeleteDC", "ptr", mdc)
    DllCall("DeleteObject", "ptr", bmp)
    return 4                                                    ; CDRF_SKIPDEFAULT
}

; A rounded tick box: ticked = accent fill with a tick, not ticked = outlined box (text colour
; under the mouse), greyed out = line colour.
CheckBitmap(pw, ph, on, hot, dis) {
    t := ThemeColors()
    k := A_ScreenDPI / 96
    w := pw / k, h := ph / k
    sz := Min(w, h), x := (w - sz) / 2, y := (h - sz) / 2
    cv := Gp_Canvas(pw, ph, t.bg, true)
    if on {
        Gp_Round(cv, x, y, sz, sz, 4, dis ? t.line : (hot ? t.priHot : t.pri))
        tc := dis ? t.muted : t.priText
        Gp_Line(cv, x + sz * 0.24, y + sz * 0.52, x + sz * 0.42, y + sz * 0.70, tc, 1.7)
        Gp_Line(cv, x + sz * 0.42, y + sz * 0.70, x + sz * 0.76, y + sz * 0.32, tc, 1.7)
    } else {
        bw := Round(cv.k) / cv.k                                ; outline = whole pixels
        Gp_Round(cv, x, y, sz, sz, 4, dis ? t.line : (hot ? t.fg : t.muted))
        Gp_Round(cv, x + bw, y + bw, sz - 2 * bw, sz - 2 * bw, 4 - bw, t.field)
    }
    return Gp_Done(cv)
}

BtnBitmap(pw, ph, text, hot, dis, primary, chevron := false) {
    t := ThemeColors()
    k := A_ScreenDPI / 96
    w := pw / k, h := ph / k                                   ; drawing units
    ; primary: "danger" = red (Cancel). A disabled button is plain grey, never coloured.
    glass := t.HasOwnProp("glass")
    edge := ""
    if dis
        fill := glass ? t.dis : t.btn, textColor := t.muted
    else if primary = "danger"
        fill := glass ? (hot ? t.dangerHot : t.danger) : (hot ? "E0453A" : "C42B1C"), textColor := "FFFFFF", edge := glass ? t.dangerEdge : ""
    else if primary
        fill := hot ? t.priHot : t.pri, textColor := t.priText, edge := glass ? t.priEdge : ""
    else
        fill := hot ? t.btnHot : t.btn, textColor := t.fg, edge := glass ? t.edge : ""
    cv := Gp_Canvas(pw, ph, t.bg, true)
    if edge != "" {                                            ; glass: a 1-pixel outline, like the Python app
        bw := Round(cv.k) / cv.k
        Gp_Round(cv, 0, 0, w, h, 8, edge)
        Gp_Round(cv, bw, bw, w - 2 * bw, h - 2 * bw, 8 - bw, fill)
    } else
        Gp_Round(cv, 0, 0, w, h, 8, fill)
    if chevron {                                               ; a drop-down: text on the left, a ˅ on the right
        Gp_Text(cv, text, 12, 0, w - 40, h, textColor, 12, primary, 0, 5)
        Gp_Line(cv, w - 22, h / 2 - 2, w - 18, h / 2 + 2, textColor, 1.5)
        Gp_Line(cv, w - 18, h / 2 + 2, w - 14, h / 2 - 2, textColor, 1.5)
    } else
        Gp_Text(cv, text, 4, 0, w - 8, h, textColor, 12, primary, 1, 5)
    return Gp_Done(cv)
}

BtnRender(b, hot) {
    if b.HasOwnProp("drawFn")
        return b.drawFn.Call(b, hot)
    SetBitmap(b, BtnBitmap(b.px, b.py, b.btnText, hot, b.dis, b.HasOwnProp("danger") && b.danger ? "danger" : b.primary, b.HasOwnProp("items")))
}

; ---- Our own title bar --------------------------------------------------------------------
; The Windows title bar can't match the glass or our buttons, so windows get our own: the app
; icon, the title and minimise / maximise / close buttons drawn like the rest of the app.
; Call TitleBar after all controls are added (it moves them down to make room), then
; ShowTitled instead of Show. The Windows frame is removed (TitledNcCalc) but the window keeps
; its title-bar style, so dragging, snapping, double-click to maximise, the minimise animation
; and (baseW: resizable windows, laid out for that width) resizing at the edges still work
; (TitledHitTest).
TitleBar(win, title, kinds := ["close"], baseW := 0) {
    for hw in TITLED.Clone()                                    ; forget closed windows
        if !DllCall("IsWindow", "ptr", hw)
            TITLED.Delete(hw)
    k := A_ScreenDPI / 96, dy := Round(TB_H * k)
    for hwnd, c in win {                                        ; everything moves down
        c.GetPos(&cx, &cy)
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", cx, "int", cy + dy, "int", 0, "int", 0, "uint", 0x15)
        if ANCH.Has(hwnd)
            ANCH[hwnd].y += TB_H
    }
    t := ThemeColors()
    ico := 0
    hi := LoadAppIcon(t.dark ? "white" : "black", Round(16 * k))
    if hi
        try ico := win.AddPicture("x12 y8 w16 h16", "HICON:" hi)
    win.SetFont("s9 norm", "Segoe UI")
    txt := win.AddText("x" (ico ? 38 : 14) " y0 w" (baseW ? 400 : 150) " h" TB_H " +0x200", title)   ; 0x200 = centred vertically
    btns := []
    for i, kind in kinds {
        b := win.AddText("x" (baseW ? baseW - (kinds.Length - i + 1) * 46 : 0) " y0 w46 h" TB_H " +0xD +0x100", "")
        b.GetPos(, , &pw, &ph)
        b.px := pw, b.py := ph, b.kind := kind, b.dis := false, b.win := win.Hwnd
        b.drawFn := TitleBtnDraw
        BTN[b.Hwnd] := b                                        ; lighter under the mouse
        b.OnEvent("Click", TitleBtnClick)
        if baseW
            Anchor(b, "x")                                      ; stays at the right edge
        TitleBtnDraw(b)
        btns.Push(b)
    }
    SetTimer(BtnHoverTick, 40)
    TITLED[win.Hwnd] := {resize: baseW > 0, btns: btns, text: txt, icon: ico}
    DllCall("SetWindowPos", "ptr", win.Hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37)   ; FRAMECHANGED: frame off now
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", win.Hwnd, "int", 33, "int*", 2, "int", 4)   ; Windows 11: round corners
    if VerCompare(A_OSVersion, "10.0.22000") < 0 {               ; Windows 10: a 1-pixel frame strip keeps the shadow
        m := Buffer(16, 0)
        NumPut("int", 1, m, 8)                                  ; MARGINS.cyTopHeight
        try DllCall("dwmapi\DwmExtendFrameIntoClientArea", "ptr", win.Hwnd, "ptr", m)
    }
}

; Show a TitleBar window. pos = "x.. y.." or "" (centred); cw / ch = its size (96-dpi units),
; or 0 = fit the controls. AHK sizes windows as if they had the Windows frame, so the size is
; set here, then the title bar buttons go to the right edge.
ShowTitled(win, pos := "", cw := 0, ch := 0) {
    k := A_ScreenDPI / 96
    win.Show(Trim(pos " Hide " (cw ? "w" cw " h" ch : "AutoSize")))
    if cw
        nw := Round(cw * k), nh := Round(ch * k)
    else
        TitledFit(win, &nw, &nh)
    rc := Buffer(16)
    DllCall("GetWindowRect", "ptr", win.Hwnd, "ptr", rc)
    wx := NumGet(rc, 0, "int"), wy := NumGet(rc, 4, "int")
    if pos = "" {                                               ; AHK centred its own size: centre ours
        wx += (NumGet(rc, 8, "int") - wx - nw) // 2
        wy += (NumGet(rc, 12, "int") - wy - nh) // 2
    }
    TitlePlace(win, nw)
    ; Size, place and show in one step. (win.Show() here would size the window again as if it
    ; had the Windows frame: that left empty space at the bottom and right.)
    DllCall("SetWindowPos", "ptr", win.Hwnd, "ptr", 0, "int", wx, "int", wy, "int", nw, "int", nh, "uint", 0x44)   ; NOZORDER | SHOWWINDOW
    DllCall("SetForegroundWindow", "ptr", win.Hwnd)
}

; Fit a TitleBar window to its controls again (a box was shown or hidden), keeping its place.
SizeTitled(win) {
    TitledFit(win, &nw, &nh)
    DllCall("SetWindowPos", "ptr", win.Hwnd, "ptr", 0, "int", 0, "int", 0, "int", nw, "int", nh, "uint", 0x16)
    TitlePlace(win, nw)
}

; The size that fits the visible controls, with the left margin on the right and at the bottom.
TitledFit(win, &nw, &nh) {
    tb := TITLED.Has(win.Hwnd) ? TITLED[win.Hwnd] : 0
    skip := Map()
    if tb {
        for b in tb.btns
            skip[b.Hwnd] := 1
        skip[tb.text.Hwnd] := 1
        if tb.icon
            skip[tb.icon.Hwnd] := 1
    }
    minX := 99999, maxR := 0, maxB := 0
    for hwnd, c in win {
        if skip.Has(hwnd) || SCROLLS.Has(hwnd) || !(DllCall("GetWindowLong", "ptr", hwnd, "int", -16, "int") & 0x10000000)   ; WS_VISIBLE
            continue
        c.GetPos(&cx, &cy, &cw, &ch)
        minX := Min(minX, cx), maxR := Max(maxR, cx + cw), maxB := Max(maxB, cy + ch)
    }
    pad := minX = 99999 ? 0 : minX
    nw := maxR + pad, nh := maxB + pad
}

; Fixed-size windows: the title bar buttons at the right edge, the title up to them.
TitlePlace(win, nw) {
    if !TITLED.Has(win.Hwnd) || TITLED[win.Hwnd].resize
        return
    tb := TITLED[win.Hwnd]
    k := A_ScreenDPI / 96, bw := Round(46 * k)
    for i, b in tb.btns
        DllCall("SetWindowPos", "ptr", b.Hwnd, "ptr", 0, "int", nw - (tb.btns.Length - i + 1) * bw, "int", 0, "int", 0, "int", 0, "uint", 0x15)
    tb.text.GetPos(&tx)
    DllCall("SetWindowPos", "ptr", tb.text.Hwnd, "ptr", 0, "int", 0, "int", 0, "int", Max(10, nw - tx - tb.btns.Length * bw - Round(8 * k)), "int", Round(TB_H * k), "uint", 0x16)
}

TitleBtnDraw(b, hot := false) {
    t := ThemeColors()
    k := A_ScreenDPI / 96
    w := b.px / k, h := b.py / k, cx := Round(w / 2), cy := Round(h / 2)
    cv := Gp_Canvas(b.px, b.py, t.bg, true)
    close := b.kind = "close"
    if hot
        Gp_Rect(cv, 0, 0, w, h, close ? "C42B1C" : t.btnHot)
    ic := hot && close ? "FFFFFF" : t.fg
    switch b.kind {
        case "min":
            Gp_Line(cv, cx - 5, cy, cx + 5, cy, ic, 1)
        case "max":
            if DllCall("IsZoomed", "ptr", b.win) {             ; maximised: two windows = restore
                GpBox(cv, cx - 5, cy - 3, 8, 8, ic)
                Gp_Line(cv, cx - 3, cy - 5, cx + 5, cy - 5, ic, 1)
                Gp_Line(cv, cx + 5, cy - 5, cx + 5, cy + 3, ic, 1)
            } else
                GpBox(cv, cx - 5, cy - 5, 10, 10, ic)
        default:
            Gp_Line(cv, cx - 5, cy - 5, cx + 5, cy + 5, ic, 1)
            Gp_Line(cv, cx + 5, cy - 5, cx - 5, cy + 5, ic, 1)
    }
    SetBitmap(b, Gp_Done(cv))
}

GpBox(cv, x, y, w, h, hex) {
    Gp_Line(cv, x, y, x + w, y, hex, 1), Gp_Line(cv, x + w, y, x + w, y + h, hex, 1)
    Gp_Line(cv, x + w, y + h, x, y + h, hex, 1), Gp_Line(cv, x, y + h, x, y, hex, 1)
}

; The title bar buttons do what Windows' own do (WM_SYSCOMMAND), so the window's Close event runs.
TitleBtnClick(b, *) {
    h := b.win
    switch b.kind {
        case "min": PostMessage(0x112, 0xF020, 0, , "ahk_id " h)                                    ; SC_MINIMIZE
        case "max": PostMessage(0x112, DllCall("IsZoomed", "ptr", h) ? 0xF120 : 0xF030, 0, , "ahk_id " h)   ; SC_RESTORE / SC_MAXIMIZE
        default:    PostMessage(0x112, 0xF060, 0, , "ahk_id " h)                                    ; SC_CLOSE
    }
}

; WM_NCCALCSIZE: the whole window is ours (no Windows frame or title bar). Maximised, Windows
; puts the frame edges off screen, so the content is pulled in by that much.
TitledNcCalc(wParam, lParam, msg, hwnd) {
    if !wParam || !TITLED.Has(hwnd)
        return
    if DllCall("IsZoomed", "ptr", hwnd) {
        pad := DllCall("GetSystemMetrics", "int", 92)          ; SM_CXPADDEDBORDER
        fx := DllCall("GetSystemMetrics", "int", 32) + pad, fy := DllCall("GetSystemMetrics", "int", 33) + pad
        NumPut("int", NumGet(lParam, 0, "int") + fx, "int", NumGet(lParam, 4, "int") + fy
             , "int", NumGet(lParam, 8, "int") - fx, "int", NumGet(lParam, 12, "int") - fy, lParam)
    }
    return 0
}

; WM_NCHITTEST: our title bar acts as Windows' title bar; the edges resize (resizable windows).
TitledHitTest(wParam, lParam, msg, hwnd) {
    if !TITLED.Has(hwnd)
        return
    x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
    x := x > 32767 ? x - 65536 : x, y := y > 32767 ? y - 65536 : y
    rc := Buffer(16)
    DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
    rx := x - NumGet(rc, 0, "int"), ry := y - NumGet(rc, 4, "int")
    ww := NumGet(rc, 8, "int") - NumGet(rc, 0, "int"), wh := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
    k := A_ScreenDPI / 96
    if TITLED[hwnd].resize && !DllCall("IsZoomed", "ptr", hwnd) {
        e := Round(6 * k)
        l := rx < e, r := rx >= ww - e, t := ry < e, bt := ry >= wh - e
        if t && l
            return 13                                            ; HTTOPLEFT
        if t && r
            return 14                                            ; HTTOPRIGHT
        if bt && l
            return 16                                            ; HTBOTTOMLEFT
        if bt && r
            return 17                                            ; HTBOTTOMRIGHT
        if l
            return 10                                            ; HTLEFT
        if r
            return 11                                            ; HTRIGHT
        if t
            return 12                                            ; HTTOP
        if bt
            return 15                                            ; HTBOTTOM
    }
    if ry < Round(TB_H * k)
        return 2                                                 ; HTCAPTION
}

; A number box shaped like a pill: our drawn pill with a borderless one-line box in its middle.
; Clicking the pill's ends puts the cursor in the box.
PillBox(win, x, y, w, h, value) {
    pill := BoxFrame(win, x, y, w, h, "pill")
    e := win.AddEdit("x" (x + 10) " y" y " w" (w - 20) " r1 Number Center Limit9 -E0x200", value)
    e.pill := pill
    FitInFrame(win, e, pill, h / 2)
    return e
}

; A rounded box drawn behind a borderless text box: a 1 px outline and the text-box colour.
; r: corner radius, or "pill" for fully round ends. On glass it is mixed into the glass the
; way Windows paints the text box itself, so both are the same colour.
BoxFrame(win, x, y, w, h, r := 8) {
    f := win.AddText("x" x " y" y " w" w " h" h " +0xD +0x100", "")
    f.GetPos(, , &pw, &ph)
    f.px := pw, f.py := ph, f.r := r
    f.drawFn := BoxFrameDraw
    BoxFrameDraw(f)
    return f
}

BoxFrameDraw(f, hot := false) {
    t := ThemeColors()
    cv := Gp_Canvas(f.px, f.py, t.bg, true)
    k := cv.k, w := f.px / k, h := f.py / k
    bw := Round(k) / k                                          ; 1 pixel
    r := f.r = "pill" ? h / 2 : f.r
    Gp_Round(cv, 0, 0, w, h, r, t.HasOwnProp("edge") ? t.edge : t.line)
    Gp_Round(cv, bw, bw, w - 2 * bw, h - 2 * bw, r - bw, t.field)
    SetBitmap(f, Gp_Done(cv, GlassOn() && t.dark))              ; (light glass: solid, like the layered box)
}

; Puts a text box inside its frame, padX (96-dpi units) in from the sides. padY < 0: one line of
; text high, in the middle (measured from the real font); otherwise padY in from top and bottom.
; Clicking the frame puts the cursor in the box.
FitInFrame(win, e, f, padX, padY := -1) {
    k := A_ScreenDPI / 96
    rc := Buffer(16)
    DllCall("GetWindowRect", "ptr", f.Hwnd, "ptr", rc)
    DllCall("MapWindowPoints", "ptr", 0, "ptr", win.Hwnd, "ptr", rc, "uint", 2)
    l := NumGet(rc, 0, "int"), t := NumGet(rc, 4, "int"), r := NumGet(rc, 8, "int"), b := NumGet(rc, 12, "int")
    px := Round(padX * k)
    if padY < 0 {
        dc := DllCall("GetDC", "ptr", e.Hwnd, "ptr")
        old := DllCall("SelectObject", "ptr", dc, "ptr", SendMessage(0x31, 0, 0, e), "ptr")    ; WM_GETFONT
        tm := Buffer(64, 0)
        DllCall("GetTextMetrics", "ptr", dc, "ptr", tm)
        lh := NumGet(tm, 0, "int")                               ; tmHeight
        DllCall("SelectObject", "ptr", dc, "ptr", old)
        DllCall("ReleaseDC", "ptr", e.Hwnd, "ptr", dc)
        ey := t + (b - t - lh) // 2
    } else
        ey := t + Round(padY * k), lh := b - t - 2 * Round(padY * k)
    DllCall("MoveWindow", "ptr", e.Hwnd, "int", l + px, "int", ey, "int", r - l - 2 * px, "int", lh, "int", 1)
    f.OnEvent("Click", (*) => e.Focus())
}

; Closes a dialog that disabled its owner. The owner is enabled first, so Windows hands the focus
; straight back to it (closing first made Windows briefly activate another window: a flash).
EndModal(d, owner) {
    try owner.Opt("-Disabled")
    try d.Destroy()
}

; ---- Our own scroll bars ------------------------------------------------------------------
; Windows' scroll bars can't be coloured or rounded, so every scrolling box gets ours: a thin
; rounded thumb in a rounded track, in the theme's colours. The box keeps its own scroll bar
; (wheel, keys and positions stay Windows'), cut off with a window region, and ours sits in
; that strip. A timer keeps ours in step; dragging it or clicking its track scrolls the box.
; target: a list or text box, or "guide" (the Shortcuts page).
ScrollOverlay(win, target, onField := false) {
    sb := win.AddText("x0 y0 w1 h1 +0xD +0x100", "")
    if onField                                                  ; inside one of our box frames
        PICFIELD[sb.Hwnd] := 1
    sb.target := target, sb.kind := IsObject(target) ? target.Type : "guide"
    sb.info := "", sb.hot := false, sb.px := 1, sb.py := 1
    SCROLLS[sb.Hwnd] := sb
    SetTimer(ScrollTick, 50)
    return sb
}

ScrollTarget(sb) => sb.kind = "guide" ? GUIDE.hwnd : sb.target.Hwnd

; Put the scroll bar over the right edge of its box, and cut the box's own one off.
ScrollPlace(sb) {
    h := ScrollTarget(sb)
    if !h || !DllCall("IsWindow", "ptr", h)
        return
    rc := Buffer(16)
    DllCall("GetWindowRect", "ptr", h, "ptr", rc)
    DllCall("MapWindowPoints", "ptr", 0, "ptr", DllCall("GetParent", "ptr", sb.Hwnd, "ptr"), "ptr", rc, "uint", 2)
    l := NumGet(rc, 0, "int"), t := NumGet(rc, 4, "int"), r := NumGet(rc, 8, "int"), b := NumGet(rc, 12, "int")
    w := DllCall("GetSystemMetrics", "int", 2)                  ; SM_CXVSCROLL: the width of Windows' bar
    DllCall("SetWindowPos", "ptr", sb.Hwnd, "ptr", 0, "int", r - w, "int", t, "int", w, "int", b - t, "uint", 0x10)   ; on top
    d := Round(14 * A_ScreenDPI / 96)                           ; round corners, like the buttons
    DllCall("SetWindowRgn", "ptr", h, "ptr", DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", r - l - w + 1, "int", b - t + 1
        , "int", d, "int", d, "ptr"), "int", 1)
    sb.px := w, sb.py := b - t, sb.info := ""
    ScrollDraw(sb)
}

; Where the box is scrolled: {ok, mn, mx, pg, pos}. ok = there is something to scroll.
ScrollState(h) {
    si := Buffer(28, 0)
    NumPut("uint", 28, "uint", 0x17, si)                        ; SIF_ALL
    got := h && DllCall("GetScrollInfo", "ptr", h, "int", 1, "ptr", si)
    s := {mn: NumGet(si, 8, "int"), mx: NumGet(si, 12, "int"), pg: NumGet(si, 16, "uint"), pos: NumGet(si, 20, "int")}
    s.ok := got && s.pg > 0 && s.mx - s.mn + 1 > s.pg
    return s
}

; The thumb in pixels: top, height, track top and track length.
ScrollGeom(sb, s) {
    k := A_ScreenDPI / 96, pad := Round(2 * k)
    len := sb.py - 2 * pad, rng := s.mx - s.mn + 1
    th := Max(Round(24 * k), Round(len * s.pg / rng))
    ty := pad + Round((len - th) * (s.pos - s.mn) / Max(1, rng - s.pg))
    return {ty: ty, th: th, pad: pad, len: len}
}

ScrollDraw(sb) {
    s := ScrollState(ScrollTarget(sb))
    t := ThemeColors()
    key := s.ok "|" s.mn "|" s.mx "|" s.pg "|" s.pos "|" sb.hot "|" sb.px "x" sb.py "|" t.bg t.field
    if key = sb.info
        return
    sb.info := key
    k := A_ScreenDPI / 96
    cv := Gp_Canvas(sb.px, sb.py, t.bg, true)
    if PICFIELD.Has(sb.Hwnd) && t.HasOwnProp("key")             ; light glass, inside a box: solid like the box
        Gp_Rect(cv, 0, 0, sb.px / k, sb.py / k, t.field)
    if s.ok {
        gm := ScrollGeom(sb, s)
        bw := 6, x := (sb.px / k - bw) / 2
        Gp_Round(cv, x, gm.pad / k, bw, gm.len / k, bw / 2, t.dark ? t.field : "E6E6E6")             ; track
        thumb := t.dark ? (sb.hot ? "9A9DAA" : "6A6D7A") : (sb.hot ? "6E6E6E" : "A6A6A6")
        Gp_Round(cv, x, gm.ty / k, bw, gm.th / k, bw / 2, thumb)                                       ; thumb
    }
    SetBitmap(sb, Gp_Done(cv))
}

; Keeps every visible scroll bar in step with its box (and lighter under the mouse).
ScrollTick() {
    if !SCROLLS.Count {
        SetTimer(ScrollTick, 0)
        return
    }
    MouseGetPos(, , , &over, 2)
    for hw, sb in SCROLLS.Clone() {
        if !DllCall("IsWindow", "ptr", hw) {
            SCROLLS.Delete(hw)
            continue
        }
        if !DllCall("IsWindowVisible", "ptr", hw)
            continue
        sb.hot := over = hw
        ScrollDraw(sb)
    }
}

; Mouse down on one of our scroll bars: drag the thumb (or, on the track, jump there and drag).
ScrollDown(wParam, lParam, msg, hwnd) {
    if !SCROLLS.Has(hwnd)
        return
    sb := SCROLLS[hwnd], h := ScrollTarget(sb)
    s := ScrollState(h)
    if !s.ok
        return 0
    gm := ScrollGeom(sb, s)
    my := (lParam >> 16) & 0xFFFF
    grab := my >= gm.ty && my < gm.ty + gm.th ? my - gm.ty : gm.th // 2
    pt := Buffer(8)
    while GetKeyState("LButton", "P") {
        DllCall("GetCursorPos", "ptr", pt)
        DllCall("ScreenToClient", "ptr", hwnd, "ptr", pt)
        frac := Min(1, Max(0, (NumGet(pt, 4, "int") - grab - gm.pad) / Max(1, gm.len - gm.th)))
        ScrollTo(sb, h, s.mn + Round(frac * (s.mx - s.mn + 1 - s.pg)))
        sb.hot := true
        ScrollDraw(sb)
        Sleep 10
    }
    return 0
}

; The wheel over one of our scroll bars scrolls its box (Windows sends it to the bar itself).
ScrollWheel(wParam, lParam, msg, hwnd) {
    if !SCROLLS.Count
        return
    x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
    x := x >= 0x8000 ? x - 0x10000 : x, y := y >= 0x8000 ? y - 0x10000 : y
    over := DllCall("WindowFromPoint", "int64", (y << 32) | (x & 0xFFFFFFFF), "ptr")
    if !SCROLLS.Has(over)
        return
    sb := SCROLLS[over]
    if sb.kind = "guide" {
        delta := (wParam >> 16) & 0xFFFF
        delta := delta >= 0x8000 ? delta - 0x10000 : delta
        GuideScroll(-delta / 120 * Round(20 * A_ScreenDPI / 96) * 3)
    } else
        PostMessage(0x20A, wParam, lParam, , "ahk_id " ScrollTarget(sb))
    sb.info := ""                                               ; redraw at the new place
    return 0
}

ScrollTo(sb, h, newPos) {
    cur := ScrollState(h).pos
    if newPos = cur
        return
    switch sb.kind {
        case "guide":
            GuideScroll(newPos - GUIDE.pos)
        case "ListView":                                        ; scrolled in pixels: rows x row height
            rc := Buffer(16, 0)
            SendMessage(0x100E, 0, rc.Ptr, h)                   ; LVM_GETITEMRECT (row 0, LVIR_BOUNDS)
            ih := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
            if ih > 0
                SendMessage(0x1014, 0, (newPos - cur) * ih, h)  ; LVM_SCROLL
        default:                                                ; a text box: lines
            SendMessage(0xB6, 0, newPos - cur, h)               ; EM_LINESCROLL
    }
}

; ---- Release notes: a pop-up over the settings window, no title bar, Close or Esc ----------
ShowNotes(owner) {
    md := ChangelogText()
    text := md = "" ? "The release notes aren't included in this copy of the app.`nThey are on GitHub (GitHub repo button)."
                    : StrReplace(NotesText(RegExReplace(md, "^\s*#\s+Changelog\s*")), Chr(96))   ; no `code` marks
    k := A_ScreenDPI / 96
    d := Gui("-Caption +Owner" owner.Hwnd (VerCompare(A_OSVersion, "10.0.22000") < 0 ? " +Border" : ""))
    hw := d.Hwnd
    POPUPS[hw] := 1
    d.SetFont("s12 bold", "Segoe UI")
    d.AddText("x24 y20 w512", "What's new")
    d.SetFont("s9 norm", "Segoe UI")
    ed := d.AddEdit("x24 y56 w512 h336 ReadOnly Multi VScroll -E0x200", text)
    edSb := ScrollOverlay(d, ed)
    SendMessage(0xD3, 3, Round(10 * k) | (Round(10 * k) << 16), ed)   ; EM_SETMARGINS: room at the left and right
    AddBtn(d, "x436 y410 w100 h30", "Close").OnEvent("Click", (*) => EndModal(d, owner))
    d.OnEvent("Escape", (*) => EndModal(d, owner))
    ApplyTheme(d)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hw, "int", 33, "int*", 2, "int", 4)   ; Windows 11: round corners
    rc := Buffer(16)                                            ; centred on the settings window
    DllCall("GetWindowRect", "ptr", owner.Hwnd, "ptr", rc)
    x := (NumGet(rc, 0, "int") + NumGet(rc, 8, "int") - Round(560 * k)) // 2
    y := (NumGet(rc, 4, "int") + NumGet(rc, 12, "int") - Round(462 * k)) // 2
    owner.Opt("+Disabled")                                      ; stays put over the app until closed
    d.Show("x" x " y" y " w560 h462")
    ScrollPlace(edSb)                                           ; our scroll bar; rounds the box too
    SendMessage(0xB1, 0, 0, ed)                                 ; EM_SETSEL: nothing selected
    WinWaitClose("ahk_id " hw)
    owner.Opt("-Disabled")
    try POPUPS.Delete(hw)
}

; CHANGELOG.md: embedded in the exe (resource CHANGELOG), next to the script otherwise.
ChangelogText() {
    if !A_IsCompiled
        return FileExist(A_ScriptDir "\CHANGELOG.md") ? FileRead(A_ScriptDir "\CHANGELOG.md", "UTF-8") : ""
    try {
        hr := DllCall("FindResource", "ptr", 0, "str", "CHANGELOG", "ptr", 10, "ptr")   ; RT_RCDATA
        if !hr
            return ""
        sz := DllCall("SizeofResource", "ptr", 0, "ptr", hr, "uint")
        p := DllCall("LockResource", "ptr", DllCall("LoadResource", "ptr", 0, "ptr", hr, "ptr"), "ptr")
        return p ? StrGet(p, sz, "UTF-8") : ""
    }
    return ""
}

; A drop-down drawn like our buttons: the chosen item and a ˅; a click opens a menu of the items.
; .sel = the chosen item's number.
DropBtn(win, opts, items, sel) {
    b := AddBtn(win, opts, items[sel])
    b.items := items, b.sel := sel
    BtnRender(b, false)                                        ; again, now with the ˅
    b.OnEvent("Click", DropBtnMenu)
    return b
}

DropBtnMenu(b, *) {
    items := []
    for i, name in b.items
        items.Push({text: name, fn: DropBtnPick.Bind(b, i), check: i = b.sel})
    rc := Buffer(16)                                           ; opens below the drop-down, at its right end
    DllCall("GetWindowRect", "ptr", b.Hwnd, "ptr", rc)
    PopMenu(b, items, NumGet(rc, 8, "int") - Round(176 * A_ScreenDPI / 96), NumGet(rc, 12, "int") + Round(4 * A_ScreenDPI / 96))
}

; A menu in the app's own style (Windows' menus can't be rounded or coloured to match): a small
; frameless window with the items drawn like our buttons, on glass when the glass is on.
; Closes on a pick, Esc, or a click anywhere else. items: {text, fn, check} or "-" for a line.
PopMenu(ctrl, items, x, y) {
    k := A_ScreenDPI / 96
    owner := DllCall("GetAncestor", "ptr", ctrl.Hwnd, "uint", 2, "ptr")       ; GA_ROOT
    m := Gui("-Caption +ToolWindow +AlwaysOnTop +Owner" owner (VerCompare(A_OSVersion, "10.0.22000") < 0 ? " +Border" : ""))
    m.MarginX := 0, m.MarginY := 0
    mh := m.Hwnd                                                ; kept: m.Hwnd can't be read once it's closed
    POPUPS[mh] := 1
    W := 176, iy := 6
    for it in items {
        if !IsObject(it) {                                      ; "-": a thin line
            sp := m.AddText("x12 y" (iy + 3) " w" (W - 24) " h1"), sp.role := "line"
            iy += 8
            continue
        }
        b := m.AddText("x6 y" iy " w" (W - 12) " h26 +0xD +0x100", "")
        b.GetPos(, , &pw, &ph)
        b.px := pw, b.py := ph, b.dis := false, b.itemText := it.text, b.check := it.HasOwnProp("check") && it.check
        b.drawFn := MenuItemDraw
        BTN[b.Hwnd] := b                                        ; lighter under the mouse
        b.OnEvent("Click", Pick.Bind(it.fn))
        MenuItemDraw(b)
        iy += 27
    }
    H := iy + 5
    m.OnEvent("Escape", (*) => Close())
    ApplyTheme(m)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", m.Hwnd, "int", 33, "int*", 2, "int", 4)   ; Windows 11: round corners
    MonitorGetWorkArea(MonitorFromPt(x, y), &ml, &mt, &mr, &mb)  ; stay on the screen
    x := Max(ml, Min(x, mr - Round(W * k))), y := Max(mt, Min(y, mb - Round(H * k)))
    m.Show("x" x " y" y " w" W " h" H)
    SetTimer(BtnHoverTick, 40)
    SetTimer(Watch, 60)

    Watch() {                                                   ; another window took over: close
        if !DllCall("IsWindow", "ptr", mh) {
            SetTimer(Watch, 0)
            return
        }
        if DllCall("GetForegroundWindow", "ptr") != mh
            Close()
    }
    Pick(fn, *) {
        Close()
        fn.Call()
    }
    Close() {                                                   ; forget its items, then close
        SetTimer(Watch, 0)
        if !DllCall("IsWindow", "ptr", mh)
            return
        for hw, c in m
            try BTN.Delete(hw)
        try POPUPS.Delete(mh)
        try m.Destroy()
    }
}

; The monitor number at a screen point (for MonitorGetWorkArea).
MonitorFromPt(x, y) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if x >= l && x < r && y >= t && y < b
            return A_Index
    }
    return MonitorGetPrimary()
}

MenuItemDraw(b, hot := false) {
    t := ThemeColors()
    k := A_ScreenDPI / 96
    w := b.px / k, h := b.py / k
    cv := Gp_Canvas(b.px, b.py, t.bg, true)
    if hot
        Gp_Round(cv, 0, 0, w, h, 6, t.btnHot)
    if b.check {                                               ; ✓ for the chosen item
        Gp_Line(cv, 10, h / 2, 14, h / 2 + 4, t.accent, 1.6)
        Gp_Line(cv, 14, h / 2 + 4, 21, h / 2 - 4, t.accent, 1.6)
    }
    Gp_Text(cv, b.itemText, 30, 0, w - 36, h, t.fg, 12, false, 0, hot ? 5 : 3)
    SetBitmap(b, Gp_Done(cv))
}

DropBtnPick(b, i, *) {
    b.sel := i
    b.Text := b.items[i]
}

BtnDisable(b) {
    b.Enabled := false
    b.dis := true
    BtnRender(b, false)
}

; The button under the mouse is drawn lighter.
BtnHoverTick() {
    global BTN_HOT
    MouseGetPos(, , , &h, 2)
    if !h || !BTN.Has(h) || !DllCall("IsWindowEnabled", "ptr", h)
        h := 0
    if h = BTN_HOT
        return
    if BTN_HOT && BTN.Has(BTN_HOT)
        try BtnRender(BTN[BTN_HOT], false)
    BTN_HOT := h
    if h
        try BtnRender(BTN[h], true)
}

; The mouse with its side buttons, drawn for the Mouse & keys page. The whole picture
; (labels + mouse) is centred in its 300-wide box.
MouseArt(win, x, y) {
    pic := win.AddText("x" x " y" y " w300 h200 +0xD", "")
    pic.GetPos(, , &pw, &ph)
    pic.px := pw, pic.py := ph
    pic.drawFn := MouseArtDraw
    MouseArtDraw(pic)
    return pic
}

MouseArtDraw(pic, hot := false) {
    t := ThemeColors()
    cv := Gp_Canvas(pic.px, pic.py, t.bg, true)
    ac := t.accent, fg := t.fg, mu := t.muted
    if pic.HasOwnProp("dis") && pic.dis                        ; section switched off: greyed
        ac := t.dark ? "4A4D58" : "C2C2C2", fg := mu := t.dark ? "5C5F6B" : "B4B4B4"
    mx := 174                                                  ; left edge of the mouse body
    Gp_Round(cv, mx - 1, 7, 94, 152, 47, t.line)               ; body (with a thin edge)
    Gp_Round(cv, mx, 8, 92, 150, 46, t.btn)
    gap := t.HasOwnProp("key") ? t.line : t.bg                 ; (light glass: bg is black = clear glass)
    Gp_Line(cv, mx + 46, 8, mx + 46, 74, gap, 2)               ; gap between the two main buttons
    Gp_Line(cv, mx + 2, 74, mx + 90, 74, gap, 2)
    Gp_Round(cv, mx + 39, 24, 14, 28, 7, ac)             ; wheel
    Gp_Round(cv, mx - 7, 84, 10, 26, 4, ac)              ; forward button
    Gp_Round(cv, mx - 7, 116, 10, 26, 4, ac)             ; back button
    Gp_Line(cv, mx - 20, 97, mx - 9, 97, ac, 1.5)
    Gp_Line(cv, mx - 20, 129, mx - 9, 129, ac, 1.5)
    Gp_Text(cv, "Forward  ›  Redo", mx - 142, 85, 120, 24, fg, 12, true, 2)
    Gp_Text(cv, "Back  ›  Undo", mx - 142, 117, 120, 24, fg, 12, true, 2)
    Gp_Text(cv, "Both together  ›  Enter", 0, 174, 300, 22, mu, 12, false, 1)
    SetBitmap(pic, Gp_Done(cv))
}

; ---- Theme cards (Settings > General): a rounded square with an icon, the name under it ----
ThemeCard(win, x, y, key, label, onPick) {
    pic := win.AddText("x" x " y" y " w96 h80 +0xD +0x100", "")
    pic.GetPos(, , &pw, &ph)
    pic.px := pw, pic.py := ph, pic.key := key, pic.dis := false
    pic.drawFn := ThemeCardDraw
    BTN[pic.Hwnd] := pic                                       ; lighter under the mouse, like buttons
    SetTimer(BtnHoverTick, 40)
    pic.OnEvent("Click", (*) => onPick(key))
    win.AddText("x" x " y" (y + 84) " w96 Center", label)
    ThemeCardDraw(pic)
    return pic
}

ThemeCardDraw(b, hot := false) {
    t := ThemeColors()
    k := A_ScreenDPI / 96
    w := b.px / k, h := b.py / k, cx := w / 2, cy := h / 2
    sel := cfg.theme = b.key
    fill := hot ? t.btnHot : t.btn
    ic := sel ? t.accent : t.fg
    cv := Gp_Canvas(b.px, b.py, t.bg, true)
    if sel {                                                   ; chosen: accent frame
        bw := Round(2 * cv.k) / cv.k                          ; frame = whole pixels, same on every side
        Gp_Round(cv, 0, 0, w, h, 12, t.accent)
        Gp_Round(cv, bw, bw, w - 2 * bw, h - 2 * bw, 12 - bw, fill)
    } else if t.HasOwnProp("glass") {                          ; glass: thin outline
        bw := Round(cv.k) / cv.k
        Gp_Round(cv, 0, 0, w, h, 12, t.edge)
        Gp_Round(cv, bw, bw, w - 2 * bw, h - 2 * bw, 12 - bw, fill)
    } else
        Gp_Round(cv, 0, 0, w, h, 12, fill)
    switch b.key {
        case "light":                                          ; sun
            Gp_Round(cv, cx - 9, cy - 9, 18, 18, 9, ic)
            Loop 8 {
                a := (A_Index - 1) * 3.14159265 / 4
                Gp_Line(cv, cx + 13 * Cos(a), cy + 13 * Sin(a), cx + 19 * Cos(a), cy + 19 * Sin(a), ic, 2.2)
            }
        case "dark":                                           ; crescent moon
            Gp_Round(cv, cx - 14, cy - 14, 28, 28, 14, ic)
            Gp_Round(cv, cx - 6, cy - 19, 28, 28, 14, fill)
        default:                                               ; auto: a screen, half light half dark
            Gp_Round(cv, cx - 22, cy - 17, 44, 30, 5, ic)
            Gp_Round(cv, cx - 19, cy - 14, 38, 24, 3, fill)
            Gp_Round(cv, cx - 19, cy - 14, 19, 24, 3, ic)
            Gp_Line(cv, cx, cy + 13, cx, cy + 19, ic, 2.5)
            Gp_Line(cv, cx - 10, cy + 20, cx + 10, cy + 20, ic, 2.5)
    }
    SetBitmap(b, Gp_Done(cv))
}

; ---- A toggle switch (a pill with a knob) and its label; the label clicks it too ----
; getOn() / canUse() are asked every time it is drawn; when canUse() is false it is grey,
; shows labelOff and ignores clicks (Frosted glass on the light theme).
ToggleSwitch(win, x, y, getOn, canUse, label, labelOff, onFlip) {
    pic := win.AddText("x" x " y" y " w40 h20 +0xD +0x100", "")
    pic.GetPos(, , &pw, &ph)
    pic.px := pw, pic.py := ph, pic.dis := false
    pic.getOn := getOn, pic.canUse := canUse, pic.label := label, pic.labelOff := labelOff
    pic.lbl := win.AddText("x" (x + 50) " y" (y + 2) " w340 +0x100", label)
    pic.drawFn := ToggleSwitchDraw
    BTN[pic.Hwnd] := pic                                       ; lighter under the mouse, like buttons
    SetTimer(BtnHoverTick, 40)
    flip := (*) => canUse() ? (onFlip(!getOn()), ToggleSwitchDraw(pic)) : 0
    pic.OnEvent("Click", flip)
    pic.lbl.OnEvent("Click", flip)
    ToggleSwitchDraw(pic)
    return pic
}

ToggleSwitchDraw(b, hot := false) {
    t := ThemeColors()
    k := A_ScreenDPI / 96
    w := b.px / k, h := b.py / k
    use := b.canUse.Call()
    on := use && b.getOn.Call()
    cv := Gp_Canvas(b.px, b.py, t.bg, true)
    if on {                                                    ; on: accent pill, knob on the right
        Gp_Round(cv, 0, 0, w, h, h / 2, hot ? t.priHot : t.pri)
        Gp_Round(cv, w - h + 4, 4, h - 8, h - 8, (h - 8) / 2, t.priText)
    } else {                                                   ; off: outlined pill, knob on the left
        edge := use ? (hot ? t.fg : t.muted) : t.line
        Gp_Round(cv, 0, 0, w, h, h / 2, edge)
        Gp_Round(cv, 1.5, 1.5, w - 3, h - 3, h / 2 - 1.5, t.field)
        Gp_Round(cv, 5, 5, h - 10, h - 10, (h - 10) / 2, edge)
    }
    SetBitmap(b, Gp_Done(cv))
    try {
        b.lbl.Text := use ? b.label : b.labelOff
        b.lbl.role := use ? "" : "muted"                       ; ApplyTheme keeps this colour
        b.lbl.SetFont("c" (use ? t.fg : t.muted))
    }
}

; The settings window's own icons: the small one (title bar) follows the app theme, the big one
; (taskbar) follows the Windows theme.
SetWindowIcons(win) {
    sysLight := 1
    try sysLight := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme")
    small := LoadAppIcon(IsDarkTheme() ? "white" : "black", DllCall("GetSystemMetrics", "int", 49))
    big := LoadAppIcon(sysLight ? "black" : "white", DllCall("GetSystemMetrics", "int", 11))
    if small
        SendMessage(0x80, 0, small, win.Hwnd)                ; WM_SETICON, ICON_SMALL
    if big
        SendMessage(0x80, 1, big, win.Hwnd)                  ; ICON_BIG
}

LoadAppIcon(shade, size) {
    if A_IsCompiled {                                          ; embedded resources 300 (white) / 301 (black)
        hm := DllCall("LoadLibraryEx", "str", A_ScriptFullPath, "ptr", 0, "uint", 0x2, "ptr")
        if !hm
            return 0
        ico := DllCall("LoadImage", "ptr", hm, "ptr", shade = "white" ? 300 : 301, "uint", 1, "int", size, "int", size, "uint", 0, "ptr")
        DllCall("FreeLibrary", "ptr", hm)
        return ico
    }
    return DllCall("LoadImage", "ptr", 0, "str", A_ScriptDir "\icons\tray-" shade ".ico", "uint", 1, "int", size, "int", size, "uint", 0x10, "ptr")
}

; A list with no frame, no grid lines and no header (we draw the header ourselves).
NewList(win, opts, cols, anchorFlags) {
    lv := win.AddListView(opts " -Multi -Hdr -E0x200 +0x4000000", cols)   ; 0x4000000 = WS_CLIPSIBLINGS
    SendMessage(0x1036, 0x1, 0, lv)                            ; LVM_SETEXTENDEDLISTVIEWSTYLE: grid lines off
    ; Thin lines between the columns and at the end of the last one, like the dark list theme
    ; draws (Windows' own grid lines can't be coloured). FitList puts them in place; the list
    ; never paints over them (WS_CLIPSIBLINGS).
    lv.seps := []
    Loop cols.Length {
        sp := win.AddText("x0 y0 w1 h1")
        sp.role := "line"
        lv.seps.Push(sp)
    }
    lv.sb := ScrollOverlay(win, lv)                            ; our scroll bar (FitList places it)
    return Anchor(lv, anchorFlags)
}

; Column titles drawn above a list (the list's own header can't be made dark).
; cols = [[title, width], ...]; the first column starts 6 px in, like the list's text.
LvHeader(win, x, y, w, cols) {
    cx := x + 6
    for c in cols {
        t := win.AddText("x" cx " y" y " w" (c[2] - 6) " h20 +0x200", c[1])
        t.role := "head"
        cx += c[2]
    }
    l := Anchor(win.AddText("x" x " y" (y + 21) " w" w " h1"), "w")
    l.role := "line"
}

; The controls a window has now; PanelSince(win, mark) = the ones added after it (one section).
PanelMark(win) {
    m := Map()
    for hw, c in win                                           ; (two variables: one alone gets the control, not its hwnd)
        m[hw] := 1
    return m
}

PanelSince(win, mark) {
    a := []
    for hw, c in win
        if !mark.Has(hw)
            a.Push(c)
    return a
}

; A section switched off (on = false): its text greyed, its buttons, key boxes, sliders and
; number boxes greyed and not responding, its list greyed (double-click does nothing).
; Switched on: back to normal.
PanelState(ctrls, on) {
    t := ThemeColors()
    dim := t.dark ? "5C5F6B" : "B4B4B4"
    for c in ctrls {
        hw := c.Hwnd
        if SCROLLS.Has(hw)
            continue
        if BTN.Has(hw) {                                       ; our buttons, drop-downs, key boxes, ×
            c.Enabled := on, c.dis := !on
            BtnRender(c, false)
            continue
        }
        role := c.HasOwnProp("role") ? c.role : ""
        switch c.Type {
            case "Text":
                if c.HasOwnProp("drawFn") {                    ; drawn pictures (the mouse)
                    c.dis := !on
                    c.drawFn.Call(c, false)
                } else if role != "line"
                    c.SetFont("c" (on ? (role = "muted" || role = "head" ? t.muted : t.fg) : dim))
            case "Edit":                                       ; number boxes: can't be typed in
                SendMessage(0xCF, on ? 0 : 1, 0, c)            ; EM_SETREADONLY
                c.SetFont("c" (on ? t.fg : dim))
            case "Slider":
                c.Enabled := on
                RefreshSlider(hw)
            case "ListView":
                c.off := !on
                c.SetFont("c" (on ? t.fg : dim))
                DllCall("RedrawWindow", "ptr", hw, "ptr", 0, "ptr", 0, "uint", 0x0185)
        }
    }
}

; Grey hint text.
Muted(ctrl) {
    ctrl.role := "muted"
    return ctrl
}

SecHeader(win, opts, text) {
    win.SetFont("s10 bold")
    win.AddText(opts, text)
    win.SetFont("s9 norm")
}

; A check box whose label is a separate text, because themed check boxes ignore the text
; colour (black text on a dark window). Clicking the label toggles the box.
AddCheck(win, x, y, checked, label, w := 400, onChange := 0) {
    cb := win.AddCheckbox("x" x " y" (y + 1) " w16 h16 Checked" (checked ? 1 : 0))
    CHECKS[cb.Hwnd] := 1                                ; drawn by us (CheckDraw), in the accent colour
    lbl := win.AddText("x" (x + 22) " y" y " w" w, label)
    lbl.OnEvent("Click", (*) => (cb.Value := !cb.Value, onChange ? onChange() : 0))
    if onChange
        cb.OnEvent("Click", (*) => onChange())
    cb.lbl := lbl                                       ; so callers can grey the label out
    return cb
}

; =============================================================================
;  Install / start with Windows (all per-user, no admin rights)
; =============================================================================
InstalledHere() => A_IsCompiled && A_ScriptFullPath = INSTALL_EXE

StartupCmd() => (A_IsCompiled ? '"' A_ScriptFullPath '"' : '"' A_AhkPath '" "' A_ScriptFullPath '"') " /startup"

StartupOn() {
    try return RegRead(RUN_KEY, APP_NAME) != ""
    return false
}

SetStartup(on, cmd := StartupCmd()) {
    if on
        RegWrite(cmd, "REG_SZ", RUN_KEY, APP_NAME)
    else
        try RegDelete(RUN_KEY, APP_NAME)
}

; Process ids of the installed copy that are running (not this one).
InstalledRunning() {
    pids := []
    try {
        for p in ComObjGet("winmgmts:").ExecQuery("Select ProcessId, ExecutablePath from Win32_Process Where Name = '" APP_NAME ".exe'")
            if p.ProcessId != DllCall("GetCurrentProcessId") && p.ExecutablePath = INSTALL_EXE
                pids.Push(p.ProcessId)
    }
    return pids
}

; Each time the portable exe is opened, offer to install (or update) it. "Portable" just runs it.
OfferInstall() {
    r := InstallPrompt(FileExist(INSTALL_EXE))
    if r.cancel
        ExitApp
    if r.install
        return InstallApp(r.startup)
    ; Portable: don't run twice next to the installed copy (every shortcut would fire twice).
    if InstalledRunning().Length {
        MsgBox(APP_NAME " is already running.`nThis copy will close.", APP_NAME, "Iconi")
        ExitApp
    }
}

; Install from the settings window: ask first, so the startup choice is made there.
InstallFlow() {
    r := InstallPrompt(FileExist(INSTALL_EXE))
    if r.install
        InstallApp(r.startup)
}

; The Install / Portable question. Returns {install, startup}: install is true for Install (or
; Update); startup is the state of the "Start with Windows" box.
InstallPrompt(updating) {
    if updating
        return UpdatePrompt()
    res := {install: false, startup: true, cancel: false}
    d := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", APP_NAME)
    d.MarginX := 24, d.MarginY := 20
    d.SetFont("s11 bold", "Segoe UI")
    d.AddText("x24 y20 w330", updating ? "Update the installed " APP_NAME "?" : "Install " APP_NAME "?")
    d.SetFont("s9 norm", "Segoe UI")
    cb := AddCheck(d, 24, 60, updating ? StartupOn() : true, "Start with Windows", 300)
    Muted(d.AddText("x24 y90 w330", updating ? "Portable: run this copy without updating." : "Portable: run without installing."))
    b1 := AddBtn(d, "x24 y122 w130 h32", updating ? "Update" : "Install", true)
    b2 := AddBtn(d, "x+8 w130 h32", "Portable")
    b1.OnEvent("Click", (*) => (res.install := true, res.startup := cb.Value, d.Destroy()))
    b2.OnEvent("Click", (*) => d.Destroy())
    d.OnEvent("Close", (*) => (res.cancel := true, d.Destroy()))      ; the X: quit without starting
    d.OnEvent("Escape", (*) => (res.cancel := true, d.Destroy()))
    ApplyTheme(d)
    d.Show("AutoSize")
    ; While the mouse is on "Portable", "Start with Windows" is unticked and greyed out
    ; (a portable copy can't start with Windows); moving away restores it.
    st := {saved: 0, over: false}
    hb2 := b2.Hwnd
    hw := d.Hwnd                                         ; keep it: a destroyed Gui has no Hwnd any more
    SetTimer(Hover, 40)
    WinWaitClose("ahk_id " hw)
    SetTimer(Hover, 0)
    return res

    Hover() {
        if !WinExist("ahk_id " hw) {
            SetTimer(Hover, 0)
            return
        }
        MouseGetPos(, , , &h, 2)
        over := (h = hb2)
        if over = st.over
            return
        st.over := over
        t := ThemeColors()
        if over {
            st.saved := cb.Value
            cb.Value := 0
            cb.Enabled := false
            cb.lbl.SetFont("c" t.muted)
        } else {
            cb.Value := st.saved
            cb.Enabled := true
            cb.lbl.SetFont("c" t.fg)
        }
    }
}

; Already installed: Update (newer) / Re-install (same) / Replace (older), Uninstall or Cancel.
; No "Start with Windows" box here: the installed copy keeps its current setting.
UpdatePrompt() {
    res := {install: false, startup: StartupOn(), cancel: true}
    inst := ""
    try inst := RegRead(UNINSTALL_KEY, "DisplayVersion")
    if inst = ""
        try inst := FileGetVersion(INSTALL_EXE)
    c := 1
    try c := VerCompare(APP_VERSION, inst)
    if inst = ""
        q := "Update the installed " APP_NAME " to " APP_VERSION "?", main := "Update"
    else if c > 0
        q := "Update " APP_NAME " " inst " to " APP_VERSION "?", main := "Update"
    else if c = 0
        q := APP_NAME " " APP_VERSION " is already installed.", main := "Re-install"
    else
        q := "This is an older version (" APP_VERSION ").`nThe installed " APP_NAME " is newer (" inst ").`nDowngrade to " APP_VERSION "?", main := "Downgrade"
    r := AppDialog(q, [main, "Uninstall", "Cancel"])
    if r = main
        res.install := true, res.cancel := false
    else if r = "Uninstall"
        try Run('"' INSTALL_EXE '" /uninstall')
    return res
}

; Desktop + Start menu shortcuts: asked only if neither exists yet and the question was never
; answered with Yes or "Don't ask again" (so updates don't ask every time).
OfferShortcuts() {
    lnks := [A_Desktop "\" APP_NAME ".lnk", A_Programs "\" APP_NAME ".lnk"]
    if FileExist(lnks[1]) || FileExist(lnks[2]) || IniRead(INI, "State", "ShortcutsAsked", 0) = 1
        return
    st := {never: false}
    r := AppDialog("Add shortcuts to the Desktop and Start menu?", ["Yes", "No"], ""
        , {check: {label: "Don't ask again", value: false, onChange: (v) => st.never := v}})
    if r = "Yes" {
        try FileCreateShortcut(INSTALL_EXE, lnks[1], INSTALL_DIR, , APP_NAME)
        try FileCreateShortcut(INSTALL_EXE, lnks[2], INSTALL_DIR, , APP_NAME)
    }
    if r = "Yes" || st.never
        IniWrite(1, INI, "State", "ShortcutsAsked")
}

; Copy this exe to %APPDATA%\HK Master, start it with Windows, offer shortcuts, then switch to it.
InstallApp(startup := true) {
    if !A_IsCompiled || InstalledHere()
        return
    for pid in InstalledRunning()                    ; free the old exe so it can be replaced
        try ProcessClose(pid)
    DirCreate(INSTALL_DIR)
    ok := false
    Loop 10 {
        try {
            FileCopy(A_ScriptFullPath, INSTALL_EXE, 1)
            ok := true
            break
        }
        Sleep 300
    }
    if !ok {
        MsgBox("Could not install.`n" INSTALL_EXE, APP_NAME, "Icon!")
        return
    }
    SetStartup(startup, '"' INSTALL_EXE '" /startup')
    RegisterUninstall()
    OfferShortcuts()
    Run('"' INSTALL_EXE '"', INSTALL_DIR)
    ExitApp
}

; A message box in the app's own style (theme colours, rounded buttons, rounded corners).
; buttons: labels left to right; the first is the main (blue) one. Returns the label clicked,
; or "" when closed with X / Esc.
; opts (optional): check = {label, value, onChange(value)} adds a check box above the buttons;
; keepOpen = Map(label, fn): those buttons run fn and leave the dialog open.
AppDialog(text, buttons := ["OK"], title := "", opts := 0) {
    res := ""
    d := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", title = "" ? APP_NAME : title)
    d.MarginX := 24, d.MarginY := 20
    n := buttons.Length
    bw := 110
    W := Max(340, n * bw + (n - 1) * 8)
    d.SetFont("s10", "Segoe UI")
    lines := StrSplit(text, "`n").Length
    d.AddText("x24 y20 w" W " h" (lines * 20), text)
    d.SetFont("s9", "Segoe UI")
    y := 20 + lines * 20 + 18
    if opts && opts.HasOwnProp("check") {
        ck := opts.check
        cb := AddCheck(d, 24, y, ck.value, ck.label, W - 30, (*) => ck.onChange.Call(cb.Value))
        y += 34
    }
    x := 24 + W - n * bw - (n - 1) * 8                 ; right-aligned
    for i, label in buttons {
        b := AddBtn(d, (i = 1 ? "x" x " y" y : "x+8 yp") " w" bw " h30", label, i = 1)
        b.OnEvent("Click", Pick.Bind(label))
    }
    ; details = {label, text}: that button opens the text in a box under the buttons (the window grows).
    det := 0, detSb := 0
    if opts && opts.HasOwnProp("details") && opts.details.text != "" {
        det := d.AddEdit("x24 y" (y + 44) " w" W " h240 ReadOnly Multi VScroll -E0x200 Hidden", opts.details.text)
        detSb := ScrollOverlay(d, det)
        detSb.Visible := false
    }
    d.OnEvent("Close", (*) => d.Destroy())
    d.OnEvent("Escape", (*) => d.Destroy())
    TitleBar(d, title = "" ? APP_NAME : title)
    ApplyTheme(d)
    SetWindowIcons(d)
    ShowTitled(d)
    ; Rounded corners on Windows 11. Windows 10 keeps its square frame: clipping a window that has
    ; a title bar to a rounded shape showed its invisible resize border as a thick white rim.
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", d.Hwnd, "int", 33, "int*", 2, "int", 4)
    hw := d.Hwnd
    APPDLGS[hw] := d
    WinWaitClose("ahk_id " hw)
    try APPDLGS.Delete(hw)
    return res

    Pick(label, *) {
        if det && label = opts.details.label {            ; show / hide the details box
            det.Visible := !det.Visible
            detSb.Visible := det.Visible
            SizeTitled(d)
            if det.Visible
                ScrollPlace(detSb)
            return
        }
        if opts && opts.HasOwnProp("keepOpen") && opts.keepOpen.Has(label)
            return opts.keepOpen[label].Call()
        res := label
        d.Destroy()
    }
}

; Any unexpected error: write it to error-log.txt and show it once, instead of Windows' error
; box. A repeating error (from a timer or a mouse hotkey) would otherwise open a new box on every
; tick or wheel notch. The same error is shown only once per run; it is still logged (up to 50 times).
AppError(e, mode) {
    static seen := Map(), busy := false, logged := 0
    msg := "", where := ""
    try msg := Type(e) ": " e.Message (e.Extra != "" ? "  [" e.Extra "]" : "")
    try where := "line " e.Line (e.What != "" ? ", in " e.What : "")
    if logged < 50 {
        logged++
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " APP_NAME " " APP_VERSION "  " msg "  (" where ")`n"
            , DATA_DIR "\error-log.txt", "UTF-8")
    }
    key := msg "|" where
    if busy || seen.Has(key)
        return 1                                   ; already shown: skip quietly
    seen[key] := true
    busy := true
    try {
        if MsgBox(APP_NAME " hit an error and skipped it:`n`n" msg "`n(" where ")`n`nIt was saved to error-log.txt in the settings folder.`nReport it on GitHub?"
            , APP_NAME " error", "YesNo Icon! 0x40000") = "Yes"          ; 0x40000 = always on top
            OpenIssue(, "Error: " msg " (" where ")")
    }
    busy := false
    return 1                                       ; no Windows error box
}

; =============================================================================
;  Report a problem
; =============================================================================
; Fast scroll first tries the usual fixes (canvas list, real wheel input), then opens a
; prefilled GitHub issue in the browser. Nothing is sent without the user pressing Submit there.
ReportProblem(onCanvasRemoved := 0) {
    r := AppDialog("What isn't working?", ["Fast scroll", "Something else", "Cancel"], "Report a problem")
    if r = "Something else"
        return OpenIssue()
    if r != "Fast scroll"
        return
    m := Menu()
    m.Add("Which app doesn't fast scroll?", (*) => 0)
    m.Disable("Which app doesn't fast scroll?")
    m.Add()
    for exe in RunningApps()
        m.Add(exe, (name, *) => ReportScroll(name, onCanvasRemoved))
    m.Show()
}

ReportScroll(exe, onCanvasRemoved := 0) {
    tryMsg := "Try Shift + scroll in " exe " now."
    if IsCadApp(exe) {
        if AppDialog("Fast scroll is off over the drawing area`nof " exe " on purpose.`nIts panels and dialogs still glide."
            , ["Report anyway", "OK"]) = "Report anyway"
            OpenIssue(exe)
        return
    }
    if cfg.fs.canvasMap.Has(exe) {
        if AppDialog(exe ' is in your "No fast scroll" list.', ["Remove it", "Keep it"]) != "Remove it"
            return
        for i, e in cfg.fs.canvas
            if e = exe {
                cfg.fs.canvas.RemoveAt(i)
                break
            }
        cfg.fs.canvasMap.Delete(exe)
        list := ""
        for e in cfg.fs.canvas
            list .= (list = "" ? "" : ",") e
        IniWrite(list, INI, "FastScroll", "canvasApps")
        if onCanvasRemoved
            onCanvasRemoved.Call(exe)
        if AppDialog("✔  Removed.`n" tryMsg, ["It works", "Still not working"]) != "Still not working"
            return
    }
    added := false
    if !NeedsRealWheelExe(exe) {
        AddRealWheelApp(exe), added := true
        if AppDialog("Switched " exe "`nto real wheel scrolling.`n" tryMsg, ["It works", "Still not working"]) != "Still not working"
            return
        RemoveRealWheelApp(exe)                            ; didn't help: back to how it was
    }
    if AppDialog("Sorry, that didn't fix it.`nSend a bug report? It opens on GitHub`nin your browser, filled in for you to check."
        , ["Open report", "Cancel"]) = "Open report"
        OpenIssue(exe, added ? "Real wheel input tried: no change." : (NeedsRealWheelExe(exe) ? "Already uses real wheel input." : ""))
}

; Like NeedsRealWheel, for an exe name (no window needed).
NeedsRealWheelExe(exe) => InStr(exe, "Foxit") = 1 || cfg.fs.realMap.Has(exe) || exe = "WhatsApp.Root.exe"

OpenIssue(exe := "", note := "") {
    info := "- HK-Master: " APP_VERSION (A_IsCompiled ? "" : " (script)") "`n- Windows: " A_OSVersion
    if exe != "" {
        info .= "`n- App: " exe
        if FS_LASTUNDER.Has(exe)
            info .= "`n- Window under the mouse: " FS_LASTUNDER[exe]
    }
    if note != ""
        info .= "`n- " note
    title := exe != "" ? "Fast scroll doesn't work in " exe : ""
    body := (exe != "" ? "Shift + wheel doesn't scroll in this app.`n`nAnything else that helps (what you were scrolling, steps):`n`n" : "What happened, and what did you expect?`n`n")
        . "`n`n---`n" info
    Run("https://github.com/sliver301/HK-Master/issues/new?title=" UriEncode(title) "&body=" UriEncode(body))
}

UriEncode(str) {
    buf := Buffer(StrPut(str, "UTF-8"))
    StrPut(str, buf, "UTF-8")
    out := ""
    loop buf.Size - 1 {
        b := NumGet(buf, A_Index - 1, "UChar")
        out .= (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E ? Chr(b) : Format("%{:02X}", b)
    }
    return out
}

; =============================================================================
;  Updates (GitHub releases)
; =============================================================================
; "Last checked" line on the General page (if the settings window is open).
UpdateStatusText() {
    global UPD_LABEL
    last := IniRead(INI, "State", "LastUpdateCheck", "")
    txt := "Version " APP_VERSION "   ·   last checked: " (last = "" ? "never" : FormatTime(last, "d MMM yyyy, HH:mm"))
    if UPD_LABEL
        try UPD_LABEL.Text := txt
    return txt
}

; Automatic check (on unless [General] AutoUpdate=0), twice a day at 9:00 and 21:00. Runs every
; minute but only asks GitHub when the last successful check ([State] LastUpdateCheck) is older
; than the latest 9:00 / 21:00 that has passed, so a time missed while the PC was off, asleep or
; hibernating is caught up once it is back on: one check, however many were missed. Only one
; try per time: if it fails (offline), it waits for the next 9:00 / 21:00 instead of retrying,
; since a PC that is offline is probably meant to be. Just after waking it waits 30 s for the
; network to come back.
AutoUpdateCheck() {
    global UPD_TRIED
    if IniRead(INI, "General", "AutoUpdate", 1) != 1
        return
    if UPD_WAKE && A_TickCount - UPD_WAKE < 30000
        return
    slot := UpdateSlot()
    last := IniRead(INI, "State", "LastUpdateCheck", "")
    if last != "" && last >= slot
        return
    if UPD_TRIED = slot                                ; already tried for this time (and failed)
        return
    UPD_TRIED := slot
    CheckForUpdates(false)
}

; The latest 9:00 or 21:00 that has already passed, as YYYYMMDDHH24MISS.
UpdateSlot() {
    today := FormatTime(A_Now, "yyyyMMdd")
    if today "210000" <= A_Now
        return today "210000"
    if today "090000" <= A_Now
        return today "090000"
    return FormatTime(DateAdd(today "210000", -1, "Days"), "yyyyMMddHHmmss")   ; yesterday 21:00
}

; WM_POWERBROADCAST: back from sleep / hibernation (PBT_APMRESUMESUSPEND 7, PBT_APMRESUMEAUTOMATIC 18).
PowerWake(wParam, lParam, msg, hwnd) {
    global UPD_WAKE
    if wParam = 7 || wParam = 18 {
        UPD_WAKE := A_TickCount
        SetTimer(AutoUpdateCheck, -31000)
    }
}

; Asks GitHub for the latest release without freezing the shortcuts (the request runs in the
; background and a timer waits for it). manual: also say "up to date" / "could not check".
CheckForUpdates(manual := false) {
    global UPD_BUSY
    if UPD_BUSY
        return
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(5000, 5000, 5000, 10000)      ; resolve, connect, send, receive (ms)
        whr.Open("GET", UPDATE_API, true)
        whr.SetRequestHeader("User-Agent", APP_NAME)
        whr.SetRequestHeader("Accept", "application/vnd.github+json")
        whr.Send()
    } catch {
        if manual
            AppDialog("Could not check for updates.`nAre you online?")
        return
    }
    UPD_BUSY := true
    t0 := A_TickCount
    SetTimer(Poll, 250)

    Poll() {
        global UPD_BUSY
        done := false, failed := false
        try done := whr.WaitForResponse(0)
        catch
            failed := true                            ; offline / DNS failure: no need to wait it out
        if !done {
            if !failed && A_TickCount - t0 < 12000
                return
            SetTimer(Poll, 0)
            UPD_BUSY := false
            if manual
                AppDialog("Could not reach GitHub.`nAre you online?")
            return
        }
        SetTimer(Poll, 0)
        UPD_BUSY := false
        st := 0, body := ""
        try {
            st := whr.Status
            body := whr.ResponseText
        }
        if st != 200 || !RegExMatch(body, '"tag_name"\s*:\s*"v?([^"]+)"', &m) {
            if manual
                AppDialog("Could not check for updates (GitHub answered " st ").")
            return
        }
        IniWrite(A_Now, INI, "State", "LastUpdateCheck")
        UpdateStatusText()
        latest := m[1]
        newer := false
        try newer := VerCompare(latest, APP_VERSION) > 0
        if !newer {
            if manual
                AppDialog("✔  You have the latest version (" APP_VERSION ").")
            return
        }
        if !manual && IniRead(INI, "State", "SkipVersion", "") = latest
            return                                          ; the user chose "Skip Version"
        url := RegExMatch(body, '"browser_download_url"\s*:\s*"([^"]*/HK-Master[^"/]*\.exe)"', &u) ? u[1] : ""
        notes := RegExMatch(body, '"body"\s*:\s*"((?:[^"\\]++|\\.)*+)"', &nb) ? NotesText(JsonUnescape(nb[1])) : ""
        OfferUpdate(latest, url, notes)
    }
}

OfferUpdate(latest, url, notesText := "") {
    page := "https://github.com/sliver301/HK-Master/releases/tag/v" latest
    r := AppDialog("A new version is available: " latest "`nYou have " APP_VERSION "."
        , ["Update", "What's New", "Not Now", "Skip Version"], APP_NAME " update"
        , {check: {label: "Check for updates automatically", value: IniRead(INI, "General", "AutoUpdate", 1) = 1
                 , onChange: (v) => IniWrite(v ? 1 : 0, INI, "General", "AutoUpdate")}
         , details: {label: "What's New", text: notesText}           ; shown inside the window
         , keepOpen: Map("What's New", () => Run(page))})            ; no notes downloaded: open the page
    if r = "Skip Version"
        IniWrite(latest, INI, "State", "SkipVersion")       ; not offered again (Check now still shows it)
    if r != "Update"
        return                                              ; Not Now: asked again tomorrow
    if !A_IsCompiled || url = "" {                          ; running as a script: get it from the page
        Run(RELEASES_URL)
        return
    }
    DoUpdate(url, latest)
}

; A JSON string's escapes (\n, \", \u00e9...) turned back into text.
JsonUnescape(s) {
    out := "", i := 1, n := StrLen(s)
    while i <= n {
        c := SubStr(s, i, 1)
        if c != "\" || i = n {
            out .= c, i++
            continue
        }
        e := SubStr(s, i + 1, 1)
        switch e, true {
            case "n": out .= "`n"
            case "r": out .= ""
            case "t": out .= "`t"
            case "u":
                out .= Chr(Integer("0x" SubStr(s, i + 2, 4))), i += 4
            default: out .= e                      ; \" \\ \/
        }
        i += 2
    }
    return out
}

; Release notes (Markdown) as plain text for the update window: no ** or ## marks, bullets as •.
NotesText(md) {
    t := ""
    for line in StrSplit(md, "`n", "`r") {
        line := StrReplace(line, "**")
        line := RegExReplace(line, "^#+\s*")
        line := RegExReplace(line, "^\s*[-*]\s+", "•  ")
        t .= line "`r`n"
    }
    return Trim(t, "`r`n")
}

; Download the new exe to Temp, check it is a real program, then hand over to it
; (see "/update" at the top of the script): it replaces this exe and starts again.
DoUpdate(url, ver) {
    tmp := A_Temp "\HK-Master-" ver ".exe"
    TrayTip("Downloading version " ver "...", APP_NAME, "Iconi Mute")
    ok := false
    try {
        Download(url, tmp)
        f := FileOpen(tmp, "r")
        ok := f.Length > 300000 && f.ReadUShort() = 0x5A4D      ; "MZ" = a Windows program
        f.Close()
    }
    if !ok {
        try FileDelete(tmp)
        if AppDialog("The download failed.", ["Open download page", "Close"]) = "Open download page"
            Run(RELEASES_URL)
        return
    }
    FS_Stop()
    Run('"' tmp '" /update "' A_ScriptFullPath '"')
    ExitApp
}

; Adds HK-Master to Windows Settings > Apps (this user only), with an Uninstall button.
RegisterUninstall() {
    try {
        RegWrite(APP_NAME, "REG_SZ", UNINSTALL_KEY, "DisplayName")
        RegWrite(APP_VERSION, "REG_SZ", UNINSTALL_KEY, "DisplayVersion")
        RegWrite(APP_NAME, "REG_SZ", UNINSTALL_KEY, "Publisher")
        RegWrite('"' INSTALL_EXE '"', "REG_SZ", UNINSTALL_KEY, "DisplayIcon")
        RegWrite(INSTALL_DIR, "REG_SZ", UNINSTALL_KEY, "InstallLocation")
        RegWrite('"' INSTALL_EXE '" /uninstall', "REG_SZ", UNINSTALL_KEY, "UninstallString")
        RegWrite(1, "REG_DWORD", UNINSTALL_KEY, "NoModify")
        RegWrite(1, "REG_DWORD", UNINSTALL_KEY, "NoRepair")
        RegWrite(FormatTime(, "yyyyMMdd"), "REG_SZ", UNINSTALL_KEY, "InstallDate")
        RegWrite(Round(FileGetSize(INSTALL_EXE) / 1024), "REG_DWORD", UNINSTALL_KEY, "EstimatedSize")
    }
}

; Removes the installed copy: startup entry, shortcuts, Apps entry and the exe (the settings
; too, if asked). The exe can't delete itself while running, so a hidden command does it after we exit.
UninstallApp(fromWindows := false) {
    if !fromWindows && MsgBox("Uninstall " APP_NAME "?", APP_NAME, "YesNo Icon?") != "Yes"
        return
    wipe := MsgBox("Also delete your settings?", APP_NAME, "YesNo Icon? Default2") = "Yes"
    for pid in InstalledRunning()
        try ProcessClose(pid)
    try RegDelete(RUN_KEY, APP_NAME)
    try RegDelete(UNINSTALL_KEY)
    for f in [A_Desktop "\" APP_NAME ".lnk", A_Programs "\" APP_NAME ".lnk"]
        try FileDelete(f)
    cmd := wipe ? 'rmdir /s /q "' INSTALL_DIR '"' : 'del /f /q "' INSTALL_EXE '"'
    Run(A_ComSpec ' /c ping 127.0.0.1 -n 3 >nul & ' cmd, , "Hide")
    ExitApp
}

; The small "still running" note shown when the settings window is closed.
ShowTrayNotice() {
    if IniRead(INI, "General", "HideTrayNotice", 0) = 1
        return
    d := Gui("+AlwaysOnTop +ToolWindow -Caption +Border")
    d.SetFont("s9", "Segoe UI")
    d.AddText("x16 y14 w280", APP_NAME " is still running in the tray.")
    cb := AddCheck(d, 16, 46, false, "Don't show again", 180)   ; label must end before the OK button (x228)
    ok := AddBtn(d, "x228 y40 w70 h28", "OK", true)
    Done(*) {
        if cb.Value
            IniWrite(1, INI, "General", "HideTrayNotice")
        SetTimer(FadeOut, 0)
        d.Destroy()
    }
    FadeOut(*) {                                          ; after 5 s: fade away on its own
        if cb.Value
            IniWrite(1, INI, "General", "HideTrayNotice")
        try DllCall("AnimateWindow", "ptr", d.Hwnd, "uint", 500, "uint", 0x90000)    ; AW_HIDE | AW_BLEND
        d.Destroy()
    }
    ok.OnEvent("Click", Done)
    ApplyTheme(d)
    k := A_ScreenDPI / 96
    MonitorGetWorkArea(, &wl, &wt, &wr, &wb)
    d.Show("NA w314 h80 x" (wr - Round(314 * k) - 12) " y" (wb - Round(80 * k) - 12))
    ; Round corners: Windows 11 does it itself; on Windows 10 clip the window to a rounded shape.
    if DllCall("dwmapi\DwmSetWindowAttribute", "ptr", d.Hwnd, "int", 33, "int*", 2, "int", 4) != 0 {
        d.GetPos(, , &pw, &ph)
        DllCall("SetWindowRgn", "ptr", d.Hwnd, "ptr", DllCall("CreateRoundRectRgn", "int", 0, "int", 0
            , "int", pw + 1, "int", ph + 1, "int", 24, "int", 24, "ptr"), "int", true)
    }
    SetTimer(FadeOut, -5000)
}

; The window title: the name, plus (portable) when this copy is not the installed one.
AppTitle() => APP_NAME (InstalledHere() ? "" : " (portable)")

; Reload without asking to install again.
AppReload(*) {
    IniWrite(1, INI, "State", "Reloaded")
    Reload()
}

; =============================================================================
;  Key recorder
; =============================================================================
; A key box is a button that shows a shortcut ("Ctrl + Shift + Z"); a small × button next
; to it clears it. Clicking it records keys, or with withMenu also offers ready-made media /
; common keys (for keys the keyboard may not have). The value is kept in AutoHotkey Send
; syntax ("^+{z}", or a sequence like "+{m}+{f}").
KeyBox(owner, opts, value, withMenu := false) {
    b := AddBtn(owner, opts, PrettyKeys(value))
    KEYBOX_VALUES[b.Hwnd] := value
    b.OnEvent("Click", withMenu ? KeyBoxMenu : RecordKeys)
    b.clr := AddBtn(owner, "x+2 yp w26", "×")
    b.clr.OnEvent("Click", (*) => SetKeyBox(b, ""))
    return b
}

KeyBoxValue(b) => KEYBOX_VALUES.Has(b.Hwnd) ? KEYBOX_VALUES[b.Hwnd] : ""

SetKeyBox(b, value) {
    KEYBOX_VALUES[b.Hwnd] := value
    b.Text := PrettyKeys(value)
}

KeyBoxMenu(b, *) {
    cur := KeyBoxValue(b)
    items := [{text: "Record keys...", fn: (*) => RecordKeys(b)}, "-"]
    for group in [["{Volume_Up}", "{Volume_Down}", "{Volume_Mute}"]
                , ["{Media_Play_Pause}", "{Media_Next}", "{Media_Prev}", "{Media_Stop}"]
                , ["{Enter}", "{Escape}", "{Delete}", "^{z}", "^{y}", "^+{z}"]] {
        for keys in group
            items.Push({text: PrettyKeys(keys), fn: KeyBoxSetter(b, keys), check: keys = cur})
        items.Push("-")
    }
    items.Push({text: "(none)", fn: KeyBoxSetter(b, ""), check: cur = ""})
    rc := Buffer(16)                                           ; below the box, at its right end (by the ×)
    DllCall("GetWindowRect", "ptr", b.Hwnd, "ptr", rc)
    PopMenu(b, items, NumGet(rc, 8, "int") - Round(176 * A_ScreenDPI / 96), NumGet(rc, 12, "int") + Round(4 * A_ScreenDPI / 96))
}

KeyBoxSetter(b, keys) => (*) => SetKeyBox(b, keys)

; Records a key or a sequence of keys (e.g. Shift + M + F): it keeps listening until no new
; key comes for 1 second (8 s for the first key). Modifiers alone are not keys; Esc as the
; first key cancels. Held keys are counted once (auto-repeat is ignored).
RecordKeys(b, *) {
    st := {seq: "", count: 0, down: Map()}
    b.Text := "Press keys..."
    ih := InputHook("L0 T8")
    ih.KeyOpt("{All}", "NS")
    ih.KeyOpt("{LCtrl}{RCtrl}{LShift}{RShift}{LAlt}{RAlt}{LWin}{RWin}", "-N-S")
    ih.OnKeyDown := KeyDown
    ih.OnKeyUp := (hook, vk, sc) => (st.down.Has(vk) && st.down.Delete(vk))
    ih.Start()
    ih.Wait()
    if st.count
        SetKeyBox(b, st.seq)
    else
        b.Text := PrettyKeys(KeyBoxValue(b))

    KeyDown(hook, vk, sc) {
        if st.down.Has(vk)
            return
        st.down[vk] := true
        name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
        mods := (GetKeyState("Ctrl") ? "^" : "") (GetKeyState("Shift") ? "+" : "")
              . (GetKeyState("Alt") ? "!" : "") (GetKeyState("LWin") || GetKeyState("RWin") ? "#" : "")
        if name = "Escape" && mods = "" && !st.count {
            hook.Stop()
            return
        }
        st.seq .= mods "{" (StrLen(name) = 1 ? StrLower(name) : name) "}"
        st.count += 1
        b.Text := PrettyKeys(st.seq) " ..."
        hook.Timeout := 1                       ; restart: stop 1 s after the last key
    }
}

; "^+{z}" -> "Ctrl + Shift + Z", "+{m}+{f}" -> "Shift + M + F", "{Volume_Up}" -> "Volume Up".
; Keys in a row with the same modifiers are joined; a change of modifiers starts a new group.
PrettyKeys(keys) {
    if keys = ""
        return "(none)"
    static names := Map("Media_Play_Pause", "Play / Pause", "Media_Next", "Next track"
        , "Media_Prev", "Previous track", "Media_Stop", "Stop media", "Escape", "Esc"
        , "Volume_Up", "Volume Up", "Volume_Down", "Volume Down", "Volume_Mute", "Mute")
    groups := []
    lastMods := Chr(1)
    pos := 1
    while pos := RegExMatch(keys, "([\^!+#<>]*)(\{[^}]+\}|.)", &m, pos) {
        pos += m.Len
        k := m[2]
        if RegExMatch(k, "^\{(.+)\}$", &n)
            k := n[1]
        if names.Has(k)
            k := names[k]
        else if StrLen(k) = 1
            k := StrUpper(k)
        else
            k := StrReplace(k, "_", " ")
        mods := RegExReplace(m[1], "[<>]")
        if mods == lastMods {
            groups[groups.Length] .= " + " k
            continue
        }
        lastMods := mods
        label := ""
        for pair in [["^", "Ctrl"], ["+", "Shift"], ["!", "Alt"], ["#", "Win"]]
            if InStr(mods, pair[1])
                label .= pair[2] " + "
        groups.Push(label k)
    }
    out := ""
    for grp in groups
        out .= (out = "" ? "" : ", ") grp
    return out
}

; =============================================================================
;  App picker
; =============================================================================
; Pops up a menu of the apps that have a window open, plus "Browse for an .exe...".
; onPick receives the chosen exe name (e.g. "acad.exe").
ChooseApp(owner, onPick) {
    m := Menu()
    for exe in RunningApps()
        m.Add(exe, (name, *) => onPick(name))
    m.Add()
    m.Add("Browse for an .exe...", (*) => BrowseExe(owner, onPick))
    m.Show()
}

BrowseExe(owner, onPick) {
    owner.Opt("+OwnDialogs")
    path := FileSelect(3, A_ProgramFiles, "Choose the app's .exe", "Programs (*.exe)")
    if path = ""
        return
    SplitPath(path, &name)
    onPick(name)
}

; Exe names of visible, titled windows (this script and the Windows shell left out), sorted.
RunningApps() {
    seen := Map()
    seen.CaseSense := false
    me := DllCall("GetCurrentProcessId")
    for hwnd in WinGetList() {
        try {
            if WinGetPID(hwnd) = me || WinGetTitle(hwnd) = ""
                continue
            exe := WinGetProcessName(hwnd)
            if exe != "explorer.exe" && exe != "ApplicationFrameHost.exe" && exe != "TextInputHost.exe"
                seen[exe] := true
        }
    }
    out := ""
    for exe in seen
        out .= (out = "" ? "" : "`n") exe
    return out = "" ? [] : StrSplit(Sort(out, "C0"), "`n")
}

; Modal dialog for adding / editing one side-button app.
SideAppDialog(owner, e := 0) {
    res := {val: ""}
    d := Gui("+Owner" owner.Hwnd " +ToolWindow", "Side buttons for an app")
    d.SetFont("s9", "Segoe UI")
    d.AddText("x10 y14 w110", "App:")
    fApp := BoxFrame(d, 120, 10, 160, 28)                       ; rounded, in the theme colours
    eApp := d.AddEdit("x130 y14 w140 r1 -E0x200", e ? e.app : "")
    FitInFrame(d, eApp, fApp, 10)
    AddBtn(d, "x286 y10 w150", "Pick app...").OnEvent("Click", (*) => ChooseApp(d, (exe) => eApp.Value := exe))
    boxes := Map()
    for i, row in [["back", "Back"], ["fwd", "Forward"], ["both", "Both"]] {
        y := 46 + (i - 1) * 32
        d.AddText("x10 y" (y + 4) " w110", row[2])
        boxes[row[1]] := KeyBox(d, "x120 y" y " w160", e ? e.%row[1]% : "")
    }
    Muted(d.AddText("x10 y146 w430", "Click a box, press the keys. × clears."))
    AddBtn(d, "x10 y172 w80", "OK").OnEvent("Click", OkClick)
    AddBtn(d, "x+8 w80", "Cancel").OnEvent("Click", (*) => EndModal(d, owner))
    d.OnEvent("Escape", (*) => EndModal(d, owner))
    d.OnEvent("Close", (*) => EndModal(d, owner))
    hw := d.Hwnd
    TitleBar(d, "Side buttons for an app")
    ApplyTheme(d)
    owner.Opt("+Disabled")
    ShowTitled(d)
    WinWaitClose(hw)
    owner.Opt("-Disabled")
    WinActivate(owner.Hwnd)
    return res.val

    OkClick(*) {
        a := Trim(eApp.Value)
        if a = "" {
            MsgBox("Please enter the app's .exe name, or use Choose app.", "Side buttons", "Icon! Owner" hw)
            return
        }
        if a = "explorer.exe" {
            MsgBox("File Explorer can't be added: Ctrl+Z there can undo file moves and deletes.", "Side buttons", "Icon! Owner" hw)
            return
        }
        res.val := {app: a, back: KeyBoxValue(boxes["back"]), fwd: KeyBoxValue(boxes["fwd"]), both: KeyBoxValue(boxes["both"])}
        EndModal(d, owner)
    }
}

; Small modal dialog for adding / editing one text shortcut.
SnippetDialog(owner, trig := "", txt := "") {
    res := {val: ""}
    d := Gui("+Owner" owner.Hwnd " +ToolWindow", "Text shortcut")
    d.SetFont("s9", "Segoe UI")
    ; Rounded boxes in the theme colours (no Windows frame), with our scroll bar on the big one.
    d.AddText("x12 y10 w340", "You type:")
    fT := BoxFrame(d, 12, 30, 340, 30)
    eT := d.AddEdit("x22 y34 w320 r1 -E0x200", trig)
    d.AddText("x12 y72 w340", "You get:")
    fX := BoxFrame(d, 12, 92, 340, 112)
    eX := d.AddEdit("x20 y98 w324 h100 Multi WantReturn VScroll -E0x200", txt)
    eXSb := ScrollOverlay(d, eX, true)
    AddBtn(d, "x12 y218 w80", "OK").OnEvent("Click", OkClick)
    AddBtn(d, "x+8 w80", "Cancel").OnEvent("Click", (*) => EndModal(d, owner))
    d.OnEvent("Escape", (*) => EndModal(d, owner))
    d.OnEvent("Close", (*) => EndModal(d, owner))
    hw := d.Hwnd
    FitInFrame(d, eT, fT, 10)
    FitInFrame(d, eX, fX, 8, 6)
    TitleBar(d, "Text shortcut")
    ApplyTheme(d)
    owner.Opt("+Disabled")
    ShowTitled(d)
    ScrollPlace(eXSb)
    WinWaitClose(hw)
    owner.Opt("-Disabled")
    WinActivate(owner.Hwnd)
    return res.val

    OkClick(*) {
        t := Trim(eT.Value)
        if t = "" {
            MsgBox("Please enter a trigger.", "Text shortcut", "Icon! Owner" hw)
            return
        }
        res.val := {trigger: t, text: StrReplace(eX.Value, "`r`n", "`n")}
        EndModal(d, owner)
    }
}
