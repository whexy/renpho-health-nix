"""renpho-health CLI.

Subcommands:
  latest                  Print the most recent measurement as JSON.
  recent --count K        Print K most recent measurements (json or text).
  refresh --out PATH      Fetch and atomically write a JSON cache.

Credentials (for `latest` / `recent` / `refresh`):
  --creds-file PATH    KEY=VALUE file with RENPHO_EMAIL and RENPHO_PASSWORD
  $RENPHO_CREDS_FILE   same, as env var
  $RENPHO_EMAIL + $RENPHO_PASSWORD   direct env vars

Debouncing: by default (`--debounce day`) records taken on the same
calendar day are collapsed to a single daily entry whose numeric fields
are the mean of that day's raw records (zero-valued fields are excluded
from the mean as Renpho stores 0 for "not measured"). Pass
`--debounce none` to keep raw records.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

# Numeric fields whose mean is taken when collapsing same-day records.
# Excluded: identifiers, flags, raw timestamps, and one-off measurements
# like resistance values that don't average meaningfully.
_AVG_NUMERIC_FIELDS = (
    "weight",
    "bmi",
    "bodyfat",
    "muscle",
    "water",
    "bone",
    "bmr",
    "visfat",
    "subfat",
    "protein",
    "fatFreeWeight",
    "sinew",
    "bodyage",
    "heartRate",
    "cardiacIndex",
)


# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------


def _parse_creds_file(path: Path) -> dict[str, str]:
    """Parse a KEY=VALUE file (agenix-style)."""
    out: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def _load_credentials(creds_file: str | None) -> tuple[str, str]:
    """Resolve email/password from --creds-file, env file path, or env vars."""
    path = creds_file or os.environ.get("RENPHO_CREDS_FILE")
    if path:
        creds = _parse_creds_file(Path(path))
        email = creds.get("RENPHO_EMAIL")
        password = creds.get("RENPHO_PASSWORD")
    else:
        email = os.environ.get("RENPHO_EMAIL")
        password = os.environ.get("RENPHO_PASSWORD")

    if not email or not password:
        raise SystemExit(
            "Missing credentials. Provide --creds-file (KEY=VALUE format with "
            "RENPHO_EMAIL/RENPHO_PASSWORD), or set $RENPHO_CREDS_FILE, or "
            "export $RENPHO_EMAIL and $RENPHO_PASSWORD."
        )
    return email, password


# ---------------------------------------------------------------------------
# Network fetch
# ---------------------------------------------------------------------------


def _fetch_measurements(email: str, password: str) -> list[dict]:
    """Log into Renpho and return all measurements sorted newest-first."""
    # Imported lazily so cache-only CLI queries do not load the network client.
    from renpho import RenphoAPIError, RenphoClient  # type: ignore

    client = RenphoClient(email, password)
    try:
        return client.get_all_measurements()
    except RenphoAPIError as e:
        raise SystemExit(f"Renpho API error: {e}") from e


# ---------------------------------------------------------------------------
# Cache I/O
# ---------------------------------------------------------------------------


def _read_cache(cache_path: Path) -> list[dict] | None:
    try:
        with cache_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, list) else None


def _atomic_write_json(path: Path, data: object) -> None:
    """Write JSON atomically to `path` (same filesystem)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=path.name + ".",
        suffix=".tmp",
        dir=str(path.parent),
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, sort_keys=True)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


# ---------------------------------------------------------------------------
# Same-day debounce
# ---------------------------------------------------------------------------


def _day_key(record: dict) -> str:
    """Return a YYYY-MM-DD key for grouping records by local date.

    Prefers `localCreatedAt` (the API's already-localized timestamp).
    Falls back to deriving a date from the raw UTC `timeStamp`.
    """
    local = record.get("localCreatedAt")
    if isinstance(local, str) and len(local) >= 10:
        # Format from the API: "YYYY-MM-DD HH:MM:SS"
        return local[:10]
    ts = record.get("timeStamp")
    if isinstance(ts, (int, float)) and ts > 0:
        return datetime.fromtimestamp(int(ts), tz=timezone.utc).strftime("%Y-%m-%d")
    return ""  # ungroupable; treated as its own bucket


def _collapse_same_day(records: list[dict]) -> list[dict]:
    """Merge same-day records into a single entry per day (mean of numerics).

    Input must be newest-first. Output is newest-first.

    For each day group:
      - Numeric fields in _AVG_NUMERIC_FIELDS are averaged across records
        where the value is present and non-zero.
      - All other fields are taken from the newest record in the group.
      - `localCreatedAt` is rewritten to the day key (YYYY-MM-DD) for
        clean display.
      - `timeStamp` retains the newest record's value so downstream
        chronological ordering and delta computations still work.
    """
    if not records:
        return []

    # Bucket by day, preserving newest-first order within each bucket.
    order: list[str] = []
    buckets: dict[str, list[dict]] = {}
    for r in records:
        key = _day_key(r)
        if key not in buckets:
            buckets[key] = []
            order.append(key)
        buckets[key].append(r)

    merged: list[dict] = []
    for key in order:
        group = buckets[key]
        if not group:
            continue
        if len(group) == 1:
            r = dict(group[0])
            if key:
                r["localCreatedAt"] = key
            merged.append(r)
            continue
        # Start from the newest record (group[0]) and overwrite the
        # numeric fields with the group mean.
        out = dict(group[0])
        for field in _AVG_NUMERIC_FIELDS:
            values: list[float] = []
            for r in group:
                v = r.get(field)
                if isinstance(v, (int, float)) and v != 0:
                    values.append(float(v))
            if values:
                out[field] = sum(values) / len(values)
        if key:
            out["localCreatedAt"] = key
        merged.append(out)

    return merged


def _apply_debounce(records: list[dict], mode: str) -> list[dict]:
    if mode == "day":
        return _collapse_same_day(records)
    return records


# ---------------------------------------------------------------------------
# Subcommand: latest / recent
# ---------------------------------------------------------------------------


def _get_measurements_source(args: argparse.Namespace) -> list[dict]:
    """Read from --cache if given, otherwise fetch fresh from the API.

    Applies `--debounce` if the subcommand defines it (default `day`).
    """
    if getattr(args, "cache", None):
        data = _read_cache(Path(args.cache))
        if data is None:
            raise SystemExit(f"Cache not found or unreadable: {args.cache}")
    else:
        email, password = _load_credentials(getattr(args, "creds_file", None))
        data = _fetch_measurements(email, password)

    mode = getattr(args, "debounce", "day")
    return _apply_debounce(data, mode)


def cmd_latest(args: argparse.Namespace) -> int:
    data = _get_measurements_source(args)
    if not data:
        print("{}", file=sys.stdout)
        return 1
    print(json.dumps(data[0], indent=2, sort_keys=True))
    return 0


# ----- recent: formatters -----

# Width plan for the aligned text/notify rows:
#   date     YYYY-MM-DD     10
#   weight   "{:>6.1f}kg"   ~ 8 ("100.1kg" = 7, " 99.5kg" = 7)
#   bmi      "BMI {:>4.1f}" 8
#   bf       "BF {:>4.1f}%" 8
#   trend    "▼0.3" or "─"  ~ 4


def _fmt_row(rec: dict, prev: dict | None) -> str:
    date = (rec.get("localCreatedAt") or "")[:10] or "----------"
    w = rec.get("weight")
    weight = f"{w:>6.1f}kg" if isinstance(w, (int, float)) else "  ?  kg"

    bmi = rec.get("bmi")
    bmi_s = f"BMI {bmi:>4.1f}" if isinstance(bmi, (int, float)) and bmi else "BMI   ? "

    bf = rec.get("bodyfat")
    bf_s = f"BF {bf:>4.1f}%" if isinstance(bf, (int, float)) and bf else "BF   ? %"

    trend = "  ─ "
    if (
        prev is not None
        and isinstance(w, (int, float))
        and isinstance(prev.get("weight"), (int, float))
    ):
        delta = w - prev["weight"]
        if abs(delta) < 0.05:
            trend = "  ─ "
        elif delta < 0:
            trend = f"\u25bc{abs(delta):>3.1f}"
        else:
            trend = f"\u25b2{abs(delta):>3.1f}"

    return f"{date}  {weight}  {bmi_s}  {bf_s}  {trend}"


def _render_text(records: list[dict]) -> str:
    if not records:
        return "no data yet"
    lines: list[str] = []
    for i, rec in enumerate(records):
        prev = records[i + 1] if i + 1 < len(records) else None
        lines.append(_fmt_row(rec, prev))
    return "\n".join(lines)


def cmd_recent(args: argparse.Namespace) -> int:
    data = _get_measurements_source(args)
    sliced = data[: args.count]

    if args.format == "json":
        print(json.dumps(sliced, indent=2, sort_keys=True))
        return 0

    print(_render_text(sliced))
    return 0


# ---------------------------------------------------------------------------
# Subcommand: refresh
# ---------------------------------------------------------------------------


def cmd_refresh(args: argparse.Namespace) -> int:
    """Fetch and write cache atomically. Failure leaves prior cache intact."""
    email, password = _load_credentials(args.creds_file)
    data = _fetch_measurements(email, password)
    # Keep only the K most recent to bound cache size.
    sliced = data[: args.count]
    out_path = Path(args.out)
    _atomic_write_json(out_path, sliced)
    print(
        f"Wrote {len(sliced)} measurement(s) to {out_path}",
        file=sys.stderr,
    )
    return 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="renpho-health",
        description="Fetch and query Renpho scale data.",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    def _add_creds_args(sp):
        sp.add_argument("--creds-file", help="KEY=VALUE creds file")
        sp.add_argument(
            "--cache",
            help="Read from this JSON cache instead of network",
        )

    def _add_debounce(sp):
        sp.add_argument(
            "--debounce",
            choices=["day", "none"],
            default="day",
            help="Collapse same-day records to a daily mean (default: day).",
        )

    sp = sub.add_parser("latest", help="Print the most recent measurement.")
    _add_creds_args(sp)
    _add_debounce(sp)
    sp.set_defaults(func=cmd_latest)

    sp = sub.add_parser("recent", help="Print K most recent measurements.")
    sp.add_argument("--count", "-k", type=int, default=10)
    sp.add_argument(
        "--format",
        choices=["json", "text"],
        default="json",
        help="Output format. `text` emits aligned multi-line rows.",
    )
    _add_creds_args(sp)
    _add_debounce(sp)
    sp.set_defaults(func=cmd_recent)

    sp = sub.add_parser("refresh", help="Fetch and atomically write cache.")
    sp.add_argument("--out", required=True, help="Output path (atomic write).")
    sp.add_argument("--count", "-k", type=int, default=30, help="Max records to keep.")
    sp.add_argument("--creds-file", help="KEY=VALUE creds file")
    sp.set_defaults(func=cmd_refresh)

    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        return args.func(args)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
