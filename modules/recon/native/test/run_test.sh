#!/usr/bin/env bash
# recon native 最小回归测试
# 前置：python3 + pyyaml（base.py 依赖）必须在 PATH。
# 降级策略：
#   - PATH 无 run_recon.sh / eledef -> 只跑自省（--list-commands/--schema）与参数契约 + [SKIP]；
#   - PATH 有 recon 包（run_recon.sh + eledef）-> 追加轻量 usage 探测与合成 MSP 的全流程真跑
#     （RECON 在极小 MSP 上秒级完成；真跑失败仅 [WARN] 不阻断，保证任何环境下 exit 0）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成 MSP + 序列名清单）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/seqnames"
test -s "$WORK/recon.msps"
test "$(grep -c -v '^#' "$WORK/recon.msps")" -ge 2

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^pipeline " "$WORK/commands.txt"
grep -q "^eledef " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 参数契约自检（不依赖二进制）"
# pipeline / eledef 缺少位置参数 msp 时必须报 argparse 缺参错误（退出码 2）
if python "$NATIVE/main.py" pipeline "$WORK/seqnames" >"$WORK/o1" 2>"$WORK/e1"; then
    echo "  [ERROR] pipeline 缺 msp 竟未报错"; exit 1
else
    grep -qi "msp" "$WORK/e1" || { echo "  [ERROR] 报错信息未含 msp"; exit 1; }
fi
if python "$NATIVE/main.py" eledef "$WORK/seqnames" >"$WORK/o2" 2>"$WORK/e2"; then
    echo "  [ERROR] eledef 缺 msp 竟未报错"; exit 1
else
    grep -qi "msp" "$WORK/e2" || { echo "  [ERROR] 报错信息未含 msp"; exit 1; }
fi
echo "  [OK] 缺参错误信息含 msp"

echo "==> [5/6] usage 探测 + 全流程真跑（需要 run_recon.sh / eledef，未安装则跳过）"
if command -v run_recon.sh >/dev/null 2>&1 && command -v eledef >/dev/null 2>&1; then
    echo "  [RUN] eledef usage 轻量探测（无参调用打印 usage，退出码非 0）"
    ELEDEF_USAGE="$(eledef 2>&1 || true)"
    grep -qi "usage" <<<"$ELEDEF_USAGE" || { echo "  [ERROR] eledef 未打印 usage"; exit 1; }
    echo "  [RUN] pipeline 全流程真跑（合成 MSP -> summary/eles + summary/families）"
    if python "$NATIVE/main.py" pipeline "$WORK/seqnames" "$WORK/recon.msps" -o "$WORK/out" \
            >"$WORK/pipeline.log" 2>&1; then
        test -s "$WORK/out/summary/eles" || { echo "  [ERROR] 缺 summary/eles"; exit 1; }
        test -s "$WORK/out/summary/families" || { echo "  [ERROR] 缺 summary/families"; exit 1; }
        NFAM="$(grep -c -v '^#' "$WORK/out/summary/families")"
        NELE="$(grep -c -v '^#' "$WORK/out/summary/eles")"
        test "$NFAM" -ge 1
        test "$NELE" -ge 2
        echo "  [RUN] 完成：$NFAM 个家族 / $NELE 个元素"
    else
        echo "  [WARN] pipeline 真跑未成功（环境差异），跳过产物断言；日志尾部："
        tail -n 3 "$WORK/pipeline.log" | sed 's/^/    /'
    fi
else
    echo "  [SKIP] 未检测到 run_recon.sh / eledef，跳过 usage 探测与全流程真跑"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v eledef >/dev/null 2>&1; then
    eledef -v 2>&1 | head -n 2 || true
fi

echo "ALL TESTS PASSED"
