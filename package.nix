# Default package: the `renpho-health` CLI.
#
# Blueprint exposes this as `packages.<system>.default` thanks to its
# top-level `package.nix` convention.
{
  pkgs,
  perSystem,
  ...
}:

pkgs.python3Packages.buildPythonApplication {
  pname = "renpho-health";
  version = "0.1.0";
  pyproject = true;
  src = ./.;

  build-system = with pkgs.python3Packages; [ setuptools ];

  dependencies = [
    # Built from the renpho-api flake input — see packages/renpho-lib.nix.
    perSystem.self.renpho-lib
  ];

  # No tests yet.
  doCheck = false;

  pythonImportsCheck = [ "renpho_health" ];

  meta = {
    description = "CLI for fetching and querying Renpho scale data";
    homepage = "https://github.com/whexy/renpho-health-nix";
    license = pkgs.lib.licenses.mit;
    mainProgram = "renpho-health";
  };
}
