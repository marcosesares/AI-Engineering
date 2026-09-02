# slice-setup.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][string]$SliceId,
    [Parameter(Mandatory = $true)][string]$BaseSha
)

$ErrorActionPreference = 'Stop'
$env:CI = '1'; $env:NO_COLOR = '1'; $env:GIT_EDITOR = 'true'; $env:GIT_TERMINAL_PROMPT = '0'

$repoRoot = $null
foreach ($line in @(& git worktree list --porcelain 2>$null)) {
    if ($line -match '^worktree (.+)$') { $repoRoot = $Matches[1]; break }
}
if (-not $repoRoot) { $repoRoot = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1) }
if (-not $repoRoot) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'not-a-git-repo'; errors = @('git worktree list / rev-parse failed') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
$repoRoot = $repoRoot.Trim()

$slicePath = Join-Path $repoRoot ".claude\worktrees\slice-$SliceId"
$taskPath  = Join-Path $repoRoot ".claude\worktrees\task-$TaskId"
$branch    = "slice/$SliceId"

if (Test-Path -LiteralPath $slicePath) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'worktree-exists'; worktree = $slicePath; errors = @('slice worktree already exists') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

# (1)+(2) create the slice worktree from BaseSha and branch slice/<SliceId> in one shot.
$out = & git worktree add -b $branch $slicePath $BaseSha 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'worktree-add-failed'; worktree = $slicePath; branch = $branch; errors = @((($out | Out-String).Trim())) } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

# (3) carry cached env/config + heap.init.gradle into the slice worktree via the shared
# bootstrap. It copies gitignored runtime files (.env, .env.*, *.local, properties,
# compose overrides) plus reasonix.toml (tracked but possibly drifted) from the SOURCE
# (task worktree) into the slice, pruning node_modules/.git/build/agent-state dirs and
# logs. Single source of truth — any location/depth rule lives only in that script.
if (Test-Path -LiteralPath $taskPath) {
    $bs = Join-Path $PSScriptRoot 'worktree-bootstrap.ps1'
    if (Test-Path -LiteralPath $bs) {
        $bjson = & pwsh -NoProfile -File $bs -Worktree $slicePath -Source $taskPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Output ([pscustomobject]@{ ok = $false; verdict = 'bootstrap-failed'; worktree = $slicePath; errors = @((($bjson | Out-String).Trim())) } | ConvertTo-Json -Compress -Depth 10)
            exit 1
        }
    }
    # Fallback (bootstrap missing): copy root reasonix.toml only (the minimal tracked
    # config a slice needs) so a codebase without env files still gets its agent config.
    else {
        $rxSrc = Join-Path $taskPath 'reasonix.toml'
        if (Test-Path -LiteralPath $rxSrc) { Copy-Item -Path $rxSrc -Destination (Join-Path $slicePath 'reasonix.toml') -Force }
    }
}

Write-Output ([pscustomobject]@{ ok = $true; worktree = $slicePath; branch = $branch } | ConvertTo-Json -Compress -Depth 10)
exit 0
