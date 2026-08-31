# Contributing

Keep changes small and aligned with both Windows and macOS. Do not add a third tool until the same behavior exists on both platforms.

## Invariants (do not break)

- **No global/user env writes.** Only process-scoped injection (`HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` / `NO_PROXY` / `no_proxy`).
- **Never `--proxy-server`** for Electron. The UI is a local `https://127.0.0.1:<port>` page.
- **Always inject `NO_PROXY`/`no_proxy`** when proxy vars are set (default `127.0.0.1,localhost`).
- **CLI wrappers are `opencode-proxy` / `agy-proxy`.** Do not shadow `opencode` / `agy`.
- **Markers stay under `$HOME` / `%USERPROFILE%`** as named in `config.json`.

Shared inject logic lives in `macos/lib.zsh` and `scripts/ProxySwitcher.ps1`. Use those; do not add a fifth copy.

## How to test

macOS (from repo root):

```bash
shellcheck install.sh macos/*.sh macos/lib.zsh macos/profile.zsh
zsh -n macos/lib.zsh macos/launch.sh macos/switcher.sh macos/profile.zsh macos/open-menu.sh macos/install.sh
bash -n install.sh
```

Windows / any machine with PowerShell 7:

```powershell
pwsh -File scripts/validate.ps1
```

Manual checks that matter:

1. Menu [1]–[4] only toggle marker files; they do not launch apps.
2. Menu [5]/[6] respect the marker (do not force-enable) and return to the menu on missing desktop paths.
3. With the desktop app already running, flip the marker and launch again — the old instance should quit and the new one should match the marker (proxy on **or** off).
4. `opencode-proxy` / `agy-proxy` do not leave proxy vars in the current shell after the command exits.

## PRs

Describe OS, tool (opencode / antigravity), and desktop vs CLI. Prefer a short CHANGELOG note under Unreleased.
