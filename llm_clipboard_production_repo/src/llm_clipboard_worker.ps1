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

    $redacted = [regex]::Replace($redacted, '(?i)\bhttps?://[^\s<>"'']*(?:token|key|secret|password|pwd|auth|session|code)=[^\s<>"'']+', '[SENSITIVE_URL]')
    $redacted = [regex]::Replace($redacted, '(?i)\b((?:api|access|auth|refresh|secret|private|session|bearer)?[ \t]*(?:key|token|secret|password|pwd|passcode|credential))[ \t]*(?:is|:|=)[ \t]*["'']?[^"'',;\r\n\s]{6,}["'']?', '$1 [SECRET]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(authorization\s*:\s*bearer)\s+[A-Za-z0-9._~+/=-]{8,}\b', '$1 [TOKEN]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(aws_access_key_id|aws_secret_access_key|client_secret|private_key|webhook_secret)\s*(?:=|:)\s*["'']?[^"'',;\r\n\s]{6,}["'']?', '$1=[SECRET]')
    $redacted = [regex]::Replace($redacted, '\bsk-[A-Za-z0-9_-]{16,}\b', '[API_KEY]')
    $redacted = [regex]::Replace($redacted, '\bAKIA[0-9A-Z]{16}\b', '[AWS_ACCESS_KEY]')
    $redacted = [regex]::Replace($redacted, '\bgh[pousr]_[A-Za-z0-9_]{20,}\b', '[GITHUB_TOKEN]')
    $redacted = [regex]::Replace($redacted, '\bxox[baprs]-[A-Za-z0-9-]{10,}\b', '[SLACK_TOKEN]')
    $redacted = [regex]::Replace($redacted, '\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b', '[JWT]')

    $redacted = [regex]::Replace($redacted, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[EMAIL]')
    $redacted = [regex]::Replace($redacted, '\b\d{3}-\d{2}-\d{4}\b', '[SSN]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(ssn|social security(?: number)?)[ \t]*(?:is|:|=)?[ \t]*[\w-]*\d[\d \t-]{3,}\b', '$1 [SSN]')
    $redacted = [regex]::Replace($redacted, '(?x)(?<!\d)(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}(?!\d)', '[PHONE]')
    $redacted = [regex]::Replace($redacted, '(?x)(?<!\d)(?:\d[ -]?){13,19}(?!\d)', '[PAYMENT_CARD]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(card|credit card|debit card|cc)[ \t]*(?:is|:|=)?[ \t]*(?:\d[ -]?){13,19}\b', '$1 [PAYMENT_CARD]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(cvv|cvc|security code)[ \t]*(?:is|:|=)?[ \t]*\d{3,4}\b', '$1 [CARD_SECURITY_CODE]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(routing number|routing|account number|bank account|iban|swift|bic)[ \t]*(?:is|:|=)?[ \t]*[A-Z0-9-]{4,34}\b', '$1 [BANK_INFO]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(passport|driver(?:''s)? license|driving licence|license number|national id|tax id|tin|ein)[ \t]*(?:number|no\.?)?[ \t]*(?:is|:|=)?[ \t]*[A-Z0-9-]{4,24}\b', '$1 [GOV_ID]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(claim number|claim id|case number|case id|ticket number|ticket id|employee id|member id|patient id|account id)[ \t]*(?:is|:|=)?[ \t]*[A-Z0-9-]{3,32}\b', '$1 [ID]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(dob|date of birth|birth date|birthday)[ \t]*(?:is|:|=)?[ \t]*(?:\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|[A-Z][a-z]+[ \t]+\d{1,2},?[ \t]+\d{4})\b', '$1 [DATE_OF_BIRTH]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(salary|income|compensation|pay|wage|bonus|revenue|profit|net worth|rent|mortgage|balance|account balance)[ \t]*(?:is|:|=)?[ \t]*(?:USD|INR|EUR|GBP)?[ \t]*\d[\d,]*(?:\.\d{1,2})?[ \t]*(?:dollars?|rupees?|usd|inr|eur|gbp|million|billion|per year|annually|monthly|/year|/yr|/mo|k|m)?', '$1 [AMOUNT]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(paid|earns?|makes?|charges?|costs?|owes?|owed|spent|spends|received|receives)[ \t]*(?:USD|INR|EUR|GBP)?[ \t]*\d[\d,]*(?:\.\d{1,2})?[ \t]*(?:dollars?|rupees?|usd|inr|eur|gbp|million|billion|per year|annually|monthly|/year|/yr|/mo|k|m)?', '$1 [AMOUNT]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(?:\d{1,3}\.){3}\d{1,3}\b', '[IP_ADDRESS]')
    $redacted = [regex]::Replace($redacted, '(?i)\b[0-9a-f]{2}(?::[0-9a-f]{2}){5}\b', '[MAC_ADDRESS]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(?:[0-9a-f]{1,4}:){2,7}[0-9a-f]{1,4}\b', '[IP_ADDRESS]')
    $redacted = [regex]::Replace($redacted, '(?i)\b\d{1,6}[ \t]+[A-Z0-9][A-Z0-9 .''-]*[ \t]+(?:Street|St|Avenue|Ave|Road|Rd|Drive|Dr|Lane|Ln|Boulevard|Blvd|Court|Ct|Way|Place|Pl)\b(?:[,\t ]+(?:Apt|Apartment|Suite|Ste|Unit)[ \t]*[A-Z0-9-]+)?', '[ADDRESS]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(zip|postal code)[ \t]*(?:is|:|=)?[ \t]*\d{5}(?:-\d{4})?\b', '$1 [POSTAL_CODE]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(user(?:name)?|login|handle)[ \t]*(?:is|:|=)[ \t]*@?[A-Z0-9._-]{3,}\b', '$1 [USERNAME]')

    $labelPattern = '(?m)\b(?<label>(?i:full[ \t]+name|name|customer|client|patient|employee)[ \t]*:[ \t]*)(?<value>[A-Z][a-z]+(?:[ \t]+[A-Z][a-z]+){1,3})\b'
    $redacted = [regex]::Replace($redacted, $labelPattern, {
        param($match)
        return $match.Groups['label'].Value + '[NAME]'
    })

    $inlineNamePattern = '(?m)\b(?<label>(?i:my name is|name is|customer is|client is|patient is|employee is)[ \t]+)(?<value>[A-Z][a-z]+(?:[ \t]+[A-Z][a-z]+){1,3})\b'
    $redacted = [regex]::Replace($redacted, $inlineNamePattern, {
        param($match)
        return $match.Groups['label'].Value + '[NAME]'
    })

    $roleNamePattern = '(?m)\b(?<label>(?i:customer|client|patient|employee|member|user)[ \t]+)(?<value>[A-Z][a-z]+(?:[ \t]+[A-Z][a-z]+){1,3})\b'
    $redacted = [regex]::Replace($redacted, $roleNamePattern, {
        param($match)
        return $match.Groups['label'].Value + '[NAME]'
    })

    $redacted = [regex]::Replace($redacted, '\](?=[A-Za-z])', '] ')
    $redacted = [regex]::Replace($redacted, '(?i)\[REDACTED_NAME\]', '[NAME]')
    $redacted = [regex]::Replace($redacted, '(?i)\[REDACTED_SECRET\]', '[SECRET]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(ssn|social security(?: number)?)[ \t]+\[SENSITIVE_VALUE\]', '$1 [SSN]')
    $redacted = [regex]::Replace($redacted, '(?i)\b(salary|income|compensation|pay|wage|bonus|revenue|profit|net worth|rent|mortgage|balance|account balance|paid|earns?|makes?|charges?|costs?|owes?|owed|spent|spends|received|receives)[ \t]+\[SENSITIVE_VALUE\]', '$1 [AMOUNT]')
    $redacted = [regex]::Replace($redacted, '(?i)\[SENSITIVE_VALUE\]', '[REDACTED]')
    $redacted = [regex]::Replace($redacted, '\[AMOUNT\]\$', '[AMOUNT]')
    $redacted = [regex]::Replace($redacted, '(?i)\brouting\s+\[BANK_INFO\]\s+\[BANK_INFO\]', 'routing number [BANK_INFO]')

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
    options = @{
        temperature = 0
        top_p = 0.1
    }
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

[System.IO.File]::WriteAllText($OutputFile, $output, [System.Text.UTF8Encoding]::new($false))
Write-DebugLog "profile=$ProfileName | output_chars=$($output.Length)"
