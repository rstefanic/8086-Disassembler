{
  description = "8086 Disassembler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, zig, flake-utils, ... } @ inputs:
    let 
      overlays = [
        (final: prev: {
          zigpkgs = inputs.zig.packages.${prev.system};
          zig = inputs.zig.packages.${prev.system}."0.15.1";
        })
      ];
    in flake-utils.lib.eachDefaultSystem(system:
      let
        pkgs = import nixpkgs { inherit overlays system; };
      in
      {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
              pkgs.zig
              pkgs.nasm
          ];
        };
      }
  );

}
