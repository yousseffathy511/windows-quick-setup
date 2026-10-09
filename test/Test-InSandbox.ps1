# Opens a fresh Windows Sandbox with this repo on its desktop, to test Install.cmd on a "clean PC".
#   .\Test-InSandbox.ps1        -> opens the folder; double-click Install.cmd yourself
#   .\Test-InSandbox.ps1 -Auto  -> runs test\sandbox-run.ps1: installs + tests Win+Shift+S / Ctrl+C / Print Screen
# The sandbox's logs and screenshots are written back to test\sandbox-logs on this PC.
# Requires the Windows Sandbox feature (Windows 10/11 Pro or higher).
param([switch]$Auto)
$repo = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $PSScriptRoot 'sandbox-logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$wsb = Join-Path $PSScriptRoot 'sandbox-test.generated.wsb'
$desk = 'C:\Users\WDAGUtilityAccount\Desktop\windows-quick-setup'
if ($Auto) { $logon = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File $desk\test\sandbox-run.ps1" }
else       { $logon = "explorer.exe $desk" }
@"
<Configuration>
  <Networking>Enable</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$repo</HostFolder>
      <SandboxFolder>$desk</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$logs</HostFolder>
      <SandboxFolder>C:\Users\WDAGUtilityAccount\AppData\Local\WindowsQuickSetup</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>$logon</Command>
  </LogonCommand>
</Configuration>
"@ | Set-Content -Path $wsb -Encoding UTF8
Start-Process $wsb
"Sandbox starting. Logs and screenshots will appear in: $logs"
