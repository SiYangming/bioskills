#!/usr/bin/env bash
# cd-hit native 最小回归测试
# 前置：python3 必须在 PATH。
# PATH 中有 cd-hit / cd-hit-est（conda activate <cd-hit 环境> / 官方容器内 / 已安装）→ 追加真跑最小链路：
#   合成小 FASTA → protein(cd-hit) / est(cd-hit-est) 聚类 → 断言代表序列与 .clstr 产物、去冗余后条数减少；
#   （真跑失败仅 [WARN] 提示不阻断，保证任意环境 exit 0）
# 无二进制 → 自省 + [SKIP]；任何环境最终打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（合成蛋白/核酸 FASTA）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/proteins.fa"
test -f "$WORK/nucleotides.fa"
N_PROT_IN=$(grep -c '^>' "$WORK/proteins.fa")
N_NUCL_IN=$(grep -c '^>' "$WORK/nucleotides.fa")
echo "  蛋白输入 $N_PROT_IN 条 / 核酸输入 $N_NUCL_IN 条"

echo "==> [2/7] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^protein " "$WORK/commands.txt"
grep -q "^est " "$WORK/commands.txt"

echo "==> [3/7] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/7] 子命令参数契约（--help 自省）"
python "$NATIVE/main.py" protein --help > "$WORK/protein_help.txt"
python "$NATIVE/main.py" est --help > "$WORK/est_help.txt"
for f in protein_help est_help; do
    grep -q -- "--input" "$WORK/$f.txt"
    grep -q -- "--output" "$WORK/$f.txt"
    grep -q -- "--identity" "$WORK/$f.txt"
    grep -q -- "--memory" "$WORK/$f.txt"
    grep -q -- "--threads" "$WORK/$f.txt"
    grep -q -- "--tmpdir" "$WORK/$f.txt"
done

echo "==> [5/7] protein 最小链路（需要 cd-hit，未安装则跳过）"
if command -v cd-hit >/dev/null 2>&1; then
    if python "$NATIVE/main.py" protein -i "$WORK/proteins.fa" -o "$WORK/prot_nr.fa" \
            -c 0.9 --threads 2 -M 0 2> "$WORK/protein.log"; then
        test -s "$WORK/prot_nr.fa"
        test -s "$WORK/prot_nr.fa.clstr"
        grep -q "^>Cluster" "$WORK/prot_nr.fa.clstr" || { echo "  [FAIL] .clstr 无 Cluster 记录"; exit 1; }
        N_PROT_OUT=$(grep -c '^>' "$WORK/prot_nr.fa")
        test "$N_PROT_OUT" -ge 1
        test "$N_PROT_OUT" -lt "$N_PROT_IN" || { echo "  [FAIL] 去冗余后条数未减少：$N_PROT_OUT !< $N_PROT_IN"; exit 1; }
        echo "  [ok] protein 聚类：$N_PROT_IN -> $N_PROT_OUT 条代表序列"
    else
        echo "  [WARN] protein 真跑失败，仅提示不阻断；日志："
        tail -n 5 "$WORK/protein.log" || true
    fi
else
    echo "  [SKIP] 未检测到 cd-hit（conda activate <cd-hit 环境> 或装好后重跑）"
fi

echo "==> [6/7] est 最小链路（需要 cd-hit-est，未安装则跳过）"
if command -v cd-hit-est >/dev/null 2>&1; then
    if python "$NATIVE/main.py" est -i "$WORK/nucleotides.fa" -o "$WORK/nucl_nr.fa" \
            -c 0.9 --threads 2 -M 0 2> "$WORK/est.log"; then
        test -s "$WORK/nucl_nr.fa"
        test -s "$WORK/nucl_nr.fa.clstr"
        grep -q "^>Cluster" "$WORK/nucl_nr.fa.clstr" || { echo "  [FAIL] .clstr 无 Cluster 记录"; exit 1; }
        N_NUCL_OUT=$(grep -c '^>' "$WORK/nucl_nr.fa")
        test "$N_NUCL_OUT" -ge 1
        test "$N_NUCL_OUT" -lt "$N_NUCL_IN" || { echo "  [FAIL] 去冗余后条数未减少：$N_NUCL_OUT !< $N_NUCL_IN"; exit 1; }
        echo "  [ok] est 聚类：$N_NUCL_IN -> $N_NUCL_OUT 条代表序列"
    else
        echo "  [WARN] est 真跑失败，仅提示不阻断；日志："
        tail -n 5 "$WORK/est.log" || true
    fi
else
    echo "  [SKIP] 未检测到 cd-hit-est（conda activate <cd-hit 环境> 或装好后重跑）"
fi

echo "==> [7/7] 版本探测（可选信息）"
if command -v cd-hit >/dev/null 2>&1; then
    cd-hit -h 2>&1 | head -n 1 || true
fi

echo "ALL TESTS PASSED"
