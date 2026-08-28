import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RESUME_PROMPT = `
Your context has just been compacted.

Analyze what you were doing before compaction. If your work was interrupted, resume it now and continue until the user's goal is met. Do not merely describe what remains; perform the next necessary actions.
`.trim();

export default function (pi: ExtensionAPI) {
	pi.on("session_compact", async (event) => {
		// Threshold compaction intentionally stops the current run. Queue a
		// continuation so the agent can resume without requiring another prompt.
		if (event.reason !== "threshold") return;

		pi.sendUserMessage(RESUME_PROMPT, {
			deliverAs: "followUp",
		});
	});
}
