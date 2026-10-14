# `vivado-install` — scripts the one-time, outside-nix install.
#
# Extracts the AMD tarball and runs the vendor `xsetup` batch installer inside
# a `buildFHSEnv` carrying the same lib set as the `vivado` wrapper, selecting
# only the device modules chosen here.
#
# LOGICAL options (edition, which device modules) come from the flake. MACHINE
# paths do NOT — they're read from the environment, so nothing host-specific is
# baked into the store:
#   VIVADO_INSTALL_ROOT  where to install (must match the wrapper's root)  [required]
#   VIVADO_INSTALLER_TAR the AMD unified installer .tar                     [required]
#   VIVADO_WORKDIR       scratch for extraction        [optional; default $TMPDIR/...]
#
# Read valid module names from
# `vivado-nix.lib.catalog.<version>.editions.<edition>`.
{
  lib,
  pkgs,
  buildFHSEnv,
  writeShellApplication,
  bash,
  gnutar,
  coreutils,
  # --- Logical options (set from the flake's mkVivado) ----------------------
  # Vivado version — selects the per-version catalog and the <version>/Vivado
  # install subdir (so multiple versions coexist side by side).
  version,
  # One of the version's `editions`; null -> its `defaultEdition`. For 2025.2
  # the free Standard edition installs Virtex UltraScale+ devices (e.g. xcux35 /
  # Alveo X3522) as NON-TIMING — synthesis works but implementation dies with
  # "Cannot run timing on a non-timing device" — so the default is Enterprise,
  # which needs no paid .lic.
  edition ? null,
  # Device families to install; NO default — a consumer must opt in.
  enabledModules ? null, # null -> none (device-less install)
  # --- Optional build-time fallbacks for the machine-path env vars ----------
  installRoot ? null,
  installerTar ? null,
  workDir ? null,
}: let
  opts = (import ./options.nix).${version};
  selectedEdition =
    if edition == null
    then opts.defaultEdition
    else edition;
  allModules = opts.editions.${selectedEdition};
  installerFhs = buildFHSEnv {
    name = "vivado-installer-fhs";
    targetPkgs = _: (import ./fhs-libs.nix pkgs) ++ [bash];
    runScript = "bash";
  };

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

  badModules = lib.subtractLists allModules selected;

  modulesLine =
    lib.concatStringsSep ","
    (map (m: "${m}:${
        if lib.elem m selected
        then "1"
        else "0"
      }")
      allModules);
in
  assert lib.assertMsg (opts.editions ? ${selectedEdition})
  "vivado-install: unknown ${version} edition \"${selectedEdition}\" (have: ${lib.concatStringsSep ", " (builtins.attrNames opts.editions)})";
  assert lib.assertMsg (badModules == [])
  "vivado-install: module(s) ${lib.concatStringsSep ", " (map (m: ''"${m}"'') badModules)} not in ${version} \"${selectedEdition}\"; see lib.catalog.\"${version}\".editions";
    writeShellApplication {
      name = "vivado-install";
      runtimeInputs = [gnutar coreutils];
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
        vivado_bin="$dest/${version}/Vivado/bin/vivado"
        modules_record="$dest/.xinstall/${version}/data/instRecord.dat"
        selected_modules=( ${lib.concatMapStringsSep " " lib.escapeShellArg selected} )

        modules_installed() {
          [ -f "$modules_record" ] || return 1
          local line module found
          for module in "''${selected_modules[@]}"; do
            found=false
            while IFS= read -r line; do
              if [[ "$line" == *"<value>$module</value>"* ]]; then
                found=true
                break
              fi
            done < "$modules_record"
            "$found" || return 1
          done
        }

        echo ">> vivado-install ${version} — edition '${selectedEdition}' -> $dest"
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

        # --- generate install config from nix options --------------------------
        cfg="$workdir/install_config.txt"
        cat > "$cfg" <<EOF
        #### Generated by vivado-install (nix) — edition ${selectedEdition} ####
        Edition=${selectedEdition}
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

        # --- run the batch install ---------------------------------------------
        # Adding modules must use the maintenance launcher from the installed
        # tree. The distribution launcher always treats itself as fresh media.
        if [ -x "$vivado_bin" ] && modules_installed; then
          echo ">> requested modules are already installed"
          exit 0
        elif [ -x "$vivado_bin" ]; then
          action=Add
          xsetup="$dest/.xinstall/${version}/xsetup"
          echo ">> adding modules to existing Vivado ${version} at $dest ..."
          if [ ! -x "$xsetup" ]; then
            echo "ERROR: existing install has no maintenance launcher at $xsetup" >&2
            exit 1
          fi
        else
          action=Install
          xsetup=./xsetup
          echo ">> installing Vivado ${version} to $dest ..."
        fi

        # xsetup can exit zero after its Java installer fails, so independently
        # verify both the executable and AMD's installed-module record below.
        # shellcheck disable=SC2016
        if ! ${installerFhs}/bin/vivado-installer-fhs -c \
          'cd "$1" && bash "$2" -a XilinxEULA,3rdPartyEULA -b "$3" -c "$4"' \
          _ "$setupdir" "$xsetup" "$action" "$cfg"; then
          echo ">> (xsetup returned non-zero; verifying result anyway)"
        fi

        if [ ! -x "$vivado_bin" ] || ! modules_installed; then
          echo "ERROR: installer did not provide all requested modules in $dest/${version}/Vivado" >&2
          echo "       Expected module record: $modules_record" >&2
          echo "       See ~/.Xilinx/xinstall/ for the installer log." >&2
          exit 1
        fi
        echo ">> requested modules installed OK: $vivado_bin"
        echo ">> run it with:  nix run <this-flake>#vivado -- -version"
      '';

      meta = {
        description = "One-time outside-nix installer for Vivado (device-limited, FHS driven)";
        platforms = ["x86_64-linux"];
        mainProgram = "vivado-install";
      };
    }
