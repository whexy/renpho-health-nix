# Home-manager module: services.renpho-health
#
# Manages a background job that refreshes a JSON cache of recent Renpho
# scale measurements: a systemd user timer on Linux and a launchd agent on
# Darwin.
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
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  refreshScript = pkgs.writeShellScript "renpho-health-refresh" ''
    exec ${lib.getExe cfg.package} refresh \
      --out ${lib.escapeShellArg cfg.cachePath} \
      --count ${toString cfg.count} \
      --creds-file "${cfg.credsFile}"
  '';
in
{
  options.services.renpho-health = {
    enable = lib.mkEnableOption "Renpho scale data refresh service";

    package = lib.mkOption {
      type = lib.types.package;
      default = flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "renpho-health.packages.\${system}.default";
      description = "The renpho-health CLI package.";
    };

    credsFile = lib.mkOption {
      type = lib.types.str;
      example = lib.literalExpression "config.age.secrets.renpho-creds.path";
      description = ''
        Path to a KEY=VALUE file containing `RENPHO_EMAIL=` and
        `RENPHO_PASSWORD=` lines. Typically pointed at an agenix or
        sops-nix decrypted secret.

        Type is `str` (not `path`) because agenix on home-manager can produce
        runtime-expanded values like `''${XDG_RUNTIME_DIR}/agenix/<name>`,
        which are not absolute paths at eval time. The Linux service lets
        systemd expand that value; the Darwin launchd wrapper lets the shell
        expand it.
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
      description = "systemd `OnUnitActiveSec=` value for the Linux refresh timer.";
    };

    onBoot = lib.mkOption {
      type = lib.types.str;
      default = "2min";
      description = "systemd `OnBootSec=` value: delay before the first Linux refresh after login.";
    };

    darwinInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3600;
      description = "Seconds between refreshes for the Darwin launchd agent.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.renpho-health-refresh = lib.mkIf isLinux {
      Unit = {
        Description = "Refresh Renpho health data cache";
        Documentation = [ "https://github.com/whexy/renpho-health-nix" ];
      };
      Service = {
        Type = "oneshot";
        # ExecStart remains a plain string so systemd can expand agenix-HM
        # runtime paths such as `${XDG_RUNTIME_DIR}/agenix/renpho-creds`.
        ExecStart = "${lib.getExe cfg.package} refresh --out ${cfg.cachePath} --count ${toString cfg.count} --creds-file ${cfg.credsFile}";
      };
    };

    systemd.user.timers.renpho-health-refresh = lib.mkIf isLinux {
      Unit.Description = "Periodic Renpho health refresh";
      Timer = {
        OnBootSec = cfg.onBoot;
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    launchd.agents.renpho-health-refresh = lib.mkIf isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${refreshScript}" ];
        RunAtLoad = true;
        StartInterval = cfg.darwinInterval;
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/renpho-health-refresh.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/renpho-health-refresh.err.log";
      };
    };
  };
}
