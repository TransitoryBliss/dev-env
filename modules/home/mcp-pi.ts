/**
 * devEnv.mcp in pi (see mcp.nix). Linked into ~/.pi/agent/extensions by mcp.nix.
 *
 * pi's built-in MCP support reads ~/.pi/agent/mcp.json and the cwd's .pi/mcp.json, nothing
 * per org. This registers the servers from the generated file that apply to the session's
 * directory: the global ones, plus a scope's when the cwd is under <host/owner> in one of
 * the scope roots (without the global ones if the scope says inheritGlobal = false).
 *
 * Registrations aren't saved, so they're made on every load: for the process's cwd while
 * the extension loads (they connect with the session), and again for the session's cwd on
 * session_start, which differs when a session is resumed from elsewhere.
 */

import { readFileSync, realpathSync } from "node:fs";
import { relative, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SERVERS_FILE = "@serversFile@";

type ServerConfig = Record<string, unknown>;

interface Config {
	roots: string[];
	servers: Record<string, ServerConfig>;
	scopes: Record<string, { inheritGlobal: boolean; servers: Record<string, ServerConfig> }>;
}

function realpath(path: string): string {
	try {
		return realpathSync(path);
	} catch {
		return resolve(path);
	}
}

/** The scope ("host/owner") the directory is in, if any. */
function scopeOf(config: Config, cwd: string): string | undefined {
	const dir = realpath(cwd);
	for (const root of config.roots) {
		const rel = relative(realpath(root), dir);
		if (!rel || rel.startsWith("..") || rel.startsWith(sep)) continue;
		const parts = rel.split(sep);
		if (parts.length < 2) continue;
		const owner = `${parts[0]}/${parts[1]}`;
		if (config.scopes[owner]) return owner;
	}
	return undefined;
}

function serversFor(config: Config, cwd: string): Record<string, ServerConfig> {
	const scope = config.scopes[scopeOf(config, cwd) ?? ""];
	if (!scope) return config.servers;
	return { ...(scope.inheritGlobal ? config.servers : {}), ...scope.servers };
}

export default function (pi: ExtensionAPI) {
	let config: Config | undefined;
	let loadError: string | undefined;
	try {
		config = JSON.parse(readFileSync(SERVERS_FILE, "utf8")) as Config;
	} catch (error) {
		loadError = `devEnv.mcp: can't read ${SERVERS_FILE}: ${error instanceof Error ? error.message : String(error)}`;
	}

	// What this extension registered, by name, as JSON, so unchanged servers aren't reconnected.
	const registered = new Map<string, string>();
	const errors: string[] = [];

	const apply = (cwd: string) => {
		if (!config) return;
		const wanted = serversFor(config, cwd);
		for (const name of [...registered.keys()]) {
			if (wanted[name]) continue;
			pi.unregisterMcpServer(name);
			registered.delete(name);
		}
		for (const [name, server] of Object.entries(wanted)) {
			const json = JSON.stringify(server);
			if (registered.get(name) === json) continue;
			try {
				pi.registerMcpServer(name, server as Parameters<ExtensionAPI["registerMcpServer"]>[1]);
				registered.set(name, json);
			} catch (error) {
				errors.push(`devEnv.mcp: server "${name}": ${error instanceof Error ? error.message : String(error)}`);
			}
		}
	};

	apply(process.cwd());

	pi.on("session_start", (_event, ctx) => {
		apply(ctx.cwd);
		for (const message of [loadError, ...errors.splice(0)]) {
			if (message) ctx.ui.notify(message, "error");
		}
		loadError = undefined;
	});
}
