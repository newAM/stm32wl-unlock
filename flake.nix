{
  description = "Unlock the flash on STM32WL microcontrollers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, crane, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        cargoToml = nixpkgs.lib.importTOML ./Cargo.toml;

        craneLib = crane.lib.${system};

        commonArgs = {
          src = ./.;
          nativeBuildInputs = with pkgs; [
            pkg-config
          ];
          buildInputs = with pkgs; [
            libusb1
            udev
          ];
        };

        cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
          pname = "${cargoToml.package.name}-deps";
        });

        clippy = craneLib.cargoClippy (commonArgs // {
          inherit cargoArtifacts;
          cargoClippyExtraArgs = "-- --deny warnings";
        });

        pkg = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
        });
      in
      rec {
        packages.default = pkg;

        apps.default = flake-utils.lib.mkApp { drv = packages.default; };

        checks = {
          inherit pkg clippy;

          format = pkgs.runCommand "format"
            {
              inherit (packages.default) nativeBuildInputs;
              buildInputs = with pkgs; [ rustfmt cargo ] ++ packages.default.buildInputs;
            } ''
            ${pkgs.rustfmt}/bin/cargo-fmt fmt --manifest-path ${./.}/Cargo.toml -- --check
            ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
            touch $out
          '';

          lint = pkgs.runCommand "lint" { } ''
            ${pkgs.statix}/bin/statix check ${./.}
            touch $out
          '';
        };
      });
}
