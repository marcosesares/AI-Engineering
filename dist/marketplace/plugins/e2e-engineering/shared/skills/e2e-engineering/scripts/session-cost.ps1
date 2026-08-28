# session-cost.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).

$ErrorActionPreference = 'Stop'
$env:CI = '1'; $env:NO_COLOR = '1'; $env:GIT_EDITOR = 'true'; $env:GIT_TERMINAL_PROMPT = '0'

# Diagnostics only (NOT wired into flight steps). zstd frame-split decode of ~/.dsh/sessions,
# best-effort per-agent token tallies. Field names are DSH-internal; this maps the common ones.

$sessionsDir = Join-Path $HOME '.dsh\sessions'
$zstd = (Get-Command zstd -ErrorAction SilentlyContinue).Source
if (-not $zstd) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'zstd-missing'; sessions = 0; agents = @(); errors = @('zstd not on PATH; install zstd to decode ~/.dsh/sessions') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
if (-not (Test-Path -LiteralPath $sessionsDir)) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'no-sessions-dir'; sessions = 0; agents = @(); errors = @("no directory $sessionsDir") } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

function Num { param($v) if ($null -eq $v) { return 0 }; try { return [int]$v } catch { return 0 } }

$files = @(Get-ChildItem -LiteralPath $sessionsDir -File -ErrorAction SilentlyContinue)
$agents = @{}
$decoded = 0

foreach ($f in $files) {
    $raw = & $zstd -d -c --long=31 $f.FullName 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $decoded++

    foreach ($line in ($raw -split "\n")) {
        $line = $line.Trim()
        if (-not $line) { continue }
        $obj = $null
        try { $obj = $line | ConvertFrom-Json } catch { continue }
        if ($null -eq $obj) { continue }

        $id = $obj.agentId; if (-not $id) { $id = $obj.agent }; if (-not $id) { $id = $obj.role }; if (-not $id) { $id = $obj.agent_id }
        if (-not $id) { continue }
        $key = [string]$id
        if (-not $agents.ContainsKey($key)) {
            $agents[$key] = [pscustomobject]@{ agentId = $key; reasoningTokens = 0; outputTokens = 0; toolResultTokens = 0; compactions = 0 }
        }
        $a = $agents[$key]

        if ($null -ne $obj.reasoning_tokens) { $a.reasoningTokens += (Num $obj.reasoning_tokens) }
        elseif ($null -ne $obj.reasoningTokens) { $a.reasoningTokens += (Num $obj.reasoningTokens) }

        if ($null -ne $obj.output_tokens) { $a.outputTokens += (Num $obj.output_tokens) }
        elseif ($null -ne $obj.outputTokens) { $a.outputTokens += (Num $obj.outputTokens) }
        elseif ($null -ne $obj.completion_tokens) { $a.outputTokens += (Num $obj.completion_tokens) }

        if ($null -ne $obj.tool_result_tokens) { $a.toolResultTokens += (Num $obj.tool_result_tokens) }
        elseif ($null -ne $obj.toolResultTokens) { $a.toolResultTokens += (Num $obj.toolResultTokens) }
        elseif ($null -ne $obj.tool_tokens) { $a.toolResultTokens += (Num $obj.tool_tokens) }

        if ($null -ne $obj.compactions) { $a.compactions += (Num $obj.compactions) }
        elseif ($null -ne $obj.compactionCount) { $a.compactions += (Num $obj.compactionCount) }
        elseif ($null -ne $obj.compaction_count) { $a.compactions += (Num $obj.compaction_count) }
    }
}

$agentList = @($agents.Values | Sort-Object -Property agentId)
Write-Output ([pscustomobject]@{ ok = $true; sessions = $decoded; agents = $agentList } | ConvertTo-Json -Compress -Depth 10)
exit 0
