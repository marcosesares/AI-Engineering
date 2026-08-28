# compile-check.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true)][string]$Worktree,
    [Parameter(Mandatory = $true)][ValidateSet('backend','frontend','both')][string]$Scope
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
    $p = Start-Process -FilePath $Exe -ArgumentList $Args -WorkingDirectory $Dir -NoNewWindow -PassThru -RedirectStandardOutput $Log -RedirectStandardError $errLog
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
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'worktree-missing'; errors = @("no such worktree $Worktree") } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
$worktree = (Resolve-Path -LiteralPath $Worktree).Path

$errors = @()
$backendOk  = $true
$frontendOk = $true

if ($Scope -in @('backend','both')) {
    $gradlew = Join-Path $worktree 'gradlew.bat'
    if (-not (Test-Path -LiteralPath $gradlew)) { $gradlew = Join-Path $worktree 'gradlew' }
    if (-not (Test-Path -LiteralPath $gradlew)) {
        $backendOk = $false
        $errors += 'gradlew not found in worktree'
    }
    else {
        $log = Join-Path $worktree 'compile-check-backend.log'
        $r = Invoke-Bounded -Exe 'cmd.exe' -Args @('/c', (Split-Path $gradlew -Leaf), ':backend:compileJava', ':backend:compileTestJava', '--no-daemon', '--console=plain') -Dir $worktree -Log $log -TimeoutSec 360
        if ($r.TimedOut) { $backendOk = $false; $errors += 'backend compile TIMEOUT @360s' }
        elseif ($r.ExitCode -ne 0) { $backendOk = $false; $errors += (Get-FirstErrors -Log $log) }
    }
}

if ($Scope -in @('frontend','both')) {
    $log = Join-Path $worktree 'compile-check-frontend.log'
    $r = Invoke-Bounded -Exe 'cmd.exe' -Args @('/c', 'npx', '--yes', 'tsc', '-b') -Dir $worktree -Log $log -TimeoutSec 360
    if ($r.TimedOut) { $frontendOk = $false; $errors += 'frontend tsc TIMEOUT @360s' }
    elseif ($r.ExitCode -ne 0) { $frontendOk = $false; $errors += (Get-FirstErrors -Log $log) }
}

if ($backendOk -and $frontendOk) {
    Write-Output ([pscustomobject]@{ ok = $true; verdict = 'BUILD SUCCESSFUL' } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}
Write-Output ([pscustomobject]@{ ok = $false; verdict = 'BUILD FAILED'; errors = @($errors | Select-Object -First 5) } | ConvertTo-Json -Compress -Depth 10)
exit 0