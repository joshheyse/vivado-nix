{
  description = "Vivado for NixOS: out-of-store install + FHS wrapper";

  # Own pinned nixpkgs so the curated FHS lib set stays reproducible,
  # independent of the consumer's nixpkgs (matches sfc-nix).
  inputs.nixpkgs.url = "github:nixos/nixpkgs/release-25.11";

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux"; # Vivado is x86_64-linux only
    pkgs = import nixpkgs {inherit system;};

    # Version-intrinsic installer catalog: the FULL list of selectable device
    # modules ("boards"), the editions, and the installer version. Consumers
    # read valid names from `vivado-nix.lib.catalog.allModules`.
    catalog = import ./options.nix;

    # Builder — the configuration surface. A consumer's flake calls this with
    # its LOGICAL options (which boards/modules, edition) and gets both
    # packages, built consistently. MACHINE paths are NOT arguments: the
    # wrapper/installer read VIVADO_INSTALL_ROOT / VIVADO_INSTALLER_TAR from the
    # environment so nothing host-specific is baked into the store.
    #
    #   vivado-nix.lib.mkVivado {
    #     edition        = "Vivado ML Enterprise";
    #     enabledModules = [ "Virtex UltraScale+ 58G FPGAs" "Artix-7 FPGAs" ];
    #   }
    #   => { vivado, vivado-install }
    mkVivado = {
      edition ? "Vivado ML Enterprise",
      enabledModules ? catalog.defaultEnabledModules,
      # Optional build-time fallbacks for the machine-path env vars.
      installRoot ? null,
      installerTar ? null,
      workDir ? null,
    }: let
      vivado-install = pkgs.callPackage ./install-tool.nix {
        inherit edition enabledModules installRoot installerTar workDir;
      };
      vivado = pkgs.callPackage ./vivado.nix {
        inherit installRoot;
        installTool = vivado-install;
      };
    in {inherit vivado vivado-install;};

    defaults = mkVivado {};
  in {
    packages.${system} = {
      inherit (defaults) vivado vivado-install;
      default = defaults.vivado;
    };

    lib = {inherit mkVivado catalog;};

    overlays.default = _final: _prev: {inherit (defaults) vivado vivado-install;};
  };
}
