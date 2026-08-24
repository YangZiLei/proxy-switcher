$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$errors = @()

function Test-RequiredJsonFields {
    # Returns missing-field findings as a string array. Kept pure on purpose:
    # an in-function '$errors +=' would only mutate a function-local copy and
    # the caller's $errors would stay empty (PowerShell scoping).
    param([string]$Path, [string]$Label)
    $missing = @()
    $cfg = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $required = @('proxy.url', 'markers.opencode', 'markers.antigravity', 'apps.opencode.cli', 'apps.antigravity.cli')
    foreach ($key in $required) {
        $node = $cfg
        foreach ($seg in $key.Split('.')) { $node = $node.$seg }
        if ($null -eq $node) { $missing += "${Label}: missing required field '$key'" }
    }
    return $missing
}

$example = Join-Path $root 'config.example.json'
if (Test-Path -LiteralPath $example) { $errors += @(Test-RequiredJsonFields $example 'config.example.json') }

$userConfig = Join-Path $root 'config.json'
if (Test-Path -LiteralPath $userConfig) { $errors += @(Test-RequiredJsonFields $userConfig 'config.json') }

Get-ChildItem $root -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) { $errors += "$($_.FullName): $($parseErrors[0].Message)" }
}

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Configuration and PowerShell syntax are valid.'
