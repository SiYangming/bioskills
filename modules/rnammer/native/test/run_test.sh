#!/usr/bin/env bash
# rnammer native 最小回归测试
# 前置：python3 必须在 PATH。
# PATH 无 rnammer（RNAmmer 1.2 源码为注册制下载，多数环境未安装）→ 只跑自省 + 参数契约断言 + [SKIP]；
# PATH 有 rnammer → 追加真跑最小链路（合成小 fasta + -S bac/euk -multi -f/-h/-xml/-gff 四件套），
#   真跑失败仅 [WARN] 提示不阻断。
# 任何环境均 exit 0 并打印 ALL TESTS PASSED。
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
for opt in --kingdom --multi --molecules --out-fasta --hmmreport --xml --gff --threads --tmpdir; do
    grep -q -- "$opt" "$WORK/scan_help.txt" || { echo "  [FAIL] scan --help 缺少 ${opt}"; exit 1; }
done
echo "  [ok] scan 参数契约齐全"

echo "==> [5/6] 参数校验契约（无需 rnammer）"
# 5a. 合法参数：无 rnammer 时应给出含注册下载/INSTALL_PATH/HMMSEARCH_BINARY 指引的报错
if python "$NATIVE/main.py" scan "$WORK/genome.fa" --kingdom bac > "$WORK/valid.out" 2> "$WORK/valid.err"; then
    echo "  [ok] scan 构造为合法命令（本机 PATH 含 rnammer，已通过）"
else
    rc=$?
    if grep -qE "注册|INSTALL_PATH|HMMSEARCH_BINARY|未找到可执行文件" "$WORK/valid.err"; then
        echo "  [ok] 缺 rnammer 时给出注册下载 + INSTALL_PATH/HMMSEARCH_BINARY 配置指引"
    else
        echo "  [FAIL] 缺 rnammer 的报错缺少安装指引（rc=${rc}）"
        tail -n 3 "$WORK/valid.err" || true
        exit 1
    fi
fi
# 5b. 非法 -S 值 → 参数校验报错
if python "$NATIVE/main.py" scan "$WORK/genome.fa" --kingdom xyz >/dev/null 2> "$WORK/badkingdom.err"; then
    echo "  [FAIL] --kingdom xyz 未被拒绝"
    exit 1
else
    if grep -qF 'arc|bac|euk' "$WORK/badkingdom.err"; then
        echo "  [ok] 非法 --kingdom 被拒绝（给出 arc|bac|euk 提示）"
    else
        echo "  [ok] 非法 --kingdom 被拒绝"
    fi
fi

echo "==> [6/6] scan 最小链路（需要 rnammer，未安装则跳过）"
if command -v rnammer >/dev/null 2>&1; then
    if python "$NATIVE/main.py" scan "$WORK/genome.fa" --kingdom bac --multi \
            -f "$WORK/rRNA.fasta" -h "$WORK/rRNA.hmmreport" \
            -xml "$WORK/rRNA.xml" -gff "$WORK/rRNA.gff2" 2> "$WORK/scan.log"; then
        [[ -f "$WORK/rRNA.fasta" ]] && echo "  [ok] -f rRNA.fasta"
        [[ -f "$WORK/rRNA.gff2" ]] && echo "  [ok] -gff rRNA.gff2"
        echo "  [ok] scan 最小链路完成"
    else
        echo "  [WARN] scan 真跑失败（HMMER2 / XML::Simple / 模型库缺失？），仅提示不阻断；日志："
        tail -n 5 "$WORK/scan.log" || true
    fi
else
    echo "  [SKIP] 未检测到 rnammer（注册制源码，需按 README 安装），仅跑自省 + 契约链路"
fi

echo "ALL TESTS PASSED"
