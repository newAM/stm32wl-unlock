{
  description = "Unlock the flash on STM32WL microcontrollers";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      nativeBuildInputs = with pkgs; [ pkg-config ];
      buildInputs = with pkgs; [ libusb1 udev ];
      cargoToml = nixpkgs.lib.importTOML ./Cargo.toml;
    in
    {
      devShells.x86_64-linux.default = pkgs.mkShell {
        buildInputs = buildInputs ++ nativeBuildInputs;
      };

      packages.x86_64-linux.${cargoToml.package.name} = pkgs.rustPlatform.buildRustPackage {
        pname = cargoToml.package.name;
        inherit (cargoToml.package) version;

        src = ./.;

        RUSTFLAGS = "-D warnings";

        inherit buildInputs nativeBuildInputs;

        cargoLock.lockFile = ./Cargo.lock;

        doCheck = true;

        meta = with pkgs.lib; {
          inherit (cargoToml.package) description;
          homepage = cargoToml.package.repository;
          license = with licenses; [ mit ];
        };
      };

      packages.x86_64-linux.default = self.packages.x86_64-linux.${cargoToml.package.name};

      checks.x86_64-linux = {
        format = pkgs.runCommand "format"
          {
            inherit nativeBuildInputs;
            buildInputs = with pkgs; [ rustfmt cargo ] ++ buildInputs;
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
