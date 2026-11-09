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
;@Ahk2Exe-SetVersion 2.1.0
;@Ahk2Exe-ExeName HK-Master
;@Ahk2Exe-SetMainIcon icons\app.ico
;@Ahk2Exe-AddResource icons\tray-white.ico, 300
;@Ahk2Exe-AddResource icons\tray-black.ico, 301
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
global APP_VERSION := "2.1.0"
; Started by Windows at logon (the Run entry adds /startup): stay in the tray, no window.
global STARTUP_MODE := false
for arg in A_Args
    if arg = "/startup"
        STARTUP_MODE := true
; "Uninstall" in Windows Settings > Apps starts the installed exe with /uninstall.
if A_IsCompiled && A_Args.Length && A_Args[1] = "/uninstall" {
    UninstallApp(true)
    ExitApp
}
DirCreate(DATA_DIR)
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
global fs := {v: 0, acc: 0, last: 0, running: false, t0: 0, gen: 0, lastFwd: 0}   ; fast-scroll state
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
global RELOADED := IniRead(INI, "State", "Reloaded", 0) = 1 || IniRead(INI, "State", "JustSaved", 0) = 1
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
#HotIf !fs.running && FastScrollAllowed()
+WheelUp::FS_Start(1)
+WheelDown::FS_Start(-1)
; Ctrl + Shift + wheel = horizontal scroll at normal speed, in any app.
#HotIf !fs.running && cfg.fs.hscroll
^+WheelUp::HScroll(-1)
^+WheelDown::HScroll(1)
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
TRIGGERS() => [["CapsLock", "Caps Lock"], ["RAlt", "Right Alt"], ["RCtrl", "Right Ctrl"]
             , ["AppsKey", "Menu key"], ["ScrollLock", "Scroll Lock"]]

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
; AutoCAD and other MFC CAD apps (detected, so their panels and dialogs still glide), and
; apps listed as canvas apps (Photoshop, Blender...), where Shift + wheel is left alone.
FastScrollAllowed() {
    if !cfg.fs.enabled
        return false
    try {
        MouseGetPos(, , &win, &ctl, 2)
        return !OverCanvas(win, ctl)
    }
    return false
}

OverCanvas(win, ctl) {
    exe := WinGetProcessName(win)
    return cfg.fs.canvasMap.Has(exe) || REMOTE_APPS.Has(exe) || IsCadCanvas(ctl ? ctl : win)
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
    if WinGetClass(ctl) = "Intermediate D3D Window"
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
    if !target
        return
    ; A glide that started over a panel stops when the mouse moves onto a canvas.
    try {
        if OverCanvas(win, ctl) {
            FS_Log("stop: mouse moved onto a canvas")
            FS_Stop()
            return
        }
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
}

; Horizontal scroll by one notch. Controls with a horizontal scroll bar (classic lists,
; text boxes, also a parent panel's bar) get 3 "line left/right" steps; everything else gets
; a horizontal wheel message (browsers, Office, PDF readers...).
HScroll(dir) {
    CoordMode "Mouse", "Screen"
    MouseGetPos(&x, &y, &win, &ctl, 2)
    target := WheelTarget(win, ctl)
    if !target
        return
    h := target
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
    wp := ((dir * 120) & 0xFFFF) << 16
    lp := ((y & 0xFFFF) << 16) | (x & 0xFFFF)
    PostMessage(0x20E, wp, lp, target)                 ; WM_MOUSEHWHEEL
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
    global SettingsGui, PENDING, REOPEN, BTN, BTN_HOT, SLIDERS
    if SettingsGui {
        SettingsGui.Show()
        return
    }
    u := PENDING ? PENDING : cfg          ; unsaved choices survive a theme change (see ThemeChanged)
    rebuilt := PENDING ? true : false
    PENDING := 0
    ro := REOPEN
    REOPEN := 0
    BTN := Map(), BTN_HOT := 0, SLIDERS := Map()

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
    SecHeader(g, "x20 y58 w300", "Caps Lock")
    shiftEn := AddCheck(g, 20, 88, u.caps.shiftToggle, "Shift + Caps Lock turns it on / off", 290)
    Muted(g.AddText("x42 y110 w280", "Caps Lock alone does nothing."))

    SecHeader(g, "x20 y146 w300", "Media Control")
    capsEn := AddCheck(g, 20, 176, u.caps.enabled, "On", 260)
    g.AddText("x20 y212 w110", "Hold")
    trigNames := []
    for t in TRIGGERS()
        trigNames.Push(t[2])
    trigDd := g.AddDropDownList("x135 y208 w178", trigNames)
    for i, t in TRIGGERS()
        if t[1] = u.caps.trigger
            trigDd.Choose(i)
    if !trigDd.Value
        trigDd.Choose(1)
    capsEd := Map()
    for i, row in [["wheelUp", "Wheel up"], ["wheelDown", "Wheel down"], ["mButton", "Middle click"]
                 , ["xButton2", "Forward button"], ["xButton1", "Back button"]] {
        y := 240 + (i - 1) * 32
        g.AddText("x20 y" (y + 4) " w110", row[2])
        capsEd[row[1]] := KeyBox(g, "x135 y" y " w150", u.caps.%row[1]%, true)
    }
    Muted(g.AddText("x20 y404 w300", "Click a box to change its key."))

    SecHeader(g, "x345 y58 w485", "Side buttons")
    sideEn := AddCheck(g, 345, 88, u.side.enabled, "On  (not in dialogs and Explorer)", 460)
    MouseArt(g, 437, 110)
    sides := []
    for e in u.side.list
        sides.Push({app: e.app, back: e.back, fwd: e.fwd, both: e.both})
    LvHeader(g, 345, 330, 485, [["App", 150], ["Back", 110], ["Forward", 120], ["Both", 100]])
    sideLv := NewList(g, "x345 y356 w485 h134", ["App", "Back", "Forward", "Both"], "wh")
    sBtn1 := AddBtn(g, "x345 y500 w90", "Add...")
    sBtn2 := AddBtn(g, "x+8 w90", "Edit...")
    sBtn3 := AddBtn(g, "x+8 w90", "Delete")
    sBtn1.OnEvent("Click", (*) => AddSide()), sBtn2.OnEvent("Click", (*) => EditSide()), sBtn3.OnEvent("Click", (*) => DelSide())
    Anchor(sBtn1, "y"), Anchor(sBtn2, "y"), Anchor(sBtn3, "y")
    sideLv.OnEvent("DoubleClick", (ctrl, row) => (row ? EditSide() : 0))
    RefreshSides()
    EndPage(3)

    ; ---- Page 4: fast scroll ----------------------------------------------------
    fsEn := AddCheck(g, 20, 58, u.fs.enabled, "Fast scroll  (Shift + wheel)", 360)
    fsH  := AddCheck(g, 430, 58, u.fs.hscroll, "Sideways scroll  (Ctrl + Shift + wheel)", 380)
    SecHeader(g, "x20 y102 w400", "Speed")
    fsBoost := AddSlideRow("Kick per flick",        136, u.fs.boost, 5, 100)
    fsMax   := AddSlideRow("Top speed",             168, u.fs.max, 50, 800)
    fsHeld  := AddSlideRow("Glide: Shift held",     200, u.fs.glideHeld, 0, 100)
    fsRel   := AddSlideRow("Glide: Shift released", 232, u.fs.glideRelease, 0, 100)
    SecHeader(g, "x20 y288 w400", "Excluded apps")
    exLv := NewList(g, "x20 y318 w470 h210", ["App"], "h")
    aBtn1 := AddBtn(g, "x506 y318 w130", "Add app...")
    aBtn2 := AddBtn(g, "x506 y354 w130", "Remove")
    aBtn1.OnEvent("Click", (*) => ChooseApp(g, AddExclude)), aBtn2.OnEvent("Click", (*) => DelExclude())
    Muted(g.AddText("x506 y398 w300", "No fast scroll in these apps."))
    Muted(g.AddText("x506 y420 w300", "Revit and CAD canvases are skipped automatically."))
    RefreshEx()
    EndPage(4)

    ; ---- Page 5: general --------------------------------------------------------
    SecHeader(g, "x20 y58 w400", "Look")
    g.AddText("x20 y92 w80", "Theme")
    themeDd := g.AddDropDownList("x100 y88 w200", ["Auto", "Light", "Dark"])
    themeDd.Choose(u.theme = "light" ? 2 : u.theme = "dark" ? 3 : 1)
    themeDd.OnEvent("Change", ThemeChanged)                  ; applies at once, no Save needed

    SecHeader(g, "x20 y140 w400", "Startup")
    startEn := AddCheck(g, 20, 170, InstalledHere() ? (u.HasOwnProp("start") ? u.start : StartupOn()) : false
        , "Start with Windows", 400, (*) => SetStartup(startEn.Value))   ; takes effect at once
    if !InstalledHere() {                                ; a portable copy can't start with Windows
        startEn.Enabled := false
        Muted(g.AddText("x42 y194 w600", "Install the app to use this."))
    }

    SecHeader(g, "x20 y218 w400", "Install")
    g.AddText("x20 y250 w810", InstalledHere() ? "✔  Installed" : (A_IsCompiled ? "Portable copy (not installed)" : "Running as a script"))
    instBtn := AddBtn(g, "x20 y278 w150", InstalledHere() ? "Uninstall..." : (FileExist(INSTALL_EXE) ? "Update..." : "Install..."))
    instBtn.OnEvent("Click", (*) => (InstalledHere() ? UninstallApp() : InstallFlow()))
    if !A_IsCompiled
        BtnDisable(instBtn)
    Muted(g.AddText("x182 y284 w560", InstalledHere() ? "Also in Windows Settings > Apps." : "Copies to AppData and starts with Windows."))

    SecHeader(g, "x20 y338 w400", "Backup")
    AddBtn(g, "x20 y368 w120", "Export...").OnEvent("Click", (*) => ExportSettings(g))
    AddBtn(g, "x+8 w120", "Import...").OnEvent("Click", (*) => ImportSettings(g))
    Muted(g.AddText("x272 y374 w400", "Save or load all your settings."))

    SecHeader(g, "x20 y430 w400", "Settings file")
    Muted(g.AddText("x20 y460 w800", INI))
    AddBtn(g, "x20 y486 w140", "Open folder").OnEvent("Click", (*) => Run('"' DATA_DIR '"'))
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
    ApplyTheme(g)
    if !InstalledHere()
        startEn.lbl.SetFont("c" ThemeColors().muted)          ; greyed out
    ShowPage(ro ? ro.page : 1)
    g.Show(ro ? "x" ro.x " y" ro.y " w" ro.w " h" ro.h : "w850 h600")
    sc := A_ScreenDPI / 96
    g.Opt("+MinSize" Round(850 * sc) "x" Round(600 * sc))
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
        dw := Round(w / k) - 850, dh := Round(h / k) - 600
        for hw, a in ANCH {
            if !DllCall("IsWindow", "ptr", hw)
                continue
            DllCall("SetWindowPos", "ptr", hw, "ptr", 0
                , "int", Round((a.x + (InStr(a.f, "x") ? dw : 0)) * k), "int", Round((a.y + (InStr(a.f, "y") ? dh : 0)) * k)
                , "int", Round((a.w + (InStr(a.f, "w") ? dw : 0)) * k), "int", Round((a.h + (InStr(a.f, "h") ? dh : 0)) * k)
                , "uint", 0x14)                         ; NOZORDER | NOACTIVATE
        }
        PlaceGuide(guideWin, 10, 48, 830 + dw, 498 + dh)
        if curPage != 1
            DllCall("ShowWindow", "ptr", guideWin.Hwnd, "int", 0)
        GuideScroll(0)
        FitList(lv, [160])
        FitList(sideLv, [150, 110, 120])
        FitList(exLv, [])
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
        list.ModifyCol(fixed.Length + 1, Max(60, lw - used - Round(24 * k)))
        ; Column separators: a 1 px line at each column edge, the list's full height, on top.
        if !list.HasOwnProp("seps") || !list.seps.Length
            return
        rc := Buffer(16)
        DllCall("GetWindowRect", "ptr", list.Hwnd, "ptr", rc)
        DllCall("MapWindowPoints", "ptr", 0, "ptr", g.Hwnd, "ptr", rc, "uint", 2)
        lx := NumGet(rc, 0, "int"), ly := NumGet(rc, 4, "int"), lh := NumGet(rc, 12, "int") - ly
        x := 0
        for i, sp in list.seps {
            x += Round(fixed[i] * k)
            DllCall("SetWindowPos", "ptr", sp.Hwnd, "ptr", 0, "int", lx + x - Round(4 * k), "int", ly
                , "int", Max(1, Round(k)), "int", lh, "uint", 0x10)     ; HWND_TOP, NOACTIVATE
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
                ctrl.Visible := (i = n)
        if GUIDE.page                                   ; the guide is placed once the window is shown
            DllCall("ShowWindow", "ptr", guideWin.Hwnd, "int", n = 1 ? 8 : 0)
        t := ThemeColors()
        for i, tc in tabs
            tc.SetFont(i = n ? "bold c" t.fg : "norm c" t.muted)
        bar.Move(10 + (n - 1) * 134)
    }

    ; A slider with its number: label, bar, value.
    AddSlideRow(label, y, value, lo, hi) {
        g.AddText("x20 y" (y + 4) " w200", label)
        sl := g.AddSlider("x225 y" y " w330 h28 Range" lo "-" hi " ToolTip", Min(hi, Max(lo, Round(value))))
        vt := g.AddText("x565 y" (y + 4) " w70", sl.Value)
        sl.OnEvent("Change", (c, *) => vt.Text := c.Value)
        SLIDERS[sl.Hwnd] := {sl: sl, vt: vt, lo: lo, hi: hi}
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

    ThemeChanged(*) {
        global PENDING, REOPEN, SettingsGui
        SetTimer(DirtyTick, 0)
        c := BuildConfig()
        cfg.theme := c.theme
        IniWrite(c.theme, INI, "General", "Theme")
        PENDING := c
        REOPEN := WinState()
        SettingsGui := 0
        GUIDE.hwnd := 0
        g.Destroy()
        ApplyAppMode()
        SetTimer(ShowSettings, -10)
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
        c.theme := ["auto", "light", "dark"][themeDd.Value]
        c.start := startEn.Value
        c.caps.enabled := capsEn.Value
        c.caps.shiftToggle := shiftEn.Value
        c.caps.trigger := TRIGGERS()[Max(1, trigDd.Value)][1]
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
    if !SLIDERS.Count
        return
    MouseGetPos(, , , &h, 2)
    if !h || !SLIDERS.Has(h)
        return
    e := SLIDERS[h]
    delta := (wParam >> 16) & 0xFFFF
    delta := delta >= 0x8000 ? delta - 0x10000 : delta
    ; Wheel = next multiple of 5 up or down (33 -> 35 / 30).
    cur := e.sl.Value
    v := delta > 0 ? (Floor(cur / 5) + 1) * 5 : (Ceil(cur / 5) - 1) * 5
    v := Min(e.hi, Max(e.lo, v))
    e.sl.Value := v
    e.vt.Text := v
    return 0
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

ThemeColors() {
    return IsDarkTheme()
        ? {dark: true,  bg: "202020", fg: "E8E8E8", muted: "A0A0A0", field: "2B2B2B", line: "3C3C3C", btn: "3A3A3A", btnHot: "505050", accent: "4CC2FF", pri: "4CC2FF", priHot: "7AD3FF", priText: "00131F"}
        : {dark: false, bg: "F9F9F9", fg: "1B1B1B", muted: "6B6B6B", field: "FFFFFF", line: "D5D5D5", btn: "E3E3E3", btnHot: "CFCFCF", accent: "0067C0", pri: "0067C0", priHot: "1A7FD0", priText: "FFFFFF"}
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
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", win.Hwnd, "int", 20, "int*", t.dark ? 1 : 0, "int", 4)  ; title bar
    for hwnd, ctrl in win {
        role := ctrl.HasOwnProp("role") ? ctrl.role : ""
        try {
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
                if t.dark
                    SetTheme(hwnd, "DarkMode_CFD")
            case "ListView":
                ctrl.Opt("+Background" t.field)
                ctrl.SetFont("c" t.fg)
                if t.dark
                    SetTheme(hwnd, "DarkMode_Explorer")
            case "Slider":
                ctrl.Opt("+Background" t.bg)
            case "Checkbox", "Radio":
                if t.dark
                    SetTheme(hwnd, "DarkMode_Explorer")
          }
        }
    }
    SetTheme(h, name) => DllCall("uxtheme\SetWindowTheme", "ptr", h, "str", name, "ptr", 0)
}

; Remember a control's start position and how it follows a window resize
; (flags: x / y = move, w / h = grow).
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
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", gr, "int", 4)    ; anti-aliased text
    DllCall("gdiplus\GdipGraphicsClear", "ptr", gr, "uint", Gp_Argb(bgHex))
    return {bmp: bmp, gr: gr, k: k}
}

Gp_Done(cv) {
    hbm := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", cv.bmp, "ptr*", &hbm, "uint", 0xFF000000)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", cv.gr)
    DllCall("gdiplus\GdipDisposeImage", "ptr", cv.bmp)
    return hbm
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
Gp_Text(cv, text, x, y, w, h, hex, px := 12, bold := false, align := 1) {
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
    rc := Buffer(16, 0)
    NumPut("float", x * k, "float", y * k, "float", w * k, "float", h * k, rc)
    DllCall("gdiplus\GdipDrawString", "ptr", cv.gr, "str", text, "int", -1, "ptr", font, "ptr", rc, "ptr", fmt, "ptr", br)
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
    ; A text control showing a bitmap (SS_BITMAP): the bitmap is drawn 1:1, never stretched.
    b := win.AddText(opts " w" w " h" h " +0xE +0x100", "")
    b.GetPos(, , &pw, &ph)                                     ; real size in pixels
    b.role := "btn", b.btnText := text, b.px := pw, b.py := ph, b.primary := primary, b.dis := false
    b.DefineProp("Text", {get: (self) => self.btnText, set: (self, v) => (self.btnText := v, BtnRender(self, false))})
    BTN[b.Hwnd] := b
    BtnRender(b, false)
    SetTimer(BtnHoverTick, 40)
    return b
}

; Show a bitmap in a SS_BITMAP control (and free the one it showed before).
SetBitmap(ctrl, hbm) {
    old := SendMessage(0x172, 0, hbm, ctrl)                    ; STM_SETIMAGE, IMAGE_BITMAP
    if old
        DllCall("DeleteObject", "ptr", old)
}

BtnBitmap(pw, ph, text, hot, dis, primary) {
    t := ThemeColors()
    k := A_ScreenDPI / 96
    w := pw / k, h := ph / k                                   ; drawing units
    ; primary: "danger" = red (Cancel). A disabled button is plain grey, never coloured.
    if dis
        fill := t.btn, textColor := t.muted
    else if primary = "danger"
        fill := hot ? "E0453A" : "C42B1C", textColor := "FFFFFF"
    else if primary
        fill := hot ? t.priHot : t.pri, textColor := t.priText
    else
        fill := hot ? t.btnHot : t.btn, textColor := t.fg
    cv := Gp_Canvas(pw, ph, t.bg, true)
    Gp_Round(cv, 0, 0, w, h, 8, fill)
    Gp_Text(cv, text, 4, 0, w - 8, h, textColor, 12, primary, 1)
    return Gp_Done(cv)
}

BtnRender(b, hot) {
    SetBitmap(b, BtnBitmap(b.px, b.py, b.btnText, hot, b.dis, b.HasOwnProp("danger") && b.danger ? "danger" : b.primary))
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
    t := ThemeColors()
    pic := win.AddText("x" x " y" y " w300 h215 +0xE", "")
    pic.GetPos(, , &pw, &ph)
    cv := Gp_Canvas(pw, ph, t.bg, true)
    mx := 174                                                  ; left edge of the mouse body
    Gp_Round(cv, mx - 1, 7, 94, 152, 47, t.line)               ; body (with a thin edge)
    Gp_Round(cv, mx, 8, 92, 150, 46, t.btn)
    Gp_Line(cv, mx + 46, 8, mx + 46, 74, t.bg, 2)              ; gap between the two main buttons
    Gp_Line(cv, mx + 2, 74, mx + 90, 74, t.bg, 2)
    Gp_Round(cv, mx + 39, 24, 14, 28, 7, t.accent)             ; wheel
    Gp_Round(cv, mx - 7, 84, 10, 26, 4, t.accent)              ; forward button
    Gp_Round(cv, mx - 7, 116, 10, 26, 4, t.accent)             ; back button
    Gp_Line(cv, mx - 20, 97, mx - 9, 97, t.accent, 1.5)
    Gp_Line(cv, mx - 20, 129, mx - 9, 129, t.accent, 1.5)
    Gp_Text(cv, "Forward  ›  Redo", mx - 142, 85, 120, 24, t.fg, 12, true, 2)
    Gp_Text(cv, "Back  ›  Undo", mx - 142, 117, 120, 24, t.fg, 12, true, 2)
    Gp_Text(cv, "Both together  ›  Enter", 0, 174, 300, 22, t.muted, 12, false, 1)
    SetBitmap(pic, Gp_Done(cv))
    return pic
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
    ; Thin lines between the columns (Windows' own grid lines can't be coloured).
    ; FitList puts them in place; the list never paints over them (WS_CLIPSIBLINGS).
    lv.seps := []
    Loop cols.Length - 1 {
        sp := win.AddText("x0 y0 w1 h1")
        sp.role := "line"
        lv.seps.Push(sp)
    }
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
    if MsgBox("Add shortcuts to the Desktop and Start menu?", APP_NAME, "YesNo Iconi") = "Yes" {
        try FileCreateShortcut(INSTALL_EXE, A_Desktop "\" APP_NAME ".lnk", INSTALL_DIR, , APP_NAME)
        try FileCreateShortcut(INSTALL_EXE, A_Programs "\" APP_NAME ".lnk", INSTALL_DIR, , APP_NAME)
    }
    Run('"' INSTALL_EXE '"', INSTALL_DIR)
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
    cb := AddCheck(d, 16, 46, false, "Don't show again", 200)
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
    AddBtn(owner, "x+2 yp w26", "×").OnEvent("Click", (*) => SetKeyBox(b, ""))
    return b
}

KeyBoxValue(b) => KEYBOX_VALUES.Has(b.Hwnd) ? KEYBOX_VALUES[b.Hwnd] : ""

SetKeyBox(b, value) {
    KEYBOX_VALUES[b.Hwnd] := value
    b.Text := PrettyKeys(value)
}

KeyBoxMenu(b, *) {
    m := Menu()
    m.Add("Record keys...", (*) => RecordKeys(b))
    m.Add()
    for group in [["{Volume_Up}", "{Volume_Down}", "{Volume_Mute}"]
                , ["{Media_Play_Pause}", "{Media_Next}", "{Media_Prev}", "{Media_Stop}"]
                , ["{Enter}", "{Escape}", "{Delete}", "^{z}", "^{y}", "^+{z}"]] {
        for keys in group
            m.Add(PrettyKeys(keys), KeyBoxSetter(b, keys))
        m.Add()
    }
    m.Add("(none)", KeyBoxSetter(b, ""))
    m.Show()
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
    eApp := d.AddEdit("x120 y10 w160", e ? e.app : "")
    AddBtn(d, "x+6 yp w150", "Pick app...").OnEvent("Click", (*) => ChooseApp(d, (exe) => eApp.Value := exe))
    boxes := Map()
    for i, row in [["back", "Back"], ["fwd", "Forward"], ["both", "Both"]] {
        y := 46 + (i - 1) * 32
        d.AddText("x10 y" (y + 4) " w110", row[2])
        boxes[row[1]] := KeyBox(d, "x120 y" y " w160", e ? e.%row[1]% : "")
    }
    Muted(d.AddText("x10 y146 w430", "Click a box, press the keys. × clears."))
    AddBtn(d, "x10 y172 w80", "OK").OnEvent("Click", OkClick)
    AddBtn(d, "x+8 w80", "Cancel").OnEvent("Click", (*) => d.Destroy())
    d.OnEvent("Escape", (*) => d.Destroy())
    hw := d.Hwnd
    ApplyTheme(d)
    owner.Opt("+Disabled")
    d.Show()
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
        d.Destroy()
    }
}

; Small modal dialog for adding / editing one text shortcut.
SnippetDialog(owner, trig := "", txt := "") {
    res := {val: ""}
    d := Gui("+Owner" owner.Hwnd " +ToolWindow", "Text shortcut")
    d.SetFont("s9", "Segoe UI")
    d.AddText(, "You type:")
    eT := d.AddEdit("w340", trig)
    d.AddText(, "You get:")
    eX := d.AddEdit("w340 r5 WantReturn", txt)
    AddBtn(d, "w80", "OK").OnEvent("Click", OkClick)
    AddBtn(d, "x+8 w80", "Cancel").OnEvent("Click", (*) => d.Destroy())
    d.OnEvent("Escape", (*) => d.Destroy())
    hw := d.Hwnd
    ApplyTheme(d)
    owner.Opt("+Disabled")
    d.Show()
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
        d.Destroy()
    }
}
