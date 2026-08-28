# run-focused-tests.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
#   EXCEPTION (deliberate): this script writes resume.json's ports.nextFree ledger
#   write-ahead + a sibling ports.lock to serialize parallel-slice port claims
#   (followup 2026-08-27: port-claim atomicity). Both are port-ledger mechanics,
#   not authoritative state — the orchestrator remains sole writer of flight state.
param(
    [Parameter(Mandatory = $true)][string[]]$Tests,
    [int]$Port = 0,
    [string]$HeapInit = ''
)

$ErrorActionPreference = 'Stop'
$env:CI = '1'; $env:NO_COLOR = '1'; $env:GIT_EDITOR = 'true'; $env:GIT_TERMINAL_PROMPT = '0'

function Invoke-Bounded {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$Args,
        [Parameter(Mandatory = $true)][string]$Dir,
        [Parameter(Mandatory = $true)][string]$Log,
        [Parameter(Mandatory = $true)][int]$TimeoutSec
    )
    $errLog = "$Log.err"
    Remove-Item -Path $Log, $errLog -ErrorAction SilentlyContinue
    # Build ONE pre-quoted command string (space-separated; whitespace args wrapped in
    # quotes, embedded quotes backslash-escaped) so space-bearing paths survive.
    if ([System.IO.Path]::GetFileName($Exe) -eq 'cmd.exe') {
        $payload = ($Args | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match '\s' -or $_ -eq '') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }) -join ' '
        $quoted = '/c "' + $payload + '"'
    } else {
        $quoted = ($Args | ForEach-Object {
            if ($_ -match '\s' -or $_ -eq '') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }) -join ' '
    }
    $p = Start-Process -FilePath $Exe -ArgumentList $quoted -WorkingDirectory $Dir -NoNewWindow -PassThru -RedirectStandardOutput $Log -RedirectStandardError $errLog
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 250
        if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) {
            try { $p.Kill($true) } catch {}
            try { $p.WaitForExit() } catch {}
            return [pscustomobject]@{ TimedOut = $true; ExitCode = $null; Log = $Log; ErrLog = $errLog }
        }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ TimedOut = $false; ExitCode = $p.ExitCode; Log = $Log; ErrLog = $errLog }
}

$repoRoot = $null
foreach ($line in @(& git worktree list --porcelain 2>$null)) {
    if ($line -match '^worktree (.+)$') { $repoRoot = $Matches[1]; break }
}
if (-not $repoRoot) { $repoRoot = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1) }
if (-not $repoRoot) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'not-a-git-repo'; counts = @{ tests = 0; failures = 0; errors = 0; skipped = 0 }; errors = @('git worktree list / rev-parse failed') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
$repoRoot = $repoRoot.Trim()
$worktree = (Get-Location).Path

# (1) claim a port from resume.json ports.nextFree (write-ahead increment) when -Port is empty.
# The claim is serialized via an exclusive lock file so parallel slices cannot collide.
function Acquire-PortLock {
    param(
        [Parameter(Mandatory = $true)][string]$ResumePath,
        [int]$TimeoutSec = 30
    )
    $lockPath = Join-Path (Split-Path -Parent $ResumePath) 'ports.lock'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try {
            $fs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            return $fs
        }
        catch {
            if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) {
                Write-Output ([pscustomobject]@{ ok = $false; verdict = 'port-lock-timeout'; counts = @{ tests = 0; failures = 0; errors = 0; skipped = 0 }; errors = @('could not acquire ports.lock within ' + $TimeoutSec + 's') } | ConvertTo-Json -Compress -Depth 10)
                exit 1
            }
            Start-Sleep -Milliseconds 250
        }
    }
}

$claimed = $false
$resumePath = $null
if ($Port -le 0) {
    $resumePath = Get-ChildItem -LiteralPath (Join-Path $repoRoot '.e2e-engineering\tasks') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'resume.json' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $resumePath) {
        Write-Output ([pscustomobject]@{ ok = $false; verdict = 'no-resume-no-port'; counts = @{ tests = 0; failures = 0; errors = 0; skipped = 0 }; errors = @('no resume.json found and -Port not given') } | ConvertTo-Json -Compress -Depth 10)
        exit 1
    }
    $lockFs = Acquire-PortLock -ResumePath $resumePath
    try {
        $resume = Get-Content -LiteralPath $resumePath -Raw | ConvertFrom-Json
        if (-not $resume.ports -or $null -eq $resume.ports.nextFree) {
            Write-Output ([pscustomobject]@{ ok = $false; verdict = 'no-ports-ledger'; counts = @{ tests = 0; failures = 0; errors = 0; skipped = 0 }; errors = @('resume.json has no ports.nextFree') } | ConvertTo-Json -Compress -Depth 10)
            exit 1
        }
        $Port = [int]$resume.ports.nextFree
        $resume.ports.nextFree = $Port + 1
        $resume | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resumePath -Encoding utf8
        $claimed = $true
    }
    finally {
        if ($lockFs) { $lockFs.Dispose() }
    }
}

$env:TEST_PORT = [string]$Port

# (2) bounded focused run (gradle preferred, vitest fallback), log to file, heap init script when given.
$log = Join-Path $worktree 'focused-tests.log'
$gradlew = Join-Path $worktree 'gradlew.bat'
if (-not (Test-Path -LiteralPath $gradlew)) { $gradlew = Join-Path $worktree 'gradlew' }
$isGradle = Test-Path -LiteralPath $gradlew

if ($isGradle) {
    $args = @('/c', (Split-Path $gradlew -Leaf), 'test', '--no-daemon', '--console=plain')
    if ($HeapInit) { $args += @('--init-script', $HeapInit) }
    foreach ($t in $Tests) { $args += @('--tests', $t) }
    $r = Invoke-Bounded -Exe 'cmd.exe' -Args $args -Dir $worktree -Log $log -TimeoutSec 720
}
else {
    $args = @('/c', 'npx', '--yes', 'vitest', 'run', '--reporter=json') + @($Tests)
    $r = Invoke-Bounded -Exe 'cmd.exe' -Args $args -Dir $worktree -Log $log -TimeoutSec 720
}

# (3) release the port (only if we claimed and the ledger is still exactly one ahead).
# Same exclusive lock as the claim — the read-check-write is one atomic section.
if ($claimed -and $resumePath) {
    try {
        $lockFs = Acquire-PortLock -ResumePath $resumePath
        try {
            $resume = Get-Content -LiteralPath $resumePath -Raw | ConvertFrom-Json
            if ([int]$resume.ports.nextFree -eq ($Port + 1)) {
                $resume.ports.nextFree = $Port
                $resume | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resumePath -Encoding utf8
            }
        }
        finally {
            if ($lockFs) { $lockFs.Dispose() }
        }
    }
    catch {}
}

# (4) read test-result XML ONLY after BUILD SUCCESSFUL in the log (stale-XML discipline).
$buildSuccessful = (Test-Path -LiteralPath $log) -and ((Get-Content -LiteralPath $log -Raw) -match 'BUILD SUCCESSFUL')

if ($isGradle) {
    if (-not $r.TimedOut -and $r.ExitCode -eq 0 -and $buildSuccessful) {
        $counts = @{ tests = 0; failures = 0; errors = 0; skipped = 0 }
        $xmls = Get-ChildItem -LiteralPath $worktree -Recurse -Filter '*.xml' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'test-results[\\/]test[\\/]' }
        foreach ($f in $xmls) {
            try {
                [xml]$x = Get-Content -LiteralPath $f.FullName -Raw
                $suites = @()
                if ($x.testsuites) { $suites = @($x.testsuites.testsuite) }
                elseif ($x.testsuite) { $suites = @($x.testsuite) }
                foreach ($suite in $suites) {
                    $counts.tests += [int]$suite.tests
                    $counts.failures += [int]$suite.failures
                    $counts.errors += [int]$suite.errors
                    $counts.skipped += [int]$suite.skipped
                }
            }
            catch {}
        }
        $green = ($counts.failures -eq 0 -and $counts.errors -eq 0)
        Write-Output ([pscustomobject]@{ ok = $green; verdict = 'BUILD SUCCESSFUL'; counts = $counts } | ConvertTo-Json -Compress -Depth 10)
        exit 0
    }
    $verdict = if ($r.TimedOut) { 'TIMEOUT' } else { 'BUILD FAILED' }
    Write-Output ([pscustomobject]@{ ok = $false; verdict = $verdict; counts = @{ tests = 0; failures = 0; errors = 0; skipped = 0 } } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

# vitest path: best-effort JSON reporter parse.
$counts = @{ tests = 0; failures = 0; errors = 0; skipped = 0 }
if (-not $r.TimedOut -and $r.ExitCode -eq 0) {
    try {
        $j = Get-Content -LiteralPath $log -Raw | ConvertFrom-Json
        $counts.tests = [int]$j.numTotalTests
        $counts.failures = [int]$j.numFailedTests
        $counts.skipped = [int]$j.numPendingTests + [int]$j.numTodoTests
        $counts.errors = 0
    }
    catch {}
}
$green = ($counts.failures -eq 0 -and $counts.errors -eq 0 -and -not $r.TimedOut)
Write-Output ([pscustomobject]@{ ok = $green; verdict = if ($r.TimedOut) { 'TIMEOUT' } elseif ($green) { 'TESTS PASSED' } else { 'TESTS FAILED' }; counts = $counts } | ConvertTo-Json -Compress -Depth 10)
exit 0
