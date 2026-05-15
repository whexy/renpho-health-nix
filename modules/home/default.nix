# Home-manager module: services.renpho-health
#
# Manages a systemd user timer that refreshes a JSON cache of recent Renpho
# scale measurements. On Darwin this module is a true no-op (the entire
# `config` block is gated on isLinux), so the same `imports` list can be
# shared across mixed Linux/Darwin fleets.
#
# Blueprint exposes this as `homeModules.default` (filename `default.nix`
# inside `modules/home/`). The outer function-form takes `flake` so the
# module can resolve its sibling CLI package against the consumer's
# system, regardless of where the module is imported from.
{ flake, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.renpho-health;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.services.renpho-health = {
    enable = lib.mkEnableOption "Renpho scale data refresh (Linux user service)";

    package = lib.mkOption {
      type = lib.types.package;
      default = flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "renpho-health.packages.\${system}.default";
      description = "The renpho-health CLI package.";
    };

    credsFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression "config.age.secrets.renpho-creds.path";
      description = ''
        Path to a KEY=VALUE file containing `RENPHO_EMAIL=` and
        `RENPHO_PASSWORD=` lines. Typically pointed at an agenix or
        sops-nix decrypted secret.
      '';
    };

    cachePath = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/renpho/data.json";
      defaultText = lib.literalExpression ''"\${config.xdg.stateHome}/renpho/data.json"'';
      description = "Path to the JSON cache written by the refresh service.";
    };

    count = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "How many of the most recent measurements to retain in the cache.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = "systemd `OnUnitActiveSec=` value for the refresh timer.";
    };

    onBoot = lib.mkOption {
      type = lib.types.str;
      default = "2min";
      description = "systemd `OnBootSec=` value: delay before the first refresh after login.";
    };
  };

  # Strictly Linux. Darwin imports become inert.
  config = lib.mkIf (cfg.enable && isLinux) {
    home.packages = [ cfg.package ];

    systemd.user.services.renpho-health-refresh = {
      Unit = {
        Description = "Refresh Renpho health data cache";
        Documentation = [ "https://github.com/whexy/renpho-health" ];
      };
      Service = {
        Type = "oneshot";
        # Atomic write in the CLI keeps the prior cache intact on failure.
        # No Restart= here: the timer will retry on the next cycle.
        ExecStart = lib.escapeShellArgs [
          (lib.getExe cfg.package)
          "refresh"
          "--out"
          cfg.cachePath
          "--count"
          (toString cfg.count)
          "--creds-file"
          (toString cfg.credsFile)
        ];
      };
    };

    systemd.user.timers.renpho-health-refresh = {
      Unit.Description = "Periodic Renpho health refresh";
      Timer = {
        OnBootSec = cfg.onBoot;
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
