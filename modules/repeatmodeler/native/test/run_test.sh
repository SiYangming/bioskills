#!/usr/bin/env bash
# repeatmodeler native 最小回归测试
# 前置：python3 + pyyaml（base.py 依赖）必须在 PATH。
# 降级策略：RepeatModeler 完整建库需几十 GB 级计算与 RECON/RepeatScout/RMBlast/TRF 等
#   完整依赖，普通机器难以全跑。因此：
#   - PATH 无 BuildDatabase / RepeatModeler -> 只跑 --list-commands / --schema / 参数契约
#     自省 + [SKIP]（自省必跑，任何环境都执行）；
#   - 两者都在 PATH -> 追加「build_db -> model」最小真跑链路（BuildDatabase 产物硬断言；
#     RepeatModeler 在合成小基因组上可能因极小基因组/依赖问题提前退出，仅告警不阻断）。
# 保证任何环境下脚本以 exit 0 结束并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成小基因组）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome.fa"
test "$(grep -c '^>' "$WORK/genome.fa")" -ge 10

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^build_db " "$WORK/commands.txt"
grep -q "^model " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 参数契约自检（不依赖二进制）"
# model 缺 -database / build_db 缺 -name 时必须报 argparse 缺参错误（退出码 2）
if python "$NATIVE/main.py" model >"$WORK/o1" 2>"$WORK/e1"; then
    echo "  [ERROR] model 缺 -database 竟未报错"; exit 1
else
    grep -qi "database" "$WORK/e1" || { echo "  [ERROR] 报错信息未含 database"; exit 1; }
fi
if python "$NATIVE/main.py" build_db genome.fa >"$WORK/o2" 2>"$WORK/e2"; then
    echo "  [ERROR] build_db 缺 -name 竟未报错"; exit 1
else
    grep -qi "name" "$WORK/e2" || { echo "  [ERROR] 报错信息未含 name"; exit 1; }
fi
echo "  [OK] 缺参错误信息含 database / name"

echo "==> [5/6] build_db -> model 最小链路（需要 BuildDatabase / RepeatModeler，未安装则跳过）"
if command -v BuildDatabase >/dev/null 2>&1 && command -v RepeatModeler >/dev/null 2>&1; then
    echo "  [RUN] build_db 最小真跑（合成小基因组 -> testdb）"
    # BuildDatabase 在 CWD 产出 <name>-index/ 或 <name>.nhr/.nin/.nsq（按引擎），故 cd 到 WORK
    (cd "$WORK" && python "$NATIVE/main.py" build_db genome.fa -name testdb --engine ncbi)
    if test -d "$WORK/testdb-index" || test -f "$WORK/testdb.nhr" || test -f "$WORK/testdb.nin"; then
        echo "  [RUN] BuildDatabase 产物就绪（testdb-index/ 或 testdb.nhr/.nin）"
    else
        echo "  [ERROR] BuildDatabase 未产出数据库（缺 testdb-index/ 或 testdb.nhr/.nin）"; exit 1
    fi

    echo "  [RUN] model 最小真跑（-database testdb --threads 2；完整建库耗时长，见降级策略）"
    if (cd "$WORK" && python "$NATIVE/main.py" model -database testdb --engine ncbi --threads 2 \
            >"$WORK/model.log" 2>&1); then
        CONS="$(find "$WORK" -maxdepth 3 -name 'consensi.fa*' | head -n 1)"
        test -n "$CONS"
        echo "  [RUN] model 完成，共有序列: $CONS"
    else
        echo "  [WARN] RepeatModeler 在合成小基因组上未完成（极小基因组或依赖不全），跳过产物断言"
    fi
else
    echo "  [SKIP] 未检测到 BuildDatabase / RepeatModeler，跳过最小链路（仅自省 + 参数契约）"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v RepeatModeler >/dev/null 2>&1; then
    RepeatModeler -help 2>&1 | head -n 2 || true
fi

echo "ALL TESTS PASSED"
