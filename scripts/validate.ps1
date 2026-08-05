$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$config = Join-Path $root 'config.example.json'
Get-Content $config -Raw | ConvertFrom-Json | Out-Null

$errors = @()
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
