{
  description = "Vivado for NixOS: out-of-store install + FHS wrapper";

  # Own pinned nixpkgs so the curated FHS lib set stays reproducible,
  # independent of the consumer's nixpkgs (matches sfc-nix).
  inputs.nixpkgs.url = "github:nixos/nixpkgs/release-25.11";

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux"; # Vivado is x86_64-linux only
    pkgs = import nixpkgs {inherit system;};
    inherit (nixpkgs) lib;

    # Per-version installer catalogs (installer dir, per-edition modules), keyed
    # by version string. Consumers read valid module names from
    # `vivado-nix.lib.catalog.<version>.editions.<edition>`, and available
    # versions from `vivado-nix.lib.versions`.
    catalog = import ./options.nix;

    # Builder — the configuration surface. A consumer's flake calls this with
    # its LOGICAL options (version, edition, which device modules) and gets both
    # packages, built consistently. MACHINE paths are NOT required arguments:
    # the wrapper/installer read VIVADO_INSTALL_ROOT / VIVADO_INSTALLER_TAR from
    # the environment (with optional per-call fallbacks), so nothing
    # host-specific is baked into the store.
    #
    #   vivado-nix.lib.mkVivado {
    #     version        = "2025.2";                            # side-by-side installs
    #     edition        = "Vivado ML Enterprise";              # default: catalog's defaultEdition
    #     enabledModules = [ "Virtex UltraScale+ 58G FPGAs" "Artix-7 FPGAs" ];
    #   }
    #   => { vivado, vivado-install }
    mkVivado = {
      version ? "2025.2",
      edition ? null, # null -> that version's defaultEdition
      enabledModules ? null, # null -> no device modules
      # Optional build-time fallbacks for the machine-path env vars.
      installRoot ? null,
      installerTar ? null,
      workDir ? null,
    }:
      assert lib.assertMsg (catalog ? ${version})
      "vivado-nix: no catalog for Vivado ${version} (have: ${lib.concatStringsSep ", " (builtins.attrNames catalog)})"; let
        vivado-install = pkgs.callPackage ./install-tool.nix {
          inherit version edition enabledModules installRoot installerTar workDir;
        };
        vivado = pkgs.callPackage ./vivado.nix {
          inherit version installRoot;
          installTool = vivado-install;
        };
      in {inherit vivado vivado-install;};

    defaults = mkVivado {};
  in {
    packages.${system} = {
      inherit (defaults) vivado vivado-install;
      default = defaults.vivado;
    };

    lib = {
      inherit mkVivado catalog;
      versions = builtins.attrNames catalog;
    };

    overlays.default = _final: _prev: {inherit (defaults) vivado vivado-install;};
  };
}
