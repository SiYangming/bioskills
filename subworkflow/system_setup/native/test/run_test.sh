#!/usr/bin/env bash
# 仅语法检查（不改系统）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
for os in centos6 centos8; do
  for s in modify_system_config_files system_software_installation; do
    f="$NATIVE/$os/$s.sh"
    test -f "$f"
    bash -n "$f"
    echo "OK bash -n $os/$s.sh"
  done
done
