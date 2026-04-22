param(
    [Parameter(Mandatory=$true)][string]$ProfileName,
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [Parameter(Mandatory=$true)][string]$InputFile,
    [Parameter(Mandatory=$true)][string]$OutputFile
)

$ErrorActionPreference = "Stop"

function Write-DebugLog {
    param([string]$Message)
    $logPath = Join-Path (Split-Path -Parent $ConfigPath) "llm_clipboard_debug.log"
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Message"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}
if (-not (Test-Path -LiteralPath $InputFile)) {
    throw "Input file not found: $InputFile"
}

$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
$profile = $config.profiles | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1

if (-not $profile) {
    throw "Profile not found in config.json: $ProfileName"
}
if (-not (Test-Path -LiteralPath $profile.prompt_file)) {
    throw "Prompt file not found: $($profile.prompt_file)"
}

$inputText = Get-Content -Raw -LiteralPath $InputFile
if ([string]::IsNullOrWhiteSpace($inputText)) {
    throw "Input text was empty."
}

$prompt = Get-Content -Raw -LiteralPath $profile.prompt_file

$fullPrompt = @"
$prompt

Input text:
$inputText
"@

$body = @{
    model  = $config.model
    prompt = $fullPrompt
    stream = $false
} | ConvertTo-Json -Depth 6

Write-DebugLog "profile=$ProfileName | request_chars=$($fullPrompt.Length) | input_chars=$($inputText.Length)"

try {
    Write-DebugLog "profile=$ProfileName | calling_ollama"
    $response = Invoke-RestMethod -Uri $config.ollama_url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 120
    Write-DebugLog "profile=$ProfileName | ollama_returned"
}
catch {
    Write-DebugLog "profile=$ProfileName | ollama_error=$($_.Exception.Message)"
    throw "Ollama request failed or timed out: $($_.Exception.Message)"
}

$output = [string]$response.response
if ($config.trim_output -and $null -ne $output) {
    $output = $output.Trim()
}

if ([string]::IsNullOrWhiteSpace($output)) {
    throw "Model returned empty output."
}

Set-Content -LiteralPath $OutputFile -Value $output -Encoding UTF8
Write-DebugLog "profile=$ProfileName | output_chars=$($output.Length)"
