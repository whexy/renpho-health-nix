# renpho-health

CLI + home-manager module for fetching [Renpho](https://renpho.com/) smart-scale
data. Built on top of the unofficial
[`renpho-api`](https://github.com/danvaneijck/renpho-api) Python library and
exposed as a Nix flake.

Two consumers:

- **CLI** — `renpho-health {latest,recent,refresh,waybar}` for ad-hoc use or
  scripting.
- **Home-manager module** — runs a user-level systemd timer that refreshes a
  JSON cache hourly, plus an optional [waybar](https://github.com/Alexays/Waybar)
  pill that displays weight + trend.

## Quick start (CLI)

```sh
nix run github:whexy/renpho-health -- latest \
  --creds-file <(printf 'RENPHO_EMAIL=you@example.com\nRENPHO_PASSWORD=secret\n')
```

Or with environment variables:

```sh
export RENPHO_EMAIL=you@example.com
export RENPHO_PASSWORD=secret
nix run github:whexy/renpho-health -- recent --count 5
```

### Subcommands

| Command | Description |
| --- | --- |
| `latest [--cache PATH \| --creds-file PATH]` | Print the most recent measurement as JSON. |
| `recent --count K [--cache PATH \| --creds-file PATH]` | Print K most recent measurements as a JSON array. |
| `refresh --out PATH [--count K] [--creds-file PATH]` | Atomically write JSON cache. Used by the systemd timer. |
| `waybar --cache PATH [--format weight-arrow\|weight-bmi\|weight]` | Read cache and emit one line of waybar custom-module JSON. Never touches the network; never errors out. |

### Credentials resolution order

1. `--creds-file PATH` flag (KEY=VALUE format)
2. `$RENPHO_CREDS_FILE` env var (same format)
3. `$RENPHO_EMAIL` + `$RENPHO_PASSWORD` env vars

KEY=VALUE file format:

```ini
RENPHO_EMAIL=you@example.com
RENPHO_PASSWORD=secret
```

## Home-manager integration

Add as a flake input:

```nix
inputs.renpho-health = {
  url = "github:whexy/renpho-health";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Then in your home-manager config:

```nix
{
  imports = [
    inputs.renpho-health.homeModules.default   # timer + cache
    inputs.renpho-health.homeModules.waybar    # waybar pill (optional)
  ];

  services.renpho-health = {
    enable    = true;
    credsFile = config.age.secrets.renpho-creds.path;  # or any KEY=VALUE file
  };

  programs.waybar.renpho.enable = true;
}
```

The agenix secret should decrypt to a file containing
`RENPHO_EMAIL=...` / `RENPHO_PASSWORD=...` (newline-separated).

### `services.renpho-health` options

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `false` | Enable the refresh timer. |
| `package` | `flake.packages.${system}.default` | The CLI package. |
| `credsFile` | _required_ | Path to KEY=VALUE creds file. |
| `cachePath` | `$XDG_STATE_HOME/renpho/data.json` | Where to write the JSON cache. |
| `count` | `30` | Max measurements retained in the cache. |
| `interval` | `"1h"` | systemd `OnUnitActiveSec`. |
| `onBoot` | `"2min"` | systemd `OnBootSec`. |

### `programs.waybar.renpho` options

| Option | Default | Description |
| --- | --- | --- |
| `enable` | `false` | Add the renpho pill to waybar. |
| `position` | `"right"` | Which `modules-<position>` list to append to. |
| `interval` | `300` | Seconds between cache polls (local FS). |
| `format` | `"weight-arrow"` | `weight-arrow`, `weight-bmi`, or `weight`. |

Failure handling: a failed refresh leaves the previous cache untouched. Once
the cache is older than 36 hours the waybar pill is rendered with the
`.stale` class (gray).

### Darwin

The `services.renpho-health` and `programs.waybar.renpho` modules are no-ops
on Darwin: `config = lib.mkIf (cfg.enable && isLinux) {...}`. You can still
use the CLI ad-hoc via `nix run`.

## Hacking

```sh
nix develop                                    # devshell with python + ruff
nix build .#renpho-lib .#default               # build both packages
nix run . -- --help
```

## License

MIT.
