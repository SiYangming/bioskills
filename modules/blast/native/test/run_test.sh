#!/usr/bin/env bash
# blast（NCBI BLAST+）native 最小回归测试
# 前置：python3 + pyyaml（base.py 依赖）必须在 PATH。
#   自省（--list-commands/--schema）+ 参数契约断言在任何环境都必跑；
#   若本机装有 makeblastdb/blastn/blastp（conda activate 或 brew install blast），
#   则追加真跑最小链路 makeblastdb → blastn（核苷酸）与 makeblastdb → blastp（蛋白）；
#   未安装则 [SKIP]。
# 保证任何环境下脚本以 exit 0 结束并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成核苷酸/蛋白参考 + 查询）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/ref_nucl.fa"
test -s "$WORK/query_nucl.fa"
test -s "$WORK/ref_prot.fa"
test -s "$WORK/query_prot.fa"

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^makeblastdb " "$WORK/commands.txt"
grep -q "^blastn " "$WORK/commands.txt"
grep -q "^blastp " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 参数契约自检（不依赖二进制）"
# makeblastdb 缺 input（驱动级必填校验，RuntimeError 退出码 1）
if python "$NATIVE/main.py" makeblastdb >"$WORK/o1" 2>"$WORK/e1"; then
    echo "  [ERROR] makeblastdb 缺 input 竟未报错"; exit 1
else
    grep -qi "input" "$WORK/e1" || { echo "  [ERROR] 报错信息未含 input"; exit 1; }
fi
# blastn 缺 -db（argparse 必填，退出码 2）
if python "$NATIVE/main.py" blastn -query "$WORK/query_nucl.fa" >"$WORK/o2" 2>"$WORK/e2"; then
    echo "  [ERROR] blastn 缺 -db 竟未报错"; exit 1
else
    grep -qi "db" "$WORK/e2" || { echo "  [ERROR] 报错信息未含 db"; exit 1; }
fi
# blastn 缺 -query（argparse 必填，退出码 2）
if python "$NATIVE/main.py" blastn -db "$WORK/nodb" >"$WORK/o3" 2>"$WORK/e3"; then
    echo "  [ERROR] blastn 缺 -query 竟未报错"; exit 1
else
    grep -qi "query" "$WORK/e3" || { echo "  [ERROR] 报错信息未含 query"; exit 1; }
fi
echo "  [OK] 缺参错误信息含 input / db / query"

echo "==> [5/6] main.py 最小链路（需要 makeblastdb/blastn/blastp，未安装则跳过）"
if command -v makeblastdb >/dev/null 2>&1 && command -v blastn >/dev/null 2>&1 && command -v blastp >/dev/null 2>&1; then
    # 核苷酸库 + blastn
    python "$NATIVE/main.py" makeblastdb "$WORK/ref_nucl.fa" --dbtype nucl --out "$WORK/nucl_db" --threads 2
    test -f "$WORK/nucl_db.nhr"
    test -f "$WORK/nucl_db.nsq"

    python "$NATIVE/main.py" blastn -query "$WORK/query_nucl.fa" -db "$WORK/nucl_db" \
        -o "$WORK/blastn.tsv" --outfmt 6 --threads 2
    test -s "$WORK/blastn.tsv"
    test "$(grep -c -v '^#' "$WORK/blastn.tsv")" -ge 1

    # 蛋白库 + blastp
    python "$NATIVE/main.py" makeblastdb "$WORK/ref_prot.fa" --dbtype prot --out "$WORK/prot_db" --threads 2
    test -f "$WORK/prot_db.phr"
    test -f "$WORK/prot_db.psq"

    python "$NATIVE/main.py" blastp -query "$WORK/query_prot.fa" -db "$WORK/prot_db" \
        -o "$WORK/blastp.tsv" --outfmt 6 --threads 2
    test -s "$WORK/blastp.tsv"
    test "$(grep -c -v '^#' "$WORK/blastp.tsv")" -ge 1
else
    echo "  [SKIP] 未检测到 makeblastdb/blastn/blastp，跳过建库 + 比对最小链路（仅跑自省 + 参数契约）"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v blastn >/dev/null 2>&1; then
    blastn -version 2>/dev/null | sed -n '1,2p'
fi

echo "ALL TESTS PASSED"
