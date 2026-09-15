#!/usr/bin/env bash
# hmmer native 最小回归测试（单一实现，覆盖 HMMER 3.x + 2.x 两条版本线）
#
# 前置：python3 必须在 PATH。可选真跑（未安装则 [SKIP]）：
#   - HMMER 3.x：PATH 有 hmmbuild/hmmpress/hmmsearch → 跑 hmmbuild→hmmpress→hmmsearch 最小链路；
#   - HMMER 2.x：按多候选名探测（hmmbuild2/hmmbuild/hmm2build、hmmsearch2/hmmsearch/hmm2search）
#     且校验 `-h` 输出确为 "HMMER 2."（避免误命中同名的 HMMER3）→ 跑 hmmbuild2→hmmsearch2 最小链路。
# 自省（--list-commands/--schema）与五子命令参数契约在任何环境必跑；任何环境下
# exit 0 并打印 ALL TESTS PASSED。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 不生成 __pycache__（仓库规范）

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
HMMBUILD2_BIN="$(pick_hmmer2 hmmbuild2 hmmbuild hmm2build || true)"
HMMSEARCH2_BIN="$(pick_hmmer2 hmmsearch2 hmmsearch hmm2search || true)"

echo "==> [1/7] 生成测试数据（合成蛋白 MSA + 序列库；两条版本线共用）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/family.sto"
test -f "$WORK/proteins.fa"

echo "==> [2/7] main.py --list-commands 自省（3.x 三命令 + 2.x 两命令）"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
for sub in hmmbuild hmmpress hmmsearch hmmbuild2 hmmsearch2; do
    grep -q "^${sub} " "$WORK/commands.txt"
done

echo "==> [3/7] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/7] 五子命令参数契约（--threads / --tmpdir 必须存在）"
for sub in hmmbuild hmmpress hmmsearch hmmbuild2 hmmsearch2; do
    python "$NATIVE/main.py" "$sub" --help > "$WORK/help_$sub.txt"
    grep -q -- "--threads" "$WORK/help_$sub.txt"
    grep -q -- "--tmpdir" "$WORK/help_$sub.txt"
done

echo "==> [5/7] argv 契约（monkeypatch 二进制路径；两条版本线）"
NATIVE="$NATIVE" WORK="$WORK" python3 - <<'PY'
import os
import sys

sys.path.insert(0, os.environ["NATIVE"])
from main import HmmerSkill  # noqa: E402

work = os.environ["WORK"]
skill = HmmerSkill()

# --- HMMER 3.x（无后缀二进制）---
skill._resolve_tool = lambda tool: f"/opt/hmmer3/bin/{tool}"
assert " ".join(skill.build_command("hmmbuild", hmm_out=f"{work}/f3.hmm", msa=f"{work}/family.sto",
                                    name="teach", threads=2)) == \
    f"/opt/hmmer3/bin/hmmbuild -n teach --cpu 2 {work}/f3.hmm {work}/family.sto"
assert " ".join(skill.build_command("hmmpress", hmm=f"{work}/f3.hmm", force=True)) == \
    f"/opt/hmmer3/bin/hmmpress -f {work}/f3.hmm"
assert " ".join(skill.build_command("hmmsearch", hmm=f"{work}/f3.hmm", seqdb=f"{work}/proteins.fa",
                                    tblout=f"{work}/hits.tbl", evalue=10, threads=2)) == \
    f"/opt/hmmer3/bin/hmmsearch --cpu 2 --tblout {work}/hits.tbl -E 10 {work}/f3.hmm {work}/proteins.fa"

# --- HMMER 2.x 遗留版（候选名探测结果由 _resolve_tool_v2 提供）---
skill._resolve_tool_v2 = lambda logical: f"/opt/hmmer2/bin/{logical}2"
assert " ".join(skill.build_command("hmmbuild2", hmm_out=f"{work}/f2.hmm", msa=f"{work}/family.sto",
                                    name="teach", force=True, threads=8)) == \
    f"/opt/hmmer2/bin/hmmbuild2 -n teach -F {work}/f2.hmm {work}/family.sto", "2.x hmmbuild 不应注入 --cpu"
assert " ".join(skill.build_command("hmmsearch2", hmm=f"{work}/f2.hmm", seqdb=f"{work}/proteins.fa",
                                    evalue=10, bit_score=5, alignment=0, threads=2)) == \
    f"/opt/hmmer2/bin/hmmsearch2 --cpu 2 -E 10 -T 5 -A 0 {work}/f2.hmm {work}/proteins.fa"

# --- 缺必填 / 未知子命令 ---
for sub, kw in (("hmmbuild", {}), ("hmmpress", {}), ("hmmsearch", {}),
                ("hmmbuild2", {}), ("hmmsearch2", {})):
    try:
        skill.build_command(sub, **kw)
        raise AssertionError(f"{sub} 缺必填应抛 RuntimeError")
    except RuntimeError:
        pass
try:
    skill.build_command("bogus")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: argv 契约（3.x 三命令 + 2.x 两命令 + 参数校验）")
PY

echo "==> [6/7] HMMER 3.x 最小链路 hmmbuild→hmmpress→hmmsearch（未安装则跳过）"
if command -v hmmbuild >/dev/null 2>&1 \
    && command -v hmmpress >/dev/null 2>&1 \
    && command -v hmmsearch >/dev/null 2>&1; then
    python "$NATIVE/main.py" hmmbuild "$WORK/family.hmm" "$WORK/family.sto" -n teach_family --threads 2
    test -f "$WORK/family.hmm"
    grep -q "HMMER3" "$WORK/family.hmm"

    python "$NATIVE/main.py" hmmpress "$WORK/family.hmm"
    for ext in h3f h3i h3m h3p; do
        test -f "$WORK/family.hmm.$ext"
    done

    python "$NATIVE/main.py" hmmsearch --hmm "$WORK/family.hmm" "$WORK/proteins.fa" \
        --tblout "$WORK/hits.tbl" -E 10 -o "$WORK/search.out" --threads 2
    test -f "$WORK/hits.tbl"
    test -f "$WORK/search.out"
    grep -q "^# target name" "$WORK/hits.tbl"
else
    echo "  [SKIP] 未检测到 hmmbuild/hmmpress/hmmsearch，跳过 3.x 最小链路（仅跑自省/契约）"
fi

echo "==> [7/7] HMMER 2.x 最小链路 hmmbuild2→hmmsearch2（未安装则跳过）"
if [[ -n "$HMMBUILD2_BIN" && -n "$HMMSEARCH2_BIN" ]]; then
    echo "  使用二进制：$HMMBUILD2_BIN / $HMMSEARCH2_BIN"
    python "$NATIVE/main.py" hmmbuild2 "$WORK/family2.hmm" "$WORK/family.sto" -n teach_family -F
    test -f "$WORK/family2.hmm"
    grep -qi "HMMER" "$WORK/family2.hmm"

    python "$NATIVE/main.py" hmmsearch2 "$WORK/family2.hmm" "$WORK/proteins.fa" \
        -E 10 --threads 2 > "$WORK/search2.out"
    test -s "$WORK/search2.out"
    grep -qi "HMMER" "$WORK/search2.out"
else
    echo "  [SKIP] 未检测到 HMMER2 二进制（hmmbuild2/hmmbuild/hmm2build、hmmsearch2/hmmsearch/hmm2search），跳过 2.x 最小链路（仅跑自省/契约）"
fi

echo "ALL TESTS PASSED"
