import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  baseTeam, envFor, makeHome, parseJson, readJson, requireSkill, run, runTool,
  script, tool, writeJson,
} from './helpers.mjs';

test('layered roster', async (t) => {
  if (!requireSkill(t)) return;

  const home = makeHome(t);
  const override = path.join(home, 'team.local.json');
  const effective = path.join(home, '.agents', 'team.json');
  const env = envFor(home, {
    HERDR_TEAM_BASE: baseTeam,
    HERDR_TEAM_LOCAL: override,
    HERDR_TEAM_EFFECTIVE: effective,
  });
  const teamConfig = (...args) => run(script('team-config'), args, { env });
  const model = (...args) => runTool('hteam-model', args, { env });

  await t.test('paths names base, overlay, and effective', () => {
    const result = teamConfig('paths');
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /base .*team\.json/);
    assert.match(result.stdout, /overlay .*team\.local\.json/);
    assert.match(result.stdout, /effective .*team\.json/);
  });

  await t.test('render without an overlay is a faithful copy', () => {
    assert.equal(teamConfig('render').status, 0);
    const base = readJson(baseTeam);
    const rendered = readJson(effective);
    delete rendered._generated;
    assert.deepEqual(rendered, base);
  });

  await t.test('objects merge, lists replace, siblings survive', () => {
    writeJson(override, {
      version: 4,
      roles: {
        coder: {
          routing: {
            critical: {
              primary: { runtime: 'pi', model: 'antigravity/gemini-3.8-flash' },
              alternates: [],
            },
          },
        },
      },
    });
    const merged = parseJson(teamConfig('show', '--json'));
    const base = readJson(baseTeam);
    assert.equal(merged.roles.coder.routing.critical.primary.model, 'antigravity/gemini-3.8-flash');
    assert.deepEqual(merged.roles.coder.routing.standard, base.roles.coder.routing.standard);
    assert.deepEqual(merged.roles.reviewer, base.roles.reviewer);
  });

  await t.test('validate passes with the overlay', () => {
    const result = teamConfig('validate');
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /routes resolve/);
  });

  await t.test('an overlay may not invent a role', () => {
    writeJson(override, { version: 4, roles: { ghost: { routing: {} } } });
    assert.notEqual(teamConfig('show').status, 0);
    fs.rmSync(override, { force: true });
  });

  await t.test('--set pins one route and renders the effective roster', () => {
    const result = model('--set', 'coder', 'standard', 'pi', 'antigravity/gemini-3.8-flash');
    assert.equal(result.status, 0, result.stderr);
    assert.equal(
      readJson(override).roles.coder.routing.standard.primary.model,
      'antigravity/gemini-3.8-flash',
    );
    assert.equal(
      readJson(effective).roles.coder.routing.standard.primary.model,
      'antigravity/gemini-3.8-flash',
    );
    assert.ok(readJson(effective).roles.tester.routing.standard, 'unrelated roles must survive');
  });

  await t.test('a model outside the allowlist needs an explicit extension', () => {
    assert.equal(model('--set', 'coder', 'standard', 'pi', 'not/a-model').status, 2);
    const allowed = model('--set', 'coder', 'standard', 'pi', 'not/a-model', '--allow-model', 'pi', 'not/a-model');
    assert.equal(allowed.status, 0, allowed.stderr);
    assert.ok(readJson(override).roles.coder.models.pi.includes('not/a-model'));
  });

  await t.test('--unset removes the route override', () => {
    const result = model('--unset', 'coder', 'standard');
    assert.equal(result.status, 0, result.stderr);
    const coder = readJson(override).roles?.coder ?? {};
    assert.equal(coder.routing?.standard, undefined);
  });

  await t.test('--reset restores the canonical roster', () => {
    assert.equal(model('--reset').status, 0);
    assert.equal(fs.existsSync(override), false);
    const rendered = readJson(effective);
    delete rendered._generated;
    assert.deepEqual(rendered, readJson(baseTeam));
  });

  await t.test('the installed layout resolves team-config', () => {
    const binDir = path.join(home, 'bin');
    fs.mkdirSync(binDir, { recursive: true });
    const installed = path.join(binDir, 'hteam-model');
    fs.copyFileSync(tool('hteam-model'), installed);
    fs.chmodSync(installed, 0o755);
    const result = run(installed, ['--json'], { env });
    assert.equal(result.status, 0, result.stderr);
    assert.ok('coder' in parseJson(result).roles);
  });

  await t.test('interactive mode is refused without a TTY', () => {
    assert.equal(model().status, 2);
  });

  await t.test('--json reports the routing table', () => {
    const data = parseJson(model('--json'));
    assert.equal(data.schema, 1);
    assert.ok('critical' in data.roles.coder);
    assert.ok(data.roles.coder.critical.model);
  });
});
