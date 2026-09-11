#!/usr/bin/env bash
# hmmer2（HMMER 2.x）native 最小回归测试
# 前置：python3 必须在 PATH；若本机装有 HMMER2（bioconda hmmer2 的 hmmbuild2/hmmsearch2、
# 上游自编译的 hmmbuild/hmmsearch、Debian 的 hmm2build/hmm2search），则追加跑
# hmmbuild→hmmsearch 最小链路，否则跳过（自省 + 契约测试必跑）。
# 任何环境下 exit 0 并打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 按多候选名探测 HMMER2 二进制（bioconda 2 后缀 → 上游无后缀 → Debian 前缀）。
# ⚠️ 必须校验 `-h` 输出确为 "HMMER 2."：无后缀的 hmmsearch/hmmbuild 与 HMMER3 同名，
# 仅按名字命中会把本机 HMMER3 误当 HMMER2（详见 modules/hmmer）。
pick_hmmer2() {
    local c
    for c in "$@"; do
        if command -v "$c" >/dev/null 2>&1 && "$c" -h 2>&1 | grep -q "HMMER 2\."; then
            echo "$c"
            return 0
        fi
    done
    return 1
}
HMMBUILD_BIN="$(pick_hmmer2 hmmbuild2 hmmbuild hmm2build || true)"
HMMSEARCH_BIN="$(pick_hmmer2 hmmsearch2 hmmsearch hmm2search || true)"

echo "==> [1/6] 生成测试数据（合成蛋白 MSA + 序列库）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/family.sto"
test -f "$WORK/proteins.fa"

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^hmmbuild " "$WORK/commands.txt"
grep -q "^hmmsearch " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 子命令参数契约（--threads / --tmpdir 必须存在）"
for sub in hmmbuild hmmsearch; do
    python "$NATIVE/main.py" "$sub" --help > "$WORK/help_$sub.txt"
    grep -q -- "--threads" "$WORK/help_$sub.txt"
    grep -q -- "--tmpdir" "$WORK/help_$sub.txt"
done

echo "==> [5/6] hmmbuild→hmmsearch 最小链路（需要 HMMER 2.x，未安装则跳过）"
if [[ -n "$HMMBUILD_BIN" && -n "$HMMSEARCH_BIN" ]]; then
    echo "  使用二进制：$HMMBUILD_BIN / $HMMSEARCH_BIN"
    python "$NATIVE/main.py" hmmbuild "$WORK/family.hmm" "$WORK/family.sto" -n teach_family -F
    test -f "$WORK/family.hmm"
    grep -qi "HMMER" "$WORK/family.hmm"

    python "$NATIVE/main.py" hmmsearch "$WORK/family.hmm" "$WORK/proteins.fa" \
        -E 10 --threads 2 > "$WORK/search.out"
    test -s "$WORK/search.out"
    grep -qi "HMMER" "$WORK/search.out"
else
    echo "  [SKIP] 未检测到 HMMER2 二进制（hmmbuild2/hmmbuild/hmm2build、hmmsearch2/hmmsearch/hmm2search），跳过最小链路（仅跑自省/契约）"
fi

echo "==> [6/6] 版本探测（可选信息）"
if [[ -n "$HMMSEARCH_BIN" ]]; then
    "$HMMSEARCH_BIN" -h 2>&1 | grep -m1 "HMMER" || true
fi

echo "ALL TESTS PASSED"
