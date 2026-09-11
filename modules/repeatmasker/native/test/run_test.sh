#!/usr/bin/env bash
# repeatmasker native 最小回归测试
# 前置：python3 + pyyaml（base.py 依赖）必须在 PATH。
# 降级策略：RepeatMasker mask 的真实回归需要 Dfam/RepBase 重复库（-lib 也需 rmblast
#   完整配置），普通机器难以全跑。因此：
#   - PATH 无 RepeatMasker -> 只跑 --list-commands / --schema / 参数契约自省 + [SKIP]
#     （自省必跑，任何环境都执行）；
#   - 有 RepeatMasker -> 追加轻量自检：版本/用法头探测 + query_species_tree 可用性探测
#     （该 util 脚本随经典 RepBase 安装提供；RepeatMasker>=4.2/FamDB 环境或未配库时
#     失败仅提示不阻断）；
#   - mask 真实屏蔽不纳入回归（需重复库 + rmblast 完整配置），仅在提示中说明可用
#     generate_data.py 的 consensi.fa 做 -lib 手动自测。
# 保证任何环境下脚本以 exit 0 结束并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成小基因组 + 迷你自定义库）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome.fa"
test -s "$WORK/consensi.fa"
test "$(grep -c '^>' "$WORK/genome.fa")" -ge 5
test "$(grep -c '^>' "$WORK/consensi.fa")" -ge 2

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^mask " "$WORK/commands.txt"
grep -q "^query_species_tree " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 参数契约自检（不依赖二进制）"
# mask 缺 genome_fasta（argparse 缺参，退出码 2）
if python "$NATIVE/main.py" mask >"$WORK/o1" 2>"$WORK/e1"; then
    echo "  [ERROR] mask 缺 genome_fasta 竟未报错"; exit 1
else
    grep -qi "genome_fasta" "$WORK/e1" || { echo "  [ERROR] 报错信息未含 genome_fasta"; exit 1; }
fi
# mask 未给 -species/-lib（驱动级必填校验，RuntimeError 退出码 1）
if python "$NATIVE/main.py" mask "$WORK/genome.fa" >"$WORK/o2" 2>"$WORK/e2"; then
    echo "  [ERROR] mask 未给 -species/-lib 竟未报错"; exit 1
else
    grep -qi "species" "$WORK/e2" || { echo "  [ERROR] 报错信息未含 species"; exit 1; }
fi
echo "  [OK] 缺参/缺库错误信息含 genome_fasta / species"

echo "==> [5/6] 轻量自检（PATH 含 RepeatMasker 时追加；mask 真实回归需重复库，不纳入）"
if command -v RepeatMasker >/dev/null 2>&1; then
    echo "  [RUN] RepeatMasker 版本/用法头探测"
    RepeatMasker </dev/null 2>&1 | head -n 2 || true

    echo "  [RUN] query_species_tree 可用性探测"
    if python "$NATIVE/main.py" query_species_tree >"$WORK/tree.txt" 2>"$WORK/tree.err"; then
        if test -s "$WORK/tree.txt"; then
            echo "  [RUN] query_species_tree 输出物种树（前 5 行）："
            head -n 5 "$WORK/tree.txt" | sed 's/^/        /'
        else
            echo "  [WARN] queryRepeatDatabase.pl 已跑但 stdout 为空（当前库无可列物种）"
        fi
    else
        echo "  [SKIP] query_species_tree 不可用（RepeatMasker>=4.2/FamDB 无该 util 脚本或未配置 RepBase 库），跳过"
    fi
    echo "  [NOTE] mask 真实屏蔽需要 Dfam/RepBase 库（或 -lib 自定义库）+ rmblast 完整配置，回归不真跑；"
    echo "        教学/自测可手动执行：python $NATIVE/main.py mask $WORK/genome.fa -lib $WORK/consensi.fa -dir $WORK/rm_out"
else
    echo "  [SKIP] 未检测到 RepeatMasker，跳过真跑类自检（仅自省 + 参数契约）"
fi

echo "==> [6/6] 结束"
echo "ALL TESTS PASSED"
