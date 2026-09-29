/**
 * `wt` inside pi (see wt.zsh). Linked into ~/.pi/agent/extensions by git.nix.
 *
 *   /wt done [-f]              finish the worktree this session runs in: check it, ask,
 *                              remove it and its branch, then end the session (its
 *                              directory is gone, and the workspace closes).
 *   /wt ls                     every worktree and its state
 *   /wt [-b] <branch> [prompt] start a task in a new worktree
 *
 * The agent gets a `wt` tool that can start tasks (always in the background) and list
 * worktrees, but not remove them: finishing or throwing away work stays with the user.
 */

import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

interface DoneCheck {
	dir: string;
	main: string;
	branch: string;
	base: string;
	state: string;
	safe: boolean;
	workspace: string;
	closes_this: boolean;
}

const home = process.env.HOME ?? "";
const tilde = (p: string) => (home && p.startsWith(home) ? `~${p.slice(home.length)}` : p);
const firstLine = (s: string) => s.trim().split("\n").pop() ?? "";

export default function (pi: ExtensionAPI) {
	const wt = (args: string[], cwd: string, timeout = 120_000) => pi.exec("wt", args, { cwd, timeout });

	async function done(force: boolean, ctx: ExtensionCommandContext) {
		const check = await wt(["done", "--check"], ctx.cwd);
		if (check.code !== 0) {
			ctx.ui.notify(firstLine(check.stderr) || "wt done --check failed", "error");
			return;
		}
		const s = JSON.parse(check.stdout) as DoneCheck;
		const what = s.branch ? `branch ${s.branch}` : "detached HEAD";
		if (!force && !s.safe) {
			const why =
				s.state === "dirty"
					? "it has uncommitted changes"
					: `${what} has commits ${s.base} lacks and no merged PR`;
			ctx.ui.notify(`Not removing ${tilde(s.dir)}: ${why}. /wt done -f throws that work away.`, "warning");
			return;
		}
		if (!ctx.hasUI) {
			ctx.ui.notify("/wt done needs a UI to confirm", "error");
			return;
		}
		const lost = force && !s.safe ? `\n\nThis THROWS AWAY work: the worktree is ${s.state}.` : "";
		const closes = s.closes_this ? " This closes this herdr workspace." : "";
		const ok = await ctx.ui.confirm(
			force ? "Throw this task away?" : "Finish this task?",
			`Remove ${tilde(s.dir)} and ${what}.${closes} The session ends and stays in /resume.${lost}`,
		);
		if (!ok) return;

		// The removal closes this workspace; delay it so pi can exit cleanly first.
		const r = await pi.exec("env", ["WT_DONE_DELAY=2", "wt", "done", ...(force ? ["-f"] : [])], {
			cwd: ctx.cwd,
			timeout: 120_000,
		});
		if (r.code !== 0) {
			ctx.ui.notify(firstLine(r.stderr) || "wt done failed", "error");
			return;
		}
		ctx.ui.notify(`Removing ${tilde(s.dir)}; ending the session`, "info");
		ctx.shutdown(); // this session's directory is gone either way
	}

	pi.registerCommand("wt", {
		description: "Worktrees: /wt done [-f], /wt ls, /wt [-b] <branch> [prompt]",
		getArgumentCompletions: (prefix) =>
			[
				{ value: "done", label: "done", description: "finish this worktree's task, if nothing is lost" },
				{ value: "done -f", label: "done -f", description: "throw this task away, unmerged work too" },
				{ value: "ls", label: "ls", description: "every worktree and its state" },
			].filter((i) => i.value.startsWith(prefix.trim())),
		handler: async (args, ctx) => {
			const words = args.trim().split(/\s+/).filter(Boolean);
			if (words[0] === "done") {
				const extra = words.slice(1).filter((w) => w !== "-f");
				if (extra.length) {
					ctx.ui.notify(`/wt done: unknown option ${extra[0]}`, "error");
					return;
				}
				await done(words.includes("-f"), ctx);
				return;
			}
			if (words.length === 0 || words[0] === "ls") {
				const r = await wt(["ls"], ctx.cwd);
				ctx.ui.notify((r.stdout || r.stderr).trim(), r.code === 0 ? "info" : "error");
				return;
			}
			// /wt [-b] <branch> [prompt...]: keep the prompt as typed after the branch.
			const m = args.trim().match(/^(-b\s+)?(\S+)\s*([\s\S]*)$/);
			if (!m) return;
			const r = await wt([...(m[1] ? ["-b"] : []), m[2], ...(m[3] ? [m[3]] : [])], ctx.cwd);
			if (r.code !== 0) ctx.ui.notify(firstLine(r.stderr) || "wt failed", "error");
			else if (r.stdout.trim()) ctx.ui.notify(r.stdout.trim(), "info");
		},
	});

	pi.registerTool({
		name: "wt",
		label: "Worktree",
		description:
			"Start a task in its own git worktree, herdr workspace and pi session (runs in the background, " +
			"off the repo's default branch), or list worktrees and their state. Cannot remove worktrees.",
		promptSnippet: "wt: start parallel tasks in their own git worktree and pi session; list worktrees",
		promptGuidelines: [
			"Use wt with action start to hand independent work to parallel agents: one short kebab-case branch per task, and a self-contained prompt (the new agent sees nothing of this conversation).",
			"Never try to remove or clean up worktrees; the user does that with /wt done, and merged ones are removed automatically.",
		],
		parameters: Type.Object({
			action: StringEnum(["start", "list"] as const),
			branch: Type.Optional(Type.String({ description: "New branch name (start)" })),
			prompt: Type.Optional(Type.String({ description: "Prompt for the new agent (start)" })),
		}),
		async execute(_id, params, signal, _onUpdate, ctx) {
			let args: string[];
			if (params.action === "list") args = ["ls"];
			else {
				if (!params.branch) throw new Error("branch is required for start");
				args = ["-b", params.branch, ...(params.prompt ? [params.prompt] : [])];
			}
			const r = await pi.exec("wt", args, { cwd: ctx.cwd, timeout: 120_000, signal });
			if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim() || `wt exited ${r.code}`);
			return { content: [{ type: "text", text: r.stdout.trim() || "ok" }], details: undefined };
		},
	});
}
