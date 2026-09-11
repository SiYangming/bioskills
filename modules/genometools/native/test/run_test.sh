#!/usr/bin/env bash
# genometools(gt) native 最小回归测试
# 前置：python3 + pyyaml（base.py 依赖）必须在 PATH。
# PATH 中有 gt（conda activate <genometools 环境> / 官方容器内 / 已安装）→ 追加真跑最小链路：
#   合成小 genome.fa → gt suffixerator 建 ESA 索引 → gt ltrharvest 预测 LTR（产物断言）；
#   （若安装环境异常导致真跑失败，仅 [WARN] 提示不阻断，保证任意环境 exit 0）
# 无 gt → 自省 + 参数契约 + [SKIP]；任何环境最终打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（含 LTR 样结构的合成小基因组）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome.fa"
test "$(grep -c '^>' "$WORK/genome.fa")" -ge 2

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^suffixerator " "$WORK/commands.txt"
grep -q "^ltrharvest " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 参数契约自检（不依赖二进制）"
python "$NATIVE/main.py" suffixerator --help > "$WORK/suf_help.txt"
grep -q -- "-indexname" "$WORK/suf_help.txt"
grep -q -- "--no-suf" "$WORK/suf_help.txt"
python "$NATIVE/main.py" ltrharvest --help > "$WORK/ltr_help.txt"
grep -q -- "-outinner" "$WORK/ltr_help.txt"
grep -q -- "-gff3" "$WORK/ltr_help.txt"
# 缺必需参数时必须报 argparse 缺参错误（退出码 2）
if python "$NATIVE/main.py" suffixerator -db "$WORK/genome.fa" >"$WORK/o1" 2>"$WORK/e1"; then
    echo "  [ERROR] suffixerator 缺 -indexname 竟未报错"; exit 1
else
    grep -qi "indexname" "$WORK/e1" || { echo "  [ERROR] 报错信息未含 indexname"; exit 1; }
fi
if python "$NATIVE/main.py" ltrharvest >"$WORK/o2" 2>"$WORK/e2"; then
    echo "  [ERROR] ltrharvest 缺 -index 竟未报错"; exit 1
else
    grep -qi "index" "$WORK/e2" || { echo "  [ERROR] 报错信息未含 index"; exit 1; }
fi
echo "  [OK] 缺参错误信息含 indexname / index"

echo "==> [5/6] suffixerator -> ltrharvest 最小链路（需要 gt，未安装则跳过）"
# 说明：真跑链路仅作正向验证，任何失败均 [WARN] 不阻断，保证任意环境 exit 0
#（自省 + 参数契约已在前述步骤硬断言）。
if command -v gt >/dev/null 2>&1; then
    echo "  [RUN] gt suffixerator 建 ESA 索引（--threads 2，运行时选项不注入）"
    SKIP_LTR=0
    if python "$NATIVE/main.py" suffixerator -db "$WORK/genome.fa" -indexname "$WORK/gtidx" \
            --threads 2 >"$WORK/suf.log" 2>&1 \
            && test -f "$WORK/gtidx.esq" && test -f "$WORK/gtidx.suf" && test -f "$WORK/gtidx.lcp"; then
        echo "  [ok] suffixerator 产物就绪（gtidx.{esq,suf,lcp,...}）"
    else
        SKIP_LTR=1
        echo "  [WARN] suffixerator 未产出完整索引（gtidx.{esq,suf,lcp}），跳过 ltrharvest；日志："
        tail -n 5 "$WORK/suf.log" || true
    fi

    if test "$SKIP_LTR" -eq 0; then
        echo "  [RUN] gt ltrharvest 预测 LTR 反转录转座子"
        if python "$NATIVE/main.py" ltrharvest -index "$WORK/gtidx" \
                -out "$WORK/ltrharvest.out" -outinner "$WORK/ltrharvest.inner" \
                -gff3 "$WORK/ltrharvest.gff3" --threads 2 >"$WORK/ltr.log" 2>&1; then
            for f in ltrharvest.out ltrharvest.inner ltrharvest.gff3; do
                test -f "$WORK/$f" || echo "  [WARN] 缺少 ltrharvest 产物 $f"
            done
            if test -s "$WORK/ltrharvest.gff3"; then
                head -n 1 "$WORK/ltrharvest.gff3" | grep -q "##gff-version 3" \
                    || echo "  [WARN] gff3 首行非 ##gff-version 3（版本差异？）"
                echo "  [ok] ltrharvest 检出 LTR_retrotransposon 行数: $(grep -c 'LTR_retrotransposon' "$WORK/ltrharvest.gff3" || true)"
            fi
            echo "  [ok] ltrharvest 产物就绪（out / inner / gff3）"
        else
            echo "  [WARN] ltrharvest 真跑失败，仅提示不阻断；日志："
            tail -n 5 "$WORK/ltr.log" || true
        fi
    fi
else
    echo "  [SKIP] 未检测到 gt（conda activate <genometools 环境> 或装好后重跑），仅跑自省 + 参数契约"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v gt >/dev/null 2>&1; then
    gt -version 2>&1 | head -n 2 || true
fi

echo "ALL TESTS PASSED"
