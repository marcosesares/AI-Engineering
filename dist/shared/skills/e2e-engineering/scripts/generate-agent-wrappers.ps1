#!/usr/bin/env pwsh
# Reads canonical specs + agents.manifest.json, emits self-contained Claude Code wrappers.
# Never hand-edit .claude/agents/ — regenerate from canonical source.
# Codex uses standard worker agents with canonical specs injected in prompts; no generated Codex role files are load-bearing.
#
# Usage:
#   ./generate-agent-wrappers.ps1           # emit all wrappers
#   ./generate-agent-wrappers.ps1 -DryRun   # show what would be written without writing

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptDir   = $PSScriptRoot                                          # .../skills/e2e-engineering/scripts
$e2eEngDir   = Split-Path $scriptDir -Parent                          # .../skills/e2e-engineering
$agentsDir   = Join-Path $e2eEngDir 'agents'
$manifestPath = Join-Path $e2eEngDir 'agents.manifest.json'
$repoRoot    = Split-Path (Split-Path $e2eEngDir -Parent) -Parent     # up: skills/ -> repo root

$claudeAgentsDir = Join-Path $repoRoot '.claude\agents'

if (-not (Test-Path $manifestPath)) {
    Write-Error "Manifest not found: $manifestPath"
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$roles    = @($manifest.roles.PSObject.Properties)

Write-Host "Repo root    : $repoRoot"
Write-Host "Claude agents: $claudeAgentsDir"
Write-Host "Roles        : $($roles.Name -join ', ')"
Write-Host ""

foreach ($role in $roles) {
    $roleName = $role.Name
    $meta     = $role.Value

    $specPath = Join-Path $agentsDir "$roleName.md"
    if (-not (Test-Path $specPath)) {
        Write-Warning "Canonical spec not found, skipping: $specPath"
        continue
    }

    $specBody    = Get-Content $specPath -Raw
    $toolsStr    = $meta.tools -join ', '
    $description = $meta.description
    $claudeName  = $meta.claude_name

    # ── Claude Code wrapper (.md with YAML frontmatter) ──────────────────────
    $claudeFrontmatter = @"
---
name: $claudeName
description: $description
tools: $toolsStr
---

"@
    # Canonical spec bodies link via agent-relative paths (../standards/, ../schemas/)
    # which are correct inside skills/e2e-engineering/agents/ but break once the
    # body is copied to .claude/agents/. Rewrite those to repo-root-relative paths
    # that resolve from .claude/agents/. Same-dir agent-to-agent links (foo.md)
    # stay as-is — the siblings exist in .claude/agents/ too.
    $wrapperBody = $specBody `
        -replace '\]\(\.\./standards/', '](../../skills/e2e-engineering/standards/' `
        -replace '\]\(\.\./schemas/',   '](../../skills/e2e-engineering/schemas/' `
        -replace '\]\(\.\./constitution\.md\)', '](../../skills/e2e-engineering/constitution.md)'
    $claudeContent  = $claudeFrontmatter + $wrapperBody
    $claudeOutPath  = Join-Path $claudeAgentsDir "$claudeName.md"

    if ($DryRun) {
        Write-Host "[DRY RUN] Claude Code: $claudeOutPath"
    } else {
        New-Item -ItemType Directory -Force -Path $claudeAgentsDir | Out-Null
        # UTF8 WITHOUT a BOM. [System.Text.Encoding]::UTF8 emits one (EF BB BF), which lands
        # before the opening '---' and stops Claude Code from parsing the YAML frontmatter —
        # the agent then never registers and every dispatch fails with "Agent type not found".
        # Historical: a15d605 fixed this downstream on 2026-08-08 and skill sync 5523345
        # silently reverted it; the post-write guard below exists so a regressed generator
        # fails LOUD instead of shipping silently-broken wrappers.
        $bomlessUtf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($claudeOutPath, $claudeContent, $bomlessUtf8)

        # Post-write validity self-check: BOM probe + frontmatter opener probe.
        $writtenBytes = [System.IO.File]::ReadAllBytes($claudeOutPath)
        if ($writtenBytes.Length -ge 3 -and $writtenBytes[0] -eq 0xEF -and $writtenBytes[1] -eq 0xBB -and $writtenBytes[2] -eq 0xBF) {
            Write-Error "BOM guard failed: $claudeOutPath starts with EF BB BF — Claude Code cannot parse BOM-prefixed YAML frontmatter (agent would never register). Aborting."
            exit 1
        }
        $writtenText = [System.IO.File]::ReadAllText($claudeOutPath, $bomlessUtf8)
        if (-not $writtenText.StartsWith('---')) {
            Write-Error "Wrapper validity check failed: $claudeOutPath does not start with '---' YAML frontmatter opener. Aborting."
            exit 1
        }
        Write-Host "Written : $claudeOutPath (BOM-free, frontmatter OK)"
    }

    Write-Host ""
}

if ($DryRun) {
    Write-Host "Dry run complete. $($roles.Count) role(s) would be processed."
} else {
    Write-Host "Done. $($roles.Count) role(s) processed."
    Write-Host "Note: delete any legacy hand-authored Claude wrappers no longer in the manifest."
    Write-Host "Note: Codex reviewer roles are prompt-injected worker agents; no Codex wrapper files were written."
}
