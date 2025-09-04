{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    zls-overlay = {
      # visit https://zigtools.org/zls/install/ to find a compatible version
      url = "github:zigtools/zls/0.15.0";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-overlay.follows = "zig-overlay";
      };
    };
  };

  outputs =
    inputs@{
      flake-parts,
      zig-overlay,
      zls-overlay,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      perSystem =
        { pkgs, system, ... }:
        let
          zig = zig-overlay.packages.${system}."0.15.1";
          zls = zls-overlay.packages.${system}.zls.overrideAttrs (old: {
            nativeBuildInputs = [ zig ];
          });
        in
        {
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = [ zig ];

            buildInputs = [
              pkgs.llvmPackages.libllvm.dev
              pkgs.lld
            ];

            packages = [
              zls
            ];
          };
        };
    };
}
