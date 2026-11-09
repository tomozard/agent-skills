import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Expose the app-runtime team launcher as `/hteam` in any Pi session.
 *
 * `/hteam [check] [--voice on|off]` runs `bin/herdr-app-team` exactly like the
 * terminal command, and `/hteam setup` is an interactive wizard that writes the
 * per-machine config `bin/herdr-app-team` reads (~/.config/herdr-team/hteam.yaml).
 * Both are deterministic: no model turn is spent.
 *
 * Refuses when this Pi session already runs inside a team terminal: launching a
 * second control space from a role pane is never what the Human meant.
 */

const repoDir = (): string =>
  process.env.HERDR_TEAM_REPO ?? join(homedir(), "Workspaces", "project-scaffold");

const findBin = (name: string): string => {
  const installed = join(homedir(), "bin", name);
  if (existsSync(installed)) return installed;
  return join(repoDir(), "bin", name);
};

// herdr-core injects HC_TERMINAL_ID into EVERY app terminal, so it is not a
// team signal. agent-runtime exports HERDR_AGENT_ROLE in role panes only
// (orchestrator included), which is the real "already on the team" marker.
const inTeamTerminal = (): boolean => Boolean(process.env.HERDR_AGENT_ROLE);

/** Split on whitespace, keeping single or double quoted runs together. */
const tokenize = (raw: string): string[] => {
  const tokens: string[] = [];
  let current = "";
  let quote = "";
  let started = false;
  for (const ch of raw.trim()) {
    if (quote) {
      if (ch === quote) {
        quote = "";
      } else {
        current += ch;
      }
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      started = true;
      continue;
    }
    if (/\s/.test(ch)) {
      if (started || current) tokens.push(current);
      current = "";
      started = false;
      continue;
    }
    current += ch;
    started = true;
  }
  if (started || current) tokens.push(current);
  if (quote) throw new Error("unbalanced quote in /hteam arguments");
  return tokens;
};

const capture = (bin: string, args: string[]) => {
  const result = spawnSync(bin, args, { encoding: "utf8", timeout: 180_000, env: process.env });
  const out = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
  return { ok: result.status === 0 && result.error === undefined, out, status: result.status };
};

const CONFIG_KEYS = [
  "space",
  "folder",
  "voice",
  "watch",
  "repo",
  "registry",
  "vault",
  "activity_log",
] as const;
type ConfigKey = (typeof CONFIG_KEYS)[number];
type Config = Record<ConfigKey, string>;

const readConfig = (configBin: string): Config | undefined => {
  const result = capture(configBin, ["show", "--json"]);
  if (!result.ok) return undefined;
  try {
    return JSON.parse(result.out) as Config;
  } catch {
    return undefined;
  }
};

const askText = async (
  ctx: any,
  title: string,
  current: string,
): Promise<string | undefined> => {
  const answer = await ctx.ui.input(`${title}  (current: ${current})`, current);
  if (answer === undefined || answer === null) return undefined;
  const trimmed = String(answer).trim();
  return trimmed === "" ? current : trimmed;
};

const MODES = [
  "เริ่มต้น — ถาม 4 ค่า (space, folder, voice, watch)",
  "เร็ว — ใช้ค่าที่ตรวจพบทั้งหมด ยืนยันครั้งเดียว",
  "ละเอียด — ตรวจ path ทีละตัว + health check + review",
];

async function runSetup(preset: string, ctx: any): Promise<void> {
  const configBin = findBin("hteam-config");
  const launcher = findBin("herdr-app-team");
  if (!existsSync(configBin)) {
    ctx.ui.notify(`hteam-config not found at ${configBin} — run setup_harness.sh`, "error");
    return;
  }

  const current = readConfig(configBin);
  if (!current) {
    ctx.ui.notify("hteam-config could not report the current values", "error");
    return;
  }

  let mode = preset;
  if (!mode) {
    const picked = await ctx.ui.select("hteam setup — เลือกโหมด", MODES);
    if (!picked) return;
    const index = MODES.indexOf(picked);
    mode = index === 1 ? "quick" : index === 2 ? "detailed" : "default";
  }
  if (!["quick", "default", "detailed"].includes(mode)) {
    ctx.ui.notify(`unknown setup mode: ${mode} (quick|default|detailed)`, "error");
    return;
  }

  const next: Config = { ...current };

  if (mode === "default" || mode === "detailed") {
    const space = await askText(ctx, "control space name", next.space);
    if (space === undefined) return;
    next.space = space;

    const folder = await askText(ctx, "team terminals start folder", next.folder);
    if (folder === undefined) return;
    next.folder = folder;

    const voice = await ctx.ui.select("voice (speaks from Orchestrator and PM only)", ["off", "on"]);
    if (!voice) return;
    next.voice = voice;

    const watch = await ctx.ui.select(
      "ClickUp intake watcher (default off; `hteam --watch on` enables one run)",
      ["off", "on"],
    );
    if (!watch) return;
    next.watch = watch;
  }

  if (mode === "detailed") {
    for (const key of ["repo", "registry", "vault", "activity_log"] as ConfigKey[]) {
      const value = await askText(ctx, key, next[key]);
      if (value === undefined) return;
      next[key] = value;
    }
  }

  const summary = [
    `space:         ${next.space}`,
    `folder:        ${next.folder}`,
    `voice:         ${next.voice}`,
    `clickup watch: ${next.watch}`,
    `repo:          ${next.repo}`,
    `registry:      ${next.registry}`,
    `vault:         ${next.vault}`,
    `activity log:  ${next.activity_log}`,
  ].join("\n");

  if (!(await ctx.ui.confirm("เขียนค่าลง ~/.config/herdr-team/hteam.yaml?", summary))) {
    ctx.ui.notify("hteam setup: cancelled, nothing written", "warn");
    return;
  }

  const written = capture(configBin, ["write", "--json", JSON.stringify(next)]);
  if (!written.ok) {
    ctx.ui.notify(`hteam setup failed: ${written.out.slice(0, 600)}`, "error");
    return;
  }

  const checked = capture(launcher, ["--voice", next.voice, "check"]);
  const tail = checked.out.split("\n").slice(-14).join("\n");
  ctx.ui.notify(
    `hteam setup: wrote the config\n${tail || "(check printed nothing)"}`,
    checked.ok ? "info" : "error",
  );
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("hteam", {
    description: "Start, check, or set up the Herdr app agent team (same as `hteam`)",
    handler: async (args, ctx) => {
      if (inTeamTerminal()) {
        ctx.ui.notify(
          "Already inside a team terminal — talk to your PM in the Herdr app instead.",
          "warn",
        );
        return;
      }

      const raw = (args ?? "").trim();
      if (raw === "setup" || raw.startsWith("setup ")) {
        await runSetup(raw.slice("setup".length).trim(), ctx);
        return;
      }

      const bin = findBin("herdr-app-team");
      if (!existsSync(bin)) {
        ctx.ui.notify(`hteam launcher not found at ${bin} — run setup_harness.sh`, "error");
        return;
      }

      let argv: string[];
      try {
        argv = tokenize(raw);
      } catch (error) {
        ctx.ui.notify(String((error as Error).message ?? error), "error");
        return;
      }

      const result = capture(bin, argv);
      const body = result.out.length > 1500 ? `${result.out.slice(0, 1500)}…` : result.out;
      ctx.ui.notify(
        body || (result.ok ? "hteam: ok" : `hteam failed (exit ${result.status})`),
        result.ok ? "info" : "error",
      );
    },
  });
}