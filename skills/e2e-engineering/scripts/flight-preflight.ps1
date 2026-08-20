#!/usr/bin/env pwsh
# flight-preflight — Step-0 fail-closed checks for /e2e-flight (ADR 0033 + ADR 0034).
# Automates the bounded-shell probe, non-interactive env block, and the stale-daemon guard.
# FAIL on any check → orchestrator emits <e2e-stall reason="preflight-failed" /> and exits.
#
# Usage:
#   pwsh -NoProfile -File flight-preflight.ps1                      # check + print env block (does NOT set caller env)
#   . .\flight-preflight.ps1 -ApplyEnv                              # dot-source: ALSO applies env to this session
#   pwsh -NoProfile -File flight-preflight.ps1 -StopGradleDaemons   # safe ONLY at Step 0 with zero parallel work
#
# POSIX without pwsh: run the same checks inline per impl/command-execution.md §1–§2.

param(
    [switch]$ApplyEnv,
    [switch]$StopGradleDaemons
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Fail($msg) { $failures.Add($msg); Write-Host "FAIL $msg" }
function Ok($msg)   { Write-Host "OK   $msg" }
function Warn($msg) { Write-Host "WARN $msg" }

# --- 1. bounded-shell probe (ADR 0033) ---------------------------------------
$job = Start-Job { Start-Sleep -Seconds 30 }
$null = Wait-Job $job -Timeout 5
if ($job.State -eq 'Completed') {
    Fail "bounded-shell probe: blocking command FINISHED under 5s bound - runtime cannot time-box commands"
}
else {
    Stop-Job $job | Out-Null
    Ok "bounded-shell probe: 30s blocker did NOT complete under 5s bound; control returned (Start-Job + Wait-Job -Timeout works)"
}
Remove-Job $job -Force | Out-Null

# --- 2. non-interactive env block (command-execution §2) ---------------------
$envBlock = @{
    CI                     = '1'
    NO_COLOR               = '1'
    npm_config_yes         = 'true'
    GIT_TERMINAL_PROMPT    = '0'
    GIT_EDITOR             = 'true'
}
foreach ($k in $envBlock.Keys) {
    if ($ApplyEnv) { Set-Item -Path "env:$k" -Value $envBlock[$k] }
}
Ok "env block (CI/NO_COLOR/npm_config_yes/GIT_TERMINAL_PROMPT/GIT_EDITOR) $(if ($ApplyEnv) { 'applied to this session' } else { 'NOT applied - dot-source with -ApplyEnv to set caller env' })"

$coreEditor = (git config --get core.editor 2>$null)
if ($coreEditor -and $coreEditor -ne 'true') {
    Warn "git core.editor = $coreEditor (interactive) - GIT_EDITOR=true overrides it; keep --no-edit / -m on every merge/commit anyway"
}

# --- 3. stale-daemon guard (command-execution §8) ----------------------------
$javaProcs = @(Get-Process -Name java, javaw -ErrorAction SilentlyContinue)
$gradleProcs = @(Get-Process -Name gradle, gradlew -ErrorAction SilentlyContinue)
if ($javaProcs.Count -gt 0 -or $gradleProcs.Count -gt 0) {
    if ($StopGradleDaemons) {
        Fail "java/gradle processes running (java=$($javaProcs.Count) gradle=$($gradleProcs.Count)) - gradlew --stop BANNED while parallel work exists (command-execution §8); resolve first"
    }
    else {
        Warn "java/gradle processes running (java=$($javaProcs.Count) gradle=$($gradleProcs.Count)) - do NOT run gradlew --stop this spawn"
    }
}
elseif ($StopGradleDaemons) {
    $gradlew = @('gradlew.bat', './gradlew', 'gradlew') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($gradlew) {
        & $gradlew --stop --console=plain 2>$null | Out-Null
        Ok "no java/gradle processes; ran gradlew --stop (Step-0 only - safe window)"
    }
    else {
        Warn "-StopGradleDaemons: no gradlew in this directory; skipped"
    }
}
else {
    Ok "no java/gradle processes running"
}

# --- verdict ----------------------------------------------------------------
if ($failures.Count -gt 0) {
    Write-Host "preflight: FAIL ($($failures.Count))"
    exit 1
}
Write-Host "preflight: PASS"
exit 0
