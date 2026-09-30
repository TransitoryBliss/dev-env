# devproxy: names for the web UIs running in this machine, behind one guarded Caddy.
#
#   http://<machine>.localhost:<port>             index of everything below
#   http://<name>.<machine>.localhost:<port>      one service
#
# Caddy (a systemd user service) is the only way in: it answers only the names it
# knows, rejects requests whose Origin is another site, sets its own X-Forwarded-For
# and strips CORS headers. Backends listen on loopback only.
#
# `devproxy watch` finds services by itself: loopback listeners owned by this user,
# run from a directory under a scope root (~/source, the worktree root), plus
# plannotator's review pages (a pi or plannotator listener whose page is titled
# Plannotator). Names come from where the process runs: the repo for a main
# checkout, the branch for a worktree; the repo is added only when a name is taken,
# and names are remembered (while their directory exists) so they survive restarts.
# It pushes the whole Caddy config through the admin API on a Unix socket.
#
#   devproxy config <file>   Caddy's starting config (fixed services only)
#   devproxy watch           discover services and keep Caddy's routes current
#   devproxy ls              what is routed right now

import html
import http.client
import json
import os
import re
import socket
import subprocess
import sys
import time

CONFIG = json.load(open(os.environ.get("DEVPROXY_CONFIG") or globals()["DEFAULT_CONFIG"]))
MACHINE = CONFIG["machine"]
PORT = CONFIG["port"]
SERVICES = CONFIG["services"]
SUFFIX = MACHINE + ".localhost"
UID = os.getuid()
HOME = os.path.expanduser("~")
RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{UID}", "devproxy")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local/state"), "devproxy")
ADMIN = os.path.join(RUN, "admin.sock")
ROUTES = os.path.join(RUN, "routes.json")
NAMES = os.path.join(STATE, "names.json")
EXCLUDE = set(CONFIG.get("excludePorts", [])) | set(SERVICES.values()) | {PORT}
SCOPES = [os.path.realpath(r) for r in CONFIG["scopeRoots"]]
DENY = {"caddy", "herdr", "ssh", "sshd", "claude", "devproxy"}  # never routed
PLAN_PROGS = {"pi", "plannotator"}  # their listeners are routed only if they're plannotator
PROBE_FOR = 15  # seconds to keep probing a listener that doesn't answer yet
KIND_ORDER = {"fixed": 0, "app": 1, "plan": 2}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def host(name=""):
    return f"{name}.{SUFFIX}" if name else SUFFIX


def url(name=""):
    return f"http://{host(name)}:{PORT}"


def tilde(p):
    return "~" + p[len(HOME):] if p == HOME or p.startswith(HOME + "/") else p


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, path)


# ---- Caddy config ----

def origin_pattern(h):
    # Same host, any port: the Mac side may reach this Caddy through another port.
    return "^https?://" + h.replace(".", r"\.") + r"(:[0-9]+)?$"


def proxy_route(h, upstream):
    return {"match": [{"host": [h]}], "terminal": True, "handle": [{"handler": "subroute", "routes": [
        {"match": [{"header": {"Origin": ["*"]},
                    "not": [{"header_regexp": {"Origin": {"pattern": origin_pattern(h)}}}]}],
         "handle": [{"handler": "static_response", "status_code": 403, "body": "Forbidden origin\n"}],
         "terminal": True},
        {"handle": [{"handler": "reverse_proxy", "upstreams": [{"dial": upstream}],
                     "headers": {"response": {"delete": ["Access-Control-Allow-Origin"]}}}]},
    ]}]}


def static(h, status, body="", headers=None):
    handler = {"handler": "static_response", "status_code": status, "body": body}
    if headers:
        handler["headers"] = headers
    route = {"handle": [handler], "terminal": True}
    if h:
        route["match"] = [{"host": [h]}]
    return route


def text(s):
    # Caddy expands {placeholders} in static bodies; keep braces from names and paths literal.
    return html.escape(str(s)).replace("{", "&#123;").replace("}", "&#125;")


def index_html(entries):
    rows = "".join(
        f"<tr><td><a href='{text(url(e['name']))}'>{text(e['name'])}</a></td>"
        f"<td>{text(e['kind'])}</td><td>{text(e.get('prog', ''))}</td>"
        f"<td>{text(e.get('where', ''))}</td><td>{e['port']}</td></tr>"
        for e in sorted(entries, key=lambda e: (KIND_ORDER[e["kind"]], e["name"])))
    return (f"<!doctype html><meta charset=utf-8><title>{text(MACHINE)}</title>"
            f"<body style='font-family: sans-serif'><h1>{text(MACHINE)}</h1>"
            "<table cellpadding=4><tr><th align=left>name</th><th align=left>kind</th>"
            "<th align=left>program</th><th align=left>where</th><th align=left>port</th></tr>"
            f"{rows}</table></body>")


def caddy_config(entries):
    routes = [proxy_route(host(e["name"]), e["upstream"]) for e in entries]
    routes.append(static(SUFFIX, 200, index_html(entries), {"Content-Type": ["text/html; charset=utf-8"]}))
    # Old names (psm.localhost) and the bare localhost lead to the new ones.
    for h, to in [(f"{n}.localhost", url(n)) for n in SERVICES] + [("localhost", url())]:
        routes.append(static(h, 308, headers={"Location": [to + "{http.request.uri}"]}))
    routes.append(static(None, 404, f"Unknown name. Everything on {MACHINE}: {url()}\n"))
    return {
        "admin": {"listen": "unix/" + ADMIN, "config": {"persist": False}},
        "apps": {"http": {"servers": {"devproxy": {
            "listen": [f"127.0.0.1:{PORT}", f"[::1]:{PORT}"],
            "automatic_https": {"disable": True},
            "routes": routes,
        }}}},
    }


def fixed_entries():
    return [{"name": n, "upstream": f"127.0.0.1:{p}", "kind": "fixed", "port": p, "prog": "", "where": ""}
            for n, p in SERVICES.items()]


class UnixConnection(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost", timeout=10)
        self.unix_path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(10)
        self.sock.connect(self.unix_path)


def push(cfg):
    conn = UnixConnection(ADMIN)
    try:
        conn.request("POST", "/load", body=json.dumps(cfg), headers={"Content-Type": "application/json"})
        r = conn.getresponse()
        body = r.read().decode(errors="replace")
        if r.status != 200:
            log(f"devproxy: Caddy refused the config ({r.status}): {body[:500]}")
            return False
        return True
    except OSError as e:
        log(f"devproxy: can't reach Caddy at {ADMIN}: {e}")
        return False
    finally:
        conn.close()


# ---- discovery ----

LOOPBACK = {"0100007F": "127.0.0.1", "00000000000000000000000001000000": "::1",
            "0000000000000000FFFF00000100007F": "127.0.0.1"}


def listeners():
    """inode -> (host, port) for TCP sockets of this user listening on loopback."""
    found = {}
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                lines = f.read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            f = line.split()
            if len(f) < 10 or f[3] != "0A" or int(f[7]) != UID:
                continue
            addr, port = f[1].split(":")
            if addr in LOOPBACK:  # 0.0.0.0 and LAN addresses are never routed
                found[int(f[9])] = (LOOPBACK[addr], int(port, 16))
    return found


def owners(inodes):
    want = {f"socket:[{i}]": i for i in inodes}
    found = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            if os.stat(f"/proc/{pid}").st_uid != UID:
                continue
            fds = os.listdir(f"/proc/{pid}/fd")
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target in want:
                found.setdefault(want[target], int(pid))
    return found


def proc_info(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            comm = f.read().strip()
        return comm, os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return None


def in_scope(cwd):
    rc = os.path.realpath(cwd)
    return any(rc == r or rc.startswith(r + "/") for r in SCOPES)


def probe(h, port):
    """True if the page at / is plannotator's, False if not, None if it doesn't answer yet."""
    try:
        with socket.create_connection((h, port), timeout=1) as s:
            s.sendall(f"GET / HTTP/1.0\r\nHost: localhost:{port}\r\n\r\n".encode())
            data = b""
            while len(data) < 65536 and b"</title>" not in data:
                chunk = s.recv(8192)
                if not chunk:
                    break
                data += chunk
    except OSError:
        return None
    return b"<title>Plannotator" in data


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def place(cwd):
    """Where a process runs: the directory its name belongs to, a base name, and its repo."""
    top = git(cwd, "rev-parse", "--show-toplevel")
    if not top:
        return {"dir": cwd, "base": "home" if cwd == HOME else os.path.basename(cwd) or "root", "repo": None}
    common = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    main = os.path.dirname(common) if common else top
    repo = os.path.basename(main)
    if os.path.realpath(top) != os.path.realpath(main):
        return {"dir": top, "base": git(cwd, "branch", "--show-current") or os.path.basename(top), "repo": repo}
    return {"dir": top, "base": repo, "repo": None}


def label(s):
    s = re.sub(r"[^a-z0-9-]+", "-", s.lower()).strip("-")
    return re.sub(r"-{2,}", "-", s)[:40].strip("-") or "app"


def assign(reg, items):
    """Give each item a name, reusing remembered ones. Returns True if reg changed."""
    changed = False
    for k in [k for k, v in reg.items() if not os.path.isdir(v["dir"])]:
        del reg[k]
        changed = True
    taken = {v["name"] for v in reg.values()} | set(SERVICES)
    for it in sorted(items, key=lambda i: (i["dir"], i["kind"], i["prog"], i["ord"])):
        key = json.dumps([it["dir"], it["kind"], it["prog"], it["ord"]])
        if key not in reg:
            base = label(it["base"])
            sibling = any(v["dir"] == it["dir"] and v["kind"] == it["kind"] and v["prog"] != it["prog"]
                          for v in reg.values())
            stem = f"{label(it['prog'])}.{base}" if it["kind"] == "app" and sibling else base
            if it["ord"]:
                stem += f"-{it['ord'] + 1}"
            pre = "plan." if it["kind"] == "plan" else ""
            cands = [pre + stem]
            if it["repo"] and label(it["repo"]) != base:
                cands.append(f"{pre}{stem}.{label(it['repo'])}")
            cands += [f"{pre}{stem}-{n}" for n in range(2, 1000)]
            name = next(c for c in cands if c not in taken)
            reg[key] = {"name": name, "dir": it["dir"], "kind": it["kind"], "prog": it["prog"]}
            taken.add(name)
            changed = True
        it["name"] = reg[key]["name"]
    return changed


def notify(e):
    try:
        subprocess.run(["herdr", "notification", "show", f"Plan ready for review: {e['base']}",
                        "--body", url(e["name"])], capture_output=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        pass


class Watcher:
    def __init__(self):
        self.owner = {}  # inode -> (comm, cwd)
        self.probed = {}  # inode -> (result, first try)
        self.reg = read_json(NAMES, {})
        self.pushed = None
        self.seen_plans = None  # plan inodes already announced; None until the first push
        self.last = None
        self.checked = 0.0

    def is_plan(self, ino, h, port, now):
        res, first = self.probed.get(ino, (None, now))
        if res is None:
            res = probe(h, port)
            if res is None and now - first >= PROBE_FOR:
                res = False
            self.probed[ino] = (res, first)
        return res is True

    def discover(self, ls, now):
        missing = [i for i in ls if i not in self.owner]
        if missing:
            for ino, pid in owners(missing).items():
                info = proc_info(pid)
                if info:
                    self.owner[ino] = info
        for d in (self.owner, self.probed):
            for i in [i for i in d if i not in ls]:
                del d[i]
        found, ports = [], set()
        for ino, (h, port) in sorted(ls.items(), key=lambda kv: (kv[1][1], kv[1][0])):
            if port < 1024 or port in EXCLUDE or port in ports or ino not in self.owner:
                continue
            comm, cwd = self.owner[ino]
            if comm in DENY or cwd.endswith(" (deleted)"):
                continue
            if comm in PLAN_PROGS:
                if not self.is_plan(ino, h, port, now):
                    continue
                kind = "plan"
            elif in_scope(cwd):
                kind = "app"
            else:
                continue
            ports.add(port)
            found.append({"ino": ino, "port": port, "kind": kind, "prog": comm,
                          "upstream": f"[{h}]:{port}" if ":" in h else f"{h}:{port}", **place(cwd)})
        groups = {}
        for e in found:
            groups.setdefault((e["dir"], e["kind"], e["prog"]), []).append(e)
        for g in groups.values():
            for n, e in enumerate(sorted(g, key=lambda e: e["port"])):
                e["ord"] = n
        if assign(self.reg, found):
            write_json(NAMES, self.reg)
        for e in found:
            e["where"] = tilde(e["dir"]) if e["kind"] == "app" or e["repo"] or e["dir"] != HOME else ""
        return found

    def tick(self):
        now = time.time()
        ls = listeners()
        pending = any(r is None for i, (r, _) in self.probed.items() if i in ls)
        if set(ls) == self.last and not pending and self.pushed and now - self.checked < 30:
            return
        self.last, self.checked = set(ls), now
        found = self.discover(ls, now)
        entries = fixed_entries() + found
        cfg = caddy_config(entries)
        body = json.dumps(cfg, sort_keys=True)
        if body != self.pushed:
            if not push(cfg):
                self.pushed = None
                return
            self.pushed = body
            write_json(ROUTES, [{"name": e["name"], "url": url(e["name"]), "kind": e["kind"],
                                 "port": e["port"], "prog": e["prog"], "where": e["where"]}
                                for e in sorted(entries, key=lambda e: (KIND_ORDER[e["kind"]], e["name"]))])
            log("devproxy: routes: " + ", ".join(sorted(e["name"] for e in entries)))
        plans = {e["ino"]: e for e in found if e["kind"] == "plan"}
        if self.seen_plans is not None:
            for ino in plans.keys() - self.seen_plans:
                notify(plans[ino])
        self.seen_plans = set(plans)

    def run(self):
        while True:
            try:
                self.tick()
            except Exception as e:  # keep watching; a bad tick shouldn't drop every route
                log(f"devproxy: {e!r}")
                self.pushed = None
            time.sleep(1)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "ls"
    if cmd == "config" and len(argv) == 3:
        write_json(argv[2], caddy_config(fixed_entries()))
    elif cmd == "watch":
        Watcher().run()
    elif cmd == "ls":
        routes = read_json(ROUTES, None)
        if routes is None:
            print("devproxy isn't running (systemctl --user status devproxy)", file=sys.stderr)
            return 1
        w = max(len(r["url"]) for r in routes)
        print(f"{'URL':<{w}}  KIND   PROGRAM     WHERE")
        for r in routes:
            print(f"{r['url']:<{w}}  {r['kind']:<5}  {r['prog'] or '-':<10}  {r['where']}")
        print(f"\nindex: {url()}")
    else:
        print("usage: devproxy [ls | watch | config <file>]", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
