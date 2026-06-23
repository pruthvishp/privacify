# Building the Privacify EXE

`Privacify.iss` packages the existing PowerShell installer as a Windows setup EXE.

## Prerequisite

Install [Inno Setup 6](https://jrsoftware.org/isinfo.php), or use WinGet:

```powershell
winget install --id JRSoftware.InnoSetup -e
```

## Build

From the repository root:

```powershell
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" .\installer\Privacify.iss
```

The resulting installer is written to:

```text
dist\PrivacifySetup.exe
```

## Installer behavior

The EXE embeds the repository's installation payload and invokes `install.ps1 -StartAtLogin`. The existing installer then installs or reuses Ollama and AutoHotkey, downloads the portable Node runtime and selected local model, starts the manager UI, and enables the hotkeys at sign-in.

The EXE is unsigned. For public distribution, sign the released `PrivacifySetup.exe` with the project code-signing certificate before publishing it.
