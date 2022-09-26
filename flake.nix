{
  description = "Unlock the flash on STM32WL microcontrollers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    crane,
    flake-utils,
  }:
    flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
      inherit (nixpkgs.lib) recursiveUpdate;
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

      commonArgsArtifacts = recursiveUpdate commonArgs {inherit cargoArtifacts;};
    in rec {
      packages.default = craneLib.buildPackage commonArgsArtifacts;

      apps.default = flake-utils.lib.mkApp {drv = packages.default;};

      checks = {
        pkg = packages.default;

        clippy =
          craneLib.cargoClippy (recursiveUpdate commonArgsArtifacts
            {cargoClippyExtraArgs = "--all-targets -- --deny warnings";});

        rustfmt = craneLib.cargoFmt commonArgsArtifacts;

        alejandra = pkgs.runCommand "alejandra" {} ''
          ${pkgs.alejandra}/bin/alejandra --check ${./.}
          touch $out
        '';

        statix = pkgs.runCommand "statix" {} ''
          ${pkgs.statix}/bin/statix check ${./.}
          touch $out
        '';
      };
    });
}
