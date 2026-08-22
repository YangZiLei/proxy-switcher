$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$errors = @()

function Test-RequiredJsonFields {
    param([string]$Path, [string]$Label)
    $cfg = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $required = @('proxy.url', 'markers.opencode', 'markers.antigravity', 'apps.opencode.cli', 'apps.antigravity.cli')
    foreach ($key in $required) {
        $node = $cfg
        foreach ($seg in $key.Split('.')) { $node = $node.$seg }
        if ($null -eq $node) { $errors += "$Label: missing required field '$key'" }
    }
}

$example = Join-Path $root 'config.example.json'
if (Test-Path -LiteralPath $example) { Test-RequiredJsonFields $example 'config.example.json' }

$userConfig = Join-Path $root 'config.json'
if (Test-Path -LiteralPath $userConfig) { Test-RequiredJsonFields $userConfig 'config.json' }

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
