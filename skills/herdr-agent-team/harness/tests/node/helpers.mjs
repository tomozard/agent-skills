// Shared helpers for the node-based test suite.
//
// The suite runs from three layouts: the repository (harness/tests/node), a
// payload copy the installer validates at a temporary root, and an installed
// skill. Everything here resolves the skill the same way the tools do, so a
// layout change cannot silently skip a test.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export const harnessRoot = path.resolve(here, '..', '..');

function findSkill() {
  const candidates = [
    process.env.HERDR_AGENT_TEAM_SKILL_DIR,
    path.resolve(harnessRoot, '..'),
    path.join(os.homedir(), '.agents', 'skills', 'herdr-agent-team'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'scripts', 'team-config'))) return candidate;
  }
  return null;
}

export const skillDir = findSkill();
export const scriptsDir = skillDir ? path.join(skillDir, 'scripts') : null;
export const baseTeam = skillDir ? path.join(skillDir, 'config', 'team.json') : null;

export function requireSkill(t) {
  if (!skillDir) {
    t.skip('the skill scripts are not installed; this suite needs them');
    return false;
  }
  return true;
}

export function makeHome(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'hteam-node-'));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  return home;
}

export function envFor(home, extra = {}) {
  const base = { ...process.env };
  for (const key of Object.keys(base)) {
    if (key.startsWith('HERDR_TEAM_') || key === 'HERDR_AGENT_ROLE' || key === 'HERDR_ENV') delete base[key];
  }
  return {
    ...base,
    HOME: home,
    HERDR_AGENT_TEAM_SCRIPTS: scriptsDir,
    HERDR_TEAM_BASE: baseTeam,
    ...extra,
  };
}

export function tool(name) {
  return path.join(harnessRoot, 'bin', name);
}

export function script(name) {
  return scriptsDir ? path.join(scriptsDir, name) : path.join('missing', name);
}

// stdin is a pipe, so isTTY is false: the interactive paths are testable.
export function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, { encoding: 'utf8', input: '', ...options });
  return {
    status: result.status,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    signal: result.signal,
  };
}

export function runTool(name, args, options = {}) {
  return run(tool(name), args, options);
}

export function parseJson(result, what = 'output') {
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    throw new Error(`${what} is not JSON: ${error.message}\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);
  }
}

// python3 already is a runtime dependency; using it keeps the test suite free of
// a YAML npm dependency.
export function readYaml(file) {
  const result = run('python3', [
    '-c',
    'import json,sys,yaml;print(json.dumps(yaml.safe_load(open(sys.argv[1],encoding="utf-8"))))',
    file,
  ]);
  if (result.status !== 0) throw new Error(`cannot read YAML ${file}: ${result.stderr}`);
  return JSON.parse(result.stdout);
}

export function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

export function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

export function repoGit() {
  const result = run('git', ['rev-parse', '--show-toplevel']);
  return result.status === 0 ? result.stdout.trim() : null;
}
