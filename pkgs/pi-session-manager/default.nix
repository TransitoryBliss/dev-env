# Pi Session Manager's headless server (pi-session-cli), with its web UI
# embedded, plus the psm-bridge pi extension. Built from source: upstream
# publishes no linux-arm64 binary, and the desktop app (Tauri) isn't needed.
#
# Upstream commits no Cargo.lock, so ours is next to this file. It was made with
# CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback so every crate builds with
# nixpkgs' rustc. security.patch fixes an auth bypass and cross-origin access
# (see the README); drop it once upstream has a fix.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchPnpmDeps,
  nodejs,
  pnpm_11,
  pnpmConfigHook,
  pkg-config,
  openssl,
  fontconfig,
  freetype,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "pi-session-manager";
  version = "0.8.6";

  src = fetchFromGitHub {
    owner = "Dwsy";
    repo = "pi-session-manager";
    tag = "v${finalAttrs.version}";
    hash = "sha256-YwW/l7aO1MD2P+tNPUacZrU1HGcxpsLhky72UORauag=";
  };

  patches = [ ./security.patch ];

  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
  '';

  cargoLock.lockFile = ./Cargo.lock;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 3;
    hash = "sha256-hlxhpa0b52/dkkM+jdL8dqZqcqbyP79mixjJeNDu77A=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_11
    pnpmConfigHook
    pkg-config
  ];

  buildInputs = [
    openssl
    fontconfig
    freetype
  ];

  # The frontend goes into dist/, which pi-session-cli embeds at compile time.
  preBuild = ''
    pnpm run build
  '';

  cargoBuildFlags = [ "-p" "pi-session-cli" ];
  doCheck = false;

  postInstall = ''
    mkdir -p $out/share/pi-session-manager
    cp -r extensions/pi-session-bridge $out/share/pi-session-manager/pi-session-bridge
  '';

  meta = {
    description = "Browse, search and resume coding-agent sessions (headless server and web UI)";
    homepage = "https://github.com/Dwsy/pi-session-manager";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "pi-session-cli";
  };
})
