{
  description = "Unlock the flash on STM32WL microcontrollers";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      cargoToml = nixpkgs.lib.importTOML ./Cargo.toml;
    in
    {
      packages.x86_64-linux.${cargoToml.package.name} = pkgs.callPackage ./package.nix { };
      apps.x86_64-linux.${cargoToml.package.name} = {
        type = "app";
        program = "${self.packages.x86_64-linux.default}/bin/${cargoToml.package.name}";
      };
      apps.x86_64-linux.default = self.apps.x86_64-linux.${cargoToml.package.name};

      packages.x86_64-linux.default = self.packages.x86_64-linux.${cargoToml.package.name};

      devShells.x86_64-linux.default = pkgs.mkShell {
        inherit (self.packages.x86_64-linux.default) nativeBuildInputs;
        buildInputs = self.packages.x86_64-linux.default.buildInputs ++ [ pkgs.clippy ];
      };

      checks.x86_64-linux = {
        format = pkgs.runCommand "format"
          {
            inherit (self.packages.x86_64-linux.default) nativeBuildInputs;
            buildInputs = with pkgs; [ rustfmt cargo ] ++ self.packages.x86_64-linux.default.buildInputs;
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
    };
}
