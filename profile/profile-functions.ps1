# ============================================================
# proxy-switcher - optional PowerShell profile functions
#
# Dot-source this file from your PowerShell profile to add the
# explicit commands `opencode-proxy` and `agy-proxy`.
#
#   Add to $PROFILE:
#     . "C:\path\to\proxy-switcher\profile\profile-functions.ps1"
#
# Why functions instead of PATH wrappers?
#   * Windows resolves .EXE before .BAT for same-named commands,
#     so a same-name bat cannot shadow agy.exe without PATH
#     surgery (fragile).
#   * Explicit names avoid overwriting existing opencode/agy
#     functions, including user plugins and custom profile logic.
# ============================================================

. (Join-Path $PSScriptRoot '..\scripts\ProxySwitcher.ps1')

function agy-proxy {
    $cli = Resolve-ProxySwitcherCli -App antigravity
    Invoke-ProxySwitcherCommand -App antigravity -CommandPath $cli @args
}

function opencode-proxy {
    $cli = Resolve-ProxySwitcherCli -App opencode
    Invoke-ProxySwitcherCommand -App opencode -CommandPath $cli @args
}
