{ lib
, rustPlatform
, pkg-config
, libusb1
, udev
}:

let
  cargoToml = lib.importTOML ./Cargo.toml;
in
rustPlatform.buildRustPackage {
  pname = cargoToml.package.name;
  inherit (cargoToml.package) version;

  src = ./.;

  RUSTFLAGS = "-D warnings";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    libusb1
    udev
  ];

  cargoLock.lockFile = ./Cargo.lock;

  doCheck = true;

  meta = with lib; {
    inherit (cargoToml.package) description;
    homepage = cargoToml.package.repository;
    license = with licenses; [ mit ];
  };
}
