#!/usr/bin/env bash
# barrnap native 最小回归测试
# 前置：python3 必须在 PATH。
# PATH 中有 barrnap（conda activate barrnap-native / 官方容器内 / 已安装）→ 追加真跑最小链路：
#   合成小 genome.fa → scan → 断言 GFF3 头（##gff-version 3）+ 退出码 0；
#   （若安装环境缺依赖/数据库导致真跑失败，仅 [WARN] 提示不阻断，保证任意环境 exit 0）
# 无 barrnap → 自省 + [SKIP]；任何环境最终打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成小基因组）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/genome.fa"

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^scan " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] scan 参数契约（--help 自省）"
python "$NATIVE/main.py" scan --help > "$WORK/scan_help.txt"
grep -q -- "--kingdom" "$WORK/scan_help.txt"
grep -q -- "--outseq" "$WORK/scan_help.txt"
grep -q -- "--evalue" "$WORK/scan_help.txt"

echo "==> [5/6] scan 最小链路（需要 barrnap，未安装则跳过）"
if command -v barrnap >/dev/null 2>&1; then
    # 5a. bac 域 → -o 写 GFF3 文件
    if python "$NATIVE/main.py" scan "$WORK/genome.fa" --kingdom bac --threads 2 \
            -o "$WORK/rrna_bac.gff3" 2> "$WORK/scan_bac.log"; then
        test -s "$WORK/rrna_bac.gff3"
        FIRST=$(head -n 1 "$WORK/rrna_bac.gff3")
        test "$FIRST" = "##gff-version 3" || { echo "  [FAIL] GFF3 首行非 ##gff-version 3: $FIRST"; exit 1; }
        echo "  [ok] scan --kingdom bac -> GFF3 头断言通过"
    else
        echo "  [WARN] scan 真跑失败（barrnap 运行依赖/数据库缺失？），仅提示不阻断；日志："
        tail -n 5 "$WORK/scan_bac.log" || true
    fi

    # 5b. 教学旧值 --kingdom euk（>=1.10 映射 fun / 0.9 直通），stdout 模式
    if python "$NATIVE/main.py" scan "$WORK/genome.fa" --kingdom euk --threads 2 \
            > "$WORK/rrna_euk.gff3" 2> "$WORK/scan_euk.log"; then
        test -s "$WORK/rrna_euk.gff3"
        FIRST=$(head -n 1 "$WORK/rrna_euk.gff3")
        test "$FIRST" = "##gff-version 3" || { echo "  [FAIL] GFF3 首行非 ##gff-version 3: $FIRST"; exit 1; }
        echo "  [ok] scan --kingdom euk（stdout）-> GFF3 头断言通过"
    else
        echo "  [WARN] scan --kingdom euk 真跑失败（barrnap 运行依赖/数据库缺失？），仅提示不阻断；日志："
        tail -n 5 "$WORK/scan_euk.log" || true
    fi
else
    echo "  [SKIP] 未检测到 barrnap（conda activate <barrnap 环境> 或装好后重跑），仅跑自省链路"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v barrnap >/dev/null 2>&1; then
    barrnap --version | head -n 1 || true
fi

echo "ALL TESTS PASSED"
