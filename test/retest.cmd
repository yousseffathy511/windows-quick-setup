@echo off
rem Run inside the sandbox (wsb exec -r ExistingLogin): repair run, then Undo, with checks after each.
set "LOG=C:\Users\WDAGUtilityAccount\AppData\Local\WindowsQuickSetup\retest.txt"
set "REPO=C:\Users\WDAGUtilityAccount\Desktop\windows-quick-setup"
echo === repair run (-Yes) %TIME% > "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\setup.ps1" -Yes >> "%LOG%" 2>&1
echo === after repair %TIME% >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\test\hotkey-check.ps1" >> "%LOG%" 2>&1
echo === undo run (-Undo -Yes) %TIME% >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\setup.ps1" -Undo -Yes >> "%LOG%" 2>&1
echo === after undo %TIME% >> "%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\test\hotkey-check.ps1" >> "%LOG%" 2>&1
echo DONE %TIME% >> "%LOG%"
