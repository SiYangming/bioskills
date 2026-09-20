#!/usr/bin/env bash
# system_setup 编排器最小回归（仅 dry-run / 自省，不改系统）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试占位"
python3 "$HERE/generate_data.py" "$WORK"

echo "==> [2/4] --list-stages"
out="$(python3 "$NATIVE/main.py" --list-stages)"
echo "$out" | grep -q '"canonical": "system_setup"'
echo "$out" | grep -q 'configure_repos'
echo "$out" | grep -q 'prepare_soft_dirs'
echo "$out" | grep -q 'setup_mariadb'
echo "  OK: list-stages"

echo "==> [3/4] dry-run（默认）"
out="$(python3 "$NATIVE/main.py" \
  --train-user demo --train-home "$WORK/home/demo" \
  --bio-soft-root "$WORK/opt/biosoft" \
  --sys-soft-root "$WORK/opt/sysoft" \
  --software-cache "$WORK/software" \
  --mysql-datadir "$WORK/mysql" \
  --stages prepare_soft_dirs,configure_user_env)"
echo "$out" | grep -q '\[prepare_soft_dirs\]:'
echo "$out" | grep -q '\[configure_user_env\]:'
echo "$out" | grep -q -- "--dry-run"
echo "$out" | grep -q "$WORK/opt/biosoft"
echo "  OK: dry-run 参数化路径"

echo "==> [4/4] 未开 sysoft 时跳过；--real 无 --confirm-root 应失败"
out="$(python3 "$NATIVE/main.py" --stages install_sysoft_runtimes)"
echo "$out" | grep -q 'SKIP'
set +e
python3 "$NATIVE/main.py" --real --stages prepare_soft_dirs >/tmp/system_setup_real.out 2>/tmp/system_setup_real.err
rc=$?
set -e
[[ "$rc" -ne 0 ]]
grep -q 'confirm-root' /tmp/system_setup_real.err
echo "  OK: 安全闸门"

echo "ALL PASS: system_setup dry-run / list-stages / confirm-root"
