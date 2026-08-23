# renpho-health

CLI + home-manager module for fetching [Renpho](https://renpho.com/) smart-scale
data. Built on top of the unofficial
[`renpho-api`](https://github.com/danvaneijck/renpho-api) Python library and
exposed as a Nix flake.

- **CLI** — `renpho-health {latest,recent,refresh}` for ad-hoc use and
  scripting.
- **Home-manager module** — runs a user-level systemd timer on Linux or a
  launchd agent on Darwin to refresh a JSON cache hourly.

Status-bar rendering intentionally lives in the consumer's panel
configuration rather than this core data/query project.

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
| `latest [--cache PATH \| --creds-file PATH] [--debounce day\|none]` | Print the most recent (day-debounced) measurement as JSON. |
| `recent --count K [--format json\|text] [--cache PATH \| --creds-file PATH] [--debounce day\|none]` | Print K most recent measurements. `json` (default) is unchanged; `text` emits aligned one-line-per-record rows. |
| `refresh --out PATH [--count K] [--creds-file PATH]` | Atomically write JSON cache. Always writes raw records (no debounce). Used by the systemd timer. |

### Same-day debounce

By default (`--debounce day`), records taken on the same calendar day are
collapsed into a single daily entry whose numeric fields (weight, BMI,
body fat, muscle, water, …) are the **mean** of that day's raw records.
Zero-valued fields are excluded from the mean since Renpho stores `0` for
"not measured". Pass `--debounce none` to inspect raw records.

The cache file itself is **always raw** — debouncing happens only at read
time. This keeps the cache faithful and lets us change the grouping logic
without re-fetching.

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
  url = "github:whexy/renpho-health-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Then in your home-manager config:

```nix
{
  imports = [
    inputs.renpho-health.homeModules.default
  ];

  services.renpho-health = {
    enable    = true;
    credsFile = config.age.secrets.renpho-creds.path;  # or any KEY=VALUE file
  };
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
| `interval` | `"1h"` | systemd `OnUnitActiveSec` on Linux. |
| `onBoot` | `"2min"` | systemd `OnBootSec` on Linux. |
| `darwinInterval` | `3600` | launchd refresh interval in seconds on Darwin. |

Failure handling: a failed refresh leaves the previous cache untouched.

## Hacking

```sh
nix develop                                    # devshell with python + ruff
nix build .#renpho-lib .#default               # build both packages
nix run . -- --help
```

## License

MIT.
