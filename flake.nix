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
        pkgs = nixpkgs.legacyPackages.${system};
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

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
      in
      rec {
        packages.default = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
        });

        apps.default = flake-utils.lib.mkApp { drv = packages.default; };

        checks = {
          pkg = packages.default;

          clippy = craneLib.cargoClippy (commonArgs // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "-- --deny warnings";
          });

          rustfmt = craneLib.cargoFmt { src = ./.; };

          nixpkgs-fmt = pkgs.runCommand "nixpkgs-fmt" { } ''
            ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
            touch $out
          '';

          statix = pkgs.runCommand "statix" { } ''
            ${pkgs.statix}/bin/statix check ${./.}
            touch $out
          '';
        };
      });
}
