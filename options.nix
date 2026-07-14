# Vivado install options as Nix data — the source of truth for what the
# `vivado-install` tool can select, so the choices live in the flake rather
# than a hand-edited install_config.txt.
#
# Captured from `xsetup -b ConfigGen` for the 2025.2 unified installer
# (Vivado ML Standard). Module NAMES must match xsetup's catalog EXACTLY and
# are release-specific — when you bump the installer, regenerate by running
# `xsetup -b ConfigGen` (product Vivado, edition Standard) and reconcile the
# resulting `Modules=` line here. See README.md.
{
  version = "2025.2";

  # `xsetup` installer-dir basename inside the tarball (payload lives under it).
  installerDir = "FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1114_2157";

  editions = [
    "Vivado ML Standard"
    "Vivado ML Enterprise"
  ];

  # Full module catalog, in installer order. `vivado-install` writes each as
  # `<name>:0` or `<name>:1` depending on whether it's in `enabledModules`.
  allModules = [
    "xcv80"
    "Zynq UltraScale+ MPSoCs"
    "Kintex UltraScale+ FPGAs"
    "Virtex UltraScale+ 58G FPGAs"
    "xcve2202"
    "Vitis Model Composer(A toolbox for Simulink)"
    "Artix-7 FPGAs"
    "Install devices for Alveo and edge acceleration platforms"
    "Vitis Embedded Development"
    "xcvm1102"
    "Zynq-7000 All Programmable SoC"
    "xcve2002"
    "Virtex UltraScale+ HBM FPGAs"
    "Spartan UltraScale+"
    "xcve2302"
    "Vitis Networking P4"
    "Kintex UltraScale FPGAs"
    "Power Design Manager (PDM)"
    "Virtex UltraScale+ FPGAs"
    "Artix UltraScale+ FPGAs"
    "Spartan-7 FPGAs"
    "DocNav"
    "Versal RF Series ES1"
    "Install Devices for Kria SOMs and Starter Kits"
    "xcve2102"
    "Kintex-7 FPGAs"
  ];

  # Default selection: the device families for the boards on hand.
  #   - Virtex UltraScale+ 58G FPGAs -> xcux35 (Alveo X3522); also xcu26
  #     (AU45N/SN1000) and xcvu23p. (verified: virtexuplus58ga-family_xcux35)
  #   - Artix-7 FPGAs                -> XC7A200T (Nexys Video), XC7A35T (taxi Arty A7)
  #   - Zynq-7000 All Programmable SoC -> XC7Z020/XC7Z010 (Arty Z7)
  # 7-series families are small; they add little to the install size.
  defaultEnabledModules = [
    "Virtex UltraScale+ 58G FPGAs"
    "Artix-7 FPGAs"
    "Zynq-7000 All Programmable SoC"
  ];
}
