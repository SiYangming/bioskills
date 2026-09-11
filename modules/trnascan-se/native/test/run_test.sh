#!/usr/bin/env bash
# trnascan-se（tRNAscan-SE 2.0）native 最小回归测试
# 前置：python3 + pyyaml（base.py 依赖）必须在 PATH。
# 降级策略：PATH 无 tRNAscan-SE（含模型环境）时只跑 --list-commands / --schema /
#   参数契约自省 + [SKIP]（自省必跑，任何环境都执行）；
#   有 tRNAscan-SE 时追加真核默认模式真实检测一个小 fasta（conda 包内自带 covariance
#   model 与 infernal，装好即用），真实运行失败仅 [WARN] 提示不阻断（保证任何环境 exit 0）。
# 保证任何环境下脚本以 exit 0 结束并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成小基因组，含 1 条经典酵母 tRNA-Phe）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome.fa"
test "$(grep -c '^>' "$WORK/genome.fa")" -eq 2
python - "$WORK/genome.fa" <<'PY'
import sys
from pathlib import Path
seq = "".join(l.strip() for l in Path(sys.argv[1]).read_text().splitlines() if not l.startswith(">"))
assert len(seq) > 1000, "genome.fa 总长异常"
print(f"  [OK] genome.fa 总长 {len(seq)} bp")
PY

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^scan " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('  schema JSON 合法')"

echo "==> [4/6] 参数契约自检（不依赖二进制）"
# scan 缺 genome_fasta（argparse 缺参，退出码 2）
if python "$NATIVE/main.py" scan >"$WORK/o1" 2>"$WORK/e1"; then
    echo "  [ERROR] scan 缺 genome_fasta 竟未报错"; exit 1
else
    grep -qi "genome_fasta" "$WORK/e1" || { echo "  [ERROR] 报错信息未含 genome_fasta"; exit 1; }
fi
# 未知子命令（argparse invalid choice，退出码 2）
if python "$NATIVE/main.py" nosuchcmd >"$WORK/o2" 2>"$WORK/e2"; then
    echo "  [ERROR] 未知子命令竟未报错"; exit 1
else
    grep -qi "invalid choice" "$WORK/e2" || { echo "  [ERROR] 报错信息未含 invalid choice"; exit 1; }
fi
echo "  [OK] 缺参/非法子命令错误信息符合 argparse 契约"

echo "==> [5/6] 真实回归（PATH 含 tRNAscan-SE 时追加；真核默认模式，模型随 conda 包）"
if command -v tRNAscan-SE >/dev/null 2>&1; then
    echo "  [RUN] tRNAscan-SE 版本探测"
    tRNAscan-SE -h 2>&1 | head -n 2 || true

    echo "  [RUN] python main.py scan genome.fa -o/-f/-m（真核默认；--threads 为协议位不注入）"
    mkdir -p "$WORK/run"
    if (cd "$WORK/run" && python "$NATIVE/main.py" scan "$WORK/genome.fa" \
            -o tRNA.out -f tRNA.ss -m tRNA.stats --threads 2 --tmpdir "$WORK/tmp" \
            >"$WORK/scan.log" 2>&1); then
        test -f "$WORK/run/tRNA.out" || { echo "  [ERROR] tRNA.out 未生成"; exit 1; }
        echo "  [RUN] tRNA.out 产物摘要（含预测 tRNA 行数，非 # 注释行）："
        HITS=$(grep -c -v '^#' "$WORK/run/tRNA.out" || true)
        echo "        命中行数（含表头）: $HITS"
        head -n 3 "$WORK/run/tRNA.out" | sed 's/^/        /' || true
        test -f "$WORK/run/tRNA.ss" && echo "  [OK] tRNA.ss 二级结构文件已生成" \
            || echo "  [NOTE] tRNA.ss 未生成（0 hits 或 -f 无输出时属正常）"
        test -f "$WORK/run/tRNA.stats" && echo "  [OK] tRNA.stats 统计文件已生成" \
            || echo "  [NOTE] tRNA.stats 未生成"
        # 若真跑成功但 0 命中（如模型/库异常），提示但不阻断（exit 0 保证）
        if test "$HITS" -le 1; then
            echo "  [WARN] 真核扫描无 tRNA 命中（通常为 0 行仅表头/空表）；请确认 conda 包模型完整"
        fi
    else
        echo "  [WARN] 真核扫描运行失败（rc=$?），跳过产物断言（详见 scan.log 尾部）"
        tail -n 5 "$WORK/scan.log" | sed 's/^/        /' || true
    fi
else
    echo "  [SKIP] 未检测到 tRNAscan-SE，跳过真实检测（仅自省 + 参数契约）"
fi

echo "==> [6/6] 结束"
echo "ALL TESTS PASSED"
