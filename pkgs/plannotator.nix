# Prebuilt release binary. It's a Bun single-file executable, which patchelf
# can corrupt, so it's installed unpatched and runs via nix-ld.
{ lib, stdenvNoCC, fetchurl }:

let
  version = "0.27.16";
  # Per-platform release asset and hash (from the release's .sha256 files).
  assets = {
    aarch64-linux = {
      name = "plannotator-linux-arm64";
      hash = "sha256-DpzN6Z8OyATidNLSIPUFozLvZtMv27UDYfkyFS6FgH4=";
    };
    x86_64-linux = {
      name = "plannotator-linux-x64";
      hash = "sha256-3TMv65r3Qo4GM+1/qnSa2R6JV2tabaquOIDBvK794RY=";
    };
  };
  asset = assets.${stdenvNoCC.hostPlatform.system}
    or (throw "plannotator: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "plannotator";
  inherit version;

  src = fetchurl {
    url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  dontUnpack = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    install -Dm755 $src $out/bin/plannotator
  '';

  meta = {
    description = "Plan and code review for AI coding agents";
    homepage = "https://plannotator.ai";
    platforms = lib.attrNames assets;
    mainProgram = "plannotator";
  };
}
