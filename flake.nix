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

      # Build west dependencies ONCE and share across all keyboards
      westDeps = zmk.fetchZephyrDeps {
        name = "sofle-west-deps";
        inherit src;
        westRoot = "config";
        hash = "sha256-fgZTRT4+tTGm2k4lFZQx+bghyDOliakRqRAdhiG+Yoo=";
      };

      commonArgs = {
        inherit src westDeps;
        board = "nice_nano_v2";
        # Still need this for the derivation, but westDeps overrides it
        zephyrDepsHash = "sha256-fgZTRT4+tTGm2k4lFZQx+bghyDOliakRqRAdhiG+Yoo=";
      };

      sofle_dongle = zmk.buildKeyboard (
        commonArgs
        // {
          name = "sofle_dongle";
          shield = "sofle_dongle dongle_display";
          snippets = [ "studio-rpc-usb-uart" ];
          enableZmkStudio = true;
          extraCmakeFlags = [ "-DCONFIG_ZMK_STUDIO_LOCKING=n" ];
        }
      );

      sofle_left = zmk.buildKeyboard (
        commonArgs
        // {
          name = "sofle_left";
          shield = "sofle_left";
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

      sofle = pkgs.runCommand "sofle" {} ''
        mkdir -p $out/sofle_{dongle,left,right}
        ln -s ${sofle_dongle}/zmk.uf2 $out/sofle_dongle/zmk.uf2
        ln -s ${sofle_left}/zmk.uf2 $out/sofle_left/zmk.uf2
        ln -s ${sofle_right}/zmk.uf2 $out/sofle_right/zmk.uf2
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
        inherit sofle westDeps flash formatter settings_reset;
        default = sofle;
      };
      checks.x86_64-linux = {
        inherit sofle formatter;
      };
      formatter.x86_64-linux = formatter;
    };
}
