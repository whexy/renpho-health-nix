# Build the upstream `renpho` Python package from the `renpho-api`
# flake input (which has no flake.nix of its own — flake = false).
{
  pkgs,
  inputs,
  ...
}:

pkgs.python3Packages.buildPythonPackage {
  # The name and version in upstream's pyproject.toml. nixpkgs' metadata check
  # fails the build when the derivation's differ from the built package's.
  pname = "renpho-api";
  version = "0.1.0";
  pyproject = true;
  src = inputs.renpho-api;

  # Renpho's login endpoint answers code=-114 unless the request carries an
  # appVersion header, and upstream only sends it once a token exists.
  # Drop once danvaneijck/renpho-api#12 is fixed.
  postPatch = ''
    substituteInPlace renpho/client.py \
      --replace-fail 'headers: dict[str, str] = {}' \
                     'headers: dict[str, str] = {"appVersion": APP_VERSION, "platform": PLATFORM}'
  '';

  build-system = with pkgs.python3Packages; [ setuptools ];

  dependencies = with pkgs.python3Packages; [
    requests
    pycryptodome
  ];

  # Upstream tests hit the network; skip.
  doCheck = false;

  pythonImportsCheck = [ "renpho" ];

  meta = {
    description = "Unofficial Python client for the Renpho Health API";
    homepage = "https://github.com/danvaneijck/renpho-api";
    license = pkgs.lib.licenses.mit;
  };
}
