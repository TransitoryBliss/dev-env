/**
 * `wt` inside pi (see wt.zsh). Linked into ~/.pi/agent/extensions by git.nix.
 *
 *   /wt done [-f]              finish the worktree this session runs in: check it, ask,
 *                              remove it and its branch, then end the session (its
 *                              directory is gone, and the workspace closes).
 *   /wt ls                     every worktree and its state
 *   /wt [-b] [--plan] <branch> [prompt]
 *                              start a task in a new worktree (--plan: in plan mode)
 *   /wt task [-b] [--plan | --from-plan <file>] [--hold <repo>]... <name> <repo>... [-- <prompt>]
 *                              a task across repos of one org (see wt.zsh)
 *   /wt status, /wt task status | ls | start <repo>...
 *                              the task's agents, PRs and what each waits for; every
 *                              task; start held repos' agents
 *
 * The pi session that creates a task owns it (task.json records its session id, passed
 * to wt as WT_OWNER_SESSION) and moves into the task's workspace. In the owner, or the
 * task folder, /wt done finishes the whole task.
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
	has_plan: boolean;
}

interface TaskCheck {
	task: string;
	dir: string;
	safe: boolean;
	closes_this: boolean;
	has_plan: boolean;
	repos: { name: string; dir: string; state: string; safe: boolean }[];
}

const home = process.env.HOME ?? "";
const tilde = (p: string) => (home && p.startsWith(home) ? `~${p.slice(home.length)}` : p);
const firstLine = (s: string) => s.trim().split("\n").pop() ?? "";

export default function (pi: ExtensionAPI) {
	// Every wt call says which pi session runs it: a task records its owner session, and
	// /wt status and /wt done in the owner find their task by it (its cwd is the org folder).
	type Ctx = { cwd: string; sessionManager: { getSessionId(): string } };
	const owner = (ctx: Ctx) => `WT_OWNER_SESSION=${ctx.sessionManager.getSessionId()}`;
	const wt = (args: string[], ctx: Ctx, timeout = 120_000, extraEnv: string[] = [], signal?: AbortSignal) =>
		pi.exec("env", [owner(ctx), ...extraEnv, "wt", ...args], { cwd: ctx.cwd, timeout, signal });

	async function done(force: boolean, ctx: ExtensionCommandContext) {
		const check = await wt(["done", "--check"], ctx);
		if (check.code !== 0) {
			ctx.ui.notify(firstLine(check.stderr) || "wt done --check failed", "error");
			return;
		}
		const parsed = JSON.parse(check.stdout) as DoneCheck | TaskCheck;
		if ("repos" in parsed) return doneTask(force, parsed, ctx);
		const s = parsed;
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
		const plan = s.has_plan ? " The plan in .wt/ is saved to ~/.local/state/wt/plans/ first." : "";
		const ok = await ctx.ui.confirm(
			force ? "Throw this task away?" : "Finish this task?",
			`Remove ${tilde(s.dir)} and ${what}.${closes}${plan} The session ends and stays in /resume.${lost}`,
		);
		if (!ok) return;

		// The removal closes this workspace; delay it so pi can exit cleanly first.
		const r = await wt(["done", ...(force ? ["-f"] : [])], ctx, 120_000, ["WT_DONE_DELAY=2"]);
		if (r.code !== 0) {
			ctx.ui.notify(firstLine(r.stderr) || "wt done failed", "error");
			return;
		}
		ctx.ui.notify(`Removing ${tilde(s.dir)}; ending the session`, "info");
		ctx.shutdown(); // this session's directory is gone either way
	}

	// /wt done in a task's owner session (or its folder): every repo, then the task.
	async function doneTask(force: boolean, s: TaskCheck, ctx: ExtensionCommandContext) {
		const unsafe = s.repos.filter((r) => !r.safe);
		if (!force && unsafe.length) {
			const list = unsafe.map((r) => `${r.name} (${r.state})`).join(", ");
			ctx.ui.notify(`Not removing task ${s.task}: work would be lost in ${list}. /wt done -f throws it away.`, "warning");
			return;
		}
		if (!ctx.hasUI) {
			ctx.ui.notify("/wt done needs a UI to confirm", "error");
			return;
		}
		const gone = s.repos.filter((r) => r.state !== "removed").map((r) => `${r.name}: ${tilde(r.dir)}`);
		const lost = force && unsafe.length
			? `\n\nThis THROWS AWAY work in ${unsafe.map((r) => `${r.name} (${r.state})`).join(", ")}.`
			: "";
		const plan = s.has_plan ? " The plan is saved to ~/.local/state/wt/plans/ first." : "";
		const closes = s.closes_this ? " This closes the task's herdr workspace." : "";
		const ok = await ctx.ui.confirm(
			force ? `Throw task ${s.task} away?` : `Finish task ${s.task}?`,
			`Remove these worktrees and their branch ${s.task}:\n${gone.join("\n") || "(none left)"}\n\n` +
				`and the task folder.${plan}${closes} The session ends and stays in /resume.${lost}`,
		);
		if (!ok) return;
		const r = await wt(["task", "done", ...(force ? ["-f"] : []), s.task], ctx, 180_000, ["WT_DONE_DELAY=2"]);
		if (r.code !== 0) {
			ctx.ui.notify(firstLine(r.stderr) || "wt task done failed", "error");
			return;
		}
		ctx.ui.notify(`Removing task ${s.task}; ending the session`, "info");
		ctx.shutdown();
	}

	// /wt task ...: split off "-- <prompt>" so the prompt stays one argument.
	async function task(rest: string, ctx: ExtensionCommandContext) {
		const words0 = rest.trim().split(/\s+/).filter(Boolean);
		if (words0[0] === "done") {
			await done(words0.includes("-f"), ctx);
			return;
		}
		const i = rest.search(/(^|\s)--(\s|$)/);
		const head = i < 0 ? rest : rest.slice(0, i);
		const prompt = i < 0 ? "" : rest.slice(i).replace(/^\s*--\s*/, "").trim();
		const words = head.trim().split(/\s+/).filter(Boolean);
		const args = ["task", ...words, ...(prompt ? ["--", prompt] : [])];
		const r = await wt(args, ctx, 180_000);
		const out = (r.code === 0 ? r.stdout : r.stderr || r.stdout).trim();
		if (words[0] === "status" || words[0] === "ls" || r.code !== 0) {
			ctx.ui.notify(out || `wt task exited ${r.code}`, r.code === 0 ? "info" : "error");
		} else if (out) ctx.ui.notify(out, "info");
	}

	pi.registerCommand("wt", {
		description: "Worktrees: /wt done [-f], /wt ls, /wt [-b] [--plan] <branch> [prompt], /wt task ...",
		getArgumentCompletions: (prefix) =>
			[
				{ value: "done", label: "done", description: "finish this worktree's task, if nothing is lost" },
				{ value: "done -f", label: "done -f", description: "throw this task away, unmerged work too" },
				{ value: "ls", label: "ls", description: "every worktree and its state" },
				{ value: "task ", label: "task", description: "a task across repos: task <name> <repo>... -- <prompt>" },
				{ value: "status", label: "status", description: "this task's PRs, checks and merge order" },
				{ value: "task status", label: "task status", description: "this task's PRs, checks and merge order" },
				{ value: "task ls", label: "task ls", description: "every task" },
				{ value: "task start ", label: "task start", description: "start held repos' agents" },
			].filter((i) => i.value.startsWith(prefix.trim())),
		handler: async (args, ctx) => {
			const words = args.trim().split(/\s+/).filter(Boolean);
			if (words[0] === "status") {
				await task(["status", ...words.slice(1)].join(" "), ctx);
				return;
			}
			if (words[0] === "task") {
				await task(args.trim().slice(4), ctx);
				return;
			}
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
				const r = await wt(["ls"], ctx);
				ctx.ui.notify((r.stdout || r.stderr).trim(), r.code === 0 ? "info" : "error");
				return;
			}
			// /wt [-b] [--plan] <branch> [prompt...]: options in any order, then the
			// branch; the prompt is kept as typed.
			let rest = args.trim();
			const opts: string[] = [];
			for (let m; (m = rest.match(/^(-b|--plan)(?:\s+|$)/)); rest = rest.slice(m[0].length)) {
				if (!opts.includes(m[1])) opts.push(m[1]);
			}
			const m = rest.match(/^(\S+)\s*([\s\S]*)$/);
			if (!m || m[1].startsWith("-")) {
				ctx.ui.notify("Usage: /wt [-b] [--plan] <branch> [prompt]", "error");
				return;
			}
			const r = await wt([...opts, m[1], ...(m[2] ? [m[2]] : [])], ctx);
			if (r.code !== 0) ctx.ui.notify(firstLine(r.stderr) || "wt failed", "error");
			else if (r.stdout.trim()) ctx.ui.notify(r.stdout.trim(), "info");
		},
	});

	pi.registerTool({
		name: "wt",
		label: "Worktree",
		description:
			"Start a task in its own git worktree, herdr workspace and pi session (runs in the background, " +
			"off the repo's default branch), or list worktrees and their state. With plan: true the new " +
			"session starts in plannotator's plan mode and writes a plan for the user to review before " +
			"implementing. Action task creates a task across several repos of one org (one branch name, a " +
			"worktree and an agent per repo, one herdr workspace); this session becomes its owner and moves " +
			"into that workspace as the first tab. status shows the task's agents, PRs, checks and merge " +
			"order; start_repos starts the agents of held repos. Cannot remove worktrees.",
		promptSnippet: "wt: start parallel tasks in their own git worktree and pi session, or a task across repos; list worktrees",
		promptGuidelines: [
			"Use wt with action start to hand independent work to parallel agents: one short kebab-case branch per task, and a self-contained prompt (the new agent sees nothing of this conversation).",
			"Set plan: true when the user wants a task planned (and reviewed) before it is implemented; the prompt must then say what to plan.",
			"A plan that changes several repos of one org has an Interfaces section fixing what the repos share (APIs, schemas, events), one section per repo in the order their PRs must merge, and says which repos must wait for another's work before starting.",
			"When such a plan is approved, the first step is wt with action task: branch is a short kebab-case task name (starting with the issue key if there is one), repos lists the repos in merge order, planFile is the approved plan's path, and hold lists repos that must wait. An agent per repo implements its part; don't implement anything yourself.",
			"As a task's owner, follow it with wt action status (each repo's agent, PR, checks, and what it waits for), mark the plan's steps done as the repo agents finish them, and start held repos with action start_repos once what they wait for is done.",
			"Never try to remove or clean up worktrees; the user does that with /wt done, and merged ones are removed automatically.",
		],
		parameters: Type.Object({
			action: StringEnum(["start", "list", "task", "status", "start_repos"] as const),
			branch: Type.Optional(
				Type.String({ description: "New branch name (start), or task name (task; optional for status)" }),
			),
			repos: Type.Optional(
				Type.Array(Type.String(), {
					description: "Repos of the current org, in merge order (task); held repos to start (start_repos)",
				}),
			),
			planFile: Type.Optional(
				Type.String({ description: "Approved plan (markdown) the repo agents implement (task)" }),
			),
			hold: Type.Optional(
				Type.Array(Type.String(), { description: "Repos whose agents wait until started later (task)" }),
			),
			prompt: Type.Optional(Type.String({ description: "Prompt for the new agent (start)" })),
			plan: Type.Optional(
				Type.Boolean({ description: "Start the new agent in plan mode (start; needs a prompt)" }),
			),
		}),
		async execute(_id, params, signal, _onUpdate, ctx) {
			let args: string[];
			if (params.action === "list") args = ["ls"];
			else if (params.action === "status") args = ["task", "status", ...(params.branch ? [params.branch] : [])];
			else if (params.action === "start_repos") {
				if (!params.repos?.length) throw new Error("repos (the held repos to start) is required for start_repos");
				args = ["task", "start", ...(params.branch ? ["--task", params.branch] : []), ...params.repos];
			}
			else if (params.action === "task") {
				if (!params.branch) throw new Error("branch (the task name) is required for task");
				args = [
					"task",
					"-b",
					...(params.plan ? ["--plan"] : []),
					...(params.planFile ? ["--from-plan", params.planFile] : []),
					...(params.hold ?? []).flatMap((r) => ["--hold", r]),
					params.branch,
					...(params.repos ?? []),
					...(params.prompt ? ["--", params.prompt] : []),
				];
			} else {
				if (!params.branch) throw new Error("branch is required for start");
				args = ["-b", ...(params.plan ? ["--plan"] : []), params.branch, ...(params.prompt ? [params.prompt] : [])];
			}
			const r = await wt(args, ctx, 180_000, [], signal);
			if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim() || `wt exited ${r.code}`);
			let text = r.stdout.trim() || "ok";
			if (params.action === "task" && params.planFile) {
				text +=
					"\n\nYou own this task now. The repo agents implement the plan in their own tabs: don't change " +
					"code yourself. When asked how it's going, use action status, and mark the plan's steps done " +
					"as they finish. Start held repos with action start_repos once what they wait for is done. " +
					"The user finishes the task with /wt done here once every PR is merged.";
			}
			return { content: [{ type: "text", text }], details: undefined };
		},
	});
}
