import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { envFor, makeHome, parseJson, runTool } from './helpers.mjs';

test('hteam health', async (t) => {
  const home = makeHome(t);
  const env = envFor(home);

  await t.test('--json is schema 1 with a stable check shape', () => {
    const result = runTool('hteam-health', ['--json'], { env });
    assert.ok([0, 1, 3].includes(result.status), `unexpected exit ${result.status}`);
    const data = parseJson(result, 'health --json');
    assert.equal(data.schema, 1);
    assert.ok(['ok', 'warn', 'fail'].includes(data.status));
    assert.equal(typeof data.host_ready, 'boolean');
    assert.ok(Array.isArray(data.checks) && data.checks.length > 0);
    for (const key of ['ok', 'warn', 'fail', 'skip']) assert.ok(key in data.summary);
    for (const check of data.checks) {
      assert.deepEqual(Object.keys(check).sort(),
        ['detail', 'hint', 'id', 'section', 'status']);
      assert.ok(['ok', 'warn', 'fail', 'skip'].includes(check.status));
    }
  });

  await t.test('--section returns only that section', () => {
    const data = parseJson(runTool('hteam-health', ['--section', 'host', '--json'], { env }));
    assert.ok(data.checks.length > 0);
    assert.deepEqual([...new Set(data.checks.map((check) => check.section))], ['host']);
  });

  await t.test('a missing Herdr is a host failure (exit 3)', () => {
    const result = runTool('hteam-health', ['--json'], {
      env: { ...env, HERDR_APP_BIN: '/nonexistent/herdr-app', HC_BIN: '/nonexistent/herdr-core' },
    });
    assert.equal(result.status, 3);
    const data = parseJson(result, 'health --json');
    assert.equal(data.host_ready, false);
    const failed = data.checks.filter((check) => check.status === 'fail').map((check) => check.id);
    assert.ok(failed.includes('herdr-app'), failed.join(','));
    assert.ok(failed.includes('herdr-core'), failed.join(','));
  });

  await t.test('the launcher hands health to the same checker', () => {
    const viaLauncher = parseJson(runTool('herdr-app-team', ['health', '--section', 'policy', '--json'], { env }));
    assert.equal(viaLauncher.schema, 1);
    assert.deepEqual([...new Set(viaLauncher.checks.map((check) => check.section))], ['policy']);
  });

  await t.test('the human output ends with a verdict and prints hints', () => {
    const result = runTool('hteam-health', ['--section', 'host'], { env });
    assert.ok([0, 1, 3].includes(result.status));
    assert.match(result.stdout, /^(healthy|healthy with warnings|not healthy):/m);
    assert.match(result.stdout, /hint:/);
  });
});
