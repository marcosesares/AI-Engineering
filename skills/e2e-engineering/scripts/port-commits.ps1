# port-commits.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true)][string[]]$Shas,
    [Parameter(Mandatory = $true)][hashtable]$MigrationMap,
    [Parameter(Mandatory = $true)][string]$Branch
)

$ErrorActionPreference = 'Stop'
$env:CI = '1'; $env:NO_COLOR = '1'; $env:GIT_EDITOR = 'true'; $env:GIT_TERMINAL_PROMPT = '0'

# Run in the caller's workdir (the target worktree). Verify we are on the target branch.
$null = & git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'not-a-git-repo'; errors = @('not inside a git work tree') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

$current = (& git rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1).Trim()
if ($current -ne $Branch) {
    $out = & git checkout $Branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Output ([pscustomobject]@{ ok = $false; verdict = 'checkout-failed'; branch = $Branch; errors = @((($out | Out-String).Trim())) } | ConvertTo-Json -Compress -Depth 10)
        exit 1
    }
}

$cherryPicked = @()
$renamedAll  = @()

# (2)+(3)+(4) cherry-pick each sha in order; apply migration renames inside the cherry-picked tree.
foreach ($sha in $Shas) {
    $out = & git cherry-pick --no-edit $sha 2>&1
    if ($LASTEXITCODE -ne 0) {
        $conflictFiles = [string[]]@(& git diff --name-only --diff-filter=U 2>$null) | Where-Object { $_.Trim() }
        $first = if ($conflictFiles.Count -gt 0) { $conflictFiles[0] } else { '' }
        Write-Output ([pscustomobject]@{ ok = $false; verdict = 'cherry-pick-conflict'; sha = $sha; conflict = $first; errors = @((($out | Out-String).Trim())) } | ConvertTo-Json -Compress -Depth 10)
        exit 1
    }
    $cherryPicked += $sha

    $renamed = @()
    foreach ($entry in $MigrationMap.GetEnumerator()) {
        $old = [string]$entry.Key
        $new = [string]$entry.Value
        if (Test-Path -LiteralPath $old) {
            $mv = & git mv $old $new 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Output ([pscustomobject]@{ ok = $false; verdict = 'migration-rename-failed'; sha = $sha; errors = @((($mv | Out-String).Trim())) } | ConvertTo-Json -Compress -Depth 10)
                exit 1
            }
            $renamed += "$old->$new"
        }
    }
    if ($renamed.Count -gt 0) {
        $cm = & git commit -m "port: migration renames ($($renamed -join ', '))" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Output ([pscustomobject]@{ ok = $false; verdict = 'rename-commit-failed'; sha = $sha; errors = @((($cm | Out-String).Trim())) } | ConvertTo-Json -Compress -Depth 10)
            exit 1
        }
        $renamedAll += $renamed
    }
}

Write-Output ([pscustomobject]@{ ok = $true; cherryPicked = @($cherryPicked); renames = @($renamedAll) } | ConvertTo-Json -Compress -Depth 10)
exit 0