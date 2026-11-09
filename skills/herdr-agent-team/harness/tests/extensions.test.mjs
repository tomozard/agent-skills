// Behaviour tests for the two role extensions: role-guard must refuse blocking
// waits at command position (and leave prose alone), auto-compact must fire above
// the threshold, not fire twice, and re-arm after the context drops.
//
// Run through tests/extensions.test.sh so the node version check stays in one place.
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const extensions = resolve(process.argv[2] ?? ".agents/extensions");
process.env.HERDR_LOG_DIR = mkdtempSync(join(tmpdir(), "ext-test-"));
process.env.HERDR_ROLE = "pm";

const handlers = {};
const fakePi = { on: (name, fn) => { (handlers[name] ||= []).push(fn); } };

let failures = 0;
const check = (condition, label) => {
  if (!condition) failures += 1;
  console.log(`${condition ? "ok  " : "FAIL"} ${label}`);
};

const guard = (await import(`${extensions}/role-guard.ts`)).default;
guard(fakePi);
const onToolCall = handlers["tool_call"][0];

const cases = [
  ["hc wait t90", true],
  ["herdr-core wait --children any", true],
  ["cd repo && sleep 30", true],
  ["for i in 1 2 3; do sleep 5; done", true],
  ["while true; do date; done", true],
  ['echo "sleep 5 in a string"', false],
  ["git status", false],
  ["grep -rn sleep bin/", false],
];
for (const [command, shouldBlock] of cases) {
  const result = onToolCall({ toolName: "bash", input: { command } });
  check(Boolean(result?.block) === shouldBlock,
        `${shouldBlock ? "block" : "allow"} :: ${command}`);
}

const compactions = [];
const context = (percent) => ({
  isIdle: () => true,
  hasPendingMessages: () => false,
  getContextUsage: () => (percent === null ? undefined : { percent }),
  compact: (options) => { compactions.push(options); options.onComplete?.(); },
});

const compact = (await import(`${extensions}/auto-compact.ts`)).default;
compact(fakePi);
const settle = (percent) => handlers["agent_settled"][0]({ type: "agent_settled" }, context(percent));

settle(30);
check(compactions.length === 0, "30% context → no compaction");
settle(74);
check(compactions.length === 1, "74% context → compaction requested");
settle(74);
check(compactions.length === 1, "second settle at 74% → no duplicate compaction");
settle(40);
settle(80);
check(compactions.length === 2, "drop below threshold re-arms, then compacts again");

console.log(`${failures === 0 ? "extensions test: ok" : `extensions test: ${failures} failed`}`);
process.exit(failures === 0 ? 0 : 1);