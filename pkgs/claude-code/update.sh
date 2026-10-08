#!/usr/bin/env bash
# Pins Claude Code to a release by writing that release's manifest (version, and
# a binary and checksum per platform) next to this script. modules/home/agents.nix
# hands it to nixpkgs' claude-code package. Without an argument: the newest release.
#
#   pkgs/claude-code/update.sh [version]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

base=https://downloads.claude.ai/claude-code-releases
version="${1:-$(curl -fsSL "$base/latest")}"
curl -fsSL "$base/$version/manifest.zst.json" -o manifest.zst.json
echo "Claude Code $version"
