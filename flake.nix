{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    # Pin exact ZMK version used by golden commit
    zmk = {
      url = "github:zmkfirmware/zmk/v0.3";
      flake = false;
    };

    # Pin exact Zephyr version (v3.5.0+zmk-fixes from zmkfirmware fork)
    zephyr = {
      url = "github:zmkfirmware/zephyr/v3.5.0+zmk-fixes";
      flake = false;
    };

    # zmk-dongle-display module
    zmk-dongle-display = {
      url = "github:englmaxi/zmk-dongle-display/v0.3";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      treefmt-nix,
      zmk,
      zephyr,
      zmk-dongle-display,
      ...
    }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      # Zephyr SDK 0.16.9 - matching Docker image
      zephyrSdk = pkgs.stdenv.mkDerivation {
        name = "zephyr-sdk-0.16.9";
        version = "0.16.9";

        srcs = [
          (pkgs.fetchurl {
            url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.9/zephyr-sdk-0.16.9_linux-x86_64_minimal.tar.xz";
            sha256 = "19c26wjy9p3a0w6r0chlyiy779qllbfmiacnfr6mzlac6fdz2cxl";
          })
          (pkgs.fetchurl {
            url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.9/toolchain_linux-x86_64_arm-zephyr-eabi.tar.xz";
            sha256 = "1y5acjl7p20ckq0glxl3pyh2kv5bly55481zqpy85jz34s1jl5l1";
          })
        ];

        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [
          pkgs.stdenv.cc.cc.lib
          pkgs.python3
          pkgs.ncurses5
          pkgs.zlib
        ];

        autoPatchelfIgnoreMissingDeps = [
          "libpython3.8.so.1.0"
          "libpython3.11.so.1.0"
        ];

        sourceRoot = ".";
        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r zephyr-sdk-0.16.9/* $out/
          cp -r arm-zephyr-eabi $out/
          rm -f $out/arm-zephyr-eabi/bin/arm-zephyr-eabi-gdb*
          runHook postInstall
        '';
      };

      # Python environment matching the Docker image
      pythonEnv = pkgs.python3.withPackages (ps: [
        ps.west
        ps.pyelftools
        ps.pyyaml
        ps.pykwalify
        ps.packaging
        ps.cbor2
        ps.setuptools  # For pkg_resources used by nanopb
        ps.protobuf    # For nanopb protoc
      ]);

      # Fetch Zephyr HAL modules (needed by west)
      halNordic = pkgs.fetchFromGitHub {
        owner = "zephyrproject-rtos";
        repo = "hal_nordic";
        rev = "884c4d61746bc35fbd379c169fc87ddb56c6461d";
        hash = "sha256-L6jCDtBfE78JZDo81VCvdJxFWMoj7EJYzXMAhgqyJ9Q=";
      };

      cmsis = pkgs.fetchFromGitHub {
        owner = "zephyrproject-rtos";
        repo = "cmsis";
        rev = "5a00331455dd74e31e80efa383a489faea0590e3";
        hash = "sha256-1oCeT681nFDbCyhp0mErktuoj3YtFDzP5dLYdWz0+AM=";
      };

      # Additional modules required by ZMK
      nanopb = pkgs.fetchFromGitHub {
        owner = "zmkfirmware";
        repo = "nanopb";
        rev = "8c60555d6277a0360c876bd85d491fc4fb0cd74a";
        hash = "sha256-L+BBhQX/oRscA/J7muAmJ/9gr+BE8/Vd7efBzQ7B5/A=";
      };

      zmkStudioMessages = pkgs.fetchFromGitHub {
        owner = "zmkfirmware";
        repo = "zmk-studio-messages";
        rev = "6cb4c283e76209d59c45fbcb218800cd19e9339d";
        hash = "sha256-Cfw1htCp3xZt1R+X3kW3e9shEcMGbeBbEqpDoyLJV3s=";
      };

      # LVGL for display support
      lvgl = pkgs.fetchFromGitHub {
        owner = "zephyrproject-rtos";
        repo = "lvgl";
        rev = "8a6a2d1d29d17d1e4bdc94c243c146a39d635fdd";
        hash = "sha256-RDirbdNZ0QQ1g0WJyWx2k70J+zUhTdWiF484VAakVWc=";
      };

      # TinyCrypt for Bluetooth crypto
      tinycrypt = pkgs.fetchFromGitHub {
        owner = "zephyrproject-rtos";
        repo = "tinycrypt";
        rev = "3e9a49d2672ec01435ffbf0d788db6d95ef28de0";
        hash = "sha256-5gtZbZNx+D/EUkyYk7rPtcxBZaNs4IFGTP/7IXzCoqU=";
      };

      # Config from this repo (excluding zephyr/ which conflicts with Zephyr source)
      configSrc = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.unions [
          ./config
          ./boards
        ];
      };

      # Build a keyboard
      buildKeyboard =
        {
          name,
          shield,
          extraCmakeFlags ? [ ],
        }:
        pkgs.stdenv.mkDerivation {
          inherit name;

          src = configSrc;

          nativeBuildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.git
            pkgs.dtc
            pkgs.protobuf
            pythonEnv
            zephyrSdk
          ];

          ZEPHYR_TOOLCHAIN_VARIANT = "zephyr";
          ZEPHYR_SDK_INSTALL_DIR = zephyrSdk;

          configurePhase = ''
            runHook preConfigure

            export HOME=$TMPDIR

            # Set up directory structure
            cd $TMPDIR
            mkdir -p zmk-workspace

            # Copy user config
            cp -r $src/* zmk-workspace/

            # Create module.yml for custom boards
            mkdir -p zmk-workspace/zephyr
            cat > zmk-workspace/zephyr/module.yml << 'MODEOF'
build:
  settings:
    board_root: .
MODEOF

            # Copy ZMK source
            mkdir -p zmk-workspace/zmk
            cp -r ${zmk}/* zmk-workspace/zmk/

            # Copy Zephyr source (making it writable for patching)
            mkdir -p zmk-workspace/zephyr-base
            cp -r ${zephyr}/* zmk-workspace/zephyr-base/
            chmod -R u+w zmk-workspace/zephyr-base/

            # Copy additional modules
            mkdir -p zmk-workspace/zmk-dongle-display
            cp -r ${zmk-dongle-display}/* zmk-workspace/zmk-dongle-display/
            mkdir -p zmk-workspace/modules/hal/nordic
            cp -r ${halNordic}/* zmk-workspace/modules/hal/nordic/
            mkdir -p zmk-workspace/modules/hal/cmsis
            cp -r ${cmsis}/* zmk-workspace/modules/hal/cmsis/
            mkdir -p zmk-workspace/modules/lib/nanopb
            cp -r ${nanopb}/* zmk-workspace/modules/lib/nanopb/
            chmod -R u+w zmk-workspace/modules/lib/nanopb/
            # Fix shebangs for Nix sandbox
            patchShebangs zmk-workspace/modules/lib/nanopb/
            mkdir -p zmk-workspace/modules/msgs/zmk-studio-messages
            cp -r ${zmkStudioMessages}/* zmk-workspace/modules/msgs/zmk-studio-messages/
            mkdir -p zmk-workspace/modules/lib/gui/lvgl
            cp -r ${lvgl}/* zmk-workspace/modules/lib/gui/lvgl/
            mkdir -p zmk-workspace/modules/crypto/tinycrypt
            cp -r ${tinycrypt}/* zmk-workspace/modules/crypto/tinycrypt/

            cd zmk-workspace

            export ZEPHYR_BASE=$(pwd)/zephyr-base

            # Patch kconfig.py to not abort on warnings
            # This is needed because newer kconfiglib versions are stricter
            sed -i 's/err("Aborting due to Kconfig warnings")/print("Warning: Kconfig warnings encountered but continuing", file=sys.stderr)/' \
              $ZEPHYR_BASE/scripts/kconfig/kconfig.py

            # Register Zephyr cmake package
            mkdir -p $HOME/.cmake/packages/Zephyr
            echo "$ZEPHYR_BASE/share/zephyr-package/cmake" > $HOME/.cmake/packages/Zephyr/ZephyrPackage
            mkdir -p $HOME/.cmake/packages/ZephyrUnittest
            echo "$ZEPHYR_BASE/share/zephyrunittest-package/cmake" > $HOME/.cmake/packages/ZephyrUnittest/ZephyrUnittestPackage

            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild

            # Build module list for ZEPHYR_MODULES (semicolon-separated)
            MODULES=""
            MODULES="$MODULES;$(pwd)/modules/hal/nordic"
            MODULES="$MODULES;$(pwd)/modules/hal/cmsis"
            MODULES="$MODULES;$(pwd)/modules/lib/nanopb"
            MODULES="$MODULES;$(pwd)/modules/msgs/zmk-studio-messages"
            MODULES="$MODULES;$(pwd)/modules/lib/gui/lvgl"
            MODULES="$MODULES;$(pwd)/modules/crypto/tinycrypt"
            MODULES="$MODULES;$(pwd)/zmk-dongle-display"
            MODULES="$MODULES;$(pwd)"  # For custom boards via zephyr/module.yml
            MODULES="''${MODULES#;}"  # Remove leading semicolon

            # Hide west from PATH so Zephyr doesn't try to use it for module discovery
            mkdir -p $TMPDIR/fake-bin
            echo '#!/bin/sh' > $TMPDIR/fake-bin/west
            echo 'exit 1' >> $TMPDIR/fake-bin/west
            chmod +x $TMPDIR/fake-bin/west
            export PATH="$TMPDIR/fake-bin:$PATH"

            mkdir -p build
            cmake -S zmk/app -B build -GNinja \
              -DBOARD=nice_nano_v2 \
              -DSHIELD="${shield}" \
              -DZMK_CONFIG="$(pwd)/config" \
              -DZEPHYR_MODULES="$MODULES" \
              ${pkgs.lib.concatStringsSep " " extraCmakeFlags}

            cmake --build build

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp build/zephyr/zmk.uf2 $out/
            runHook postInstall
          '';
        };

      sofle_dongle = buildKeyboard {
        name = "sofle_dongle";
        shield = "sofle_dongle dongle_display";
        extraCmakeFlags = [
          "-DCONFIG_ZMK_SPLIT=y"
          "-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=y"
          "-DCONFIG_ZMK_STUDIO=y"
          "-DCONFIG_ZMK_STUDIO_LOCKING=n"
          "-DSNIPPET=studio-rpc-usb-uart"
        ];
      };

      sofle_left = buildKeyboard {
        name = "sofle_left";
        shield = "sofle_left nice_view_adapter nice_view";
        extraCmakeFlags = [
          "-DCONFIG_ZMK_SPLIT=y"
          "-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=n"
        ];
      };

      sofle_right = buildKeyboard {
        name = "sofle_right";
        shield = "sofle_right nice_view_adapter nice_view";
        extraCmakeFlags = [
          "-DCONFIG_ZMK_SPLIT=y"
          "-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=n"
        ];
      };

      settings_reset = buildKeyboard {
        name = "settings_reset";
        shield = "settings_reset";
      };

      sofle = pkgs.runCommand "sofle" { } ''
        mkdir -p $out
        cp ${sofle_dongle}/zmk.uf2 "$out/sofle_dongle dongle_display-nice_nano_v2-zmk.uf2"
        cp ${sofle_left}/zmk.uf2 "$out/sofle_left nice_view_adapter nice_view-nice_nano_v2-zmk.uf2"
        cp ${sofle_right}/zmk.uf2 "$out/sofle_right nice_view_adapter nice_view-nice_nano_v2-zmk.uf2"
        cp ${settings_reset}/zmk.uf2 "$out/settings_reset-nice_nano_v2-zmk.uf2"
      '';

      flash = pkgs.writeShellApplication {
        name = "flash";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.util-linux
        ];
        runtimeEnv = {
          KEYBOARD = sofle;
        };
        text = builtins.readFile ./nix/flash.sh;
      };

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        programs.nixfmt.enable = true;
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
      };

      formatter = treefmtEval.config.build.wrapper;
    in
    {
      packages.x86_64-linux = {
        inherit
          sofle
          sofle_dongle
          sofle_left
          sofle_right
          settings_reset
          flash
          formatter
          zephyrSdk
          ;
        default = sofle;
      };

      checks.x86_64-linux = {
        inherit sofle formatter;
      };

      formatter.x86_64-linux = formatter;
    };
}
