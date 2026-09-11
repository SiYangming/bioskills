#!/usr/bin/env bash
# rmblast（RMBlast）native 最小回归测试
# 前置：python3 + pyyaml（base.py 依赖）必须在 PATH。
#   自省（--list-commands/--schema）+ 参数契约断言在任何环境都必跑；
#   若本机装有 makeblastdb/rmblastn（conda activate 或 brew tap brewsci/bio），
#   则追加真跑最小链路 makeblastdb → rmblastn 与 makeblastdb --dbtype prot；未安装则 [SKIP]。
# 保证任何环境下脚本以 exit 0 结束并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成核苷酸/蛋白参考 + 核苷酸查询）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/ref_nucl.fa"
test -s "$WORK/query_nucl.fa"
test -s "$WORK/ref_prot.fa"

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^makeblastdb " "$WORK/commands.txt"
grep -q "^rmblastn " "$WORK/commands.txt"

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
# makeblastdb 非法 dbtype（argparse choices 拦截，退出码 2）
if python "$NATIVE/main.py" makeblastdb "$WORK/ref_nucl.fa" --dbtype bogus --out "$WORK/x" >"$WORK/o4" 2>"$WORK/e4"; then
    echo "  [ERROR] makeblastdb 非法 dbtype 竟未报错"; exit 1
else
    grep -qi "dbtype" "$WORK/e4" || { echo "  [ERROR] 报错信息未含 dbtype"; exit 1; }
fi
# rmblastn 缺 -db（argparse 必填，退出码 2）
if python "$NATIVE/main.py" rmblastn -query "$WORK/query_nucl.fa" >"$WORK/o2" 2>"$WORK/e2"; then
    echo "  [ERROR] rmblastn 缺 -db 竟未报错"; exit 1
else
    grep -qi "db" "$WORK/e2" || { echo "  [ERROR] 报错信息未含 db"; exit 1; }
fi
# rmblastn 缺 -query（argparse 必填，退出码 2）
if python "$NATIVE/main.py" rmblastn -db "$WORK/nodb" >"$WORK/o3" 2>"$WORK/e3"; then
    echo "  [ERROR] rmblastn 缺 -query 竟未报错"; exit 1
else
    grep -qi "query" "$WORK/e3" || { echo "  [ERROR] 报错信息未含 query"; exit 1; }
fi
echo "  [OK] 缺参/非法参错误信息含 input / dbtype / db / query"

echo "==> [5/6] main.py 最小链路（需要 makeblastdb/rmblastn，未安装则跳过）"
if command -v makeblastdb >/dev/null 2>&1 && command -v rmblastn >/dev/null 2>&1; then
    # 核苷酸库 + rmblastn
    python "$NATIVE/main.py" makeblastdb "$WORK/ref_nucl.fa" --dbtype nucl --out "$WORK/nucl_db" --threads 2
    test -f "$WORK/nucl_db.nhr"
    test -f "$WORK/nucl_db.nsq"

    python "$NATIVE/main.py" rmblastn -query "$WORK/query_nucl.fa" -db "$WORK/nucl_db" \
        -o "$WORK/rmblastn.tsv" --outfmt 6 --threads 2
    test -s "$WORK/rmblastn.tsv"
    test "$(grep -c -v '^#' "$WORK/rmblastn.tsv")" -ge 1

    # 蛋白库（覆盖 --dbtype prot 建库路径）
    python "$NATIVE/main.py" makeblastdb "$WORK/ref_prot.fa" --dbtype prot --out "$WORK/prot_db" --threads 2
    test -f "$WORK/prot_db.phr"
    test -f "$WORK/prot_db.psq"
else
    echo "  [SKIP] 未检测到 makeblastdb/rmblastn，跳过建库 + rmblastn 最小链路（仅跑自省 + 参数契约）"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v rmblastn >/dev/null 2>&1; then
    rmblastn -version 2>/dev/null | sed -n '1,2p'
fi

echo "ALL TESTS PASSED"
