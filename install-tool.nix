# `vivado-install` — scripts the one-time, outside-nix install.
#
# Extracts the AMD tarball, fixes its `/bin/bash` shebangs (NixOS has none),
# and runs the vendor `xsetup` batch installer under the host's nix-ld,
# selecting only the device modules chosen here.
#
# LOGICAL options (edition, which device modules) come from the flake. MACHINE
# paths do NOT — they're read from the environment, so nothing host-specific is
# baked into the store:
#   VIVADO_INSTALL_ROOT  where to install (must match the wrapper's root)  [required]
#   VIVADO_INSTALLER_TAR the AMD unified installer .tar                     [required]
#   VIVADO_WORKDIR       scratch for extraction        [optional; default $TMPDIR/...]
#
# Requires `programs.nix-ld.enable = true` on the host. Read valid module names
# from `vivado-nix.lib.catalog.<version>.allModules`.
{
  lib,
  pkgs,
  writeShellApplication,
  bash,
  gnutar,
  coreutils,
  gnused,
  gawk,
  findutils,
  which,
  util-linux,
  procps,
  glibc,
  # --- Logical options (set from the flake's mkVivado) ----------------------
  # Vivado version — selects the per-version catalog and the <version>/Vivado
  # install subdir (so multiple versions coexist side by side).
  version,
  # Default to Enterprise: the free Standard edition installs Virtex UltraScale+
  # devices (e.g. xcux35 / Alveo X3522) as NON-TIMING — synthesis works but
  # implementation dies with "Cannot run timing on a non-timing device". The
  # Enterprise edition ships the timing/speed data, enabling full
  # synth->P&R->bitstream. No paid .lic is needed. Use "Vivado ML Standard" for
  # 7-series-only installs.
  edition ? "Vivado ML Enterprise",
  # Device families to install; NO default — a consumer must opt in.
  enabledModules ? null, # null -> none (device-less install)
  # --- Optional build-time fallbacks for the machine-path env vars ----------
  installRoot ? null,
  installerTar ? null,
  workDir ? null,
}: let
  opts = (import ./options.nix).${version};
  fhsLibs = import ./fhs-libs.nix pkgs;
  ldLibraryPath = lib.makeLibraryPath fhsLibs;

  installRootFallback =
    if installRoot == null
    then ""
    else installRoot;
  installerTarFallback =
    if installerTar == null
    then ""
    else installerTar;
  # literal shell ${TMPDIR:-/tmp}/... when no fallback is configured
  workDirFallback =
    if workDir == null
    then "\${TMPDIR:-/tmp}/vivado-extract"
    else workDir;

  selected =
    if enabledModules == null
    then []
    else enabledModules;

  # Validate selections against the catalog so a typo fails at eval, not mid-install.
  bad = lib.subtractLists opts.allModules selected;
  _ =
    lib.throwIf (bad != [])
    "vivado-install: unknown module(s) ${lib.concatStringsSep ", " (map (m: ''"${m}"'') bad)}; see options.nix allModules"
    null;

  modulesLine =
    lib.concatStringsSep ","
    (map (m: "${m}:${
        if lib.elem m selected
        then "1"
        else "0"
      }")
      opts.allModules);
in
  writeShellApplication {
    name = "vivado-install";
    runtimeInputs = [bash gnutar coreutils gnused gawk findutils which util-linux procps];
    text = ''
      # --- machine paths from the environment (fallbacks baked from flake) ----
      dest="''${VIVADO_INSTALL_ROOT:-${installRootFallback}}"
      if [ -z "$dest" ]; then
        echo "vivado-install: set VIVADO_INSTALL_ROOT to the install directory." >&2
        exit 1
      fi
      installer_tar="''${VIVADO_INSTALLER_TAR:-${installerTarFallback}}"
      if [ -z "$installer_tar" ]; then
        echo "vivado-install: set VIVADO_INSTALLER_TAR to the AMD unified installer (.tar)." >&2
        exit 1
      fi
      workdir="''${VIVADO_WORKDIR:-${workDirFallback}}"
      setupdir="$workdir/${opts.installerDir}"

      echo ">> vivado-install ${version} — edition '${edition}' -> $dest"
      echo ">> modules enabled: ${lib.concatStringsSep ", " selected}"

      if [ ! -f "$installer_tar" ]; then
        echo "ERROR: installer tar not found: $installer_tar" >&2
        exit 1
      fi

      # --- extract -----------------------------------------------------------
      # Payload (95 GB) is expensive: extract only if missing.
      if [ ! -d "$setupdir/payload" ] || [ -z "$(ls -A "$setupdir/payload" 2>/dev/null)" ]; then
        echo ">> extracting full installer (incl. payload) to $workdir ..."
        mkdir -p "$workdir"
        tar xf "$installer_tar" -C "$workdir"
      fi
      # Always refresh the front-end scripts from the tar so shebang patching
      # starts from pristine "#! /bin/bash" lines — makes re-runs idempotent and
      # wipes any prior mis-patch. Cheap (~1.3 GB), leaves payload untouched.
      echo ">> refreshing installer front-end (excluding payload) ..."
      tar xf "$installer_tar" -C "$workdir" --exclude='*/payload/*'

      # --- patch /bin/bash shebangs (NixOS has none) -------------------------
      # Anchored to the shebang only ("#!" + optional spaces + /bin/bash), so it
      # never matches a /bin/bash substring inside an already-substituted store
      # path. Scope excludes payload/ (95 GB of .xz).
      echo ">> patching /bin/bash shebangs"
      while IFS= read -r f; do
        sed -i '1s|^#! */bin/bash|#!${bash}/bin/bash|' "$f"
      done < <(grep -rl --exclude-dir=payload '/bin/bash' "$setupdir" 2>/dev/null || true)

      # --- generate install config from nix options --------------------------
      cfg="$workdir/install_config.txt"
      cat > "$cfg" <<EOF
      #### Generated by vivado-install (nix) — edition ${edition} ####
      Edition=${edition}
      Product=Vivado
      Destination=$dest
      Modules=${modulesLine}
      InstallOptions=Acquire or Manage a License Key:0
      CreateProgramGroupShortcuts=0
      ProgramGroupFolder=AMD Adaptive SoC and FPGA Tools
      CreateShortcutsForAllUsers=0
      CreateDesktopShortcuts=0
      CreateFileAssociation=0
      EOF
      echo ">> config written to $cfg"

      # --- nix-ld environment for the vendor JRE / tools ---------------------
      # Curated set first, then the host's nix-ld default set as a proven
      # fallback for any native-lib dependency the curated list misses.
      export NIX_LD_LIBRARY_PATH="${ldLibraryPath}:/run/current-system/sw/share/nix-ld/lib"
      if [ -r /run/current-system/sw/nix-support/dynamic-linker ]; then
        NIX_LD="$(cat /run/current-system/sw/nix-support/dynamic-linker)"
      else
        NIX_LD="${glibc}/lib/ld-linux-x86-64.so.2"
      fi
      export NIX_LD
      export HOME="$workdir/home"; mkdir -p "$HOME"

      # --- run the batch install ---------------------------------------------
      # NOTE: xsetup exits 0 even when its Java installer dies, so we cannot
      # trust its return code — verify the vivado binary exists afterwards.
      echo ">> installing to $dest ..."
      if ! ( cd "$setupdir" && bash ./xsetup -a XilinxEULA,3rdPartyEULA -b Install -c "$cfg" ); then
        echo ">> (xsetup returned non-zero; verifying result anyway)"
      fi

      vivado_bin="$dest/${version}/Vivado/bin/vivado"
      if [ ! -x "$vivado_bin" ]; then
        echo "ERROR: install did not produce $vivado_bin — see the installer log in" >&2
        echo "       $HOME/.Xilinx/xinstall/ (look for 'native libs' / shebang errors)." >&2
        exit 1
      fi
      echo ">> installed OK: $vivado_bin"
      echo ">> run it with:  nix run <this-flake>#vivado -- -version"
    '';

    meta = {
      description = "One-time outside-nix installer for Vivado (device-limited, nix-ld driven)";
      platforms = ["x86_64-linux"];
      mainProgram = "vivado-install";
    };
  }
