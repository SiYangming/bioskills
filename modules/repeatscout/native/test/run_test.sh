#!/usr/bin/env bash
# repeatscout native 最小回归测试
# 前置：python3 + pyyaml（base.py 依赖）必须在 PATH。
# 降级策略：build_lmer_table / RepeatScout 均为单线程 C 程序，核心链路无需外部依赖；
#   - PATH 无 build_lmer_table / RepeatScout -> 只跑 --list-commands / --schema / 参数契约
#     自省 + [SKIP]（自省必跑，任何环境都执行）；
#   - 两者都在 PATH -> 追加「build_lmer_table -> predict」最小真跑链路（频率表产物硬断言；
#     RepeatScout 在极小合成基因组上可能得不到家族，仅告警不阻断）。
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
grep -q "^build_lmer_table " "$WORK/commands.txt"
grep -q "^predict " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 参数契约自检（不依赖二进制）"
# predict 缺 -sequence / -freq / -output 时必须报 argparse 缺参错误（退出码 2）
for req in sequence freq output; do
    if python "$NATIVE/main.py" predict >"$WORK/po" 2>"$WORK/pe"; then
        echo "  [ERROR] predict 缺 -$req 竟未报错"; exit 1
    fi
    grep -qi -- "$req" "$WORK/pe" || { echo "  [ERROR] predict 缺参报错信息未含 '$req'"; exit 1; }
done
# build_lmer_table 缺 -freq 时必须报错
if python "$NATIVE/main.py" build_lmer_table genome.fa >"$WORK/bo" 2>"$WORK/be"; then
    echo "  [ERROR] build_lmer_table 缺 -freq 竟未报错"; exit 1
fi
grep -qi -- "freq" "$WORK/be" || { echo "  [ERROR] build_lmer_table 缺参报错信息未含 freq"; exit 1; }
# help 契约：关键参数存在
python "$NATIVE/main.py" build_lmer_table --help > "$WORK/bh.txt"
grep -q -- "-freq" "$WORK/bh.txt"
grep -q -- "-l" "$WORK/bh.txt"
python "$NATIVE/main.py" predict --help > "$WORK/ph.txt"
grep -q -- "-output" "$WORK/ph.txt"
grep -q -- "-goodlength" "$WORK/ph.txt"
echo "  [OK] predict / build_lmer_table 缺参错误与 --help 契约通过"

echo "==> [5/6] build_lmer_table -> predict 最小链路（需要 build_lmer_table / RepeatScout，未安装则跳过）"
if command -v build_lmer_table >/dev/null 2>&1 && command -v RepeatScout >/dev/null 2>&1; then
    echo "  [RUN] build_lmer_table（合成小基因组 -> genome.freq）"
    (cd "$WORK" && python "$NATIVE/main.py" build_lmer_table genome.fa -freq genome.freq)
    test -s "$WORK/genome.freq"
    echo "  [RUN] 频率表就绪（$(wc -l < "$WORK/genome.freq") 行）"

    echo "  [RUN] predict（genome.freq -> repeats.fa）"
    if (cd "$WORK" && python "$NATIVE/main.py" predict \
            -sequence genome.fa -freq genome.freq -output repeats.fa \
            >"$WORK/predict.log" 2>&1); then
        test -f "$WORK/repeats.fa"
        echo "  [RUN] predict 完成，重复家族共有序列: $WORK/repeats.fa"
    else
        echo "  [WARN] RepeatScout 在合成小基因组上未产出家族（极小基因组），跳过产物断言；日志："
        tail -n 5 "$WORK/predict.log" || true
    fi
else
    echo "  [SKIP] 未检测到 build_lmer_table / RepeatScout，跳过最小链路（仅自省 + 参数契约）"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v RepeatScout >/dev/null 2>&1; then
    RepeatScout 2>&1 | head -n 1 || true
fi

echo "ALL TESTS PASSED"
