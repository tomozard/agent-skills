import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// Compaction is a safety net for long-lived panes. It fires only on a settled
// run: compacting mid-run would interrupt the agent, so turn_end is deliberately
// not hooked and both the idle and queued-work guards stay.
//
// The original version also logged nothing, which is how a manager pane reached
// 98% context without anyone noticing that compaction never ran (the pane
// predated the extension). Every decision is written to auto-compact.log now.

const COMPACT_THRESHOLD_PERCENT = 50;
const STUCK_MS = 4 * 60 * 1000;

const LOG_DIR = process.env.HERDR_LOG_DIR ?? join(homedir(), ".config", "herdr");
const LOG_FILE = join(LOG_DIR, "auto-compact.log");

const log = (line: string) => {
  try {
    mkdirSync(LOG_DIR, { recursive: true });
    appendFileSync(LOG_FILE, `${new Date().toISOString()} ${line}\n`);
  } catch {
    // logging must never break the agent
  }
};

type Usage = { percent?: number; tokens?: number; limit?: number };

const percentOf = (ctx: ExtensionContext): number | null => {
  let usage: unknown;
  try {
    usage = ctx.getContextUsage();
  } catch {
    return null;
  }
  if (!usage || typeof usage !== "object") return null;
  const u = usage as Usage & Record<string, unknown>;
  if (typeof u.percent === "number") return u.percent;
  const used = typeof u.tokens === "number" ? u.tokens : Number(u.used ?? NaN);
  const limit = typeof u.limit === "number" ? u.limit : Number(u.max ?? NaN);
  if (Number.isFinite(used) && Number.isFinite(limit) && limit > 0) {
    return (used / limit) * 100;
  }
  return null;
};

export default function (pi: ExtensionAPI) {
  const state = { compacting: false, armed: true, since: 0, warnedNoUsage: false };

  const compactIfNeeded = (ctx: ExtensionContext, where: string) => {
    if (state.compacting && Date.now() - state.since > STUCK_MS) {
      log(`${where}: compacting stuck for ${Math.round((Date.now() - state.since) / 1000)}s, resetting`);
      state.compacting = false;
      state.armed = true;
    }
    if (state.compacting) return;
    if (!ctx.isIdle()) return;
    if (ctx.hasPendingMessages()) return;

    const percent = percentOf(ctx);
    if (percent === null) {
      if (!state.warnedNoUsage) {
        state.warnedNoUsage = true;
        log(`${where}: context usage unavailable, compaction inactive`);
      }
      return;
    }
    if (percent <= COMPACT_THRESHOLD_PERCENT) {
      state.armed = true;
      return;
    }
    if (!state.armed) return;

    state.armed = false;
    state.compacting = true;
    state.since = Date.now();
    log(`${where}: compacting at ${percent.toFixed(1)}% (threshold ${COMPACT_THRESHOLD_PERCENT}%)`);
    try {
      ctx.compact({
        customInstructions:
          "Preserve the Human's current task, decisions made, files and branches touched, " +
          "open approvals, and the next step. Drop repeated apologies and restated rules.",
        onComplete: () => {
          state.compacting = false;
          state.armed = false;
          log(`${where}: compaction complete`);
        },
        onError: (error: unknown) => {
          state.compacting = false;
          state.armed = true;
          log(`${where}: compaction failed: ${String(error)}`);
        },
      });
    } catch (error) {
      state.compacting = false;
      state.armed = true;
      log(`${where}: compaction threw: ${String(error)}`);
    }
  };

  pi.on("agent_before_settle", (_event, ctx) => {
    compactIfNeeded(ctx, "before_settle");
  });
  pi.on("agent_settled", (_event, ctx) => {
    compactIfNeeded(ctx, "settled");
  });
}