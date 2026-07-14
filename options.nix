# Per-version Vivado installer catalogs, keyed by version string.
#
# To support a new release, add an entry: run `xsetup -b ConfigGen` (product
# Vivado, edition Standard) against that installer and copy the resulting
# `installerDir` basename + `Modules=` names here (module NAMES are
# release-specific). Multiple versions can be installed side by side — each
# lands under $VIVADO_INSTALL_ROOT/<version>/Vivado.
{
  "2025.2" = {
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
  };
}
