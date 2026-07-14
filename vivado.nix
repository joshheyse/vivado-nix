# AMD/Xilinx Vivado, runtime-wrapped for NixOS.
#
# The installed tree (~52 GB) lives OUTSIDE the nix store, in a directory named
# by the `VIVADO_INSTALL_ROOT` environment variable, produced once by the
# `vivado-install` tool. This package is just a tiny `buildFHSEnv` wrapper: it
# sources that tree's settings and runs the real vivado inside an FHS whose lib
# set (fhs-libs.nix) satisfies its dependencies.
#
# No machine path is baked in — the install location is a property of the host
# (set VIVADO_INSTALL_ROOT in your NixOS/home config), so the same store-built
# wrapper works regardless of where the install lives. `installRoot` is an
# optional build-time fallback for that env var.
#
# It's a drop-in `vivado` — `vivado -version`, interactive `vivado`, and a
# Makefile that calls `vivado -mode batch ...` all work.
{
  lib,
  pkgs,
  buildFHSEnv,
  writeShellScript,
  # Vivado version — selects the <version>/Vivado subdir under the install root,
  # so multiple versions coexist side by side.
  version,
  # Optional build-time fallback for $VIVADO_INSTALL_ROOT. null => require the
  # env var at runtime (the default; keeps machine paths out of the store).
  installRoot ? null,
  # The matching `vivado-install` derivation, surfaced via passthru.
  installTool ? null,
}: let
  fhsLibs = import ./fhs-libs.nix pkgs;
  installRootFallback =
    if installRoot == null
    then ""
    else installRoot;
in
  buildFHSEnv {
    name = "vivado";
    # Vivado's runtime libs (fhs-libs already includes coreutils/sed/awk/find);
    # add make/diff so `make`-driven HDL flows (e.g. taxi) work in the FHS too.
    targetPkgs = _: fhsLibs ++ (with pkgs; [gnumake diffutils]);

    # Resolve the install root from the environment, source settings64.sh (puts
    # real vivado/vitis/xsct on PATH), then exec the requested vivado command.
    runScript = writeShellScript "vivado-run" ''
      root="''${VIVADO_INSTALL_ROOT:-${installRootFallback}}"
      if [ -z "$root" ]; then
        echo "vivado: VIVADO_INSTALL_ROOT is not set." >&2
        echo "        point it at your Vivado install dir (e.g. via" >&2
        echo "        environment.sessionVariables in your NixOS config)." >&2
        exit 1
      fi
      vroot="$root/${version}/Vivado"
      if [ ! -e "$vroot/settings64.sh" ]; then
        echo "vivado: no install at $vroot" >&2
        echo "        install once with:  nix run <this-flake>#vivado-install" >&2
        exit 1
      fi
      source "$vroot/settings64.sh"
      # Vivado's loader resets LD_LIBRARY_PATH and its ldconfig cache misses the
      # ncurses5 compat symlinks, so force the FHS lib dirs onto the search path.
      export LD_LIBRARY_PATH="/usr/lib:/lib''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}"
      exec vivado "$@"
    '';

    passthru =
      {inherit installRoot;}
      // lib.optionalAttrs (installTool != null) {inherit installTool;};

    meta = {
      description = "AMD/Xilinx Vivado ${version} (FHS wrapper over an out-of-store install)";
      homepage = "https://www.xilinx.com/products/design-tools/vivado.html";
      # Store contents are just the wrapper + free FHS libs; unfree Vivado lives
      # out-of-store, so no allowUnfree gate is needed to put this on a PATH.
      platforms = ["x86_64-linux"];
      mainProgram = "vivado";
    };
  }
