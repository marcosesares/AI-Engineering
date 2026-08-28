# lint-check.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true)][string]$Worktree,
    [string[]]$ChangedFiles = @()
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

function Get-FirstErrors {
    param([Parameter(Mandatory = $true)][string]$Log, [int]$N = 5)
    if (-not (Test-Path -LiteralPath $Log)) { return @() }
    $lines = Get-Content -LiteralPath $Log | Where-Object { $_ -match '(?i)error|fail|exception|cannot|not found|no such' }
    return @($lines | Select-Object -First $N)
}

if (-not (Test-Path -LiteralPath $Worktree)) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'worktree-missing'; problems = -1; files = @(); errors = @("no such worktree $Worktree") } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
$worktree = (Resolve-Path -LiteralPath $Worktree).Path

$lintable = @($ChangedFiles | Where-Object { $_ -match '\.(?:js|jsx|ts|tsx|mjs|cjs|vue)$' -and (Test-Path -LiteralPath (Join-Path $worktree $_)) })
if ($lintable.Count -eq 0) {
    Write-Output ([pscustomobject]@{ ok = $true; problems = 0; files = @() } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

$log = Join-Path $worktree 'lint-check.log'
$r = Invoke-Bounded -Exe 'cmd.exe' -Args (@('/c', 'npx', '--yes', 'eslint', '--format', 'json') + $lintable) -Dir $worktree -Log $log -TimeoutSec 180

if ($r.TimedOut) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'lint-timeout'; problems = -1; files = @(); errors = @('eslint TIMEOUT @180s') } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

$files = @()
$problems = 0
try {
    $raw = Get-Content -LiteralPath $log -Raw
    $parsed = $raw | ConvertFrom-Json
    foreach ($res in @($parsed)) {
        $e = [int]($res.errorCount)
        $w = [int]($res.warningCount)
        $problems += ($e + $w)
        $files += [pscustomobject]@{ file = [string]$res.filePath; errors = $e; warnings = $w }
    }
}
catch {
    if ($r.ExitCode -ge 2) {
        $errs = @(Get-Content -LiteralPath $r.ErrLog -ErrorAction SilentlyContinue | Select-Object -First 5)
        Write-Output ([pscustomobject]@{ ok = $false; verdict = 'eslint-fatal'; problems = -1; files = @(); errors = @($errs) } | ConvertTo-Json -Compress -Depth 10)
        exit 0
    }
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'eslint-parse-failed'; problems = -1; files = @(); errors = @('could not parse eslint --format json output') } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

Write-Output ([pscustomobject]@{ ok = ($problems -eq 0); problems = $problems; files = @($files) } | ConvertTo-Json -Compress -Depth 10)
exit 0
