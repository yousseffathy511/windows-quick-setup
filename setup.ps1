<#
.SYNOPSIS
    Windows Quick Setup - installs Flameshot, superwhisper and Raycast and makes them your defaults.

.DESCRIPTION
    Sets up a Windows 10/11 PC with three apps:
      - Flameshot    : Win+Shift+S opens a screenshot capture. Select an area, then press Ctrl+C
                       (or click the Copy button, or double-click inside the box) to copy it.
                       Print Screen keeps working as normal (Windows Snipping Tool).
      - superwhisper : voice to text.
      - Raycast      : fast app launcher (Alt+Space).
    All three start automatically every time you sign in to Windows.

    Safe to run again at any time: it repairs anything that is missing or broken.

.PARAMETER Yes
    Do not ask "Install them and make them your defaults?" (unattended / repair use).
.PARAMETER Undo
    Give Win+Shift+S back to Windows and stop the three apps from starting with Windows.
    Afterwards it offers to uninstall the apps too.
.PARAMETER Hotkey
    Flameshot shortcut in Qt notation. Default: Meta+Shift+S (Meta = the Windows key).

.EXAMPLE
    Double-click Install.cmd
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Yes
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$Undo,
    [string]$Hotkey = 'Meta+Shift+S'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

# ------------------------------------------------------------------------------------ settings
$Title          = 'Windows Quick Setup'
$RepoRaw        = 'https://raw.githubusercontent.com/yousseffathy511/windows-quick-setup/main'
$WorkDir        = Join-Path $env:LOCALAPPDATA 'WindowsQuickSetup'
$LogFile        = Join-Path $WorkDir 'setup-log.txt'
$RunKey         = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$ApprovedKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$AdvancedKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$FlameshotIni   = Join-Path $env:APPDATA 'flameshot\flameshot.ini'
$SwExe          = Join-Path $env:LOCALAPPDATA 'superwhisper\Superwhisper.exe'
$SwPrefs        = Join-Path $env:LOCALAPPDATA 'com.superwhisper.app\preferences.json'
$SwFallbackUrl  = 'https://fresh.superwhisper.com/download?asset=541658201&filename=superwhisper_1.6.5_x64-setup.exe'
$RaycastStoreId = '9PFXXSHC64H3'
$RepairLnk      = Join-Path ([Environment]::GetFolderPath('Programs')) 'Windows Quick Setup (repair).lnk'

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# ------------------------------------------------------------------------------------ helpers
function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'STEP', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
    $color  = switch ($Level) { 'STEP' { 'Cyan' } 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'Gray' } }
    $prefix = switch ($Level) { 'STEP' { '==> ' } 'OK' { '[OK] ' } 'WARN' { '[!] ' } 'ERROR' { '[X] ' } default { '     ' } }
    Write-Host ($prefix + $Message) -ForegroundColor $color
}

function Ask-YesNo {
    param([string]$Text)
    # 4 = Yes/No buttons, 32 = question icon, 4096 = stays on top of other windows
    $answer = (New-Object -ComObject WScript.Shell).Popup($Text, 0, $Title, 4 + 32 + 4096)
    return ($answer -eq 6)
}

function Show-Info {
    param([string]$Text, [int]$Icon = 64)
    if (-not $Yes) {
        [void](New-Object -ComObject WScript.Shell).Popup($Text, 0, $Title, $Icon + 4096)
        return
    }
    # With -Yes (unattended / repair) the message closes by itself after 60 seconds.
    # (WScript's Popup timeout is not reliable, MessageBoxTimeout is.)
    if (-not ('WQS.Msg' -as [type])) {
        Add-Type -Namespace WQS -Name Msg -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int MessageBoxTimeoutW(System.IntPtr hWnd, string text, string caption, uint type, ushort lang, uint ms);
'@
    }
    [void][WQS.Msg]::MessageBoxTimeoutW([IntPtr]::Zero, $Text, $Title, [uint32]($Icon + 4096), 0, 60000)
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-App {
    # Apps are started through Explorer when this script is elevated, so they never run as admin.
    param([string]$Target)
    try {
        if ((Test-IsAdmin) -or ($Target -like 'shell:*')) {
            Start-Process -FilePath "$env:WINDIR\explorer.exe" -ArgumentList "`"$Target`""
        } else {
            Start-Process -FilePath $Target
        }
    } catch { Write-Log "Could not start $Target : $($_.Exception.Message)" 'WARN' }
}

function Save-Download {
    param([string]$Url, [string]$OutFile)
    Write-Log "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -Headers @{ 'User-Agent' = 'WindowsQuickSetup' } -ErrorAction Stop
}

function Get-HotkeyParts {
    param([string]$Sequence)
    $mods = 0; $vk = 0
    foreach ($token in ($Sequence -split '\+')) {
        $t = $token.Trim()
        if ($t -match '^(meta|win|windows)$')  { $mods = $mods -bor 8 }
        elseif ($t -match '^shift$')           { $mods = $mods -bor 4 }
        elseif ($t -match '^(ctrl|control)$')  { $mods = $mods -bor 2 }
        elseif ($t -match '^alt$')             { $mods = $mods -bor 1 }
        elseif ($t -match '^[A-Za-z0-9]$')     { $vk = [int][char]$t.ToUpper() }
    }
    return @{ Mods = [uint32]$mods; Vk = [uint32]$vk; Letter = [string][char]$vk }
}

function Test-HotkeyTaken {
    # True if some program (or Windows) already owns this global shortcut.
    param([uint32]$Mods, [uint32]$Vk)
    if (-not ('WQS.HotKey' -as [type])) {
        Add-Type -Namespace WQS -Name HotKey -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern bool RegisterHotKey(System.IntPtr hWnd, int id, uint fsModifiers, uint vk);
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern bool UnregisterHotKey(System.IntPtr hWnd, int id);
'@
    }
    $free = [WQS.HotKey]::RegisterHotKey([IntPtr]::Zero, 0x5A51, $Mods, $Vk)
    if ($free) { [void][WQS.HotKey]::UnregisterHotKey([IntPtr]::Zero, 0x5A51); return $false }
    return $true
}

function Set-StartupEntry {
    param([string]$Name, [string]$Command)
    New-ItemProperty -Path $RunKey -Name $Name -Value $Command -PropertyType String -Force | Out-Null
    if (-not (Test-Path $ApprovedKey)) { New-Item -Path $ApprovedKey -Force | Out-Null }
    # 02 00 00 00 ... = "On" in Settings > Apps > Startup
    New-ItemProperty -Path $ApprovedKey -Name $Name -Value ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -PropertyType Binary -Force | Out-Null
}

function Remove-StartupEntry {
    param([string]$Name)
    Remove-ItemProperty -Path $RunKey -Name $Name -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $ApprovedKey -Name $Name -ErrorAction SilentlyContinue
}

function Restart-Explorer {
    Write-Log 'Restarting the taskbar so Windows lets go of the shortcut (it blinks for a moment)...'
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { break }
    }
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process "$env:WINDIR\explorer.exe" }
    Start-Sleep -Seconds 4
}

# ------------------------------------------------------------------------------------ WinGet
function Get-Winget {
    $candidates = @()
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    $candidates += (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe')
    foreach ($w in $candidates) {
        if ($w -and (Test-Path $w)) {
            try { $v = & $w --version 2>$null; if ($LASTEXITCODE -eq 0 -and $v) { return $w } } catch { }
        }
    }
    return $null
}

function Install-Winget {
    Write-Log 'WinGet (the Windows package manager) is missing - installing it the official Microsoft way...' 'STEP'
    try {
        $scope = 'CurrentUser'
        if (Test-IsAdmin) { $scope = 'AllUsers' }
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $scope -ErrorAction Stop | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force -AllowClobber -Scope $scope -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
        if (Test-IsAdmin) { Repair-WinGetPackageManager -AllUsers -Force -Latest -ErrorAction Stop | Out-Null }
        else { Repair-WinGetPackageManager -Force -Latest -ErrorAction Stop | Out-Null }
    } catch { Write-Log "WinGet could not be installed: $($_.Exception.Message)" 'WARN' }
    Start-Sleep -Seconds 2
    return (Get-Winget)
}

function Invoke-Winget {
    param([string]$Winget, [string[]]$Arguments)
    Write-Log ('winget ' + ($Arguments -join ' '))
    $output = & $Winget @Arguments 2>&1
    $code = $LASTEXITCODE
    foreach ($l in $output) {
        $s = "$l".Trim()
        if ($s -and $s -notmatch '^[\-\\|/ ]+$' -and $s -notmatch ('[' + [char]0x2580 + '-' + [char]0x259F + ']')) {
            try { Add-Content -Path $LogFile -Value "      $s" -Encoding UTF8 } catch { }
        }
    }
    Write-Log "winget exit code: $code"
    return $code
}

# ------------------------------------------------------------------------------------ detection
function Get-FlameshotExe {
    foreach ($p in @("$env:ProgramFiles\Flameshot\bin\flameshot.exe", "${env:ProgramFiles(x86)}\Flameshot\bin\flameshot.exe", "$env:LOCALAPPDATA\Programs\Flameshot\bin\flameshot.exe")) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    $u = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
         Where-Object { $_.DisplayName -eq 'Flameshot' -and $_.InstallLocation } | Select-Object -First 1
    if ($u) { $p = Join-Path $u.InstallLocation 'bin\flameshot.exe'; if (Test-Path $p) { return $p } }
    return $null
}

function Get-RaycastPackage { return (Get-AppxPackage -Name 'Raycast.Raycast' -ErrorAction SilentlyContinue | Select-Object -First 1) }

function Get-RaycastAumid {
    $pkg = Get-RaycastPackage
    if (-not $pkg) { return $null }
    $appId = 'Raycast'
    try { $m = Get-AppxPackageManifest -Package $pkg; $id = @($m.Package.Applications.Application)[0].Id; if ($id) { $appId = $id } } catch { }
    return "$($pkg.PackageFamilyName)!$appId"
}

# ------------------------------------------------------------------------------------ installs
function Install-Flameshot {
    param([string]$Winget)
    if (Get-FlameshotExe) { Write-Log 'Flameshot is already installed.' 'OK'; return $true }
    Write-Log 'Installing Flameshot (if Windows asks for permission, click Yes)...' 'STEP'
    if ($Winget) {
        [void](Invoke-Winget $Winget @('install', '--id', 'Flameshot.Flameshot', '--exact', '--source', 'winget',
                '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity'))
    }
    if (-not (Get-FlameshotExe)) {
        Write-Log "Trying the direct download from Flameshot's GitHub releases..." 'WARN'
        try {
            $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/flameshot-org/flameshot/releases/latest' -Headers @{ 'User-Agent' = 'WindowsQuickSetup' } -UseBasicParsing -ErrorAction Stop
            $asset = @($rel.assets | Where-Object { $_.name -match 'win64\.msi$' })[0]
            $msi = Join-Path $WorkDir $asset.name
            Save-Download $asset.browser_download_url $msi
            $p = Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Verb RunAs -Wait -PassThru -ErrorAction Stop
            Write-Log "msiexec exit code: $($p.ExitCode)"
        } catch { Write-Log "Direct install failed: $($_.Exception.Message)" 'ERROR' }
    }
    $ok = [bool](Get-FlameshotExe)
    if ($ok) { Write-Log 'Flameshot installed.' 'OK' } else { Write-Log 'Flameshot could not be installed.' 'ERROR' }
    return $ok
}

function Install-Superwhisper {
    param([string]$Winget)
    if (Test-Path $SwExe) { Write-Log 'superwhisper is already installed.' 'OK'; return $true }
    Write-Log 'Installing superwhisper...' 'STEP'
    if ($Winget) {
        [void](Invoke-Winget $Winget @('install', '--id', 'SuperUltra.superwhisper', '--exact', '--source', 'winget',
                '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity'))
    }
    if (-not (Test-Path $SwExe)) {
        Write-Log 'Trying the direct download from superwhisper.com...' 'WARN'
        try {
            $exe = Join-Path $WorkDir 'superwhisper-setup.exe'
            Save-Download $SwFallbackUrl $exe
            $p = Start-Process -FilePath $exe -ArgumentList '/S' -Wait -PassThru -ErrorAction Stop
            Write-Log "superwhisper installer exit code: $($p.ExitCode)"
        } catch { Write-Log "Direct install failed: $($_.Exception.Message)" 'ERROR' }
    }
    $ok = Test-Path $SwExe
    if ($ok) { Write-Log 'superwhisper installed.' 'OK' } else { Write-Log 'superwhisper could not be installed.' 'ERROR' }
    return $ok
}

function Install-Raycast {
    param([string]$Winget)
    if (Get-RaycastPackage) { Write-Log 'Raycast is already installed.' 'OK'; return $true }
    Write-Log 'Installing Raycast (from the Microsoft Store)...' 'STEP'
    if ($Winget) {
        [void](Invoke-Winget $Winget @('install', '--id', $RaycastStoreId, '--exact', '--source', 'msstore',
                '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity'))
    }
    if (-not (Get-RaycastPackage)) {
        Write-Log "Trying Microsoft's Store installer for Raycast (gives up after 5 minutes)..." 'WARN'
        try {
            $exe = Join-Path $WorkDir 'Raycast Installer.exe'
            Save-Download "https://get.microsoft.com/installer/download/$RaycastStoreId" $exe
            $proc = Start-Process -FilePath $exe -PassThru -ErrorAction Stop
            # Never wait forever: the Store can show a message (for example "not available in your
            # region") that waits for a click and would otherwise block the whole setup.
            $deadline = (Get-Date).AddMinutes(5)
            while ((Get-Date) -lt $deadline -and -not (Get-RaycastPackage)) {
                if ($proc.HasExited) { Start-Sleep -Seconds 3; break }
                Start-Sleep -Seconds 3
            }
            if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        } catch { Write-Log "Store installer failed: $($_.Exception.Message)" 'ERROR' }
    }
    $ok = [bool](Get-RaycastPackage)
    if ($ok) { Write-Log 'Raycast installed.' 'OK' }
    else {
        Write-Log 'Raycast could not be installed automatically (the Microsoft Store is not working on this PC). Opening its download page.' 'WARN'
        Start-App 'https://www.raycast.com/windows'
    }
    return $ok
}

# ------------------------------------------------------------------------------------ configuration
function Set-FlameshotConfig {
    Get-Process -Name flameshot -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 700
    New-Item -ItemType Directory -Force -Path (Split-Path $FlameshotIni) | Out-Null
    if (Test-Path $FlameshotIni) {
        Set-ItemProperty -Path $FlameshotIni -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        # Keep a backup of the user's own Flameshot settings (for Undo) - but never of a file this script wrote
        $bak = Join-Path $WorkDir 'flameshot.ini.before-setup'
        $existing = [IO.File]::ReadAllText($FlameshotIni)
        if (-not (Test-Path $bak) -and $existing.Trim() -and $existing -notmatch 'Written by Windows Quick Setup') {
            Copy-Item $FlameshotIni $bak -Force
        }
    }
    $lines = @(
        '; Written by Windows Quick Setup - https://github.com/yousseffathy511/windows-quick-setup',
        '[General]',
        'captureActiveMonitor=true',          # capture the screen under the mouse - no "pick a monitor" step
        'contrastOpacity=188',
        'copyOnDoubleClick=true',             # double-click inside the box also copies
        'ignorePrntScrForcesSnipping=true',   # leave Print Screen to Windows, no pop-up about it
        'showSelectionGeometryHideTime=3000',
        'showStartupLaunchMessage=false',     # no pop-up at sign-in
        'startupLaunch=true',
        '',
        '[Shortcuts]',
        "TAKE_SCREENSHOT=$Hotkey"
    )
    [IO.File]::WriteAllText($FlameshotIni, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    # Flameshot 14 can recreate this file EMPTY while saving it, which silently loses the shortcut.
    # Read-only prevents that. (To change Flameshot settings later, untick Read-only on this file.)
    Set-ItemProperty -Path $FlameshotIni -Name IsReadOnly -Value $true
    Write-Log "Flameshot settings written ($HotkeyText, copy on double-click, no monitor picker)." 'OK'
}

function Release-WindowsShortcut {
    # Windows reserves Win+S / Win+Shift+S / Win+Ctrl+S. DisabledHotkeys tells Explorer to let them go.
    param([string]$Letter)
    $cur = [string](Get-ItemProperty -Path $AdvancedKey -Name DisabledHotkeys -ErrorAction SilentlyContinue).DisabledHotkeys
    if ($cur.ToUpper().Contains($Letter.ToUpper())) { Write-Log "Windows already leaves Win+$Letter shortcuts free." 'OK'; return $false }
    $new = $cur + $Letter.ToUpper()
    New-ItemProperty -Path $AdvancedKey -Name DisabledHotkeys -Value $new -PropertyType String -Force | Out-Null
    Write-Log "Windows' own Win+$Letter shortcuts released (DisabledHotkeys=$new)." 'OK'
    return $true
}

function Set-SuperwhisperLaunchAtLogin {
    param([bool]$Enabled)
    if (-not (Test-Path $SwPrefs)) { return $false }
    $json = [IO.File]::ReadAllText($SwPrefs)
    if ($json -notmatch '"launchAtLogin"\s*:\s*(true|false)') { return $false }
    $value = 'false'
    if ($Enabled) { $value = 'true' }
    $new = $json -replace '"launchAtLogin"\s*:\s*(true|false)', ('"launchAtLogin": ' + $value)
    if ($new -ne $json) { [IO.File]::WriteAllText($SwPrefs, $new, (New-Object Text.UTF8Encoding($false))) }
    return $true
}

function Enable-SuperwhisperAutostart {
    if (-not (Test-Path $SwPrefs)) {
        Write-Log 'Opening superwhisper once so it creates its settings...'
        Start-App $SwExe
        for ($i = 0; $i -lt 90 -and -not (Test-Path $SwPrefs); $i++) { Start-Sleep -Seconds 1 }
        Start-Sleep -Seconds 3
    }
    # superwhisper must be closed while its settings file is changed, or it writes its old value back
    Get-Process -Name Superwhisper -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Set-SuperwhisperLaunchAtLogin $true) { Write-Log 'superwhisper: its own "Launch at login" setting is now on.' 'OK' }
    else { Write-Log 'superwhisper settings file not found - using the Windows startup list only.' 'WARN' }
    Set-StartupEntry 'superwhisper' ('"' + $SwExe + '"')
    Write-Log 'superwhisper will start with Windows.' 'OK'
}

function Enable-RaycastAutostart {
    $aumid = Get-RaycastAumid
    if (-not $aumid) { return }
    if (-not (Get-Process -Name Raycast -ErrorAction SilentlyContinue)) {
        Write-Log 'Opening Raycast...'
        Start-App "shell:AppsFolder\$aumid"
    }
    $task = $null
    for ($i = 0; $i -lt 30; $i++) {
        $task = Get-ScheduledTask -TaskPath '\Raycast\' -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' } | Select-Object -First 1
        if ($task) { break }
        Start-Sleep -Seconds 1
    }
    if ($task) {
        Remove-StartupEntry 'Raycast'
        Write-Log 'Raycast starts itself with Windows (its own "Open at Login" task).' 'OK'
    } else {
        Set-StartupEntry 'Raycast' "$env:WINDIR\explorer.exe shell:AppsFolder\$aumid"
        Write-Log 'Raycast will start with Windows.' 'OK'
    }
}

function Install-RepairShortcut {
    try {
        $dest = Join-Path $WorkDir 'setup.ps1'
        if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
            if ($PSCommandPath -ne $dest) { Copy-Item $PSCommandPath $dest -Force }
        } else {
            Save-Download "$RepoRaw/setup.ps1" $dest
        }
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($RepairLnk)
        $lnk.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$dest`" -Yes -Hotkey `"$Hotkey`""
        $lnk.WorkingDirectory = $WorkDir
        $lnk.Description = 'Re-applies the Flameshot / superwhisper / Raycast setup. Safe to run any time.'
        $lnk.IconLocation = "$env:WINDIR\System32\shell32.dll,238"
        $lnk.Save()
        Write-Log 'Start menu: "Windows Quick Setup (repair)" added.' 'OK'
    } catch { Write-Log "Could not create the repair shortcut: $($_.Exception.Message)" 'WARN' }
}

# ------------------------------------------------------------------------------------ undo
function Invoke-Undo {
    if (-not $Yes) {
        $q = "Undo Windows Quick Setup?`n`n" +
             " - Give Win+$($hk.Letter) shortcuts (like Win+Shift+S and Win+S) back to Windows`n" +
             " - Stop Flameshot, superwhisper and Raycast from starting with Windows`n`n" +
             'The apps stay installed (you will be asked about that next).'
        if (-not (Ask-YesNo $q)) { return }
    }
    Write-Log 'Undoing Windows Quick Setup...' 'STEP'
    $cur = [string](Get-ItemProperty -Path $AdvancedKey -Name DisabledHotkeys -ErrorAction SilentlyContinue).DisabledHotkeys
    if ($cur) {
        $new = (($cur.ToCharArray() | Where-Object { "$_".ToUpper() -ne $hk.Letter.ToUpper() }) -join '')
        if ($new) { New-ItemProperty -Path $AdvancedKey -Name DisabledHotkeys -Value $new -PropertyType String -Force | Out-Null }
        else { Remove-ItemProperty -Path $AdvancedKey -Name DisabledHotkeys -ErrorAction SilentlyContinue }
    }
    foreach ($n in 'Flameshot', 'superwhisper', 'Raycast') { Remove-StartupEntry $n }
    Get-Process -Name Superwhisper -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    [void](Set-SuperwhisperLaunchAtLogin $false)
    if (Test-Path $FlameshotIni) {
        Get-Process -Name flameshot -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 700
        Set-ItemProperty -Path $FlameshotIni -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        $bak = Join-Path $WorkDir 'flameshot.ini.before-setup'
        if (Test-Path $bak) { Copy-Item $bak $FlameshotIni -Force } else { Remove-Item $FlameshotIni -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path $RepairLnk) { Remove-Item $RepairLnk -Force -ErrorAction SilentlyContinue }
    Restart-Explorer
    Write-Log 'Undo finished: Windows owns its shortcuts again and the apps no longer start with Windows.' 'OK'

    if (-not $Yes -and (Ask-YesNo 'Also uninstall Flameshot, superwhisper and Raycast?')) {
        $w = Get-Winget
        if ($w) {
            [void](Invoke-Winget $w @('uninstall', '--id', 'Flameshot.Flameshot', '--exact', '--silent', '--disable-interactivity', '--accept-source-agreements'))
            [void](Invoke-Winget $w @('uninstall', '--id', 'SuperUltra.superwhisper', '--exact', '--silent', '--disable-interactivity', '--accept-source-agreements'))
        }
        $rc = Get-RaycastPackage
        if ($rc) { try { Remove-AppxPackage -Package $rc.PackageFullName -ErrorAction Stop; Write-Log 'Raycast uninstalled.' 'OK' } catch { Write-Log "Raycast: $($_.Exception.Message)" 'WARN' } }
    }
    Show-Info 'Undo finished. Win+Shift+S and Win+S belong to Windows again.'
}

# ------------------------------------------------------------------------------------ main
$hk = Get-HotkeyParts $Hotkey
$HotkeyText = ($Hotkey -replace '(?i)meta', 'Win')

Write-Host ''
Write-Host "  $Title - Flameshot + superwhisper + Raycast" -ForegroundColor White
Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray
Write-Log ("Started. Windows {0}, user {1}, admin={2}, hotkey={3}" -f [Environment]::OSVersion.Version, $env:USERNAME, (Test-IsAdmin), $Hotkey)

if ($Undo) { Invoke-Undo; return }

if (-not $Yes) {
    $q = "This will set up this PC with:`n`n" +
         " - Flameshot: $HotkeyText takes a screenshot. Select an area, then press Ctrl+C to copy it.`n" +
         " - superwhisper: voice to text.`n" +
         " - Raycast: fast app launcher (Alt+Space).`n`n" +
         "All three start automatically with Windows. Print Screen keeps working as usual.`n"
    if ($hk.Mods -band 8) { $q += "Windows' own Win+$($hk.Letter) search shortcut is turned off (press the Windows key and type to search).`n" }
    $q += "`nInstall them and make them your defaults?"
    if (-not (Ask-YesNo $q)) { Write-Log 'Cancelled. Nothing was changed.' 'WARN'; return }
}

$winget = Get-Winget
if (-not $winget) { $winget = Install-Winget }
if ($winget) { Write-Log "Using WinGet: $winget" 'OK' } else { Write-Log 'WinGet is not available - using direct downloads instead.' 'WARN' }

$installed = [ordered]@{}
$installed['Flameshot']    = Install-Flameshot $winget
$installed['superwhisper'] = Install-Superwhisper $winget
$installed['Raycast']      = Install-Raycast $winget

if ($installed['Flameshot']) {
    Write-Log "Making Flameshot open on $HotkeyText..." 'STEP'
    Set-FlameshotConfig
    if ($hk.Mods -band 8) {
        if (Release-WindowsShortcut $hk.Letter) { Restart-Explorer }
    }
    if (Test-HotkeyTaken $hk.Mods $hk.Vk) { Write-Log "$HotkeyText is still held by Windows - it becomes free after the next restart." 'WARN' }
    else { Write-Log "$HotkeyText is free for Flameshot." 'OK' }
    $fs = Get-FlameshotExe
    Set-StartupEntry 'Flameshot' ('"' + $fs + '"')
    Write-Log 'Flameshot will start with Windows.' 'OK'
    Start-App $fs
}
if ($installed['superwhisper']) {
    Write-Log 'Setting up superwhisper...' 'STEP'
    Enable-SuperwhisperAutostart
    Start-App $SwExe
}
if ($installed['Raycast']) {
    Write-Log 'Setting up Raycast...' 'STEP'
    Enable-RaycastAutostart
}
Install-RepairShortcut

Write-Log 'Checking everything...' 'STEP'
for ($i = 0; $i -lt 15 -and -not (Get-Process -Name flameshot -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
Start-Sleep -Seconds 6
$check = [ordered]@{}
$check['Flameshot installed']              = [bool](Get-FlameshotExe)
$check['Flameshot running']                = [bool](Get-Process -Name flameshot -ErrorAction SilentlyContinue)
$check["$HotkeyText opens Flameshot"]      = ($check['Flameshot running'] -and (Test-HotkeyTaken $hk.Mods $hk.Vk))
$check['Flameshot settings protected']     = ((Test-Path $FlameshotIni) -and (Get-Item $FlameshotIni).IsReadOnly -and ([IO.File]::ReadAllText($FlameshotIni) -match [regex]::Escape("TAKE_SCREENSHOT=$Hotkey")))
$check['Flameshot starts with Windows']    = [bool](Get-ItemProperty $RunKey -Name Flameshot -ErrorAction SilentlyContinue)
$check['superwhisper installed']           = (Test-Path $SwExe)
$check['superwhisper running']             = [bool](Get-Process -Name Superwhisper -ErrorAction SilentlyContinue)
$check['superwhisper starts with Windows'] = [bool](Get-ItemProperty $RunKey -Name superwhisper -ErrorAction SilentlyContinue)
$check['Raycast installed']                = [bool](Get-RaycastPackage)
$check['Raycast running']                  = [bool](Get-Process -Name Raycast -ErrorAction SilentlyContinue)
$check['Raycast starts with Windows']      = [bool]((Get-ScheduledTask -TaskPath '\Raycast\' -ErrorAction SilentlyContinue) -or (Get-ItemProperty $RunKey -Name Raycast -ErrorAction SilentlyContinue))

foreach ($k in $check.Keys) {
    if ($check[$k]) { Write-Log $k 'OK' } else { Write-Log "$k - NO" 'WARN' }
}
$failed = @($check.Keys | Where-Object { -not $check[$_] })
if ($failed.Count -eq 0) {
    Write-Log 'All done!' 'OK'
    Show-Info ("All done!`n`n" +
        " - $HotkeyText : Flameshot. Select an area, then Ctrl+C to copy (or the Copy button, or double-click).`n" +
        " - superwhisper and Raycast (Alt+Space) are running.`n" +
        " - All three start automatically with Windows.`n`n" +
        "Next: open superwhisper and enter your license, and sign in to Raycast if you like.`n`n" +
        "If anything ever stops working: Start menu > 'Windows Quick Setup (repair)'.")
} elseif (-not $installed['Raycast'] -and @($failed | Where-Object { $_ -notlike 'Raycast*' }).Count -eq 0) {
    Write-Log 'Done - everything except Raycast.' 'WARN'
    Show-Info ("Done - Flameshot and superwhisper are set up:`n`n" +
        " - $HotkeyText : Flameshot. Select an area, then Ctrl+C to copy.`n" +
        " - Both start automatically with Windows.`n`n" +
        "Raycast could not be installed automatically because the Microsoft Store is not working on this PC " +
        "(for example no region is set). Its download page is open - install it from there; " +
        "Raycast then starts with Windows by itself.`n`n" +
        "Next: open superwhisper and enter your license.") 48
} else {
    Show-Info ("Finished, but these need attention:`n`n - " + ($failed -join "`n - ") + "`n`nDetails are in:`n$LogFile") 48
}
