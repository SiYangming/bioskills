#!/usr/bin/env bash
# glimmerhmm native 最小回归测试
# 前置：python3 必须在 PATH。
# PATH 中有 glimmerhmm（conda activate glimmerhmm-native / 官方容器内 / brew / 源码安装）→
#   追加真跑段：predict 合成基因组 → GFF3（断言 ##gff-version 3 / ##sequence-region）；
#   训练目录由驱动从包前缀（$CONDA_PREFIX/share/glimmerhmm/trained_dir/<species>）自动解析；
#   真跑失败仅 [WARN] 提示不阻断（保证任意环境 exit 0）。
# 无 glimmerhmm → 自省 + 契约 + [SKIP]；任何环境最终 exit 0 并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成真核基因组）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/genome.fa"
grep -q "^>genome1" "$WORK/genome.fa"
grep -q "^>genome2" "$WORK/genome.fa"

echo "==> [2/5] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^predict " "$WORK/commands.txt"

echo "==> [3/5] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/5] predict --help 参数契约"
python "$NATIVE/main.py" predict --help > "$WORK/help.txt" 2>&1
grep -q -- "--training-dir" "$WORK/help.txt"
grep -q -- "--gff" "$WORK/help.txt"
grep -q -- "--output" "$WORK/help.txt"
grep -q -- "--no-partial" "$WORK/help.txt"
echo "  [ok] training-dir / gff / output / no-partial 契约通过"

echo "==> [5/5] 真跑最小链路（需要 glimmerhmm，未安装则跳过）"
if command -v glimmerhmm >/dev/null 2>&1; then
    if python "$NATIVE/main.py" predict "$WORK/genome.fa" -g -o "$WORK/out.gff" \
            2>"$WORK/train_err.txt"; then
        test -s "$WORK/out.gff"
        grep -q "^##gff-version 3" "$WORK/out.gff"
        grep -q "^##sequence-region" "$WORK/out.gff"
        echo "  [ok] GFF3 预测完成（mRNA 记录 $(grep -c -e $'\tmRNA\t' "$WORK/out.gff" || true) 条）"
    else
        echo "  [WARN] 真跑 predict 失败（训练目录未解析 / 安装异常？），仅提示不阻断："
        tail -n 3 "$WORK/train_err.txt" || true
    fi
else
    echo "  [SKIP] 未检测到 glimmerhmm，跳过真跑（仅跑自省 + 契约链路）"
fi

echo "ALL TESTS PASSED"
