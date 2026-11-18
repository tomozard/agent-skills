import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  baseTeam, envFor, makeHome, parseJson, readJson, requireSkill, run, runTool,
  script, writeJson,
} from './helpers.mjs';

test('hteam agent', async (t) => {
  if (!requireSkill(t)) return;

  const home = makeHome(t);
  const override = path.join(home, 'team.local.json');
  const effective = path.join(home, '.agents', 'team.json');
  const roleText = path.join(home, '.config', 'herdr-team', 'roles', 'security_reviewer.md');
  const claudeText = path.join(home, '.claude', 'agents', 'herdr-security_reviewer.md');
  const env = envFor(home, {
    HERDR_TEAM_BASE: baseTeam,
    HERDR_TEAM_LOCAL: override,
    HERDR_TEAM_EFFECTIVE: effective,
  });
  const agent = (...args) => runTool('hteam-agent', args, { env });
  const resolver = (intake) => run(script('workflow-shape'), ['--team', effective, '--intake', intake, '--format', 'json'], { env });

  assert.equal(run(script('team-config'), ['render'], { env }).status, 0);

  const w3 = path.join(home, 'w3.json');
  const w7 = path.join(home, 'w7.json');
  writeJson(w3, { task_class: 'bug-fix', known_cause: true, touches_behavior: true, runnable_acceptance: false });
  writeJson(w7, { task_class: 'feature', new_behavior: true, touches_behavior: true, runnable_acceptance: true });

  await t.test('--json starts empty', () => {
    const data = parseJson(agent('--json'));
    assert.deepEqual(data.local_roles, {});
  });

  await t.test('add writes role text, Claude file, overlay, and roster', () => {
    const result = agent('--add', 'security_reviewer', '--from', 'reviewer', '--shapes', 'W3-fix');
    assert.equal(result.status, 0, result.stderr);
    assert.ok(fs.existsSync(roleText), 'role text missing');
    assert.ok(fs.existsSync(claudeText), 'Claude agent file missing');
    assert.match(fs.readFileSync(roleText, 'utf8'), /local role: security_reviewer/);
    const over = readJson(override);
    const local = over.local_roles.security_reviewer;
    assert.equal(local.base, 'reviewer');
    assert.equal(local.kind, 'verifier');
    assert.deepEqual(local.shapes, ['W3-fix']);
    const entry = readJson(effective).roles.security_reviewer;
    assert.equal(entry.repo_mode, 'read_only');
    assert.equal(entry.model_selection, 'fixed');
  });

  await t.test('the resolver staffs it only in the declared shapes', () => {
    const first = parseJson(resolver(w3));
    assert.equal(first.shape, 'W3-fix');
    assert.ok(first.verifiers.includes('security_reviewer'), first.verifiers.join(','));
    assert.ok(first.verifiers.includes('reviewer'), first.verifiers.join(','));
    const second = parseJson(resolver(w7));
    assert.equal(second.shape, 'W7-feature');
    assert.ok(!second.verifiers.includes('security_reviewer'), second.verifiers.join(','));
  });

  await t.test('guardrails refuse unsafe or contradictory clones', () => {
    const cases = [
      ['--add', 'coder', '--from', 'reviewer', '--shapes', 'W3-fix'],
      ['--add', 'x', '--from', 'ghost', '--shapes', 'W3-fix'],
      ['--add', 'x', '--from', 'pm', '--shapes', 'W3-fix'],
      ['--add', 'x', '--from', 'reviewer', '--kind', 'worker', '--shapes', 'W3-fix'],
      ['--add', 'x', '--from', 'reviewer', '--shapes', 'W99'],
      ['--add', 'x', '--from', 'reviewer', '--shapes', ''],
      ['--add', 'x', '--from', 'coder', '--shapes', 'W3-fix'],
    ];
    for (const args of cases) {
      assert.notEqual(agent(...args).status, 0, `accepted: ${args.join(' ')}`);
    }
  });

  await t.test("a worker clone keeps the base's write authority", () => {
    const result = agent('--add', 'hotfix_coder', '--from', 'coder', '--shapes', 'W3-fix');
    assert.equal(result.status, 0, result.stderr);
    const entry = readJson(effective).roles.hotfix_coder;
    assert.equal(entry.repo_mode, 'write');
    assert.equal(entry.may_local_commit, true);
  });

  await t.test('remove deletes the files, the overlay entry, and the roster entry', () => {
    const result = agent('--remove', 'security_reviewer');
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(roleText), false, 'role text survived');
    assert.equal(fs.existsSync(claudeText), false, 'Claude file survived');
    assert.equal('security_reviewer' in (readJson(override).local_roles ?? {}), false);
    assert.equal('security_reviewer' in readJson(effective).roles, false);
    assert.ok(!parseJson(resolver(w3)).verifiers.includes('security_reviewer'));
  });

  await t.test('interactive mode is refused without a TTY', () => {
    assert.equal(agent().status, 2);
  });
});
