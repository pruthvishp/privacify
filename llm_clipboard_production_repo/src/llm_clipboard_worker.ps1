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

function Invoke-PrivacifyRedaction {
    param([Parameter(Mandatory=$true)][string]$Text)

    $redacted = $Text

    $redacted = [regex]::Replace($redacted, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[EMAIL]')
    $redacted = [regex]::Replace($redacted, '\b\d{3}-\d{2}-\d{4}\b', '[SSN]')
    $redacted = [regex]::Replace($redacted, '(?x)(?<!\d)(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}(?!\d)', '[PHONE]')
    $redacted = [regex]::Replace($redacted, '(?x)(?<!\d)(?:\d[ -]?){13,19}(?!\d)', '[PAYMENT_CARD]')
    $redacted = [regex]::Replace($redacted, '\b(?:\d{1,3}\.){3}\d{1,3}\b', '[IP_ADDRESS]')
    $redacted = [regex]::Replace($redacted, '(?i)\b\d{1,6}\s+[A-Z0-9][A-Z0-9 .''-]*\s+(?:Street|St|Avenue|Ave|Road|Rd|Drive|Dr|Lane|Ln|Boulevard|Blvd|Court|Ct|Way|Place|Pl)\b(?:[,\s]+(?:Apt|Apartment|Suite|Ste|Unit)\s*[A-Z0-9-]+)?', '[ADDRESS]')

    $labelPattern = '(?im)\b(?<label>(?:full[ \t]+name|name|customer|client|patient|employee)[ \t]*:[ \t]*)(?<value>[A-Z][a-z]+(?:[ \t]+[A-Z][a-z]+){1,3})\b'
    $redacted = [regex]::Replace($redacted, $labelPattern, {
        param($match)
        return $match.Groups['label'].Value + '[NAME]'
    })

    return $redacted
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

$isPrivacifyProfile = $ProfileName -eq "privacify"
if ($isPrivacifyProfile) {
    $inputText = Invoke-PrivacifyRedaction -Text $inputText
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

$useModel = $true
if ($isPrivacifyProfile -and $null -ne $config.privacify_use_model) {
    $useModel = [bool]$config.privacify_use_model
}

if ($useModel) {
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
}
else {
    Write-DebugLog "profile=$ProfileName | skipped_ollama"
    $output = $inputText
}

if ($config.trim_output -and $null -ne $output) {
    $output = $output.Trim()
}

if ($isPrivacifyProfile -and $null -ne $output) {
    $output = Invoke-PrivacifyRedaction -Text $output
}

if ([string]::IsNullOrWhiteSpace($output)) {
    throw "Model returned empty output."
}

Set-Content -LiteralPath $OutputFile -Value $output -Encoding UTF8
Write-DebugLog "profile=$ProfileName | output_chars=$($output.Length)"
