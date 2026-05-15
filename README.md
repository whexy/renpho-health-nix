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
| `latest [--cache PATH \| --creds-file PATH] [--debounce day\|none]` | Print the most recent (day-debounced) measurement as JSON. |
| `recent --count K [--format json\|text] [--cache PATH \| --creds-file PATH] [--debounce day\|none]` | Print K most recent measurements. `json` (default) is unchanged; `text` emits aligned one-line-per-record rows. |
| `refresh --out PATH [--count K] [--creds-file PATH]` | Atomically write JSON cache. Always writes raw records (no debounce). Used by the systemd timer. |
| `waybar --cache PATH [--format weight-arrow\|weight-bmi\|weight] [--summary-count K] [--debounce day\|none]` | Read cache and emit one line of waybar custom-module JSON. Tooltip contains the K most recent (debounced) records as a pango-marked-up table. Never touches the network; never errors out. |

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
| `summaryCount` | `5` | How many recent (day-debounced) records to show in the hover tooltip. |

Hovering the pill reveals a tooltip with the most recent measurements as
a small attached window (same UX as the clock's calendar tooltip):

```
2026-05-15   102.2kg  BMI 30.9  BF 26.7%  ▲2.1
2026-04-29   100.1kg  BMI 30.2  BF 25.7%  ▼0.6
2026-04-21   100.7kg  BMI 30.4  BF 26.0%  ▼1.1
2026-04-20   101.8kg  BMI 30.7  BF 26.5%  ▲1.4
2026-03-26   100.4kg  BMI 30.3  BF 25.9%    ─
```

The tooltip is wrapped in `<tt>` (pango monospace) so columns stay aligned
regardless of your tooltip font. Trend arrow shows the delta vs. the
next-older row.

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
