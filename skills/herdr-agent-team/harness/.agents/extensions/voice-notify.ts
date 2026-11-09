import { spawn, spawnSync } from "node:child_process";
import { appendFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Speak one short summary after a Human-facing controller really settles.
 *
 * The complete assistant response remains in Pi's UI. This extension only
 * keeps the latest assistant text, reduces it locally to an outcome plus any
 * required Human action, and sends that short text to the managed macOS helper.
 * It is intentionally limited to the Orchestrator and PM. The managed helper
 * owns the cross-pane lease and suppresses PM turns that were triggered by
 * agent-to-agent protocol messages, except DONE/STUCK/AWAITING_HUMAN_COMMIT
 * results that the owning PM relays to the Human.
 */

type UnknownRecord = Record<string, unknown>;

const isEnabled = (value: string | undefined) => {
  return ["1", "true", "yes", "on"].includes((value ?? "0").toLowerCase());
};

const role = process.env.HERDR_AGENT_ROLE ?? "";
const voiceRole = role === "orchestrator" || role === "pm";
const enabled =
  process.platform === "darwin" &&
  voiceRole &&
  (process.env.HERDR_VOICE_MODE ?? "off").toLowerCase() === "on" &&
  isEnabled(process.env.HERDR_VOICE_NOTIFY);
const helper = process.env.HERDR_VOICE_NOTIFY_BIN ?? join(homedir(), "bin", "voice-notify");
const logFile = process.env.HERDR_VOICE_LOG_FILE ?? join(homedir(), ".config", "herdr", "voice-notify.log");
const MAX_SUMMARY_CHARS = 160;
const FALLBACK_SUMMARY = "สรุปผลการทำงานอยู่ในแชตค่ะ";
const THAI_DIGITS = "๐๑๒๓๔๕๖๗๘๙";
const HUMAN_ACTION_START = /^(?:กรุณา|โปรด|ขอให้|รบกวน|ช่วย|เลือก|ยืนยัน|ระบุ|ตอบกลับ|ส่ง|อนุมัติ|Human\s*(?:ต้อง|ควร)|คุณ\s*(?:ต้อง|ควร))/i;

function asRecord(value: unknown): UnknownRecord | undefined {
  return value !== null && typeof value === "object" ? (value as UnknownRecord) : undefined;
}

function textFromContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";

  return content
    .map((block) => {
      const record = asRecord(block);
      return record?.type === "text" && typeof record.text === "string" ? record.text : "";
    })
    .filter(Boolean)
    .join("\n");
}

function latestAssistantText(messages: unknown): string {
  if (!Array.isArray(messages)) return "";

  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = asRecord(messages[index]);
    if (message?.role !== "assistant") continue;
    const text = textFromContent(message.content);
    if (text.trim()) return text;
  }
  return "";
}

function normalizeThaiDigits(value: string): string {
  return [...value]
    .map((digit) => {
      const index = THAI_DIGITS.indexOf(digit);
      return index >= 0 ? String(index) : digit;
    })
    .join("");
}

function registryStartupSummary(value: string): string | undefined {
  const match = value.match(
    /Workspace Registry[\s\S]*?มีทั้งหมด\s+([0-9๐-๙]+)\s+โปรเจกต์[\s\S]*(?:โปรด\s*)?เลือกโปรเจกต์/i,
  );
  if (!match) return undefined;

  const count = normalizeThaiDigits(match[1]);
  return `ตรวจสอบ Workspace Registry เรียบร้อยแล้วค่ะ พบ ${count} โปรเจกต์ กรุณาเลือกโปรเจกต์ที่ต้องการเปิดค่ะ`;
}

function firstSentence(value: string): string {
  return value.match(/^.*?(?:[.!?。！？]+|$)/)?.[0].trim() ?? value.trim();
}

function humanAction(lines: string[]): string | undefined {
  for (const line of lines.slice(1)) {
    if (!HUMAN_ACTION_START.test(line)) continue;
    const sentence = firstSentence(line);
    if (sentence && sentence.length <= MAX_SUMMARY_CHARS) return sentence;
  }
  return undefined;
}

function summarize(value: string): string {
  const text = value
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/<think>[\s\S]*?<\/think>/gi, " ")
    .replace(/https?:\/\/\S+/g, " ")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/^[ \t]*#{1,6}[ \t]*/gm, "")
    .replace(/^[ \t]*[-*+][ \t]+/gm, "")
    .replace(/^[ \t]*>[ \t]?/gm, "")
    .replace(/[*_~`]+/g, "")
    .replace(/^\s*สวัสดี(?:ครับ|ค่ะ|คะ)?[^\n.!?。！？]*(?:[.!?。！？]+|\n|$)/i, "")
    .trim();

  const lines = text
    .split(/\r?\n/)
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter((line) => line && !/^[-*_]{3,}$/.test(line));
  const startupSummary = registryStartupSummary(text);
  if (startupSummary) return startupSummary;

  const candidate = lines[0] ?? "";
  if (!candidate) return FALLBACK_SUMMARY;

  const sentence = firstSentence(candidate);
  const action = humanAction(lines);
  if (action && !/(?:กรุณา|โปรด|ขอให้|รบกวน|ช่วย)/.test(sentence)) {
    const combined = `${sentence} ${action}`;
    if (combined.length <= MAX_SUMMARY_CHARS) return combined;
    if (action.length <= MAX_SUMMARY_CHARS) return action;
  }

  return sentence && sentence.length <= MAX_SUMMARY_CHARS ? sentence : FALLBACK_SUMMARY;
}

function log(message: string) {
  try {
    appendFileSync(logFile, `${new Date().toISOString()} pi ${message}\n`);
  } catch {
    // Notification failures must never affect the agent session.
  }
}

function announce(summary: string) {
  if (!enabled) return;
  try {
    const child = spawn(helper, ["summary", summary], {
      detached: true,
      stdio: "ignore",
      env: process.env,
    });
    child.on("error", (error) => log(`spawn summary failed: ${error.message}`));
    child.unref();
  } catch (error) {
    log(`announce summary failed: ${String(error)}`);
  }
}

function claimHumanTurn(text: string) {
  if (!enabled || !text.trim()) return;
  try {
    spawnSync(helper, ["claim", text], {
      stdio: "ignore",
      env: process.env,
    });
  } catch (error) {
    log(`claim failed: ${String(error)}`);
  }
}

function isInterAgentPrompt(text: string): boolean {
  const firstLine = text.trimStart().split(/\r?\n/, 1)[0] ?? "";
  return /^\[[A-Z_]+\]\s+from:/i.test(firstLine);
}

// Results the owning PM relays to the Human; the helper keeps ownership unchanged.
function isHumanResultPrompt(text: string): boolean {
  const firstLine = text.trimStart().split(/\r?\n/, 1)[0] ?? "";
  return /^\[(?:DONE|STUCK|AWAITING_HUMAN_COMMIT)\]\s+from:/.test(firstLine);
}

export default function (pi: ExtensionAPI) {
  if (!enabled) return;

  let lastAssistantText = "";
  let captureCurrentRun = role === "orchestrator";

  pi.on("input", (event) => {
    if (event.source !== "extension") claimHumanTurn(event.text);
    return { action: "continue" };
  });

  pi.on("before_agent_start", (event) => {
    captureCurrentRun =
      role === "orchestrator" || !isInterAgentPrompt(event.prompt) || isHumanResultPrompt(event.prompt);
  });

  pi.on("agent_end", (event) => {
    if (!captureCurrentRun) return;
    const text = latestAssistantText(event.messages);
    if (text) lastAssistantText = text;
  });

  pi.on("agent_settled", () => {
    announce(summarize(lastAssistantText));
    lastAssistantText = "";
  });
}
