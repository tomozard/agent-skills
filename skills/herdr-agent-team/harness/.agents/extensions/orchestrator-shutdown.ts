import { spawnSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Expose the team shutdown protocol as an explicit Pi command.
 *
 * The existing Orchestrator shutdown handling remains the source of truth for
 * workspace IDs and launcher cleanup. This command only translates `/shutdown`
 * into that exact standalone Human message; Pi's built-in `/quit` is untouched.
 */
export default function (pi: ExtensionAPI) {
  if (process.env.HERDR_AGENT_ROLE !== "orchestrator") return;

  pi.registerCommand("shutdown", {
    description: "Stop the current Herdr agent-team session",
    handler: async () => {
      const helper = process.env.HERDR_VOICE_NOTIFY_BIN;
      if (helper) {
        spawnSync(helper, ["claim", "shutdown"], {
          stdio: "ignore",
          env: process.env,
        });
      }
      await pi.sendUserMessage("shutdown");
    },
  });
}
