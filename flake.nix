{
  description = "Renpho Health: CLI and cache refresh service for Renpho scale data";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    blueprint = {
      url = "github:numtide/blueprint";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Upstream Python library, pulled as plain source (no flake.nix upstream).
    # We build our own derivation from it in packages/renpho-lib.nix.
    renpho-api = {
      url = "github:danvaneijck/renpho-api";
      flake = false;
    };
  };

  outputs = inputs: inputs.blueprint { inherit inputs; };
}
