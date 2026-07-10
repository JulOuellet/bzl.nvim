{
  description = "bzl.nvim development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            # bazel from nixpkgs rather than via bazelisk: bazelisk downloads
            # generic linux binaries, which cannot run on NixOS
            pkgs.bazel_8
            pkgs.stylua
            pkgs.gnumake
          ];
        };
      }
    );
}
