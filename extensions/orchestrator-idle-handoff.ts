// Herdr orchestrator idle-handoff extension.
// Installed automatically by this bundle's Pi package manifest, or manually
// with scripts/install.sh. Requires pi-intercom in every participating session.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PARENT_ENV = "PI_ORCHESTRATOR_PARENT";
const INTERCOM_EVENT = "subagent:result-intercom";
export const ORCHESTRATOR_IDLE_HANDOFF_FORMATTERS_V1 = Symbol.for("pi.orchestrator-idle-handoff.formatters.v1");

type ContextUsage = { tokens?: number | null; contextWindow?: number | null; percent?: number | null };
export type IdleHandoff = Readonly<{ child: string; parent: string; message: string; session: string | undefined; observedAt: string; usage: ContextUsage | undefined }>;
export type IdleHandoffFormatter = (handoff: IdleHandoff) => string;
type FormatterRegistry = Readonly<{ version: 1; register(formatter: IdleHandoffFormatter): () => void; format(handoff: IdleHandoff): string }>;

/** Versioned managed API. Formatters are ordered, pure message transforms only. */
function installFormatterRegistry(): FormatterRegistry {
  const root = globalThis as typeof globalThis & { [ORCHESTRATOR_IDLE_HANDOFF_FORMATTERS_V1]?: FormatterRegistry };
  const existing = root[ORCHESTRATOR_IDLE_HANDOFF_FORMATTERS_V1];
  if (existing) return existing;
  const formatters: IdleHandoffFormatter[] = [];
  const registry: FormatterRegistry = Object.freeze({ version: 1, register(formatter) {
    if (typeof formatter !== "function") throw new Error("idle-handoff formatter must be a function");
    formatters.push(formatter);
    let active = true;
    return () => { if (!active) return; active = false; const index = formatters.indexOf(formatter); if (index >= 0) formatters.splice(index, 1); };
  }, format(handoff) {
    return formatters.reduce((message, formatter) => {
      try { const next = formatter(Object.freeze({ ...handoff, message })); return typeof next === "string" ? next : message; } catch { return message; }
    }, handoff.message);
  } });
  Object.defineProperty(root, ORCHESTRATOR_IDLE_HANDOFF_FORMATTERS_V1, { value: registry, configurable: false, enumerable: false, writable: false });
  return registry;
}

const formatterRegistry = installFormatterRegistry();
const format = (handoff: IdleHandoff) => formatterRegistry.format(handoff);

function assistantText(messages: unknown[]): string {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index] as { role?: string; content?: Array<{ type?: string; text?: string }> };
    if (message?.role !== "assistant" || !Array.isArray(message.content)) continue;
    return message.content.filter((part) => part.type === "text" && typeof part.text === "string").map((part) => part.text!.trim()).filter(Boolean).join("\n\n");
  }
  return "";
}

export default function orchestratorIdleHandoff(pi: ExtensionAPI) {
  const configuredParent = process.env[PARENT_ENV]?.trim(); if (!configuredParent) return;
  const parent: string = configuredParent;
  let runEnded = false; let finalText = ""; let runNumber = 0; let deliveryTimer: ReturnType<typeof setTimeout> | undefined;
  function scheduleDelivery(ctx: { isIdle(): boolean; hasPendingMessages(): boolean; getContextUsage?(): ContextUsage | undefined; sessionManager?: { getSessionFile(): string | undefined } }) {
    const endedRun = runNumber; if (deliveryTimer) clearTimeout(deliveryTimer);
    deliveryTimer = setTimeout(() => { deliveryTimer = undefined; if (endedRun !== runNumber || !runEnded || !ctx.isIdle() || ctx.hasPendingMessages()) return;
      const text = finalText; runEnded = false; finalText = ""; if (!text) return;
      const child = pi.getSessionName() ?? "Unnamed Pi session";
      const message = format(Object.freeze({ child, parent, message: `${child} is idle.\n\n${text}`, session: ctx.sessionManager?.getSessionFile(), observedAt: new Date().toISOString(), usage: ctx.getContextUsage?.() }));
      pi.events.emit(INTERCOM_EVENT, { to: parent, message });
    }, 1000);
  }
  pi.on("agent_end", (event, ctx) => { runEnded = true; finalText = assistantText(event.messages as unknown[]); runNumber += 1; scheduleDelivery(ctx); });
  pi.on("agent_settled", (_event, ctx) => { if (runEnded) scheduleDelivery(ctx); });
}
