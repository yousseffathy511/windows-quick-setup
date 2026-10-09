# Prints who holds Win+Shift+S plus the startup entries and Flameshot settings state (used by retest.cmd)
Add-Type -Namespace H -Name K -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(System.IntPtr hWnd, int id, uint mods, uint vk);
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)] public static extern bool UnregisterHotKey(System.IntPtr hWnd, int id);
'@
$free = [H.K]::RegisterHotKey([IntPtr]::Zero, 0x6B6B, 0x0C, 0x53)
if ($free) { [void][H.K]::UnregisterHotKey([IntPtr]::Zero, 0x6B6B) }
'Win+Shift+S       : ' + $(if ($free) { 'FREE (nobody)' } elseif (Get-Process flameshot -ErrorAction SilentlyContinue) { 'taken (Flameshot is running)' } else { 'taken (Windows)' })
'Flameshot running : ' + [bool](Get-Process flameshot -ErrorAction SilentlyContinue)
$run = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
'Run entries       : ' + (($run.GetValueNames() | ForEach-Object { "$_" }) -join ', ')
'DisabledHotkeys   : ' + (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').DisabledHotkeys
$ini = Join-Path $env:APPDATA 'flameshot\flameshot.ini'
'flameshot.ini     : ' + $(if (Test-Path $ini) { 'exists, read-only=' + (Get-Item $ini).IsReadOnly } else { 'removed' })
'Repair shortcut   : ' + (Test-Path (Join-Path ([Environment]::GetFolderPath('Programs')) 'Windows Quick Setup (repair).lnk'))
