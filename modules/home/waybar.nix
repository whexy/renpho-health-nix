# Home-manager module: programs.waybar.renpho
#
# Opt-in waybar pill that reads the cache produced by services.renpho-health.
# Imported separately from the main module (as `homeModules.waybar`) so that
# users who don't run waybar (e.g. tty-only, hyprland status bar, etc.) can
# still consume the timer + CLI.
{ flake, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.waybar.renpho;
  hcfg = config.services.renpho-health;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.programs.waybar.renpho = {
    enable = lib.mkEnableOption "Renpho weight pill for waybar";

    position = lib.mkOption {
      type = lib.types.enum [
        "left"
        "center"
        "right"
      ];
      default = "right";
      description = "Which `modules-<position>` list to append the pill to.";
    };

    interval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = ''
        Seconds between cache polls. The waybar subcommand only reads the
        local JSON cache, so this can be aggressive without cost. The cache
        itself is refreshed independently on the `services.renpho-health`
        timer.
      '';
    };

    format = lib.mkOption {
      type = lib.types.enum [
        "weight-arrow"
        "weight-bmi"
        "weight"
      ];
      default = "weight-arrow";
      description = "Pill text style.";
    };

    summaryCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = ''
        How many recent (day-debounced) records to show in the
        click-to-show notification.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && isLinux) {
    assertions = [
      {
        assertion = hcfg.enable;
        message = "programs.waybar.renpho.enable requires services.renpho-health.enable = true";
      }
    ];

    programs.waybar.settings.mainBar = {
      "modules-${cfg.position}" = lib.mkAfter [ "custom/renpho" ];

      "custom/renpho" = {
        exec = "${lib.getExe hcfg.package} waybar --cache ${hcfg.cachePath} --format ${cfg.format}";
        interval = cfg.interval;
        return-type = "json";
        format = "{}";
        tooltip = true;
        # Show K most recent (day-debounced) measurements as a notification.
        # `--format notify` emits aligned text rows; notify-send adds the
        # title. -t 10000 keeps it on screen long enough to read 5+ lines.
        on-click = "${lib.getExe hcfg.package} recent --cache ${hcfg.cachePath} --count ${toString cfg.summaryCount} --format notify | ${pkgs.libnotify}/bin/notify-send -t 10000 'Renpho — recent measurements' -";
      };
    };

    # Gruvbox-inspired pill; matches the existing waybar.nix palette.
    programs.waybar.style = lib.mkAfter ''
      #custom-renpho {
        padding: 2px 10px;
        margin: 3px 2px;
        border-radius: 10px;
        background-color: #3c3836;
        color: #d3869b;
        transition: all 0.3s ease;
      }
      #custom-renpho.down  { color: #b8bb26; }
      #custom-renpho.up    { color: #fb4934; }
      #custom-renpho.stale { color: #928374; }
      #custom-renpho:hover {
        background-color: #d3869b;
        color: #282828;
      }
    '';
  };
}
