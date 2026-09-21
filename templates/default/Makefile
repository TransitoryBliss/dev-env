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

# SSH in, forwarding plannotator's review UI to http://localhost:19432 on the Mac.
vm/ssh:
	@test "$(NIXADDR)" != "unset" || (echo "set NIXADDR=<vm-ip>" && exit 1)
	ssh -L 19432:localhost:19432 $(NIXUSER)@$(NIXADDR)

# Run inside the machine (VM or WSL), from this repo.
switch:
	sudo nixos-rebuild switch --flake .#$(HOST) $(LOCAL_FLAGS)

# Run inside the machine. Agent add-ons that install through their own tooling; safe to re-run.
agents/setup:
	pi install npm:@plannotator/pi-extension
	pi install npm:pi-claude-code-provider
	rtk init -g --auto-patch
	herdr plugin list | grep -q annotate || herdr plugin install plannotator/herdr-annotate
	herdr config check
	-herdr server reload-config

check:
	nix flake check
