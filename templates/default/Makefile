# Run from the Mac unless noted. VM targets copy this repo to ~/dev-env in the
# VM (devEnv.configDir) and build there, so the Mac doesn't need Nix.
#   HOST      nixosConfigurations entry to build (default: see below)
#   NIXADDR   IP of the VM (shown by `ip addr` in the VM console)
#   NIXUSER   devEnv.user.name
#   NIXBLOCK  install disk inside the VM (check with `lsblk`)
#   DEV_ENV   optional: local checkout of the dev-env base to build against
#             instead of the flake input (for developing the base itself)

# Inside a NixOS machine, HOST defaults to its hostname (each host sets
# networking.hostName to its nixosConfigurations name); from the Mac, to the VM.
# Only a command-line HOST= overrides this, not an inherited environment variable.
ifneq ($(origin HOST),command line)
ifneq ($(wildcard /etc/NIXOS),)
HOST := $(shell hostname)
else
HOST := vm
endif
endif
NIXADDR ?= unset
NIXUSER ?= me
NIXBLOCK ?= /dev/sda
DEV_ENV ?=

# The @playwright/cli release whose playwright-core wants exactly the Chromium
# revision in the Nix browsers (devEnv.languages.playwright.enable). See
# `agents/setup` for why it is pinned, and how to find the next one.
PLAYWRIGHT_CLI = 0.1.19

# Pi packages for `agents/setup`, pinned. Pi checks unpinned ones against npm
# at every start and lists any newer release; pinned ones only change here.
# To upgrade, bump a version (`npm view <pkg> version`) and re-run agents/setup.
PI_PACKAGES = \
	@plannotator/pi-extension@0.27.19 \
	pi-claude-code-provider@0.5.0 \
	pi-mcp-adapter@2.37.0 \
	pi-subagents@0.71.0 \
	@juicesharp/rpiv-ask-user-question@2.11.0 \
	pi-playwright@0.1.2 \
	pi-web-access@0.31.0

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

.PHONY: vm/bootstrap0 vm/bootstrap vm/update vm/copy vm/ssh switch agents/setup check

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

# Update flake inputs in the VM (the Mac has no Nix), copy the lock back, rebuild.
#   make vm/update NIXADDR=<ip>                all inputs
#   make vm/update NIXADDR=<ip> INPUT=dev-env  just the shared base
vm/update: vm/copy
	ssh $(NIXUSER)@$(NIXADDR) "cd ~/dev-env && nix flake update $(INPUT)"
	scp $(NIXUSER)@$(NIXADDR):dev-env/flake.lock ./flake.lock
	ssh $(NIXUSER)@$(NIXADDR) "sudo nixos-rebuild switch --flake ~/dev-env#$(HOST)"

# Sync this repo (and DEV_ENV, if set) into the VM's home directory.
vm/copy:
	@test "$(NIXADDR)" != "unset" || (echo "set NIXADDR=<vm-ip>" && exit 1)
	rsync -av --delete $(RSYNC_EXCLUDES) ./ $(NIXUSER)@$(NIXADDR):~/dev-env/
ifneq ($(DEV_ENV),)
	ssh $(NIXUSER)@$(NIXADDR) "mkdir -p ~/$(BASE_DIR)"
	rsync -av --delete $(RSYNC_EXCLUDES) $(DEV_ENV)/ $(NIXUSER)@$(NIXADDR):~/$(BASE_DIR)/
endif

# SSH in, forwarding browser UIs to the Mac: plannotator (http://localhost:19432),
# markdown previews from `md` (http://localhost:6419) and devEnv.proxy
# (http://<name>.localhost:8090, e.g. http://psm.localhost:8090).
vm/ssh:
	@test "$(NIXADDR)" != "unset" || (echo "set NIXADDR=<vm-ip>" && exit 1)
	ssh -o LogLevel=ERROR -L 19432:localhost:19432 -L 6419:localhost:6419 -L 8090:localhost:8090 $(NIXUSER)@$(NIXADDR)

# Run inside the machine (VM or WSL), from this repo.
switch:
	sudo nixos-rebuild switch --flake .#$(HOST) $(LOCAL_FLAGS)

# Run inside the machine, after logging in to Claude Code (`claude`) once.
# Agent add-ons that install through their own tooling; safe to re-run.
agents/setup:
	@test -d ~/.claude || { echo "Run 'claude' once and log in first, then re-run make agents/setup."; exit 1; }
	for p in $(PI_PACKAGES); do pi install npm:$$p || exit 1; done
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

check:
	nix flake check
