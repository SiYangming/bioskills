#!/usr/bin/env python3
"""Prepare Primer3 settings from p3_settings.txt template.

Strips comments/blank lines; rewrites or drops PRIMER_THERMODYNAMIC_PARAMETERS_PATH
so primer3_core does not fail on a missing teaching-machine path.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_DEFAULT_TEMPLATE = _HERE / "p3_settings.txt"


def resolve_primer3_config(primer3_core: str | None = None) -> Path | None:
    cands: list[Path] = []
    bin_path = primer3_core or shutil.which("primer3_core")
    if bin_path:
        b = Path(bin_path).resolve()
        cands += [
            b.parent / "primer3_config",
            b.parent.parent / "share" / "primer3" / "primer3_config",
            b.parent.parent / "share" / "primer3_config",
            b.parent.parent / "primer3_config",
        ]
    for env in ("CONDA_PREFIX", "PREFIX"):
        prefix = os.environ.get(env)
        if prefix:
            cands += [
                Path(prefix) / "share" / "primer3" / "primer3_config",
                Path(prefix) / "share" / "primer3_config",
            ]
    cands += [
        Path("/usr/local/share/primer3/primer3_config"),
        Path("/usr/share/primer3/primer3_config"),
    ]
    for cand in cands:
        if cand.is_dir():
            return cand
    return None


def prepare_p3_settings(
    template: str | Path,
    out_path: str | Path,
    thermo_dir: str | Path | None = None,
) -> dict:
    src = Path(template)
    if not src.is_file():
        raise FileNotFoundError(f"template not found: {src}")

    lines: list[str] = []
    for raw in src.read_text(encoding="utf-8").splitlines():
        line = re.sub(r"\s*#.*$", "", raw)
        if not line.strip():
            continue
        if line.startswith("P3_FILE_ID") and lines and lines[-1].strip():
            lines.append("")
        lines.append(line)

    out_lines: list[str] = []
    thermo_state = "not-present"
    for line in lines:
        if line.startswith("PRIMER_THERMODYNAMIC_PARAMETERS_PATH"):
            if thermo_dir:
                out_lines.append(
                    "PRIMER_THERMODYNAMIC_PARAMETERS_PATH="
                    f"{Path(thermo_dir).as_posix().rstrip('/')}/"
                )
                thermo_state = "set"
            else:
                thermo_state = "dropped"
            continue
        out_lines.append(line)

    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    return {
        "path": str(out),
        "lines": len(out_lines),
        "thermodynamic_path": thermo_state,
        "thermodynamic_dir": str(thermo_dir) if thermo_state == "set" else None,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("-i", "--template", type=Path, default=_DEFAULT_TEMPLATE)
    p.add_argument("-o", "--output", type=Path, required=True)
    p.add_argument(
        "--thermo-dir",
        type=Path,
        default=None,
        help="primer3_config dir; default: auto-detect or drop PATH line",
    )
    p.add_argument(
        "--primer3-core",
        default=None,
        help="primer3_core binary used to locate primer3_config",
    )
    args = p.parse_args(argv)

    thermo = args.thermo_dir
    if thermo is None:
        thermo = resolve_primer3_config(args.primer3_core)

    info = prepare_p3_settings(args.template, args.output, thermo)
    print(
        f"[OK] wrote {info['path']} ({info['lines']} lines); "
        f"thermodynamic_path={info['thermodynamic_path']}"
        + (f" ({info['thermodynamic_dir']})" if info["thermodynamic_dir"] else "")
    )
    if info["thermodynamic_path"] == "dropped":
        print(
            "[WARN] primer3_config not found; PATH line removed "
            "(primer3_core uses built-in defaults)",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
