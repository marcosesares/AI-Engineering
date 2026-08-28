# review-bundle.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true)][string]$SliceId,
    [Parameter(Mandatory = $true)][string]$Base,
    [Parameter(Mandatory = $true)][string]$Head
)

$ErrorActionPreference = 'Stop'
$env:CI = '1'; $env:NO_COLOR = '1'; $env:GIT_EDITOR = 'true'; $env:GIT_TERMINAL_PROMPT = '0'

$null = & git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'not-a-git-repo'; errors = @('not inside a git work tree') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

$changedFiles = @()
$nameStatus = [string[]]@(& git diff --name-status "$Base..$Head" 2>$null)
foreach ($line in $nameStatus) {
    $parts = $line -split "\t"
    $path = $parts[-1]
    if ($path) { $changedFiles += $path }
}

$diffStat = (@(& git diff --stat "$Base..$Head" 2>$null) -join "\n").Trim()

$bundle = [pscustomobject]@{
    sliceId = $SliceId
    baseCommit = $Base
    headCommit = $Head
    changedFiles = @($changedFiles)
    diffStat = $diffStat
    testEvidence = @()
}

Write-Output ([pscustomobject]@{ ok = $true; bundle = $bundle } | ConvertTo-Json -Compress -Depth 10)
exit 0