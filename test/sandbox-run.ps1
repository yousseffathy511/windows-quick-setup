# Runs INSIDE Windows Sandbox (started by Test-InSandbox.ps1 -Auto).
# 1. Runs Install.cmd exactly like a user would, answering the Yes / OK dialogs.
# 2. Tests: Win+Shift+S -> drag a box -> Ctrl+C -> image on clipboard, and Print Screen.
# Results and screenshots are written to the mapped log folder so they can be read on the host.
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $env:LOCALAPPDATA 'WindowsQuickSetup'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$log  = Join-Path $out 'sandbox-test.txt'
function Log([string]$m) { $l = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m; Add-Content -Path $log -Value $l; Write-Host $l }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace T -Name U -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, System.UIntPtr extra);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] public static extern System.IntPtr FindWindow(string cls, string title);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint msg, System.IntPtr w, System.IntPtr l);
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(System.IntPtr hWnd, int id, uint mods, uint vk);
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)] public static extern bool UnregisterHotKey(System.IntPtr hWnd, int id);
'@

function Press([int[]]$vks) {
    foreach ($v in $vks) { $f = 0; if ($v -eq 0x5B -or $v -eq 0x2C) { $f = 1 }; [T.U]::keybd_event([byte]$v, 0, $f, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
    for ($i = $vks.Length - 1; $i -ge 0; $i--) { $v = $vks[$i]; $f = 2; if ($v -eq 0x5B -or $v -eq 0x2C) { $f = 3 }; [T.U]::keybd_event([byte]$v, 0, $f, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80 }
}
function Shot([string]$name) {
    try {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $bmp.Save((Join-Path $out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
    } catch { Log "screenshot $name failed: $($_.Exception.Message)" }
}
function Clip-Marker { try { [System.Windows.Forms.Clipboard]::SetText('MARKER') } catch { } }
function Clip-State {
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsImage()) { $i = [System.Windows.Forms.Clipboard]::GetImage(); return "IMAGE $($i.Width)x$($i.Height)" }
        return 'TEXT: ' + [System.Windows.Forms.Clipboard]::GetText()
    } catch { return "ERROR $($_.Exception.Message)" }
}
function HotkeyTaken([uint32]$mods, [uint32]$vk) {
    $ok = [T.U]::RegisterHotKey([IntPtr]::Zero, 0x7A7A, $mods, $vk)
    if ($ok) { [void][T.U]::UnregisterHotKey([IntPtr]::Zero, 0x7A7A); return $false }; return $true
}

Log "=== Sandbox test started. Windows $([Environment]::OSVersion.Version), user $env:USERNAME"
Log ("winget before install: " + [bool](Get-Command winget.exe -ErrorAction SilentlyContinue))
Log ("Win+Shift+S before install: " + $(if (HotkeyTaken 0x0C 0x53) { 'held by Windows' } else { 'free' }))

# ---- 1. run Install.cmd like a user; answer the dialogs
$cmd = Join-Path $repo 'Install.cmd'
$p = Start-Process -FilePath cmd.exe -ArgumentList "/c echo.| `"$cmd`"" -PassThru
$dialogs = 0
$deadline = (Get-Date).AddMinutes(25)
while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
    $h = [T.U]::FindWindow('#32770', 'Windows Quick Setup')
    if ($h -ne [IntPtr]::Zero) {
        $dialogs++
        Start-Sleep -Milliseconds 800
        Shot ("01-dialog-{0}" -f $dialogs)
        Log "Dialog #$dialogs shown - answering Yes/OK"
        [void][T.U]::PostMessage($h, 0x0111, [IntPtr]6, [IntPtr]::Zero)   # IDYES
        [void][T.U]::PostMessage($h, 0x0111, [IntPtr]1, [IntPtr]::Zero)   # IDOK
        Start-Sleep -Seconds 2
    }
    Start-Sleep -Milliseconds 500
}
Log "Install.cmd finished: exited=$($p.HasExited), dialogs answered=$dialogs"
Start-Sleep -Seconds 8
Shot '02-after-install'

# ---- 2. state checks
$run = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$ini = Join-Path $env:APPDATA 'flameshot\flameshot.ini'
Log ("Flameshot running      : " + [bool](Get-Process flameshot -ErrorAction SilentlyContinue))
Log ("superwhisper running   : " + [bool](Get-Process Superwhisper -ErrorAction SilentlyContinue))
Log ("Raycast running        : " + [bool](Get-Process Raycast -ErrorAction SilentlyContinue))
Log ("Run entries            : " + (($run.GetValueNames() | ForEach-Object { "$_=" + $run.GetValue($_) }) -join ' | '))
Log ("Raycast task           : " + [bool](Get-ScheduledTask -TaskPath '\Raycast\' -ErrorAction SilentlyContinue))
Log ("DisabledHotkeys        : " + (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').DisabledHotkeys)
if (Test-Path $ini) { Log ("flameshot.ini read-only : " + (Get-Item $ini).IsReadOnly + "  shortcut line: " + ((Get-Content $ini) -match '^TAKE_SCREENSHOT=')) } else { Log 'flameshot.ini MISSING' }
Log ("Win+Shift+S owner      : " + $(if (HotkeyTaken 0x0C 0x53) { 'taken (Flameshot)' } else { 'FREE - nobody' }))
Log ("Repair shortcut        : " + (Test-Path (Join-Path ([Environment]::GetFolderPath('Programs')) 'Windows Quick Setup (repair).lnk')))
Get-CimInstance Win32_StartupCommand | ForEach-Object { Log ("Startup (WMI)          : [$($_.Name)] $($_.Command)") }

# ---- 3. functional test: Win+Shift+S -> drag -> Ctrl+C
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Clip-Marker
Log 'Pressing Win+Shift+S'
Press @(0x5B, 0x10, 0x53)
Start-Sleep -Seconds 3
Shot '03-win-shift-s'
$x1 = [int]($b.Width * 0.30); $y1 = [int]($b.Height * 0.30); $x2 = [int]($b.Width * 0.60); $y2 = [int]($b.Height * 0.60)
[void][T.U]::SetCursorPos($x1, $y1); Start-Sleep -Milliseconds 300
[T.U]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
for ($s = 1; $s -le 15; $s++) { [void][T.U]::SetCursorPos($x1 + ($x2 - $x1) * $s / 15, $y1 + ($y2 - $y1) * $s / 15); Start-Sleep -Milliseconds 40 }
[T.U]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Seconds 1
Shot '04-selection'
Log 'Pressing Ctrl+C'
Press @(0x11, 0x43)
Start-Sleep -Seconds 3
Log ("Clipboard after Ctrl+C : " + (Clip-State))
Shot '05-after-ctrl-c'

# ---- 4. Print Screen
Clip-Marker
Log 'Pressing Print Screen'
Press @(0x2C)
Start-Sleep -Seconds 3
Shot '06-print-screen'
Log ("Clipboard after PrtScn : " + (Clip-State))
Log ("Processes after PrtScn : " + ((Get-Process | Where-Object { $_.ProcessName -match 'Snipping|ScreenClipping|flameshot' } | ForEach-Object { $_.ProcessName }) -join ', '))
Press @(0x1B)
Start-Sleep -Seconds 1
Shot '07-after-esc'
Log '=== Sandbox test finished'
