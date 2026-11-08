# Replace Nocebook/LiquidGlass main with the local Glassify tree.
#
# Steps:
#   1) point origin at the repo
#   2) fetch
#   3) save remote main as a backup tag
#   4) commit any local change
#   5) force push main
#
# Usage (run in your own PowerShell, needs network):
#   powershell -ExecutionPolicy Bypass -File scripts\replace_repo.ps1
#
# If git fails with "schannel: failed to receive handshake",
# every step is retried once with the openssl TLS backend.
param(
    [string]$Remote = 'https://github.com/Nocebook/LiquidGlass.git',
    [string]$BackupTag = 'legacy-7.4.0'
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Run-Git([string[]]$GitArgs) {
    & git @GitArgs | Out-Host
    if ($LASTEXITCODE -eq 0) { return $true }

    Write-Host "  retry with openssl backend: git $($GitArgs -join ' ')" -ForegroundColor Yellow
    & git -c http.sslBackend=openssl @GitArgs | Out-Host
    return ($LASTEXITCODE -eq 0)
}

Write-Host "[1/5] remote" -ForegroundColor Cyan
$existing = git remote
if ($existing -contains 'origin') {
    git remote set-url origin $Remote
} else {
    git remote add origin $Remote
}
Write-Host "      $Remote" -ForegroundColor DarkGray

Write-Host "[2/5] fetch" -ForegroundColor Cyan
if (-not (Run-Git @('fetch', 'origin', '--tags'))) {
    Write-Host "fetch failed - network or proxy issue, nothing was changed" -ForegroundColor Red
    exit 1
}

Write-Host "[3/5] backup tag $BackupTag" -ForegroundColor Cyan
if (-not (Run-Git @('tag', '-f', $BackupTag, 'origin/main'))) {
    Write-Host "cannot create backup tag - abort" -ForegroundColor Red
    exit 1
}
if (-not (Run-Git @('push', 'origin', $BackupTag, '--force'))) {
    Write-Host "backup push failed - abort, remote untouched" -ForegroundColor Red
    exit 1
}

Write-Host "[4/5] commit" -ForegroundColor Cyan
git add -A | Out-Host
$pending = git status --porcelain
if ($pending) {
    if (-not (Run-Git @('commit', '-m', '8.0.0: replace with Glassify'))) {
        Write-Host "commit failed - abort" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "      nothing new to commit" -ForegroundColor DarkGray
}

Write-Host "[5/5] force push main" -ForegroundColor Cyan
if (-not (Run-Git @('push', '--force', 'origin', 'main'))) {
    Write-Host ""
    Write-Host "push failed." -ForegroundColor Red
    Write-Host "  - make sure the browser is logged in as Nocebook"
    Write-Host "  - if it says schannel / TLS: rerun, or use"
    Write-Host "      git -c http.sslBackend=openssl push --force origin main"
    exit 1
}

Write-Host ""
Write-Host "DONE. backup tag: $BackupTag" -ForegroundColor Green
Write-Host "  actions:  https://github.com/Nocebook/LiquidGlass/actions"
Write-Host "  rollback: git push --force origin ${BackupTag}:main"
