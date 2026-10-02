# dev-env.mk: the shared part of every config's Makefile. The canonical copy is
# templates/default/dev-env.mk in the dev-env base; each config commits a copy
# of it next to a short Makefile that sets NIXUSER and VM_HOST and includes it.
# Don't edit the copy: `make base/sync` replaces it with the one from the locked
# dev-env input (`make vm/update INPUT=dev-env` does that from the Mac), and
# `make base/check` fails when they differ. Extras go in Makefile.local.
#
# Run from the Mac unless noted. VM targets copy this repo to ~/dev-env in the
# VM (devEnv.configDir) and build there, so the Mac doesn't need Nix.
#   HOST      nixosConfigurations entry to build (default: see below)
#   NIXADDR   IP of the VM (shown by `ip addr` in the VM console)
#   NIXUSER   devEnv.user.name (set in the Makefile)
#   VM_HOST   HOST when running from the Mac (set in the Makefile)
#   NIXBLOCK  install disk inside the VM (check with `lsblk`): /dev/vda on UTM,
#             /dev/sda on Parallels, /dev/nvme0n1 on VMware Fusion
#   DEV_ENV   optional: local checkout of the dev-env base to build against
#             instead of the flake input (for developing the base itself)

NIXUSER ?= me
VM_HOST ?= vm

# Inside a NixOS machine, HOST defaults to its hostname (each host sets
# networking.hostName to its nixosConfigurations name); from the Mac, to VM_HOST.
# Only a command-line HOST= overrides this, not an inherited environment variable.
ifneq ($(origin HOST),command line)
ifneq ($(wildcard /etc/NIXOS),)
HOST := $(shell hostname)
else
HOST := $(VM_HOST)
endif
endif
NIXADDR ?= unset
NIXBLOCK ?= /dev/vda
DEV_ENV ?=

# The @playwright/cli release whose playwright-core wants exactly the Chromium
# revision in the Nix browsers (devEnv.languages.playwright.enable). See
# `agents/setup` for why it is pinned, and how to find the next one.
PLAYWRIGHT_CLI = 0.1.19

# Pi packages for `agents/setup`, pinned. Pi checks unpinned ones against npm
# at every start and lists any newer release; pinned ones only change here.
# To upgrade, bump a version (`npm view <pkg> version`) and re-run agents/setup.
PI_PACKAGES = \
	@plannotator/pi-extension@0.27.25 \
	pi-claude-code-provider@0.6.0 \
	pi-subagents@0.74.0 \
	@juicesharp/rpiv-ask-user-question@2.12.0 \
	pi-playwright@0.1.2 \
	pi-web-access@0.35.0

# Optional, per-config additions to the variables above, e.g.
#   PI_PACKAGES += some-pi-package@1.2.3
# Your extras go there, not in this file (base/sync would overwrite them).
-include Makefile.local

BASE_DIR = .cache/dev-env-base
ifneq ($(DEV_ENV),)
# From the Mac, DEV_ENV is synced to BASE_DIR in the VM; inside the machine it's used as is.
REMOTE_FLAGS = --override-input dev-env path:/home/$(NIXUSER)/$(BASE_DIR) --no-write-lock-file
LOCAL_FLAGS = --override-input dev-env path:$(abspath $(DEV_ENV)) --no-write-lock-file
endif

SSH_OPTIONS = -o PubkeyAuthentication=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no
# Reuse one connection so the installer's root password is asked for only once.
SSH_SHARED = -o ControlMaster=auto -o ControlPath=/tmp/dev-env-ssh-%C -o ControlPersist=10m
RSYNC_EXCLUDES = --exclude=.git --exclude=result

.PHONY: vm/bootstrap0 vm/bootstrap vm/update vm/copy vm/ssh vm/untunnel mac/router mac/router-remove switch agents/setup base/sync base/check check

# Step 1: from the NixOS installer ISO (after `sudo passwd root`).
# Wipes $(NIXBLOCK), partitions it, and installs the flake. The flake is locked
# first because nixos-install would otherwise write flake.lock mid-evaluation and
# fail with a NAR hash mismatch; the lock is copied back here to be committed.
# The repo is also placed at ~/dev-env, which the nvim and herdr config links point to.
vm/bootstrap0:
	@test "$(NIXADDR)" != "unset" || (echo "set NIXADDR=<vm-ip>" && exit 1)
	rsync -av -e 'ssh $(SSH_OPTIONS) $(SSH_SHARED)' $(RSYNC_EXCLUDES) ./ root@$(NIXADDR):/tmp/dev-env/
	ssh $(SSH_OPTIONS) $(SSH_SHARED) root@$(NIXADDR) \
		"nix --extra-experimental-features 'nix-command flakes' flake lock /tmp/dev-env"
	scp $(SSH_OPTIONS) $(SSH_SHARED) root@$(NIXADDR):/tmp/dev-env/flake.lock ./flake.lock
	ssh $(SSH_OPTIONS) $(SSH_SHARED) root@$(NIXADDR) " \
		set -e; \
		umount -R /mnt 2>/dev/null || true; \
		parted -s $(NIXBLOCK) -- mklabel gpt; \
		parted -s $(NIXBLOCK) -- mkpart root ext4 512MB 100%; \
		parted -s $(NIXBLOCK) -- mkpart ESP fat32 1MB 512MB; \
		parted -s $(NIXBLOCK) -- set 2 esp on; \
		udevadm settle; \
		mkfs.ext4 -F -L nixos /dev/disk/by-partlabel/root; \
		mkfs.fat -F 32 -n boot /dev/disk/by-partlabel/ESP; \
		udevadm settle; \
		mount /dev/disk/by-label/nixos /mnt; \
		mkdir -p /mnt/boot; \
		mount -o umask=077 /dev/disk/by-label/boot /mnt/boot; \
		nixos-install --no-root-passwd --flake /tmp/dev-env#$(HOST) \
			--option experimental-features 'nix-command flakes'; \
		mkdir -p /mnt/home/$(NIXUSER); \
		cp -r /tmp/dev-env /mnt/home/$(NIXUSER)/dev-env; \
		chown -R 1000:100 /mnt/home/$(NIXUSER); \
		reboot; \
	"

# Step 2, and after every change: sync this repo and rebuild.
# The rebuild locks any new flake inputs in the VM; the lock is copied back to commit.
vm/bootstrap: vm/copy
	ssh $(NIXUSER)@$(NIXADDR) "sudo nixos-rebuild switch --flake ~/dev-env#$(HOST) $(REMOTE_FLAGS)"
ifeq ($(DEV_ENV),)
	scp $(NIXUSER)@$(NIXADDR):dev-env/flake.lock ./flake.lock
endif

# Update flake inputs in the VM (the Mac has no Nix), sync dev-env.mk from the
# new dev-env input, copy both back, rebuild.
#   make vm/update NIXADDR=<ip>                all inputs
#   make vm/update NIXADDR=<ip> INPUT=dev-env  just the shared base
vm/update: vm/copy
	ssh $(NIXUSER)@$(NIXADDR) "cd ~/dev-env && nix flake update $(INPUT) && make base/sync"
	scp $(NIXUSER)@$(NIXADDR):dev-env/flake.lock ./flake.lock
	scp $(NIXUSER)@$(NIXADDR):dev-env/dev-env.mk ./dev-env.mk
	ssh $(NIXUSER)@$(NIXADDR) "sudo nixos-rebuild switch --flake ~/dev-env#$(HOST)"

# Sync this repo (and DEV_ENV, if set) into the VM's home directory.
vm/copy:
	@test "$(NIXADDR)" != "unset" || (echo "set NIXADDR=<vm-ip>" && exit 1)
	rsync -av --delete $(RSYNC_EXCLUDES) ./ $(NIXUSER)@$(NIXADDR):~/dev-env/
ifneq ($(DEV_ENV),)
	ssh $(NIXUSER)@$(NIXADDR) "mkdir -p ~/$(BASE_DIR)"
	rsync -av --delete $(RSYNC_EXCLUDES) $(DEV_ENV)/ $(NIXUSER)@$(NIXADDR):~/$(BASE_DIR)/
endif

# SSH in and attach to herdr (or start it), forwarding devEnv.proxy to the Mac.
# herdr-attach (the base's theme.nix) first writes devEnv.theme's palette to the
# Mac's terminal, and resets it on detach; without a theme it's plain herdr.
# Every browser UI in the machine is at http://<name>.<machine>.localhost:$(PROXY_PORT),
# listed at http://<machine>.localhost:$(PROXY_PORT). `make vm/ssh SSH_CMD=` gives a plain shell instead.
# LogLevel=ERROR keeps refused forwards (a stale tab retrying) from flooding
# the terminal. -t because ssh allocates no terminal when given a command.
# PROXY_PORT is devEnv.proxy.port, and MCP_OAUTH_PORT is devEnv.mcp.callbackPort,
# so pi's MCP OAuth callbacks reach the machine from the Mac's browser. A second
# VM running at the same time needs its own values for both: set them in the
# host file and, to match, in Makefile.local.
SSH_CMD ?= herdr-attach
PROXY_PORT ?= 8090
MCP_OAUTH_PORT ?= 19876
# With the Mac router (`make mac/router`, once), vm/ssh doesn't forward a port:
# it starts a background tunnel from ~/.dev-env/tunnels/<MACHINE>.sock to the
# VM's proxy, which outlives the session (`make vm/untunnel` closes it), and the
# router sends http://*.<MACHINE>.localhost:$(PROXY_PORT) there. Every VM can
# then use the same PROXY_PORT at once. MACHINE is the VM's
# devEnv.proxy.machineName, its hostname by default.
MACHINE ?= $(HOST)
ROUTER_DIR ?= $(HOME)/.dev-env
TUNNEL = $(ROUTER_DIR)/tunnels/$(MACHINE)
vm/ssh:
	@test "$(NIXADDR)" != "unset" || (echo "set NIXADDR=<vm-ip>" && exit 1)
	@if test -f "$(ROUTER_DIR)/router/Caddyfile"; then \
		mkdir -p "$(ROUTER_DIR)/tunnels" && chmod 700 "$(ROUTER_DIR)/tunnels"; \
		ssh -S "$(TUNNEL).ctl" -O check $(NIXUSER)@$(NIXADDR) 2>/dev/null || { \
			rm -f "$(TUNNEL).ctl"; \
			ssh -f -N -M -S "$(TUNNEL).ctl" -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes \
				-o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o LogLevel=ERROR \
				-L "$(TUNNEL).sock:localhost:$(PROXY_PORT)" $(NIXUSER)@$(NIXADDR) || exit 1; }; \
		FWD=; \
	else \
		FWD="-L $(PROXY_PORT):localhost:$(PROXY_PORT)"; \
	fi; \
	ssh -t -o LogLevel=ERROR $$FWD -L $(MCP_OAUTH_PORT):127.0.0.1:$(MCP_OAUTH_PORT) \
		$(NIXUSER)@$(NIXADDR) $(SSH_CMD)

vm/untunnel:
	-ssh -S "$(TUNNEL).ctl" -O exit $(NIXUSER)@$(NIXADDR)
	rm -f "$(TUNNEL).sock" "$(TUNNEL).ctl"

# The Mac router: Caddy from Homebrew, run by launchd, on 127.0.0.1 and ::1 only.
# It never listens on the network: a Host check doesn't stop LAN clients. (macOS
# lets users bind port 80 only on 0.0.0.0, which is why this stays on PROXY_PORT.)
# http://localhost:$(PROXY_PORT) lists the machines with a tunnel.
ROUTER_LABEL = dev.dev-env.router
ROUTER_PLIST = $(HOME)/Library/LaunchAgents/$(ROUTER_LABEL).plist
define ROUTER_CADDYFILE
# Written by `make mac/router`; changes here are overwritten.
{
	admin off
	auto_https off
	persist_config off
}

http://:$(PROXY_PORT) {
	bind 127.0.0.1 [::1]

	# <anything>.<machine>.localhost and <machine>.localhost -> that machine's tunnel.
	@machine vars_regexp m {host} ^(?:[a-z0-9.-]+\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?)\.localhost$$
	handle @machine {
		reverse_proxy unix/$(ROUTER_DIR)/tunnels/{re.m.1}.sock
	}

	# Bare localhost: the machines with a tunnel.
	@index host localhost
	handle @index {
		templates {
			between [[ ]]
			root $(ROUTER_DIR)/tunnels
		}
		header Content-Type "text/html; charset=utf-8"
		respond `<!doctype html><meta charset=utf-8><title>dev-env</title><body style='font-family: sans-serif'><h1>Machines</h1><ul>[[range listFiles "/"]][[if hasSuffix ".sock" .]][[$$m := trimSuffix ".sock" .]]<li><a href="http://[[$$m]].localhost:$(PROXY_PORT)">[[$$m]]</a></li>[[end]][[end]]</ul><p>No machine listed? Run <code>make vm/ssh</code> for it.</p></body>`
	}

	handle {
		respond "Unknown name" 404
	}

	handle_errors 502 {
		respond "{host}: its machine isn't connected. Run `make vm/ssh` for it." 502
	}
}
endef
define ROUTER_PLIST_XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>Label</key><string>$(ROUTER_LABEL)</string>
	<key>ProgramArguments</key><array>
		<string>@CADDY@</string><string>run</string>
		<string>--config</string><string>$(ROUTER_DIR)/router/Caddyfile</string>
		<string>--adapter</string><string>caddyfile</string>
	</array>
	<key>EnvironmentVariables</key><dict><key>HOME</key><string>$(HOME)</string></dict>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>StandardErrorPath</key><string>$(ROUTER_DIR)/router/router.log</string>
</dict></plist>
endef
export ROUTER_CADDYFILE ROUTER_PLIST_XML

mac/router:
	@test "$$(uname)" = Darwin || { echo "mac/router runs on the Mac"; exit 1; }
	@command -v caddy >/dev/null || brew install caddy
	@mkdir -p "$(ROUTER_DIR)/router" "$(ROUTER_DIR)/tunnels" && chmod 700 "$(ROUTER_DIR)/tunnels"
	@printf '%s\n' "$$ROUTER_CADDYFILE" > "$(ROUTER_DIR)/router/Caddyfile"
	@caddy validate --config "$(ROUTER_DIR)/router/Caddyfile" --adapter caddyfile >/dev/null 2>&1 || \
		{ caddy validate --config "$(ROUTER_DIR)/router/Caddyfile" --adapter caddyfile; exit 1; }
	@mkdir -p "$$(dirname "$(ROUTER_PLIST)")"
	@printf '%s\n' "$$ROUTER_PLIST_XML" | sed "s|@CADDY@|$$(command -v caddy)|" > "$(ROUTER_PLIST)"
	@# Stop a running router first; on a first install there is none, and that's fine.
	@launchctl bootout gui/$$(id -u)/$(ROUTER_LABEL) 2>/dev/null || true
	@launchctl bootstrap gui/$$(id -u) "$(ROUTER_PLIST)"
	@echo "Router running: http://localhost:$(PROXY_PORT). Reconnect with make vm/ssh."

mac/router-remove:
	-launchctl bootout gui/$$(id -u)/$(ROUTER_LABEL)
	rm -f "$(ROUTER_PLIST)" "$(ROUTER_DIR)/router/Caddyfile"

# Run inside the machine (VM or WSL), from this repo.
switch:
	sudo nixos-rebuild switch --flake .#$(HOST) $(LOCAL_FLAGS)

# Run inside the machine, after logging in to Claude Code (`claude`) once.
# Agent add-ons that install through their own tooling; safe to re-run.
agents/setup:
	@test -d ~/.claude || { echo "Run 'claude' once and log in first, then re-run make agents/setup."; exit 1; }
	for p in $(PI_PACKAGES); do pi install npm:$$p || exit 1; done
	@# pi has MCP built in since 0.99 (devEnv.mcp registers the servers), and an
	@# extension that owns /mcp, like pi-mcp-adapter, turns it off. Remove the
	@# adapter from earlier setups, and the cache files it left behind.
	@if pi list 2>/dev/null | grep -q 'npm:pi-mcp-adapter'; then pi remove npm:pi-mcp-adapter || exit 1; fi
	rm -f ~/.pi/agent/mcp-cache.json ~/.pi/agent/mcp-onboarding.json
	@# pi-playwright depends on @playwright/cli by a range, and every release of
	@# that pins a playwright-core which accepts exactly one Chromium revision.
	@# The browsers come from Nix, so the CLI is held at the release that matches
	@# them: a newer one asks for a revision the store doesn't have, and
	@# Playwright's own download is a prebuilt binary that won't run here.
	@# To move the pin, compare the revision in
	@#   npm view playwright-core@<version> ...browsers.json
	@# with `ls $$PLAYWRIGHT_BROWSERS_PATH` after a nixpkgs bump.
	@#
	@# The override also fixes the skill's wrapper: it looks for playwright-cli
	@# under its *own* package root, which npm's hoisting never creates, but
	@# which the nesting for an overridden dependency does.
	@python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.setdefault("overrides",{})["@playwright/cli"]=sys.argv[2]; json.dump(d,open(p,"w"),indent=2)' \
		~/.pi/agent/npm/package.json $(PLAYWRIGHT_CLI)
	cd ~/.pi/agent/npm && npm install
	@# Warn rather than fail: PLAYWRIGHT_BROWSERS_PATH is only in the environment
	@# after a `make switch` and a fresh login.
	@rev=$$(node -p 'require("$(HOME)/.pi/agent/npm/node_modules/pi-playwright/node_modules/playwright-core/browsers.json").browsers.find(b => b.name === "chromium").revision' 2>/dev/null); \
		test -z "$$PLAYWRIGHT_BROWSERS_PATH" || test -d "$$PLAYWRIGHT_BROWSERS_PATH/chromium-$$rev" \
		|| echo "warning: @playwright/cli $(PLAYWRIGHT_CLI) wants chromium-$$rev, which is not in $$PLAYWRIGHT_BROWSERS_PATH; move the PLAYWRIGHT_CLI pin"
	rtk init -g --auto-patch
	@# herdr plugin commands talk to the herdr server; start one in the background if needed.
	@herdr plugin list >/dev/null 2>&1 || { \
		echo "Starting herdr server"; nohup herdr server >/dev/null 2>&1 & \
		for i in 1 2 3 4 5 6 7 8 9 10; do sleep 1; herdr plugin list >/dev/null 2>&1 && break; done; }
	herdr plugin list | grep -q annotate || herdr plugin install plannotator/herdr-annotate
	@# Oh My Zsh plugin: links itself into $$ZSH_CUSTOM/plugins/herdr, which the
	@# home-manager module points at a writable directory. `plugin install` runs
	@# that link step in a temporary checkout and herdr then moves the plugin, so
	@# the link it leaves behind dangles; the install action relinks it in place.
	@# --yes because `plugin install` refuses to prompt when stdin is not a terminal.
	herdr plugin list | grep -q ohmyzsh || herdr plugin install robbyrussell/herdr-ohmyzsh --yes
	-herdr plugin action invoke install --plugin ohmyzsh.shell >/dev/null
	@link="$${ZSH_CUSTOM:-$$HOME/.local/share/oh-my-zsh-custom}/plugins/herdr"; \
		for i in 1 2 3 4 5; do test -d "$$link/" && break; sleep 1; done; \
		test -d "$$link/" || echo "warning: $$link does not resolve; run 'herdr plugin action invoke install --plugin ohmyzsh.shell'"
	herdr config check
	-herdr server reload-config

# Run inside the machine. The dev-env base this config builds against: DEV_ENV
# if set, otherwise the locked dev-env input (fetched if needed).
BASE_SRC = if test -n "$(DEV_ENV)"; then src="$(DEV_ENV)"; else \
		json=$$(nix flake archive --json --dry-run --no-write-lock-file) || exit 1; \
		src=$$(printf '%s' "$$json" | jq -r '.inputs["dev-env"].path // empty'); \
		test -n "$$src" || { echo "no dev-env input in flake.lock"; exit 1; }; \
	fi; \
	src="$$src/templates/default/dev-env.mk"; \
	test -f "$$src" || { echo "$$src not found (a dev-env from before dev-env.mk? run nix flake update dev-env)"; exit 1; }

# Copy dev-env.mk from the base. Commit the result with flake.lock.
base/sync:
	@command -v nix >/dev/null || { echo "base/sync runs inside the machine (use make vm/update INPUT=dev-env from the Mac)"; exit 1; }
	@$(BASE_SRC); \
	if cmp -s "$$src" dev-env.mk; then echo "dev-env.mk is up to date"; \
	else cp "$$src" dev-env.mk && chmod 644 dev-env.mk && echo "dev-env.mk updated from $$src"; fi

# Fail when dev-env.mk isn't the base's copy.
base/check:
	@$(BASE_SRC); \
	cmp -s "$$src" dev-env.mk || { echo "dev-env.mk differs from $$src: run make base/sync"; exit 1; }

check: base/check
	nix flake check
