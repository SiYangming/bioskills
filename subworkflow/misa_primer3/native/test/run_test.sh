#!/usr/bin/env bash
# prepare_p3_settings.py 静态自检（不跑 primer3/misa）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> help"
python3 "$NATIVE/prepare_p3_settings.py" --help | grep -q -- '--output'

echo "==> prepare (drop thermo path if no primer3_config)"
python3 "$NATIVE/prepare_p3_settings.py" -o "$WORK/p3_settings_file"
grep -q 'PRIMER_NUM_RETURN' "$WORK/p3_settings_file"
! grep -q '/opt/biosoft' "$WORK/p3_settings_file"
echo "OK"
