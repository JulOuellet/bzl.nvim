{
  description = "Bazel multilingual playground (FHS shell for NixOS toolchains)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/d407951447dcd00442e97087bf374aad70c04cea";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    packages = p: [p.bazel_8 p.gcc p.git p.curl p.gnumake p.neovim];
  in {
    packages = nixpkgs.lib.genAttrs systems (system: let
      pkgs = import nixpkgs {inherit system;};
      launcher = pkgs.writeShellScript "bzl-multilang-launch" ''
        if [ "$#" -gt 0 ]; then
          exec "$@"
        fi
        exec bash
      '';
    in {
      default =
        if pkgs.stdenv.isLinux
        then
          pkgs.buildFHSEnv {
            name = "bzl-multilang";
            targetPkgs = p: packages p ++ [p.zlib p.openssl];
            runScript = launcher;
          }
        else
          pkgs.writeShellApplication {
            name = "bzl-multilang";
            runtimeInputs = packages pkgs;
            text = ''exec ${launcher} "$@"'';
          };
    });
    devShells = nixpkgs.lib.genAttrs systems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default =
        if pkgs.stdenv.isLinux
        then self.packages.${system}.default.env
        else
          pkgs.mkShell {
            packages = packages pkgs;
          };
    });
  };
}
