# review-fan-in.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).

$ErrorActionPreference = 'Stop'
$env:CI = '1'; $env:NO_COLOR = '1'; $env:GIT_EDITOR = 'true'; $env:GIT_TERMINAL_PROMPT = '0'

# Reads the slice's reviewer result JSONs (reviews/<reviewerId>.json) and mechanically merges
# their findings[] into one review-result.json envelope. Run with workdir = manifests/<story-id>/.
$reviewDir = Join-Path (Get-Location).Path 'reviews'
$sliceId = (Split-Path (Get-Location).Path -Leaf)

if (-not (Test-Path -LiteralPath $reviewDir)) {
    $repoRoot = $null
    foreach ($line in @(& git worktree list --porcelain 2>$null)) {
        if ($line -match '^worktree (.+)$') { $repoRoot = $Matches[1]; break }
    }
    if (-not $repoRoot) { $repoRoot = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1) }
    if ($repoRoot) {
        $found = Get-ChildItem -LiteralPath (Join-Path $repoRoot.Trim() '.e2e-engineering\tasks') -Recurse -Directory -Filter 'reviews' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $reviewDir = $found.FullName; $sliceId = (Split-Path (Split-Path $reviewDir -Parent) -Leaf) }
    }
}

$reviews = @()
if ($reviewDir -and (Test-Path -LiteralPath $reviewDir)) {
    foreach ($f in Get-ChildItem -LiteralPath $reviewDir -Filter '*.json' -ErrorAction SilentlyContinue) {
        try {
            $obj = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
            if (-not $sliceId -and $obj.sliceId) { $sliceId = [string]$obj.sliceId }
            $reviewerId = [string]$obj.reviewerId
            if (-not $reviewerId) { $reviewerId = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
            $reviews += [pscustomobject]@{ reviewerId = $reviewerId; findings = @($obj.findings) }
        }
        catch {}
    }
}

Write-Output ([pscustomobject]@{ ok = $true; sliceId = $sliceId; reviews = @($reviews) } | ConvertTo-Json -Compress -Depth 10)
exit 0
