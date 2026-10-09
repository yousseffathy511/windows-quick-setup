# Saves a screenshot of the sandbox screen into the mapped log folder (run via wsb exec -r ExistingLogin)
param([string]$Name = 'shot')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save((Join-Path $env:LOCALAPPDATA "WindowsQuickSetup\$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { "$($_.ProcessName): $($_.MainWindowTitle)" } | Set-Content (Join-Path $env:LOCALAPPDATA "WindowsQuickSetup\$Name-windows.txt")
