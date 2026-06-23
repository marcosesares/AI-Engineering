#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const PKG_ROOT = path.resolve(__dirname, "..");
const DIST = path.join(PKG_ROOT, "dist");

const TARGETS = ["claude", "cursor", "codex", "opencode"];
const KNOWN_RENAMES = [
  {
    from: path.join(".claude", "agents", "ui-designer.md"),
    to: path.join(".claude", "agents", "frontend-reviewer.md")
  },
  {
    from: path.join(".claude", "agents", "senior-qa.md"),
    to: path.join(".claude", "agents", "test-reviewer.md")
  }
];

function log(msg) {
  process.stdout.write(msg + "\n");
}
function warn(msg) {
  process.stderr.write("! " + msg + "\n");
}
function die(msg) {
  process.stderr.write("e2e-engineering: " + msg + "\n");
  process.exit(1);
}

function parseArgs(argv) {
  const args = { _: [], target: null, dest: process.cwd(), force: false, dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--target" || a === "-t") args.target = argv[++i];
    else if (a.startsWith("--target=")) args.target = a.slice("--target=".length);
    else if (a === "--dest" || a === "-d") args.dest = path.resolve(argv[++i]);
    else if (a.startsWith("--dest=")) args.dest = path.resolve(a.slice("--dest=".length));
    else if (a === "--force" || a === "-f") args.force = true;
    else if (a === "--dry-run" || a === "-n") args.dryRun = true;
    else if (a === "--help" || a === "-h") args._.push("help");
    else args._.push(a);
  }
  return args;
}

function detectTarget(dest) {
  if (fs.existsSync(path.join(dest, ".claude"))) return "claude";
  if (fs.existsSync(path.join(dest, ".cursor"))) return "cursor";
  return "codex"; // AGENTS.md — read by Codex, OpenCode, and Cursor too
}

function copyRecursive(src, dst, { force, dryRun, seen }, written) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    if (!dryRun) fs.mkdirSync(dst, { recursive: true });
    for (const entry of fs.readdirSync(src)) {
      copyRecursive(path.join(src, entry), path.join(dst, entry), { force, dryRun, seen }, written);
    }
  } else {
    if (seen.has(dst)) return; // already handled this run (e.g. AGENTS.md across multiple portable targets)
    seen.add(dst);
    if (fs.existsSync(dst) && !force) {
      warn("skip (exists, use --force): " + dst);
      return;
    }
    if (!dryRun) {
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      fs.copyFileSync(src, dst);
    }
    written.push(dst);
  }
}

function requireDist(rel) {
  const p = path.join(DIST, rel);
  if (!fs.existsSync(p)) {
    die("missing dist artifact: " + rel + " — run `npm run build` in the package first.");
  }
  return p;
}

function cleanupKnownRenames(dest, opts, removed) {
  for (const rename of KNOWN_RENAMES) {
    const oldPath = path.join(dest, rename.from);
    if (!fs.existsSync(oldPath)) continue;

    const relOld = path.relative(dest, oldPath);
    if (!opts.force) {
      warn("deprecated file remains: " + relOld + " (renamed to " + rename.to + "). Re-run with --force to delete it.");
      continue;
    }

    if (opts.dryRun) {
      warn("[dry-run] would delete deprecated file: " + relOld + " (renamed to " + rename.to + ")");
    } else {
      fs.rmSync(oldPath, { force: true });
      warn("deleted deprecated file: " + relOld + " (renamed to " + rename.to + ")");
    }
    removed.push(oldPath);
  }
}

function installSharedSkills(dest, opts, written) {
  const src = requireDist(path.join("shared", "skills"));
  copyRecursive(src, path.join(dest, "skills"), opts, written);
}

// Expert reviewer agents shipped alongside the skills (ADR 0022).
function installClaudeAgents(dest, opts, written) {
  const src = requireDist(path.join("claude", "agents"));
  copyRecursive(src, path.join(dest, ".claude", "agents"), opts, written);
}

const CLAUDE_SKILLS = ["e2e-engineering", "e2e-flight", "e2e-deslop", "grill-with-docs"];

function installClaude(dest, opts, written) {
  installSharedSkills(dest, opts, written);
  for (const name of CLAUDE_SKILLS) {
    const src = requireDist(path.join("claude", "skills", name));
    copyRecursive(src, path.join(dest, ".claude", "skills", name), opts, written);
  }
  installClaudeAgents(dest, opts, written);
}

function installCodexSkills(dest, opts, written) {
  const src = requireDist(path.join("codex", ".agents", "skills"));
  copyRecursive(src, path.join(dest, ".agents", "skills"), opts, written);
}

function installAgentsMd(dest, opts, written) {
  const src = requireDist(path.join("agents-md", "AGENTS.md"));
  const target = path.join(dest, "AGENTS.md");
  if (opts.seen.has(target) || opts.seen.has(path.join(dest, "AGENTS.e2e-engineering.md"))) return; // handled this run
  if (fs.existsSync(target) && !opts.force) {
    // Don't clobber an existing AGENTS.md — drop a sidecar and instruct.
    const sidecar = path.join(dest, "AGENTS.e2e-engineering.md");
    copyRecursive(src, sidecar, opts, written);
    warn("AGENTS.md already exists. Wrote AGENTS.e2e-engineering.md instead — reference it from AGENTS.md, or re-run with --force to overwrite.");
  } else {
    copyRecursive(src, target, opts, written);
  }
}

const CURSOR_RULES = ["e2e-engineering.mdc", "e2e-flight.mdc", "e2e-deslop.mdc"];

function installCursor(dest, opts, written) {
  installSharedSkills(dest, opts, written);
  installCodexSkills(dest, opts, written);
  for (const mdc of CURSOR_RULES) {
    const rule = requireDist(path.join("cursor", ".cursor", "rules", mdc));
    copyRecursive(rule, path.join(dest, ".cursor", "rules", mdc), opts, written);
  }
  // Cursor also reads AGENTS.md — install the router.
  installAgentsMd(dest, opts, written);
}

function installCodexLike(dest, opts, written) {
  installSharedSkills(dest, opts, written);
  installCodexSkills(dest, opts, written);
  installAgentsMd(dest, opts, written);
}

function run(target, dest, opts, written) {
  switch (target) {
    case "claude": installClaude(dest, opts, written); break;
    case "cursor": installCursor(dest, opts, written); break;
    case "codex":
    case "opencode": installCodexLike(dest, opts, written); break;
    default: die("unknown target: " + target + " (expected: " + TARGETS.join(", ") + ", or all)");
  }
}

const HELP = `e2e-engineering — install the e2e-engineering engineering flow into a project

Usage:
  npx e2e-engineering init [options]

Options:
  -t, --target <name>   claude | cursor | codex | opencode | all   (default: auto-detect)
  -d, --dest <dir>      target project dir                          (default: cwd)
  -f, --force           overwrite existing files
  -n, --dry-run         print what would be written, write nothing
  -h, --help            show this

Targets:
  claude    shared skills + .claude/skills + .claude/agents
  cursor    shared skills + .agents/skills + AGENTS.md + .cursor/rules/e2e-engineering.mdc
  codex     shared skills + .agents/skills + AGENTS.md
  opencode  shared skills + .agents/skills + AGENTS.md
  all       every target above

Auto-detect: .claude/ → claude · .cursor/ → cursor · else → codex (AGENTS.md)`;

function main() {
  const args = parseArgs(process.argv.slice(2));
  const cmd = args._[0];

  if (cmd === "help" || args._.includes("help")) {
    log(HELP);
    return;
  }
  if (cmd && cmd !== "init") {
    die("unknown command: " + cmd + " (did you mean `init`?)\n\n" + HELP);
  }

  const dest = args.dest;
  if (!fs.existsSync(dest)) die("dest does not exist: " + dest);

  let targets;
  if (args.target === "all") targets = TARGETS.slice();
  else if (args.target) targets = [args.target];
  else {
    const detected = detectTarget(dest);
    log("auto-detected target: " + detected + "  (override with --target)");
    targets = [detected];
  }

  const opts = { force: args.force, dryRun: args.dryRun, seen: new Set() };
  const written = [];
  for (const t of targets) run(t, dest, opts, written);
  const removed = [];
  if (targets.includes("claude")) cleanupKnownRenames(dest, opts, removed);

  if (args.dryRun) {
    log("\n[dry-run] would write " + written.length + " file(s):");
  } else {
    log("\ninstalled " + written.length + " file(s):");
  }
  for (const f of written) log("  " + path.relative(dest, f));
  if (removed.length) {
    if (args.dryRun) log("\n[dry-run] would delete " + removed.length + " deprecated file(s):");
    else log("\ndeleted " + removed.length + " deprecated file(s):");
    for (const f of removed) log("  " + path.relative(dest, f));
  }

  if (!args.dryRun && targets.includes("claude")) {
    log("\nClaude Code: restart/refresh, then type `/e2e-engineering`.");
  }
  if (!args.dryRun && targets.some((t) => t !== "claude")) {
    log("Codex/Cursor/OpenCode: AGENTS.md routes to .agents/skills; shared skill files are under skills/.");
  }
}

main();
