# worktree-bootstrap.ps1 — e2e-flight script (D8 governance)
# Single source of truth for carrying gitignored-but-needed runtime env/config files
# from a source worktree (normally the main/master working tree) into a freshly created
# task- or slice- worktree.
#
# Why: `git worktree add` checks out TRACKED files only. Gitignored runtime files
# (.env, frontend/.env, playwright/.env) live only in the working tree where the agent
# keeps them. Without an explicit copy a new worktree has none of them, so `docker
# compose up` aborts (MERCADOPAGO_* via ${..:?...}), `npm run test:api` has no creds,
# and the frontend build lacks Keycloak vars. Prior gap is documented (task-fix-enrollment
# missed frontend/.env; video-content-protection had no .env).
#
# Candidates are enumerated by walking Source ONCE and selecting on the path RELATIVE to
# Source against an allow-list of globs. reasonix.toml is copied even though tracked — it
# may have drifted in Source's working tree — so the target matches the live agent config,
# never a stale committed copy.
#
# BOUNDED + NON-INTERACTIVE: pure file copy, no child long-running processes.
# VERDICT: exit 0|1 + ONE JSON object { "ok", "worktree", "copied":[...] }.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
param(
    [Parameter(Mandatory = $true)][string]$Worktree,   # target worktree root (abs)
    [Parameter(Mandatory = $false)][string]$Source     # source root; default = current dir
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Worktree)) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'worktree-missing'; worktree = $Worktree; errors = @('target worktree path does not exist') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}
if (-not $Source) { $Source = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Source)) {
    Write-Output ([pscustomobject]@{ ok = $false; verdict = 'source-missing'; source = $Source; errors = @('source root does not exist') } | ConvertTo-Json -Compress -Depth 10)
    exit 1
}

# Segment globs applied to the FULL relative path (forward-slash). '*' does not cross '/',
# so '**/.env' below equals '.env' (root) or 'dir/.env' at any depth via the wrapper rule.
# We list the concrete well-known locations first for clarity, plus generic leaf rules for
# `.local`, properties, and compose overrides at any depth.
$leafGlobs = @('.env', '.env.*', '*.local', 'local.properties', 'gradle-local.properties',
    'heap.init.gradle', 'docker-compose.override.yml', 'docker-compose.override.yaml')
# exact-or-deep rules: prefix/path we include at the repo root
$rootRules = @('.env', '.env.local', '.env.development', 'reasonix.toml')

# Dirs never descended into (deps, build, logs, agent state, editor/app data).
$excludedDirs = @('node_modules','.git','.gradle','build','dist','target','.auth',
    '.agents','.claude','.worktrees','.opus','.opencode','.superpowers','.junie',
    '.reasonix','.config','.idea','.vite','.dscode','.playwright-mcp','.e2e-engineering',
    '.impeccable','coverage','.mcp','.cache')

function Get-RelMatches {
    # Walk Source once, prune excluded dirs, and return relative paths matching the rules.
    param([string]$Root)
    $out = @()
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        foreach ($item in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            if ($item.PSIsContainer) {
                if ($item.Name -in $excludedDirs) { continue }
                $stack.Push($item.FullName)
                continue
            }
            $rel = $item.FullName.Substring($Root.Length).TrimStart('/','\')
            $fs = $rel -replace '\\','/'
            if ($fs -in $rootRules) { $out += $fs; continue }
            $leaf = $item.Name
            foreach ($g in $leafGlobs) {
                # match the leaf glob for depth-any but never copy a log/build leaf
                if ($leaf -like $g) { $out += $fs; break }
            }
        }
    }
    return $out
}

$matches = @(Get-RelMatches -Root $Source)

$copied = @()
foreach ($rel in ($matches | Sort-Object -Unique)) {
    $srcFull = Join-Path $Source ($rel -replace '/','\')
    if (-not (Test-Path -LiteralPath $srcFull -PathType Leaf)) { continue }
    $dstFull = Join-Path $Worktree ($rel -replace '/','\')
    $dstDir = Split-Path $dstFull -Parent
    if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $srcFull -Destination $dstFull -Force
    $copied += $rel
}

# reasonix.toml: present in Source (it is tracked at that root too, so it exists both as a
# committed file and as Source's working file). Overwrite the target's committed copy so the
# worktree always matches Source's LIVE agent config, never a stale commit at an older base.
$rxSrc = Join-Path $Source 'reasonix.toml'
if (Test-Path -LiteralPath $rxSrc) {
    Copy-Item -LiteralPath $rxSrc -Destination (Join-Path $Worktree 'reasonix.toml') -Force
    if ($copied -notcontains 'reasonix.toml') { $copied += 'reasonix.toml' }
}

Write-Output ([pscustomobject]@{ ok = $true; worktree = $Worktree; copied = @($copied) } | ConvertTo-Json -Compress -Depth 10)
exit 0
