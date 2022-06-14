{
  description = "Unlock the flash on STM32WL microcontrollers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, crane, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        cargoToml = nixpkgs.lib.importTOML ./Cargo.toml;
        pkgName = "${cargoToml.package.name}";

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
          pname = "${pkgName}-deps";
        });

        clippy = craneLib.cargoClippy (commonArgs // {
          inherit cargoArtifacts;
          cargoClippyExtraArgs = "-- --deny warnings";
        });

        "${pkgName}" = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
        });
      in
      rec {
        packages.default = stm32wl-unlock;
        checks = {
          inherit stm32wl-unlock clippy;

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

  #outputs = { self, nixpkgs }:
  #  let
  #    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  #    cargoToml = nixpkgs.lib.importTOML ./Cargo.toml;
  #  in
  #  {
  #    packages.x86_64-linux.${cargoToml.package.name} = pkgs.callPackage ./package.nix { };
  #    apps.x86_64-linux.${cargoToml.package.name} = {
  #      type = "app";
  #      program = "${self.packages.x86_64-linux.default}/bin/${cargoToml.package.name}";
  #    };
  #    apps.x86_64-linux.default = self.apps.x86_64-linux.${cargoToml.package.name};

  #    packages.x86_64-linux.default = self.packages.x86_64-linux.${cargoToml.package.name};

  #    devShells.x86_64-linux.default = pkgs.mkShell {
  #      nativeBuildInputs = self.packages.x86_64-linux.default.nativeBuildInputs ++ [
  #        pkgs.gcc
  #      ];
  #      buildInputs = self.packages.x86_64-linux.default.buildInputs ++ [
  #        pkgs.clippy
  #      ];
  #    };

  #    checks.x86_64-linux = {
  #      format = pkgs.runCommand "format"
  #        {
  #          inherit (self.packages.x86_64-linux.default) nativeBuildInputs;
  #          buildInputs = with pkgs; [ rustfmt cargo ] ++ self.packages.x86_64-linux.default.buildInputs;
  #        } ''
  #        ${pkgs.rustfmt}/bin/cargo-fmt fmt --manifest-path ${./.}/Cargo.toml -- --check
  #        ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
  #        touch $out
  #      '';

  #      lint = pkgs.runCommand "lint" { } ''
  #        ${pkgs.statix}/bin/statix check ${./.}
  #        touch $out
  #      '';
  #    };
  #  };
}
