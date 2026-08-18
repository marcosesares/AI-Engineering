<#
.SYNOPSIS
  Build + publish a new e2e-engineering release. Auto-decides the version bump.

.DESCRIPTION
  Pipeline:
    1. Decide the SemVer bump (auto, or -Bump override).
    2. Set the new version in all three SOURCE manifests:
         package.json
         .claude-plugin/marketplace.json        (metadata.version)
         .claude-plugin/plugin.json
    3. npm run build        (scripts/build-dist.js -- syncs skills + agents into dist/,
                             copies stamped .claude-plugin/ manifests to dist/)
    4. npm run validate     (links, role names, generated dist freshness, JSON manifests)
    5. git commit + tag v<version>   (unless -NoGit)
    6. npm publish --access public
    7. npm run publish:marketplace -- --remote <url> --push --force

  Auto bump heuristic (compares the last git tag against the working tree):
    MAJOR  -- a published top-level skill dir (.claude/skills/<name>/) was REMOVED
             (breaks installs that reference it).
    MINOR  -- a NEW top-level skill dir was ADDED (new capability/command).
    PATCH  -- everything else (edits, fixes, docs, ADRs).
  Override anytime with -Bump major|minor|patch. The decision is printed before
  any file is touched.

.EXAMPLE
  pwsh -File scripts/publish.ps1                 # auto bump, build, publish all
  pwsh -File scripts/publish.ps1 -Bump minor     # force minor
  pwsh -File scripts/publish.ps1 -DryRun         # show bump + npm pack dry-run, no push
#>
param(
    [ValidateSet("auto", "major", "minor", "patch")]
    [string]$Bump = "auto",
    # The marketplace is a SEPARATE standalone repo (RELEASING.md) -- NOT the source
    # repo (github.com/marcosesares/e2e-Engineering). Override with -MarketplaceRemote.
    [string]$MarketplaceRemote = "https://github.com/marcosesares/e2e-engineering-marketplace",
    [switch]$DryRun,
    [switch]$NoGit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 otherwise reads BOM-less UTF-8 as ANSI and writes a BOM.
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Step([string]$m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Run([string]$exe, [string[]]$argv) {
    Write-Host "> $exe $($argv -join ' ')" -ForegroundColor DarkGray
    & $exe @argv
    if ($LASTEXITCODE -ne 0) { throw "$exe exited $LASTEXITCODE" }
}

Step "Generate agent wrappers (generate-agent-wrappers.ps1)"
Run "pwsh" @("-File", (Join-Path $repo "skills\e2e-engineering\scripts\generate-agent-wrappers.ps1"))

$pkgPath = Join-Path $repo "package.json"
$mktPath = Join-Path $repo ".claude-plugin/marketplace.json"
$plgPath = Join-Path $repo ".claude-plugin/plugin.json"
$manifestPaths = @($pkgPath, $mktPath, $plgPath)
foreach ($p in $manifestPaths) {
    if (-not (Test-Path $p)) { throw "source manifest missing: $p" }
}
$originalManifestText = @{}
foreach ($p in $manifestPaths) {
    $originalManifestText[$p] = [System.IO.File]::ReadAllText($p, $utf8NoBom)
}

# --- current version (npm is the source of truth) ---
$current = ((Get-Content $pkgPath -Raw | ConvertFrom-Json).version)
if ($current -notmatch '^\d+\.\d+\.\d+$') { throw "package.json version not X.Y.Z: $current" }

# --- skill-dir sets: last tag vs now (drives the auto bump) ---
function Get-SkillNames-FromTree([string]$ref) {
    $out = git ls-tree -r --name-only $ref -- .claude/skills 2>$null
    if (-not $out) { return @() }
    $names = foreach ($line in $out) {
        if ($line -match '^\.claude/skills/([^/]+)/SKILL\.md$') { $Matches[1] }
    }
    return @($names | Sort-Object -Unique)
}
$nowSkills = @(Get-ChildItem (Join-Path $repo ".claude/skills") -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") } | Select-Object -ExpandProperty Name | Sort-Object -Unique)

# Prefer the nearest tag reachable from HEAD; fall back to the highest version tag
# (the release tag may not be an ancestor of the current branch).
$lastTag = (git describe --tags --abbrev=0 2>$null)
if (-not $lastTag) {
    $lastTag = (git tag --sort=-v:refname 2>$null | Select-Object -First 1)
}
$added = @(); $removed = @()
if ($lastTag) {
    $tagSkills = Get-SkillNames-FromTree $lastTag
    $added   = @($nowSkills | Where-Object { $_ -notin $tagSkills })
    $removed = @($tagSkills | Where-Object { $_ -notin $nowSkills })
}

if ($Bump -eq "auto") {
    if     ($removed.Count -gt 0) { $bumpType = "major"; $reason = "removed skill(s): $($removed -join ', ')" }
    elseif ($added.Count   -gt 0) { $bumpType = "minor"; $reason = "added skill(s): $($added -join ', ')" }
    else                          { $bumpType = "patch"; $reason = "no skill add/remove since $lastTag -- content-only" }
} else {
    $bumpType = $Bump; $reason = "forced via -Bump"
}

$parts = $current.Split('.')
[int]$maj = $parts[0]; [int]$min = $parts[1]; [int]$pat = $parts[2]
switch ($bumpType) {
    "major" { $maj++; $min = 0; $pat = 0 }
    "minor" { $min++; $pat = 0 }
    "patch" { $pat++ }
}
$newVersion = "$maj.$min.$pat"

Step "Version"
Write-Host "  current : $current   (last tag: $(if ($lastTag) { $lastTag } else { 'none' }))"
Write-Host "  bump    : $bumpType  ($reason)"
Write-Host "  new     : $newVersion" -ForegroundColor Green

# --- set version in the three manifests (regex on the version line; preserve formatting) ---
function Set-JsonVersion([string]$path, [string]$version) {
    $raw = [System.IO.File]::ReadAllText($path, $utf8NoBom)
    $pattern = '("version"\s*:\s*")\d+\.\d+\.\d+(")'
    if (-not [regex]::IsMatch($raw, $pattern)) { throw "no version field found in $path" }
    # first "version": "X.Y.Z" occurrence (top-level for package/plugin; metadata for marketplace)
    $new = [regex]::Replace($raw, $pattern, "`${1}$version`${2}", 1)
    if ($new -ne $raw) { [System.IO.File]::WriteAllText($path, $new, $utf8NoBom) }
    Write-Host "  set $version -> $([System.IO.Path]::GetFileName($path))"
}
Step "Stamp source manifests"
Set-JsonVersion $pkgPath $newVersion
Set-JsonVersion $plgPath $newVersion
Set-JsonVersion $mktPath $newVersion

Step "Build (npm run build -- copies stamped manifests to dist)"
Run "npm" @("run", "build")

Step "Validate (npm run validate)"
Run "npm" @("run", "validate")

# --- publish ---
if ($DryRun) {
    Step "DRY RUN -- npm publish --dry-run (no push, no tag)"
    try {
        Run "npm" @("publish", "--access", "public", "--dry-run")
    } finally {
        foreach ($p in $manifestPaths) {
            [System.IO.File]::WriteAllText($p, $originalManifestText[$p], $utf8NoBom)
        }
    }
    Write-Host "`nDry run complete. Nothing published, pushed, tagged, or committed." -ForegroundColor Yellow
    Write-Host "Version stamps were restored. Build output may still be refreshed in dist/." -ForegroundColor Yellow
    return
}

if (-not $NoGit) {
    Step "Commit + tag"
    Run "git" @("add", "-A")
    $status = git status --porcelain
    if ($status) { Run "git" @("commit", "-m", "Release v$newVersion") }
    else { Write-Host "  nothing to commit" }
    $existing = git tag --list "v$newVersion"
    if ($existing) { Write-Host "  tag v$newVersion already exists -- skipping" }
    else { Run "git" @("tag", "v$newVersion") }
}

Step "npm publish"
Run "npm" @("publish", "--access", "public")

Step "Publish marketplace"
Run "npm" @("run", "publish:marketplace", "--", "--remote", $MarketplaceRemote, "--push", "--force")

Step "Done"
Write-Host "Published e2e-engineering v$newVersion (npm + marketplace)." -ForegroundColor Green
if (-not $NoGit) { Write-Host "Tagged v$newVersion. Push this repo's commit/tag: git push --follow-tags" -ForegroundColor DarkGray }
