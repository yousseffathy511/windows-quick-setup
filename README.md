# Windows Quick Setup: Flameshot · superwhisper · Raycast

One click sets up any Windows 10/11 PC with three apps, already configured:

| App | What you get |
|---|---|
| **Flameshot** | **Win + Shift + S** opens a screenshot capture. Drag over an area, then **Ctrl + C** (or the Copy button, or a double-click inside the box) copies it, ready to paste into WhatsApp, Word, Discord… |
| **superwhisper** | Voice to text. |
| **Raycast** | Fast app launcher: **Alt + Space**. |

- All three **start automatically every time Windows starts**, after restarts, shutdowns and updates.
- **Print Screen keeps working as normal** (Windows' own Snipping Tool).
- Safe to run again at any time: it repairs anything that's missing.

## Install (one click)

1. Download **[Install.cmd](https://github.com/yousseffathy511/windows-quick-setup/releases/latest/download/Install.cmd)**.
2. Double-click it.
   *If Windows says "Windows protected your PC", click **More info → Run anyway**. The script isn't code-signed, but you can read every line in [`setup.ps1`](setup.ps1).*
3. Click **Yes** on *"Install them and make them your defaults?"*, and **Yes** if Windows asks for permission to install Flameshot.

When it finishes you'll see **"All done!"**. Then:
- Open **superwhisper** and enter **your own license** (no license keys are stored in this repo).
- Sign in to **Raycast** if you want its account features.

**Alternative (nothing to download):** press **Win + R**, paste this, press Enter:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; & ([scriptblock]::Create((irm https://raw.githubusercontent.com/yousseffathy511/windows-quick-setup/main/setup.ps1)))"
```

## If something stops working

Start menu → **Windows Quick Setup (repair)**. It re-applies everything in under a minute, without asking any questions.

## Undo

Download and double-click **[Undo.cmd](https://github.com/yousseffathy511/windows-quick-setup/releases/latest/download/Undo.cmd)**. It gives Win + Shift + S back to Windows, stops the apps from starting with Windows, and then asks whether to uninstall the apps too.

## What it changes on the PC

| Change | Where |
|---|---|
| Installs Flameshot, superwhisper, Raycast | Official sources through Microsoft's **WinGet** (`Flameshot.Flameshot`, `SuperUltra.superwhisper`, Microsoft Store `9PFXXSHC64H3`). If WinGet is missing it's installed the [official Microsoft way](https://learn.microsoft.com/windows/package-manager/winget); if that fails, the apps are downloaded directly from their official sites. |
| Frees Win + Shift + S from Windows | `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` → `DisabledHotkeys = S` (also frees Win + S, see notes) |
| Flameshot settings | `%APPDATA%\flameshot\flameshot.ini`: shortcut Win + Shift + S, capture the screen under the mouse, double-click copies. The file is set to **read-only** on purpose (see notes). |
| Start with Windows | `HKCU\...\CurrentVersion\Run` entries for Flameshot and superwhisper (plus superwhisper's own *Launch at login* setting). Raycast uses its own *Open at Login* task. |
| Repair shortcut + log | Start menu shortcut, and `%LOCALAPPDATA%\WindowsQuickSetup\setup-log.txt` |

## Notes

- **Win + S (Windows search shortcut) is turned off.** Windows ties Win + S and Win + Shift + S to the same letter, so freeing one frees both. Press the Windows key and type to search, or use Raycast.
- **Enter doesn't copy** in Flameshot 14 when a capture is started from a shortcut. That's how Flameshot is built. Use Ctrl + C, the Copy button, or double-click.
- **Why read-only?** Flameshot 14 can recreate its settings file *empty* while saving it, which silently loses the shortcut. Read-only prevents that. To change Flameshot settings yourself, untick *Read-only* on `%APPDATA%\flameshot\flameshot.ini` first.
- **Raycast** is distributed through the Microsoft Store, so it needs the Store to be available. It is on every normal Windows 10/11 PC, but not in Windows Sandbox. If the Store can't install it (for example no region is set), the installer gives up after at most 5 minutes, opens Raycast's download page, and finishes everything else. It never hangs.
- Different shortcut? Run `setup.ps1 -Hotkey "Meta+Ctrl+S"` (Meta = the Windows key).

## Testing

`test\Test-InSandbox.ps1 -Auto` opens a clean Windows Sandbox, runs `Install.cmd` exactly like a user (answering its questions), then presses Win+Shift+S, drags a box, presses Ctrl+C and checks the clipboard, and presses Print Screen. Logs and screenshots land in `test\sandbox-logs`.

Last result (Windows 11 24H2 Sandbox, no WinGet preinstalled):
- WinGet installed automatically; Flameshot and superwhisper installed
- Win+Shift+S → Flameshot capture; Ctrl+C → image on the clipboard ✅
- Print Screen → Windows' own Snipping Tool ✅
- Both apps registered to start with Windows; repair shortcut created ✅
- Undo returned Win+Shift+S to Windows and removed the startup entries ✅
- Raycast: not installable in the Sandbox (no Microsoft Store region). Handled without hanging.

It's also running daily on the author's own Windows 11 laptop, and survives restarts.

## License

MIT. Flameshot, superwhisper and Raycast belong to their respective owners and are downloaded from their official sources.
