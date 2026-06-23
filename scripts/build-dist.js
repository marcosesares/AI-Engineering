#!/usr/bin/env node
"use strict";

// Sync the dual-runtime source tree into npm + marketplace dist artifacts.
// Canonical source of truth:
//   skills/          shared runtime-neutral core
//   .claude/skills/  Claude entry points
//   .agents/skills/  Codex entry points
//   AGENTS.md        Codex router

const fs = require("fs");
const path = require("path");

const REPO = path.resolve(__dirname, "..");
const SHARED_SKILLS_SRC = path.join(REPO, "skills");
const CLAUDE_SKILLS_SRC = path.join(REPO, ".claude", "skills");
const CODEX_SKILLS_SRC = path.join(REPO, ".agents", "skills");
const CLAUDE_AGENTS_SRC = path.join(REPO, ".claude", "agents");
const TOP_LEVEL_SKILLS = ["e2e-engineering", "e2e-flight", "e2e-deslop", "grill-with-docs"];
const SHARED_SKILLS = ["e2e-engineering", "grill-with-docs"];
const DIST = path.join(REPO, "dist");
const PLUGIN_DIR = path.join(REPO, "dist", "marketplace", "plugins", "e2e-engineering");
const PLUGIN_SKILLS_ROOT = path.join(PLUGIN_DIR, "skills");
const PLUGIN_SHARED_ROOT = path.join(PLUGIN_DIR, "shared", "skills");

function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name);
    const d = path.join(dst, entry.name);
    if (entry.isDirectory() || fs.statSync(s).isDirectory()) copyDir(s, d);
    else fs.copyFileSync(s, d);
  }
}

function rmrf(p) {
  if (fs.existsSync(p)) fs.rmSync(p, { recursive: true, force: true });
}

function copyFileWithReplacements(src, dst, replacements) {
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  let text = fs.readFileSync(src, "utf8");
  for (const [from, to] of replacements) text = text.split(from).join(to);
  fs.writeFileSync(dst, text);
}

function assertExists(p, label) {
  if (!fs.existsSync(p)) {
    process.stderr.write("build-dist: missing " + label + " at " + p + "\n");
    process.exit(1);
  }
}

function main() {
  assertExists(SHARED_SKILLS_SRC, "shared skills");
  assertExists(CLAUDE_SKILLS_SRC, "Claude skills");
  assertExists(CODEX_SKILLS_SRC, "Codex skills");
  assertExists(CLAUDE_AGENTS_SRC, "Claude agents");
  assertExists(path.join(REPO, "AGENTS.md"), "AGENTS.md router");

  // npm installer artifacts
  syncSkillDirs(SHARED_SKILLS_SRC, path.join(DIST, "shared", "skills"), SHARED_SKILLS, "shared skills");
  syncSkillDirs(CLAUDE_SKILLS_SRC, path.join(DIST, "claude", "skills"), TOP_LEVEL_SKILLS, "Claude skills");
  syncDir(CLAUDE_AGENTS_SRC, path.join(DIST, "claude", "agents"));
  syncSkillDirs(CODEX_SKILLS_SRC, path.join(DIST, "codex", ".agents", "skills"), TOP_LEVEL_SKILLS, "Codex skills");

  // Embed shared sub-skills inside Codex skill dirs.
  // Codex resolves markdown links relative to the skill dir and does not traverse ../,
  // so sub-skills must live alongside the SKILL.md entry point.
  const CODEX_DIST_SKILLS = path.join(DIST, "codex", ".agents", "skills");
  copyDir(path.join(SHARED_SKILLS_SRC, "e2e-engineering"), path.join(CODEX_DIST_SKILLS, "e2e-engineering"));
  copyDir(path.join(SHARED_SKILLS_SRC, "grill-with-docs"), path.join(CODEX_DIST_SKILLS, "grill-with-docs"));

  // Rewrite ../../../skills/X/ path prefixes in Codex SKILL.md files to local-relative paths.
  const codexSkillRewrites = [
    { skill: "e2e-engineering", replacements: [["../../../skills/e2e-engineering/", ""]] },
    { skill: "e2e-flight",       replacements: [["../../../skills/e2e-engineering/", "../e2e-engineering/"]] },
    { skill: "e2e-deslop",       replacements: [["../../../skills/e2e-engineering/", "../e2e-engineering/"]] },
    { skill: "grill-with-docs",  replacements: [["../../../skills/grill-with-docs/", ""]] },
  ];
  for (const { skill, replacements } of codexSkillRewrites) {
    const skillMd = path.join(CODEX_DIST_SKILLS, skill, "SKILL.md");
    if (fs.existsSync(skillMd)) copyFileWithReplacements(skillMd, skillMd, replacements);
  }
  process.stdout.write("build-dist: embedded shared sub-skills + rewrote paths in Codex entries → dist/codex/.agents/skills/\n");

  copyFileWithReplacements(path.join(REPO, "AGENTS.md"), path.join(DIST, "agents-md", "AGENTS.md"), []);

  // Claude marketplace plugin artifacts. The plugin cannot install repo-root
  // `skills/`, so shared content lives under plugin/shared/skills and entry-point
  // wrappers are rewritten to that plugin-local path.
  syncSkillDirs(SHARED_SKILLS_SRC, PLUGIN_SHARED_ROOT, SHARED_SKILLS, "marketplace shared skills");
  rmrf(PLUGIN_SKILLS_ROOT);
  fs.mkdirSync(PLUGIN_SKILLS_ROOT, { recursive: true });
  for (const name of TOP_LEVEL_SKILLS) {
    const src = path.join(CLAUDE_SKILLS_SRC, name);
    assertExists(src, "Claude skill " + name);
    const dst = path.join(PLUGIN_SKILLS_ROOT, name);
    copyDir(src, dst);
    copyFileWithReplacements(
      path.join(src, "SKILL.md"),
      path.join(dst, "SKILL.md"),
      [["../../../skills/", "../../shared/skills/"]]
    );
  }

  // Marketplace JSON manifests — copy from source .claude-plugin/
  const MARKETPLACE_META_SRC = path.join(REPO, ".claude-plugin");
  assertExists(path.join(MARKETPLACE_META_SRC, "marketplace.json"), ".claude-plugin/marketplace.json");
  assertExists(path.join(MARKETPLACE_META_SRC, "plugin.json"), ".claude-plugin/plugin.json");
  const MARKETPLACE_META_DST = path.join(REPO, "dist", "marketplace", ".claude-plugin");
  fs.mkdirSync(MARKETPLACE_META_DST, { recursive: true });
  fs.copyFileSync(path.join(MARKETPLACE_META_SRC, "marketplace.json"), path.join(MARKETPLACE_META_DST, "marketplace.json"));
  const PLUGIN_META_DST = path.join(PLUGIN_DIR, ".claude-plugin");
  fs.mkdirSync(PLUGIN_META_DST, { recursive: true });
  fs.copyFileSync(path.join(MARKETPLACE_META_SRC, "plugin.json"), path.join(PLUGIN_META_DST, "plugin.json"));
  process.stdout.write("build-dist: copied marketplace manifests → dist/marketplace\n");

  syncDir(CLAUDE_AGENTS_SRC, path.join(PLUGIN_DIR, "agents"));

  // Cursor rule artifacts
  const CURSOR_RULES_SRC = path.join(REPO, ".cursor", "rules");
  const CURSOR_RULES_DST = path.join(DIST, "cursor", ".cursor", "rules");
  fs.mkdirSync(CURSOR_RULES_DST, { recursive: true });
  for (const mdc of ["e2e-engineering.mdc", "e2e-flight.mdc", "e2e-deslop.mdc"]) {
    assertExists(path.join(CURSOR_RULES_SRC, mdc), ".cursor/rules/" + mdc);
    fs.copyFileSync(path.join(CURSOR_RULES_SRC, mdc), path.join(CURSOR_RULES_DST, mdc));
  }
  process.stdout.write("build-dist: copied .cursor/rules/*.mdc → dist/cursor/.cursor/rules/\n");

  // sanity: required portable artifacts present
  const required = [
    path.join(REPO, "dist", "marketplace", ".claude-plugin", "marketplace.json"),
    path.join(PLUGIN_DIR, ".claude-plugin", "plugin.json"),
    path.join(REPO, "dist", "agents-md", "AGENTS.md"),
    path.join(REPO, "dist", "shared", "skills"),
    path.join(REPO, "dist", "claude", "skills"),
    path.join(REPO, "dist", "codex", ".agents", "skills"),
    path.join(REPO, "dist", "cursor", ".cursor", "rules", "e2e-engineering.mdc"),
    path.join(REPO, "dist", "cursor", ".cursor", "rules", "e2e-flight.mdc"),
    path.join(REPO, "dist", "cursor", ".cursor", "rules", "e2e-deslop.mdc")
  ];
  const missing = required.filter((p) => !fs.existsSync(p));
  if (missing.length) {
    process.stderr.write("build-dist: WARNING — missing portable artifacts:\n");
    for (const m of missing) process.stderr.write("  " + path.relative(REPO, m) + "\n");
  }

  const count = countFiles(PLUGIN_SKILLS_ROOT);
  process.stdout.write("build-dist: synced " + count + " marketplace entry file(s) [" + TOP_LEVEL_SKILLS.join(", ") + "] → " + path.relative(REPO, PLUGIN_SKILLS_ROOT) + "\n");
  process.stdout.write("build-dist: synced shared runtime → " + path.relative(REPO, path.join(DIST, "shared", "skills")) + "\n");
  process.stdout.write("build-dist: synced Codex runtime → " + path.relative(REPO, path.join(DIST, "codex", ".agents", "skills")) + "\n");
}

function syncDir(src, dst) {
  rmrf(dst);
  copyDir(src, dst);
  process.stdout.write("build-dist: synced " + path.relative(REPO, src) + " → " + path.relative(REPO, dst) + "\n");
}

function syncSkillDirs(srcRoot, dstRoot, names, label) {
  rmrf(dstRoot);
  fs.mkdirSync(dstRoot, { recursive: true });
  for (const name of names) {
    const src = path.join(srcRoot, name);
    assertExists(src, label + " " + name);
    copyDir(src, path.join(dstRoot, name));
  }
  process.stdout.write("build-dist: synced " + label + " → " + path.relative(REPO, dstRoot) + "\n");
}

function countFiles(dir) {
  let n = 0;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) n += countFiles(path.join(dir, e.name));
    else n++;
  }
  return n;
}

main();
