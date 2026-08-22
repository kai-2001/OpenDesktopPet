/* OpenDesktopPet Pi notification extension
 *
 * Pi exposes agent_settled for integrations that need to know the complete
 * run is finished, including retries, compaction, and queued follow-ups. This
 * extension sends only a small local UDP status payload; it never forwards
 * prompts, answers, tool output, or source code.
 */

import { createSocket } from "node:dgram";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RUNTIME_FILE_NAME = "open_desktop_pet_runtime.json";
const RUNTIME_SCHEMA_VERSION = 1;
// Keep the existing runtime key for compatibility; it represents all Pi models.
const RUNTIME_TARGET = "pi_codex_terminal";
const NOTIFY_HOST = "127.0.0.1";
const MAX_PORT = 65535;
const MIN_PORT = 1024;

interface RuntimeRegistration {
	schema_version?: number;
	port?: number;
	enabled_targets?: Record<string, boolean>;
}

function integrationHome(): string {
	return process.env.USERPROFILE || homedir();
}

function readRuntime(): RuntimeRegistration | undefined {
	const runtimePath = join(
		integrationHome(),
		".open-desktop-pet",
		RUNTIME_FILE_NAME,
	);
	if (!existsSync(runtimePath)) return undefined;
	try {
		const parsed = JSON.parse(readFileSync(runtimePath, "utf8")) as RuntimeRegistration;
		const port = Number(parsed.port);
		if (
			parsed.schema_version !== RUNTIME_SCHEMA_VERSION ||
			!parsed.enabled_targets ||
			!Number.isInteger(port) ||
			port < MIN_PORT ||
			port > MAX_PORT ||
			!parsed.enabled_targets[RUNTIME_TARGET]
		) {
			return undefined;
		}
		return parsed;
	} catch {
		return undefined;
	}
}

function sendNotification(
	port: number,
	payload: Record<string, unknown>,
): Promise<void> {
	return new Promise((resolve) => {
		const socket = createSocket("udp4");
		let finished = false;
		const finish = () => {
			if (finished) return;
			finished = true;
			try {
				socket.close();
			} catch {
				// The socket may already be closed after an error.
			}
			resolve();
		};
		socket.once("error", finish);
		try {
			socket.send(
				Buffer.from(JSON.stringify(payload), "utf8"),
				port,
				NOTIFY_HOST,
				finish,
			);
		} catch {
			finish();
		}
	});
}

export default function (pi: ExtensionAPI) {
	let sequence = 0;
	let runFailed = false;

	pi.on("agent_start", async () => {
		runFailed = false;
	});

	pi.on("agent_end", async (event) => {
		runFailed = event.messages.some((message) => {
			if (message.role !== "assistant") return false;
			return (message as { stopReason?: string }).stopReason === "error";
		});
	});

	pi.on("agent_settled", async (_event, ctx) => {
		const runtime = readRuntime();
		const port = Number(runtime?.port);
		if (!runtime || !Number.isInteger(port)) return;

		const sessionId = ctx.sessionManager.getSessionId();
		const model = ctx.model;
		const payload = {
			schema_version: RUNTIME_SCHEMA_VERSION,
			type: runFailed ? "agent-error" : "agent-turn-complete",
			source: "pi",
			agent: "pi",
			target_app: "terminal",
			target_platform: "terminal",
			target_executable: "WindowsTerminal.exe",
			event_id: `pi:${sessionId}:${Date.now()}:${sequence++}`,
			thread_id: "",
			turn_id: "",
			session_id: sessionId,
			cwd: ctx.cwd,
			model_provider: model?.provider ?? "",
			model: model?.id ?? "",
		};
		await sendNotification(port, payload);
		runFailed = false;
	});
}
