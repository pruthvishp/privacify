[CmdletBinding()]
param(
    [string]$InstallDir = "$env:USERPROFILE\LLMClipboardPaste",
    [string]$Model = "qwen2.5:3b",
    [string]$NodeVersion = "20.11.1",
    [int]$ManagerPort = 8787,
    [switch]$StartAtLogin,
    [switch]$SkipOllama,
    [switch]$SkipManagerUi,
    [switch]$NoLaunchManager
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
    & winget install --id $Id -e --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
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

function Get-NodeArch {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "ARM64" { return "arm64" }
        default { return "x64" }
    }
}

function Get-BundledNodeExe {
    param([Parameter(Mandatory=$true)][string]$TargetDir)

    $nodeRoot = Join-Path $TargetDir "runtime\node"
    $nodeExe = Join-Path $nodeRoot "node.exe"
    if (Test-Path -LiteralPath $nodeExe) { return $nodeExe }
    return $null
}

function Ensure-BundledNode {
    param(
        [Parameter(Mandatory=$true)][string]$TargetDir,
        [Parameter(Mandatory=$true)][string]$Version
    )

    $existing = Get-BundledNodeExe -TargetDir $TargetDir
    if ($existing) { return $existing }

    $arch = Get-NodeArch
    $nodeName = "node-v$Version-win-$arch"
    $nodeUrl = "https://nodejs.org/dist/v$Version/$nodeName.zip"
    $downloadPath = Join-Path $env:TEMP "$nodeName.zip"
    $extractPath = Join-Path $env:TEMP $nodeName
    $runtimeDir = Join-Path $TargetDir "runtime"
    $nodeRoot = Join-Path $runtimeDir "node"

    Write-Step "Installing bundled Node.js $Version ($arch) for the manager UI"
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

    if (Test-Path -LiteralPath $downloadPath) {
        Remove-Item -LiteralPath $downloadPath -Force
    }
    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Recurse -Force
    }

    Invoke-WebRequest -Uri $nodeUrl -OutFile $downloadPath
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $env:TEMP -Force

    if (Test-Path -LiteralPath $nodeRoot) {
        Remove-Item -LiteralPath $nodeRoot -Recurse -Force
    }
    Move-Item -LiteralPath $extractPath -Destination $nodeRoot

    $nodeExe = Join-Path $nodeRoot "node.exe"
    if (-not (Test-Path -LiteralPath $nodeExe)) {
        throw "Bundled Node.js was not found after extraction."
    }

    return $nodeExe
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
    Copy-Item -LiteralPath (Join-Path $here "src\privacify_manager.js") -Destination (Join-Path $TargetDir "privacify_manager.js") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\prompts\rewrite.txt") -Destination (Join-Path $TargetDir "prompts\rewrite.txt") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\prompts\summarize.txt") -Destination (Join-Path $TargetDir "prompts\summarize.txt") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\prompts\bullets.txt") -Destination (Join-Path $TargetDir "prompts\bullets.txt") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\prompts\privacify.txt") -Destination (Join-Path $TargetDir "prompts\privacify.txt") -Force
    Copy-Item -LiteralPath (Join-Path $here "src\privacify_examples.json") -Destination (Join-Path $TargetDir "privacify_examples.json") -Force

    $config = @{
        model = $SelectedModel
        ollama_url = "http://127.0.0.1:11434/api/generate"
        trim_output = $true
        privacify_use_model = $true
        privacify_examples_enabled = $true
        privacify_examples_limit = 60
        privacify_examples_file = (Join-Path $TargetDir "privacify_examples.json")
        app_name = "Privacify"
        accent_color = "#2563eb"
        image_path = ""
        profiles = @(
            @{ name = "rewrite";   hotkey = "^!1"; prompt_file = (Join-Path $TargetDir "prompts\rewrite.txt") },
            @{ name = "summarize"; hotkey = "^!2"; prompt_file = (Join-Path $TargetDir "prompts\summarize.txt") },
            @{ name = "bullets";   hotkey = "^!3"; prompt_file = (Join-Path $TargetDir "prompts\bullets.txt") },
            @{ name = "privacify"; hotkey = "^!4"; prompt_file = (Join-Path $TargetDir "prompts\privacify.txt") }
        )
    }

    $config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $TargetDir "config.json") -Encoding UTF8
}

function Write-ManagerLauncher {
    param(
        [Parameter(Mandatory=$true)][string]$TargetDir,
        [Parameter(Mandatory=$true)][string]$NodeExe,
        [Parameter(Mandatory=$true)][int]$Port
    )

    $launcherPath = Join-Path $TargetDir "Start Privacify Manager.ps1"
    $managerPath = Join-Path $TargetDir "privacify_manager.js"
    $content = @"
`$ErrorActionPreference = "Stop"
`$node = "$NodeExe"
`$manager = "$managerPath"
`$port = $Port

Start-Process -FilePath `$node -ArgumentList @("`"`$manager`"", "`$port") -WorkingDirectory "$TargetDir" -WindowStyle Hidden | Out-Null
Start-Sleep -Milliseconds 700
Start-Process "http://127.0.0.1:`$port/"
"@

    Set-Content -LiteralPath $launcherPath -Value $content -Encoding UTF8
    return $launcherPath
}

function Register-DesktopShortcut {
    param(
        [Parameter(Mandatory=$true)][string]$ShortcutName,
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [string]$IconLocation = ""
    )

    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "$ShortcutName.lnk"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
    if ($IconLocation) { $shortcut.IconLocation = $IconLocation }
    $shortcut.Save()

    return $shortcutPath
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
if (-not $SkipOllama) {
    $ollamaExe = Ensure-Ollama
}
$ahkExe = Ensure-AutoHotkey

Write-Step "Preparing app files"
Install-AppFiles -TargetDir $InstallDir -SelectedModel $Model

$managerLauncher = $null
if (-not $SkipManagerUi) {
    $nodeExe = Ensure-BundledNode -TargetDir $InstallDir -Version $NodeVersion
    $managerLauncher = Write-ManagerLauncher -TargetDir $InstallDir -NodeExe $nodeExe -Port $ManagerPort
    Register-DesktopShortcut `
        -ShortcutName "Privacify Manager" `
        -TargetPath "powershell.exe" `
        -Arguments ('-ExecutionPolicy Bypass -File "' + $managerLauncher + '"') `
        -WorkingDirectory $InstallDir `
        -IconLocation "$nodeExe,0" | Out-Null
}

if (-not $SkipOllama) {
    Ensure-OllamaServer -OllamaExe $ollamaExe
    Ensure-Model -OllamaExe $ollamaExe -ModelName $Model
}

$scriptPath = Join-Path $InstallDir "llm_clipboard.ahk"

if ($StartAtLogin) {
    Write-Step "Registering startup shortcut"
    Register-StartupShortcut -AutoHotkeyExe $ahkExe -ScriptPath $scriptPath
}

Write-Step "Launching hotkey app"
Start-Process -FilePath $ahkExe -ArgumentList ('"' + $scriptPath + '"') -WorkingDirectory $InstallDir | Out-Null

if ($managerLauncher -and -not $NoLaunchManager) {
    Write-Step "Launching manager UI"
    Start-Process -FilePath "powershell.exe" -ArgumentList ('-ExecutionPolicy Bypass -File "' + $managerLauncher + '"') -WorkingDirectory $InstallDir -WindowStyle Hidden | Out-Null
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Install directory: $InstallDir"
Write-Host "Model: $Model"
if ($SkipOllama) {
    Write-Host "Ollama setup skipped. Rewrite, summarize, and bullets need Ollama before use."
}
Write-Host "Hotkeys:"
Write-Host "  Ctrl+Alt+1 = rewrite"
Write-Host "  Ctrl+Alt+2 = summarize"
Write-Host "  Ctrl+Alt+3 = bullets"
Write-Host "  Ctrl+Alt+4 = privacify"
Write-Host "Manager UI:"
if ($SkipManagerUi) {
    Write-Host "  Manager UI setup skipped."
}
else {
    Write-Host "  http://127.0.0.1:$ManagerPort/"
    Write-Host "  Desktop shortcut: Privacify Manager"
    Write-Host "  Launcher: $managerLauncher"
}
Write-Host ""
Write-Host "Use -StartAtLogin if you want it to auto-start when the user signs in."
