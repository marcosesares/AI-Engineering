# slice-rebase-guard.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][string]$SliceId
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

$slicePath  = Join-Path $repoRoot ".claude\worktrees\slice-$SliceId"
$taskBranch = "task/$TaskId"
$sliceBranch = "slice/$SliceId"

$null = & git rev-parse --verify "$sliceBranch" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'slice-branch-missing'; rebased = $false; changedFiles = @(); errors = @("no such branch $sliceBranch") } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
if (-not (Test-Path -LiteralPath $slicePath)) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'slice-worktree-missing'; rebased = $false; changedFiles = @(); errors = @("no worktree at $slicePath") } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

# (1) is task/<TaskId> HEAD an ancestor of the slice branch? 0 = current, 1 = stale, 128 = error.
& git merge-base --is-ancestor "$taskBranch" "$sliceBranch" 2>$null
$ancestor = $LASTEXITCODE

if ($ancestor -eq 0) {
    Write-Output ([pscustomobject]@{ ok = $true; rebased = $false; changedFiles = @() } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}
if ($ancestor -ne 1) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'merge-base-error'; rebased = $false; changedFiles = @(); errors = @("git merge-base --is-ancestor exited $ancestor") } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

# (2) stale base -> rebase slice branch onto task/<TaskId> inside the slice worktree.
$before = (& git rev-parse "$sliceBranch" 2>$null | Select-Object -First 1).Trim()
$out = & git -C $slicePath rebase "$taskBranch" 2>&1
$code = $LASTEXITCODE

if ($code -ne 0) {
    $conflicted = [string[]]@(& git -C $slicePath diff --name-only --diff-filter=U 2>$null) | Where-Object { $_.Trim() }
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'rebase-conflict'; rebased = $false; changedFiles = @($conflicted); errors = @((($out | Out-String).Trim())) } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

$after = (& git -C $slicePath rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
$changed = [string[]]@(& git -C $slicePath diff --name-only "$before" "$after" 2>$null) | Where-Object { $_.Trim() }
Write-Output ([pscustomobject]@{ ok = $true; rebased = $true; changedFiles = @($changed) } | ConvertTo-Json -Compress -Depth 10)
exit 0
