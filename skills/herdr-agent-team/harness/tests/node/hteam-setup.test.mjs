import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { envFor, makeHome, parseJson, readYaml, runTool } from './helpers.mjs';

test('hteam setup', async (t) => {
  const home = makeHome(t);
  const config = path.join(home, 'hteam.yaml');
  const projects = path.join(home, 'projects');
  const vault = path.join(home, 'vault');
  const registry = path.join(projects, '.agents', 'workspace-registry.yaml');
  fs.mkdirSync(path.join(projects, 'app-a', '.git'), { recursive: true });
  fs.mkdirSync(path.join(projects, 'app-b', '.git'), { recursive: true });

  const env = envFor(home, { HERDR_TEAM_CONFIG: config });
  const setup = (...args) => runTool('hteam-setup', args, { env });
  const full = ['--defaults', '--folder', projects, '--vault', vault, '--projects', 'all'];

  await t.test('a non-TTY run without --defaults is refused', () => {
    const result = setup();
    assert.equal(result.status, 2);
  });

  await t.test('--dry-run writes nothing and prints the plan', () => {
    const result = setup('--dry-run', ...full);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(config), false, 'the config was written');
    assert.equal(fs.existsSync(registry), false, 'the registry was written');
    assert.equal(fs.existsSync(vault), false, 'the vault was created');
    assert.match(result.stdout, /would run:/);
  });

  await t.test('a real run writes config and registry under the chosen folder', () => {
    const result = setup(...full);
    assert.equal(result.status, 0, result.stderr);
    const text = fs.readFileSync(config, 'utf8');
    assert.match(text, new RegExp(`folder: ${projects.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`));
    assert.match(text, new RegExp(`vault: ${vault.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`));
    assert.ok(fs.existsSync(registry), 'the registry is not under the chosen folder');
    const data = readYaml(registry);
    assert.deepEqual(Object.keys(data.projects).sort(), ['app_a', 'app_b']);
    for (const entry of Object.values(data.projects)) {
      assert.equal(entry.status, 'active');
      assert.ok(entry.path);
    }
    assert.ok(fs.existsSync(path.join(vault, 'log.md')));
  });

  await t.test('re-running is idempotent', () => {
    const result = setup(...full);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /registry unchanged/);
    assert.equal(Object.keys(readYaml(registry).projects).length, 2);
  });

  await t.test('--json is machine readable on its own', () => {
    const result = setup('--defaults', '--json', '--folder', projects, '--vault', vault, '--projects', 'none');
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.stdout.trim().startsWith('{'), result.stdout.slice(0, 40));
    const data = parseJson(result, 'setup --json');
    assert.equal(data.schema, 1);
    assert.equal(data.status, 'ok');
    assert.equal(data.config.folder, projects);
  });

  await t.test('--only limits the steps', () => {
    const result = setup('--defaults', '--only', 'voice', '--voice', 'on');
    assert.equal(result.status, 0, result.stderr);
    assert.equal(readYaml(config).voice, 'on');
  });

  await t.test('the launcher hands setup to the same wizard', () => {
    const result = runTool('herdr-app-team', [
      'setup', '--defaults', '--json', '--only', 'folder', '--folder', projects,
    ], { env });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(parseJson(result, 'setup via launcher').steps, ['folder']);
  });

  await t.test('a host without Herdr cannot be configured', () => {
    const result = runTool('hteam-setup', ['--defaults', '--json'], {
      env: { ...env, HERDR_APP_BIN: '/nonexistent/herdr-app', HC_BIN: '/nonexistent/herdr-core' },
    });
    assert.equal(result.status, 3, result.stderr);
  });
});
