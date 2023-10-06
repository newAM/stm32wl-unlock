{
  description = "Unlock the flash on STM32WL microcontrollers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = {
    self,
    nixpkgs,
    crane,
    flake-utils,
  }:
    flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      craneLib = crane.lib.${system};

      src = craneLib.cleanCargoSource ./.;
      nativeBuildInputs = with pkgs; [pkg-config];
      buildInputs = with pkgs; [libusb1 udev];

      cargoArtifacts = craneLib.buildDepsOnly {
        inherit src nativeBuildInputs buildInputs;
        strictDeps = true;
      };
    in {
      packages.default = craneLib.buildPackage {
        inherit src nativeBuildInputs buildInputs cargoArtifacts;
        strictDeps = true;
      };

      apps.default = flake-utils.lib.mkApp {drv = self.packages.${system}.default;};

      checks = let
        nixSrc = nixpkgs.lib.sources.sourceFilesBySuffices ./. [".nix"];
      in {
        pkg = self.packages.${system}.default;

        clippy = craneLib.cargoClippy {
          inherit src nativeBuildInputs buildInputs cargoArtifacts;
          strictDeps = true;
          cargoClippyExtraArgs = "--all-targets -- --deny warnings";
        };

        rustfmt = craneLib.cargoFmt {
          inherit src;
        };

        alejandra = pkgs.runCommand "alejandra" {} ''
          ${pkgs.alejandra}/bin/alejandra --check ${nixSrc}
          touch $out
        '';

        statix = pkgs.runCommand "statix" {} ''
          ${pkgs.statix}/bin/statix check ${nixSrc}
          touch $out
        '';
      };
    });
}
