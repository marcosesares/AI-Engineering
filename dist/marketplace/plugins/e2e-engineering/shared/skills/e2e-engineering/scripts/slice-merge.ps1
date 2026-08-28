# slice-merge.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true)][string]$SliceId,
    [Parameter(Mandatory = $true)][string]$TaskId
)

$ErrorActionPreference = 'Stop'
$env:CI = '1'; $env:NO_COLOR = '1'; $env:GIT_EDITOR = 'true'; $env:GIT_TERMINAL_PROMPT = '0'

$repoRoot = $null
foreach ($line in @(& git worktree list --porcelain 2>$null)) {
    if ($line -match '^worktree (.+)$') { $repoRoot = $Matches[1]; break }
}
if (-not $repoRoot) { $repoRoot = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1) }
if (-not $repoRoot) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'not-a-git-repo'; conflicts = @(); errors = @('git worktree list / rev-parse failed') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
$repoRoot = $repoRoot.Trim()

$taskPath = Join-Path $repoRoot ".claude\worktrees\task-$TaskId"
if (-not (Test-Path -LiteralPath $taskPath)) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'task-worktree-missing'; conflicts = @(); errors = @("no worktree at $taskPath") } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
$sliceBranch = "slice/$SliceId"

$null = & git rev-parse --verify "$sliceBranch" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'slice-branch-missing'; conflicts = @(); errors = @("no such branch $sliceBranch") } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

# (1) merge slice/<SliceId> --no-edit inside the task worktree.
$out = & git -C $taskPath merge "$sliceBranch" --no-edit 2>&1
$code = $LASTEXITCODE

if ($code -ne 0) {
    $conflicts = [string[]]@(& git -C $taskPath diff --name-only --diff-filter=U 2>$null) | Where-Object { $_.Trim() }
    if ($conflicts.Count -gt 0) {
        Write-Output ([pscustomobject]@{ ok = $false; verdict = 'merge-conflict'; conflicts = @($conflicts) } | ConvertTo-Json -Compress -Depth 10)
        exit 0
    }
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'merge-failed'; conflicts = @(); errors = @((($out | Out-String).Trim())) } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

# (2) clean-tree verify: git status --porcelain must be empty.
$porcelain = @(& git -C $taskPath status --porcelain 2>$null)
if ($porcelain.Count -gt 0) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'tree-not-clean'; conflicts = @(); errors = @($porcelain) } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

Write-Output ([pscustomobject]@{ ok = $true; conflicts = @() } | ConvertTo-Json -Compress -Depth 10)
exit 0