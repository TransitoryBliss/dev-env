"""dev-env-updates: list what in dev-env has a newer release. Changes nothing.

Usage: dev-env-updates <info.json>  (agents.nix bakes the JSON and wraps this)

Checks
  - pi packages (`pi list`): npm ones against npm's latest, git ones against
    the repo's default branch (and npm's latest, to see when a release ships)
  - herdr plugins (`herdr plugin list`): tags against the latest release,
    commits against the default branch
  - what the Nix config pins (plannotator, pi-session-manager, herdr, rtk's pi
    hook) against GitHub releases, and pi and Claude Code against npm
  - the \u0040playwright/cli override, which must match Nix's Chromium
  - the base's GitHub flake inputs against their branch: OLD when newer
    commits exist and the locked one is over STALE_DAYS old (nixpkgs always
    has newer commits, so age alone decides)

GitHub is read through `gh api` when gh is logged in, else anonymously (60
requests an hour).
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request

STALE_DAYS = 14


def get_json(url):
    headers = {"User-Agent": "dev-env-updates"}
    if url.startswith("https://api.github.com/"):
        headers["Accept"] = "application/vnd.github+json"  # npm answers this with 406
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def gh(path):
    if shutil.which("gh"):
        out = subprocess.run(["gh", "api", path], capture_output=True, text=True)
        if out.returncode == 0:
            return json.loads(out.stdout)
    return get_json("https://api.github.com/" + path)


def safe(fn, *args):
    try:
        return fn(*args)
    except Exception:
        return None


def latest_release(repo):
    return safe(lambda: gh(f"repos/{repo}/releases/latest")["tag_name"])


def head(repo):
    return safe(lambda: gh(f"repos/{repo}/commits/HEAD")["sha"])


def behind(repo, sha, ref="HEAD"):
    return safe(lambda: gh(f"repos/{repo}/compare/{sha}...{ref}")["ahead_by"])


def npm_latest(name):
    return safe(lambda: get_json("https://registry.npmjs.org/" + name.replace("/", "%2F") + "/latest")["version"])


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    except Exception:
        return ""


rows = []


def add(group, name, current, latest, note=""):
    norm = lambda v: (v or "").lstrip("v")
    if latest is None:
        status = "?"
    elif norm(current) == norm(latest):
        status = "ok"
    else:
        status = "UPDATE"
    rows.append((status, group, name, current or "-", latest or "?", note))


def add_commit(group, name, repo, sha, note=""):
    tip = head(repo)
    if tip is None:
        add(group, name, sha[:7], None, note)
    elif tip.startswith(sha) or sha.startswith(tip):
        add(group, name, sha[:7], sha[:7], note)
    else:
        n = behind(repo, sha)
        extra = f"{n} commits behind" if n is not None else "behind"
        add(group, name, sha[:7], tip[:7], ", ".join(x for x in [extra, note] if x))


def main():
    info = json.load(open(sys.argv[1]))

    # pi packages
    for line in run("pi", "list").splitlines():
        m = re.match(r"^\s+(npm|git):(\S+)$", line)
        if not m:
            continue
        kind, spec = m.groups()
        name, _, ver = spec.rpartition("\u0040") if "\u0040" in spec[1:] else (spec, "", "")
        if kind == "npm":
            add("pi package", name, ver, npm_latest(name))
        else:
            repo = "/".join(name.split("/")[1:3])  # github.com/owner/repo
            rel = npm_latest(repo.split("/")[1])
            add_commit("pi package", f"{repo} (git)", repo, ver, f"npm latest {rel}" if rel else "")

    # herdr plugins
    for m in re.finditer(r"^- (\S+) .*\[github:([^\u0040\]]+)\u0040([^\]]+)\]", run("herdr", "plugin", "list"), re.M):
        name, repo, ref = m.groups()
        if re.fullmatch(r"[0-9a-f]{40}", ref):
            add_commit("herdr plugin", name, repo, ref)
        else:
            add("herdr plugin", name, ref, latest_release(repo))

    # pinned in Nix
    for name, repo, ver, note in [
        ("plannotator", "backnotprop/plannotator", info["plannotator"], "pkgs/plannotator.nix, and its pi extension"),
        ("pi-session-manager", "Dwsy/pi-session-manager", info["piSessionManager"], "check security.patch, Cargo.lock"),
        ("herdr", "herdrdev/herdr", info["herdr"], "flake input"),
        ("rtk pi hook", "rtk-ai/rtk", info["rtkPiHook"], "only hooks/pi/rtk.ts matters"),
    ]:
        add("nix", name, ver, latest_release(repo), note)
    pi_ver = run("pi", "--version").strip().splitlines()[-1:] or [""]
    add("nix", "pi", pi_ver[0], npm_latest("\u0040earendil-works/pi-coding-agent"), "nixpkgs-master")
    claude = re.search(r"[\d.]+", run("claude", "--version"))
    add("nix", "claude-code", claude.group(0) if claude else None, npm_latest("\u0040anthropic-ai/claude-code"), "nixpkgs-unstable")

    # \u0040playwright/cli override (PLAYWRIGHT_CLI)
    try:
        pkg = json.load(open(os.path.expanduser("~/.pi/agent/npm/package.json")))
        pw = pkg.get("overrides", {}).get("\u0040playwright/cli")
    except Exception:
        pw = None
    if pw:
        add("pin", "\u0040playwright/cli", pw, npm_latest("\u0040playwright/cli"), "must match Nix's Chromium, see agents/setup")

    # flake inputs
    now = time.time()
    for name, i in sorted(info["inputs"].items()):
        repo, ref = f"{i['owner']}/{i['repo']}", i["ref"] or "HEAD"
        days = int((now - i["lastModified"]) / 86400)
        locked = f"{i['rev'][:7]} ({days}d)"
        tip = safe(lambda: gh(f"repos/{repo}/commits/{ref}")["sha"])
        if tip is None:
            rows.append(("?", "flake input", name, locked, "?", ref))
        elif tip == i["rev"]:
            rows.append(("ok", "flake input", name, locked, tip[:7], ref))
        else:
            n = behind(repo, i["rev"], ref)
            status = "OLD" if days > STALE_DAYS else "ok"
            rows.append((status, "flake input", name, locked, tip[:7], f"{ref}, {n if n is not None else '?'} commits newer"))

    widths = [max(len(str(r[i])) for r in rows) for i in range(5)]
    for r in sorted(rows, key=lambda r: (r[0] in ("ok",), r[1], r[2])):
        print("  ".join(str(c).ljust(w) for c, w in zip(r, widths + [0])).rstrip())
    n = sum(1 for r in rows if r[0] in ("UPDATE", "OLD"))
    print(f"\n{n} to look at. Bump pins in the base (dev-env), see its AGENTS.md; nothing was changed.")


if __name__ == "__main__":
    main()
