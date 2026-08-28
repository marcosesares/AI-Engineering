# carrier-smoke.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true)][string[]]$Spec,
    [Parameter(Mandatory = $true)][ValidateSet('on','off')][string]$KillSwitchMode
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
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'docker-missing'; specs = @{}; errors = @('docker not on PATH') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
$override = Join-Path $worktree 'docker-compose.killswitch.yml'
$apiProject = if ($env:CARRIER_SMOKE_API_PROJECT) { $env:CARRIER_SMOKE_API_PROJECT } else { 'api' }

# (1) docker compose down -v (bounded 10m). Teardown-style timeout is WARN, not a block.
$r = Invoke-Bounded -Exe $docker -Args @('compose','down','-v','--ansi','never') -Dir $worktree -Log (Join-Path $worktree 'smoke-down.log') -TimeoutSec 600

# (2) build-package.ps1 (child process; its exit code cannot kill this session).
$bpOut = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'build-package.ps1') -Worktree $worktree 2>&1
$bp = $null
try { $bp = (($bpOut | Out-String).Trim() | ConvertFrom-Json) } catch {}
if (-not $bp -or -not $bp.ok) {
    $errs = if ($bp -and $bp.errors) { @($bp.errors) } else { @('build-package.ps1 failed') }
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'package-build-failed'; specs = @{}; errors = $errs } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

# (3) docker compose up --force-recreate --build -d. KillSwitchMode off -> temp override applied.
$composeArgs = @('compose')
if ($KillSwitchMode -eq 'off' -and (Test-Path -LiteralPath $override)) {
    $composeArgs += @('-f', 'docker-compose.yml', '-f', 'docker-compose.killswitch.yml')
}
$composeArgs += @('up', '--force-recreate', '--build', '-d', '--ansi', 'never')
$r = Invoke-Bounded -Exe $docker -Args $composeArgs -Dir $worktree -Log (Join-Path $worktree 'smoke-up.log') -TimeoutSec 600
if ($r.TimedOut -or $r.ExitCode -ne 0) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'stack-up-failed'; specs = @{}; errors = @('docker compose up failed or timed out') } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

# (4) bounded readiness poll (never attach to logs).
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    $states = & $docker compose ps --format '{{.State}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and @($states).Count -gt 0) {
        $bad = @($states) | Where-Object { $_ -match 'exited|restarting|dead|created|unhealthy' }
        if ($bad.Count -eq 0) { $ready = $true; break }
    }
    Start-Sleep -Seconds 5
}
if (-not $ready) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'readiness-timeout'; specs = @{}; errors = @('stack not ready after bounded poll') } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

# (5) run each -Spec file (API project only, bounded, log to file).
$specs = @{}
$allGreen = $true
$idx = 0
foreach ($s in $Spec) {
    $idx++
    $specLog = Join-Path $worktree ("smoke-spec-$idx.log")
    $r = Invoke-Bounded -Exe 'cmd.exe' -Args @('/c', 'npx', '--yes', 'playwright', 'test', $s, '--project', $apiProject, '--reporter=line') -Dir $worktree -Log $specLog -TimeoutSec 1200
    $green = (-not $r.TimedOut) -and ($r.ExitCode -eq 0)
    $specs[$s] = if ($green) { 'green' } else { 'red' }
    if (-not $green) { $allGreen = $false }
}

# (6) teardown (bounded). Timeout is WARN, never flips the verdict.
$null = Invoke-Bounded -Exe $docker -Args @('compose','down','-v','--ansi','never') -Dir $worktree -Log (Join-Path $worktree 'smoke-teardown.log') -TimeoutSec 600

Write-Output ([pscustomobject]@{ ok = $allGreen; specs = $specs } | ConvertTo-Json -Compress -Depth 10)
exit 0