{ pkgs, perSystem, ... }:

pkgs.mkShell {
  packages = [
    perSystem.self.default
    pkgs.python3
    pkgs.ruff
    pkgs.nixfmt-rfc-style
  ];
}
