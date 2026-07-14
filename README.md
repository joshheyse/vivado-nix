# vivado-nix

Run AMD/Xilinx **Vivado** on NixOS without putting its ~50 GB install in the
Nix store.

The install lives **out-of-store**, in a directory you choose (via
`$VIVADO_INSTALL_ROOT`) — typically a roomy partition like `/opt/xilinx`. A
one-time tool runs AMD's installer there; a tiny `buildFHSEnv` wrapper then runs
the real `vivado` inside an FHS. The Nix store holds only the wrapper plus free
FHS libraries — no vendor blob, and no machine-specific paths.

## Layout

| file | role |
|---|---|
| `flake.nix` | `lib.mkVivado` builder, `lib.catalog`, packages, overlay |
| `vivado.nix` | the drop-in `vivado` FHS wrapper |
| `install-tool.nix` | `vivado-install` — one-time installer driver |
| `options.nix` | installer catalog: version, editions, selectable device modules |
| `fhs-libs.nix` | shared native-lib set for the FHS / nix-ld |

## Requirements

- **x86_64-linux** (Vivado is x86_64 only).
- **`programs.nix-ld.enable = true`** on the host — the installer runs AMD's own
  binaries directly.
- The AMD **unified installer `.tar`**, downloaded from AMD (login required).
  Note it's a plain tar even though AMD sometimes names it `.tar.gz`.

## Quick start

```sh
# 1. add the flake
nix registry add vivado-nix github:joshheyse/vivado-nix   # or use it as an input, below

# 2. tell it where things are (env vars, not baked into the store)
export VIVADO_INSTALL_ROOT=/opt/xilinx
export VIVADO_INSTALLER_TAR=/path/to/FPGAs_AdaptiveSoCs_Unified_2025.2_*.tar

# 3. one-time install (device-limited, ~tens of GB) into $VIVADO_INSTALL_ROOT
nix run github:joshheyse/vivado-nix#vivado-install

# 4. drop-in vivado
nix run github:joshheyse/vivado-nix#vivado -- -version
nix run github:joshheyse/vivado-nix#vivado          # interactive
```

## Use from another flake

```nix
{
  inputs.vivado-nix.url = "github:joshheyse/vivado-nix";

  outputs = { self, nixpkgs, vivado-nix, ... }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    vivado = vivado-nix.lib.mkVivado {
      version        = "2025.2";                             # see lib.versions
      edition        = "Vivado ML Enterprise";               # or "Vivado ML Standard"
      enabledModules = [ "Virtex UltraScale+ 58G FPGAs" ];   # required; lib.catalog.<version>.allModules

      # Optional: bake this host's defaults for the env vars below, so it works
      # without exporting anything. Still overridable at runtime.
      installRoot  = "/opt/xilinx";
      installerTar = "/opt/xilinx/installer.tar";
    };
  in {
    # put vivado.vivado on a devShell PATH, expose vivado.vivado-install, etc.
    packages.${system} = { inherit (vivado) vivado vivado-install; };
  };
}
```

## Configuration

`mkVivado` takes only **logical** options; **machine paths come from the
environment** (or optional per-consumer fallbacks) so nothing host-specific is
baked into the store:

| option (`mkVivado` arg) | meaning | default |
|---|---|---|
| `version` | Vivado version; installs under `<root>/<version>/` so releases coexist side by side (`lib.versions`) | `2025.2` |
| `edition` | `Vivado ML Standard` \| `Vivado ML Enterprise` | Enterprise |
| `enabledModules` | device families to install (`lib.catalog.<version>.allModules`) | **none** — you must opt in |
| `installRoot` / `installerTar` / `workDir` | fallbacks for the env vars below | none |

| env var | meaning | required |
|---|---|---|
| `VIVADO_INSTALL_ROOT` | where the install lives (wrapper + installer) | yes* |
| `VIVADO_INSTALLER_TAR` | the AMD unified installer `.tar` | installer only* |
| `VIVADO_WORKDIR` | extraction scratch | no (default `$TMPDIR/vivado-extract`) |

\* unless a fallback was baked via the matching `mkVivado` arg. A natural home
for these on NixOS is `environment.sessionVariables`, since they describe the
machine, not the project.

## Notes

- **Not pure/reproducible, on purpose.** The install is out-of-store imperative
  state Nix doesn't track; `nix build .#vivado` only builds the wrapper.
  Reproduce the install by re-running `vivado-install`, not a Nix build.
- **Edition matters, a paid license may not.** Virtex UltraScale+ devices
  install as *non-timing* under Standard (synthesis only); Enterprise ships the
  timing data and the built-in entitlement covers full place-and-route +
  bitstream — no paid `.lic` needed. Hence the Enterprise default. Small
  7-series parts work fine under Standard.
- **Bumping the installer version:** edit `options.nix` (`version`,
  `installerDir`, and regenerate `allModules` via `xsetup -b ConfigGen`).

## License

MIT (this packaging). Vivado itself is AMD proprietary software under its own
license; this repo contains none of it — you supply the installer.
