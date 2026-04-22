[CmdletBinding()]
param(
    [string]$InstallDir = "$env:USERPROFILE\LLMClipboardPaste",
    [string]$Model = "phi3",
    [switch]$StartAtLogin
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Get-OllamaExe {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:LOCALAPPDATA\Ollama\ollama.exe",
        "$env:ProgramFiles\Ollama\ollama.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-AutoHotkeyExe {
    $candidates = @(
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\AutoHotkey64.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\AutoHotkey64.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $cmd = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Ensure-WingetPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wg) { throw "WinGet is required for $Name but was not found on this PC." }

    Write-Step "Installing $Name with WinGet"
    & winget install --id $Id -e --accept-package-agreements --accept-source-agreements --disable-interactivity
}

function Ensure-Ollama {
    $ollama = Get-OllamaExe
    if ($ollama) { return $ollama }

    try {
        Ensure-WingetPackage -Id "Ollama.Ollama" -Name "Ollama"
    }
    catch {
        Write-Warning "WinGet install for Ollama failed. Falling back to the official installer script."
        Invoke-RestMethod https://ollama.com/install.ps1 | Invoke-Expression
    }

    Refresh-Path
    $ollama = Get-OllamaExe
    if (-not $ollama) { throw "Ollama was not found after installation." }
    return $ollama
}

function Ensure-AutoHotkey {
    $ahk = Get-AutoHotkeyExe
    if ($ahk) { return $ahk }

    try {
        Ensure-WingetPackage -Id "AutoHotkey.AutoHotkey" -Name "AutoHotkey v2"
    }
    catch {
        Write-Warning "WinGet install for AutoHotkey failed. Falling back to the GitHub v2.0.23 installer."
        $tmp = Join-Path $env:TEMP "AutoHotkey_2.0.23_setup.exe"
        Invoke-WebRequest -Uri "https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.23/AutoHotkey_2.0.23_setup.exe" -OutFile $tmp
        Start-Process -FilePath $tmp -ArgumentList "/S" -Wait
    }

    Refresh-Path
    $ahk = Get-AutoHotkeyExe
    if (-not $ahk) { throw "AutoHotkey v2 was not found after installation." }
    return $ahk
}

function Ensure-OllamaServer {
    param([Parameter(Mandatory=$true)][string]$OllamaExe)

    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 2 | Out-Null
        return
    }
    catch {
    }

    Write-Step "Starting Ollama"
    Start-Process -FilePath $OllamaExe -WindowStyle Hidden | Out-Null

    $ok = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 750
        try {
            Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 2 | Out-Null
            $ok = $true
            break
        }
        catch {
        }
    }

    if (-not $ok) {
        throw "Ollama did not become ready on http://127.0.0.1:11434"
    }
}

function Ensure-Model {
    param(
        [Parameter(Mandatory=$true)][string]$OllamaExe,
        [Parameter(Mandatory=$true)][string]$ModelName
    )

    Write-Step "Ensuring model $ModelName is available"
    & $OllamaExe pull $ModelName
}

function Install-AppFiles {
    param(
        [Parameter(Mandatory=$true)][string]$TargetDir,
        [Parameter(Mandatory=$true)][string]$SelectedModel
    )

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $TargetDir "prompts") | Out-Null

    $here = $PSScriptRoot
    Copy-Item -LiteralPath (Join-Path $here "src\llm_clipboard.ahk") -Destination (Join-Path $TargetDir "llm_clipboard.ahk") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\llm_clipboard_worker.ps1") -Destination (Join-Path $TargetDir "llm_clipboard_worker.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\prompts\rewrite.txt") -Destination (Join-Path $TargetDir "prompts\rewrite.txt") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\prompts\summarize.txt") -Destination (Join-Path $TargetDir "prompts\summarize.txt") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\prompts\bullets.txt") -Destination (Join-Path $TargetDir "prompts\bullets.txt") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\prompts\privacify.txt") -Destination (Join-Path $TargetDir "prompts\privacify.txt") -Force

    $config = @{
        model = $SelectedModel
        ollama_url = "http://127.0.0.1:11434/api/generate"
        trim_output = $true
        profiles = @(
            @{ name = "rewrite";   hotkey = "^!1"; prompt_file = (Join-Path $TargetDir "prompts\rewrite.txt") },
            @{ name = "summarize"; hotkey = "^!2"; prompt_file = (Join-Path $TargetDir "prompts\summarize.txt") },
            @{ name = "bullets";   hotkey = "^!3"; prompt_file = (Join-Path $TargetDir "prompts\bullets.txt") },
            @{ name = "privacify"; hotkey = "^!4"; prompt_file = (Join-Path $TargetDir "prompts\privacify.txt") }
        )
    }

    $config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $TargetDir "config.json") -Encoding UTF8
}

function Register-StartupShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$AutoHotkeyExe,
        [Parameter(Mandatory=$true)][string]$ScriptPath
    )

    $startup = [Environment]::GetFolderPath("Startup")
    $shortcutPath = Join-Path $startup "LLM Clipboard Paste.lnk"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $AutoHotkeyExe
    $shortcut.Arguments = '"' + $ScriptPath + '"'
    $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
    $shortcut.IconLocation = "$AutoHotkeyExe,0"
    $shortcut.Save()
}

Write-Step "Installing dependencies"
$ollamaExe = Ensure-Ollama
$ahkExe = Ensure-AutoHotkey

Write-Step "Preparing app files"
Install-AppFiles -TargetDir $InstallDir -SelectedModel $Model

Ensure-OllamaServer -OllamaExe $ollamaExe
Ensure-Model -OllamaExe $ollamaExe -ModelName $Model

$scriptPath = Join-Path $InstallDir "llm_clipboard.ahk"

if ($StartAtLogin) {
    Write-Step "Registering startup shortcut"
    Register-StartupShortcut -AutoHotkeyExe $ahkExe -ScriptPath $scriptPath
}

Write-Step "Launching hotkey app"
Start-Process -FilePath $ahkExe -ArgumentList ('"' + $scriptPath + '"') -WorkingDirectory $InstallDir | Out-Null

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Install directory: $InstallDir"
Write-Host "Model: $Model"
Write-Host "Hotkeys:"
Write-Host "  Ctrl+Alt+1 = rewrite"
Write-Host "  Ctrl+Alt+2 = summarize"
Write-Host "  Ctrl+Alt+3 = bullets"
Write-Host "  Ctrl+Alt+4 = privacify"
Write-Host ""
Write-Host "Use -StartAtLogin if you want it to auto-start when the user signs in."
