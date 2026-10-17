# Waymark docs sync (Windows PowerShell). Stages ONLY the waymark/ folder, plus the
# one allowed bundle file when -Bundle is passed.
# Usage: .\waymark\tools\sync.ps1 "short message"   [-Bundle]
param(
  [string]$Message = "sync",
  [switch]$Bundle
)
$ErrorActionPreference = "Stop"
Set-Location (git rev-parse --show-toplevel)
git status --short waymark/ | Select-Object -First 40
git pull --rebase --autostash origin main
if ($LASTEXITCODE -ne 0) { throw "pull failed" }
git add waymark/
if ($Bundle) { git add ios/CaneKit/Resources/waymark_priors.json }
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) { git commit -m "waymark: $Message" }
git push origin HEAD:main
if ($LASTEXITCODE -ne 0) { throw "push failed" }
git log -1 --format="synced: %h %cI"
