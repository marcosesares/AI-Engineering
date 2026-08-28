# killswitch.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true, Position = 0)][ValidateSet('on','off')][string]$Mode
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

$worktree = (Get-Location).Path
$docker = (Get-Command docker -ErrorAction SilentlyContinue).Source
if (-not $docker) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'docker-missing'; mode = $Mode; errors = @('docker not on PATH') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
$override = Join-Path $worktree 'docker-compose.killswitch.yml'

if ($Mode -eq 'on') {
    $content = $env:KILLSWITCH_OVERRIDE
    if (-not $content) {
        Write-Output ([pscustomobject]@{ ok = $false; verdict = 'no-override-content'; mode = $Mode; errors = @('set KILLSWITCH_OVERRIDE (YAML from ARCHITECTURE.md §4.1b)') } | ConvertTo-Json -Compress -Depth 10)
        exit 1
    }
    Set-Content -LiteralPath $override -Value $content -Encoding utf8
    $r = Invoke-Bounded -Exe $docker -Args @('compose','-f','docker-compose.yml','-f','docker-compose.killswitch.yml','up','-d','--force-recreate','--build','--ansi','never') -Dir $worktree -Log (Join-Path $worktree 'killswitch-on.log') -TimeoutSec 600
}
else {
    if (Test-Path -LiteralPath $override) { Remove-Item -LiteralPath $override -Force }
    $r = Invoke-Bounded -Exe $docker -Args @('compose','up','-d','--force-recreate','--build','--ansi','never') -Dir $worktree -Log (Join-Path $worktree 'killswitch-off.log') -TimeoutSec 600
}

if ($r.TimedOut -or $r.ExitCode -ne 0) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'restart-failed'; mode = $Mode; errors = @('backend restart failed or timed out') } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}
Write-Output ([pscustomobject]@{ ok = $true; mode = $Mode } | ConvertTo-Json -Compress -Depth 10)
exit 0