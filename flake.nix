{
  description = "Unlock the flash on STM32WL microcontrollers";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      nativeBuildInputs = with pkgs; [ pkg-config ];
      buildInputs = with pkgs; [ libusb1 udev ];
      cargoToml = (builtins.fromTOML (builtins.readFile ./Cargo.toml));
    in
    {
      devShell.x86_64-linux = pkgs.mkShell {
        buildInputs = buildInputs ++ nativeBuildInputs;
      };

      packages.x86_64-linux.${cargoToml.package.name} = pkgs.rustPlatform.buildRustPackage {
        pname = cargoToml.package.name;
        version = cargoToml.package.version;

        src = ./.;

        RUSTFLAGS = "-D warnings";

        inherit buildInputs nativeBuildInputs;

        cargoLock.lockFile = ./Cargo.lock;

        doCheck = true;

        meta = with pkgs.lib; {
          description = cargoToml.package.description;
          homepage = cargoToml.package.repository;
          license = with licenses; [ mit ];
        };
      };

      defaultPackage.x86_64-linux = self.packages.x86_64-linux.${cargoToml.package.name};

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
