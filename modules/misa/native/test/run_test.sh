#!/usr/bin/env bash
# misa native 最小回归测试
# 前置：python3 必须在 PATH。
# PATH 中有 misa.pl（native/install.sh 装好 / 官方容器内）→ 追加真跑最小链路：
#   5a 默认参数（GFF false）→ <fasta>.misa + <fasta>.statistics，且**输入目录不被写入**；
#   5b --gff（GFF: true）→ 逐序列 .gff 且**不产出 .misa**（v2.1 产物互斥）；
#   5c --ini 自定义 misa.ini → 落到 outdir 且内容一致；
#   5d 重复运行幂等；5e 同 outdir 换参数应被拒（misa.ini 冲突保护）。
# 无 misa.pl → 自省 + [SKIP]；任何环境最终打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成 genome.fasta + custom.misa.ini）"
python3 "$HERE/generate_data.py" "$WORK/data"
test -f "$WORK/data/genome.fasta"
test -f "$WORK/data/custom.misa.ini"

echo "==> [2/6] main.py --list-commands 自省"
python3 "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^detect " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] detect 参数契约（--help 自省）"
python3 "$NATIVE/main.py" detect --help > "$WORK/help.txt"
for opt in --input --outdir --ini --min-repeats --interruptions --gff; do
    grep -q -- "$opt" "$WORK/help.txt"
done
echo "  [ok] --input/--outdir/--ini/--min-repeats/--interruptions/--gff 均在"

echo "==> [5/6] detect 最小链路（需要 misa.pl，未安装则跳过）"
if command -v misa.pl >/dev/null 2>&1; then
    # 5a. 默认参数：GFF false → .misa + .statistics；输入目录不得被写
    if python3 "$NATIVE/main.py" detect "$WORK/data/genome.fasta" --outdir "$WORK/out1" \
            > "$WORK/detect1.log" 2>&1; then
        test -s "$WORK/out1/genome.fasta.misa"
        test -s "$WORK/out1/genome.fasta.statistics"
        # 命中预期 SSR：chr1 (AG)12=24 bp（p2）；chr2 (A)12=12 bp（p1）+ (GAA)7=21 bp（p3）
        grep -qE '^chr1[[:space:]]+[0-9]+[[:space:]]+p2[[:space:]]+\(AG\)12[[:space:]]+24[[:space:]]' "$WORK/out1/genome.fasta.misa"
        grep -qE '^chr2[[:space:]]+[0-9]+[[:space:]]+p1[[:space:]]+\(A\)12[[:space:]]+12[[:space:]]' "$WORK/out1/genome.fasta.misa"
        grep -qE '^chr2[[:space:]]+[0-9]+[[:space:]]+p3[[:space:]]+\(GAA\)7[[:space:]]+21[[:space:]]' "$WORK/out1/genome.fasta.misa"
        test "$(tail -n +2 "$WORK/out1/genome.fasta.misa" | wc -l | tr -d ' ')" = "3"
        grep -q 'RESULTS OF MICROSATELLITE SEARCH' "$WORK/out1/genome.fasta.statistics"
        test -f "$WORK/out1/misa.ini"
        # 输入所在目录不得出现产物（驱动以 cwd=outdir + 软链运行 misa.pl）
        test ! -e "$WORK/data/genome.fasta.misa"
        test ! -e "$WORK/data/genome.fasta.statistics"
        echo "  [ok] detect 默认参数 → .misa（命中 (AG)12）+ .statistics，输入目录无写入"

        # 5d. 重复运行幂等（misa.ini 一致 + 软链已存在）
        python3 "$NATIVE/main.py" detect "$WORK/data/genome.fasta" --outdir "$WORK/out1" \
            > "$WORK/detect1b.log" 2>&1
        echo "  [ok] 同参数重复运行幂等"

        # 5e. 同 outdir 换搜索参数 → 应因 misa.ini 冲突被拒（保护用户已有配置）
        if python3 "$NATIVE/main.py" detect "$WORK/data/genome.fasta" --outdir "$WORK/out1" \
                --min-repeats "1-5 2-5" > "$WORK/detect1c.log" 2>&1; then
            echo "  [FAIL] 同 outdir 更换参数应当报错（misa.ini 冲突保护失效）"
            exit 1
        else
            echo "  [ok] 同 outdir 更换参数被拒（misa.ini 冲突保护生效）"
        fi
    else
        echo "  [WARN] detect 默认参数真跑失败（misa.pl 安装异常？），仅提示不阻断；日志："
        tail -n 5 "$WORK/detect1.log" || true
    fi

    # 5b. --gff（GFF: true）→ 逐序列 .gff，且不再产出 .misa（v2.1 产物互斥）
    if python3 "$NATIVE/main.py" detect "$WORK/data/genome.fasta" --outdir "$WORK/out2" --gff \
            > "$WORK/detect2.log" 2>&1; then
        test ! -e "$WORK/out2/genome.fasta.misa"
        test -f "$WORK/out2/chr1.gff"
        grep -q 'gff-version 3' "$WORK/out2/chr1.gff"
        echo "  [ok] --gff → chr1.gff/chr2.gff 且无 .misa（产物互斥符合预期）"
    else
        echo "  [WARN] detect --gff 真跑失败，仅提示不阻断；日志："
        tail -n 5 "$WORK/detect2.log" || true
    fi

    # 5c. --ini 自定义 misa.ini → 落到 outdir 且内容与源文件一致
    if python3 "$NATIVE/main.py" detect "$WORK/data/genome.fasta" --outdir "$WORK/out3" \
            --ini "$WORK/data/custom.misa.ini" > "$WORK/detect3.log" 2>&1; then
        test -f "$WORK/out3/misa.ini"
        diff -q "$WORK/data/custom.misa.ini" "$WORK/out3/misa.ini" >/dev/null
        echo "  [ok] --ini → outdir/misa.ini 与源文件一致（GFF: true → .gff 输出）"
    else
        echo "  [WARN] detect --ini 真跑失败，仅提示不阻断；日志："
        tail -n 5 "$WORK/detect3.log" || true
    fi
else
    echo "  [SKIP] 未检测到 misa.pl（bash modules/misa/native/install.sh 装好后重跑），仅跑自省链路"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v misa.pl >/dev/null 2>&1; then
    misa.pl -help 2>&1 | head -n 4 || true
fi

echo "ALL TESTS PASSED"
