{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      nixpkgs,
      zmk-nix,
      treefmt-nix,
      ...
    }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      zmk = zmk-nix.legacyPackages.x86_64-linux;

      src = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.unions [
          ./config
          ./boards
          ./zephyr
        ];
      };

      commonArgs = {
        inherit src;
        board = "nice_nano_v2";
        zephyrDepsHash = "sha256-xc8u2Kc6j9sWskmThcLLI5dQYxWm70mHrU9ZqC1huzY=";
      };

      mkFlash =
        keyboard:
        pkgs.writeShellApplication {
          name = "flash-${keyboard.name}";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.util-linux
          ];
          runtimeEnv.UF2_FILE = "${keyboard}/zmk.uf2";
          text = builtins.readFile ./nix/flash.sh;
        };

      sofle_left = zmk.buildKeyboard (
        commonArgs
        // {
          name = "sofle_left";
          shield = "sofle_left";
          snippets = [ "studio-rpc-usb-uart" ];
          enableZmkStudio = true;
          extraCmakeFlags = [ "-DCONFIG_ZMK_STUDIO_LOCKING=n" ];
        }
      );

      sofle_right = zmk.buildKeyboard (
        commonArgs
        // {
          name = "sofle_right";
          shield = "sofle_right";
        }
      );

      settings_reset = zmk.buildKeyboard (
        commonArgs
        // {
          name = "settings_reset";
          shield = "settings_reset";
        }
      );

      sofle_dongle = zmk.buildKeyboard (
        commonArgs
        // {
          name = "sofle_dongle";
          shield = "sofle_dongle dongle_display";
          snippets = [ "studio-rpc-usb-uart" ];
          enableZmkStudio = true;
          extraCmakeFlags = [
            "-DCONFIG_ZMK_SPLIT=y"
            "-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=y"
            "-DCONFIG_ZMK_STUDIO_LOCKING=n"
          ];
        }
      );

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        programs.nixfmt.enable = true;
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
      };

      formatter = treefmtEval.config.build.wrapper;

      packages = {
        inherit
          sofle_left
          sofle_right
          settings_reset
          sofle_dongle
          formatter
          ;

        flash-left = mkFlash sofle_left;
        flash-right = mkFlash sofle_right;
        flash-reset = mkFlash settings_reset;
        flash-dongle = mkFlash sofle_dongle;
      };
    in
    {
      packages.x86_64-linux = packages;
      checks.x86_64-linux = packages;
      formatter.x86_64-linux = formatter;
    };
}
