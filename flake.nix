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

        # provide `bazel` on PATH via bazelisk, which downloads the
        # version pinned in .bazelversion
        bazel = pkgs.writeShellScriptBin "bazel" ''
          exec ${pkgs.bazelisk}/bin/bazelisk "$@"
        '';
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            bazel
            pkgs.bazelisk
            pkgs.stylua
            pkgs.gnumake
          ];
        };
      }
    );
}
