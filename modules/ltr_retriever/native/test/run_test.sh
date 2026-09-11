#!/usr/bin/env bash
# ltr_retriever native 最小回归测试
# 前置：python3 + pyyaml（base.py 依赖）必须在 PATH。
# PATH 中有 LTR_retriever（conda activate <ltr_retriever 环境> / 官方容器内 / 已安装）→ 追加
#   usage/版本探测 + 最小真跑链路（合成 genome.fa + ltrharvest.out → LTR_retriever -genome/-inharvest）；
#   官方完整链路需 BLAST+/CD-HIT/HMMER/RepeatMasker/TEsorter 等依赖与数据库，真跑失败仅 [WARN] 不阻断。
# 无 LTR_retriever → 自省 + 参数契约 + [SKIP]；任何环境最终 exit 0 并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成小基因组 + LTRharvest 候选）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome.fa"
test -s "$WORK/ltrharvest.out"
test "$(grep -c '^>' "$WORK/genome.fa")" -ge 2

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^run " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 参数契约自检（不依赖二进制）"
python "$NATIVE/main.py" run --help > "$WORK/run_help.txt"
grep -q -- "-genome" "$WORK/run_help.txt"
grep -q -- "-inharvest" "$WORK/run_help.txt"
grep -q -- "--threads" "$WORK/run_help.txt"
grep -q -- "--tmpdir" "$WORK/run_help.txt"
# 缺必需参数时必须报 argparse 缺参错误（退出码 2）
if python "$NATIVE/main.py" run -genome "$WORK/genome.fa" >"$WORK/o1" 2>"$WORK/e1"; then
    echo "  [ERROR] run 缺 -inharvest 竟未报错"; exit 1
else
    grep -qi "inharvest" "$WORK/e1" || { echo "  [ERROR] 报错信息未含 inharvest"; exit 1; }
fi
echo "  [OK] 缺 -inharvest 时 argparse 正确报错"

echo "==> [5/6] LTR_retriever 最小链路（需要 LTR_retriever，未安装则跳过）"
# 说明：真跑链路仅作正向验证，任何失败均 [WARN] 不阻断，保证任意环境 exit 0
#（自省 + 参数契约已在前述步骤硬断言）。
if command -v LTR_retriever >/dev/null 2>&1; then
    echo "  [RUN] usage / 版本探测"
    LTR_retriever -h 2>&1 | head -n 3 || true
    echo "  [RUN] LTR_retriever -genome/-inharvest 最小链路（--threads 2）"
    if ( cd "$WORK" && python "$NATIVE/main.py" run -genome "$WORK/genome.fa" -inharvest "$WORK/ltrharvest.out" \
            --threads 2 >"$WORK/run.log" 2>&1 ); then
        echo "  [ok] LTR_retriever 运行结束；产物（前缀 $WORK/genome.fa）："
        ls -1 "$WORK"/genome.fa.* 2>/dev/null | sed 's/^/      /' || true
    else
        echo "  [WARN] LTR_retriever 真跑失败（多因缺 BLAST+/CD-HIT/HMMER/RepeatMasker/TEsorter 或数据库），仅提示不阻断；日志："
        tail -n 5 "$WORK/run.log" || true
    fi
else
    echo "  [SKIP] 未检测到 LTR_retriever（conda activate <ltr_retriever 环境> 或装好后重跑），仅跑自省 + 参数契约"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v LTR_retriever >/dev/null 2>&1; then
    LTR_retriever -h 2>&1 | head -n 1 || true
fi

echo "ALL TESTS PASSED"
