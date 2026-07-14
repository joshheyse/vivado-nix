# Shared native-library set that AMD/Xilinx tools (and the installer's bundled
# JRE) dlopen at runtime. Consumed two ways:
#   * default.nix     -> buildFHSEnv targetPkgs (runtime wrapper)
#   * install-tool.nix -> lib.makeLibraryPath for NIX_LD_LIBRARY_PATH (nix-ld)
# A single list keeps the install-time and run-time environments in sync.
pkgs:
with pkgs;
  [
    # core C/C++ runtime + terminal libs.
    # Vivado's Tcl loads libxv_commontasks.so (needs libncurses.so.5 -> ncurses5)
    # and libxv_tcltasks.so (needs libtinfo.so.6 -> ncurses/ncurses6), so BOTH
    # ABIs are required.
    ncurses5
    ncurses
    libxml2
    zlib
    # further deps of Vivado's lib/lnx64.o objects (found via ldd)
    pixman # libpixman-1.so.0
    libpng # libpng16.so.16
    libunwind # libunwind.so.8
    elfutils # libelf.so.1
    glibc
    gcc-unwrapped.lib
    stdenv.cc.cc.lib
    libxcrypt-legacy # libcrypt.so.1 for the bundled JRE
    # GL / rendering (GUI + device view)
    libGL
    libGLU
    freetype
    fontconfig
    expat
    graphite2
    # GTK stack (installer + GUI)
    gtk2
    glib
    gdk-pixbuf
    pango
    cairo
    atk
    dbus
    nss
    nspr
    alsa-lib
    # misc runtime tools the flows shell out to
    which
    gnused
    gawk
    coreutils
    procps
    util-linux
    findutils
    unzip
    # cable/JTAG + OpenCL (Vitis/XRT)
    libusb1
    ocl-icd
    # X11 libs — flattened out of the `xorg.*` set in nixpkgs 26.05.
    libx11
    libxext
    libxrender
    libxtst
    libxi
    libxft
    libxcb
    libxau
    libxdmcp
    libxrandr
    libxfixes
    libxcursor
    libxinerama
    libxscrnsaver
    libxcomposite
    libxdamage
    libsm
    libice
    xkeyboard-config
  ]
