import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// Hard Rule 4 ("coordination is push-based") was only a sentence in the prompt,
// and the manager still ran `herdr-core wait --children any` and blocked for two
// minutes. Prompts do not enforce anything, so this extension refuses the call
// before the tool runs. Patterns match at command position, so prose that merely
// mentions "sleep" inside a quoted string is not caught.

const LOG_DIR = process.env.HERDR_LOG_DIR ?? join(homedir(), ".config", "herdr");
const ROLE = process.env.HERDR_ROLE ?? process.env.AGENT_ROLE ?? "agent";

const BLOCKED: { pattern: RegExp; what: string }[] = [
  { pattern: /(^|[;&|]\s*|\bdo\s+)(hc|herdr-core)\s+wait\b/, what: "hc wait / herdr-core wait" },
  { pattern: /(^|[;&|]\s*)herdr\s+pane\s+wait\b/, what: "herdr pane wait" },
  { pattern: /(^|[;&|]\s*|\bdo\s+)sleep\s+[0-9]/, what: "sleep N" },
  { pattern: /(^|[;&|]\s*)watch\s+-n/, what: "watch -n" },
  { pattern: /while\s+true\s*;?\s*do/, what: "while true loop" },
];

const log = (line: string) => {
  try {
    mkdirSync(LOG_DIR, { recursive: true });
    appendFileSync(join(LOG_DIR, "role-guard.log"), `${new Date().toISOString()} ${line}\n`);
  } catch {
    // logging must never break the agent
  }
};

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event) => {
    if (event.toolName !== "bash") return;
    const command = String((event.input as { command?: unknown }).command ?? "");
    if (!command) return;

    for (const rule of BLOCKED) {
      if (!rule.pattern.test(command)) continue;
      log(`blocked ${ROLE}: ${rule.what} :: ${command.slice(0, 160)}`);
      return {
        block: true,
        reason:
          `Blocked ${rule.what}. Work is push-based here: assign the task, end the turn, and let the ` +
          `child push its result back to this pane. If you are waiting on a child, stop waiting and ` +
          `report what you handed off; the Human asks for the result when it matters.`,
      };
    }
    return;
  });
}