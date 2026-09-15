#!/usr/bin/env bash
# table2asn native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - table2asn 二进制【可选】：若已安装会在最后做一次真实冒烟（-help）；
#     未安装时全部走「argv 构造 + stub 二进制端到端」验证路径。
# 说明：table2asn 需要真实 FASTA + .tbl + .sbt 才能产出 .sqn，合成数据无法覆盖真实转换，
#      故本测试重点断言命令行构造（尤其 -indir/-outdir 已取代旧版 -p/-r、-Z 不再吃文件名）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PY="$(command -v python3 || command -v python)"
[[ -n "$PY" ]] || { echo "[FAIL] 未找到 python3"; exit 1; }

echo "==> [1/8] 生成测试数据（FASTA + .sbt 占位）"
"$PY" "$HERE/generate_data.py" "$WORK"

echo "==> [2/8] 自省：--list-commands / --schema"
"$PY" "$NATIVE/main.py" --list-commands
for sub in wgs complete validate; do
    "$PY" "$NATIVE/main.py" --list-commands | awk '{print $1}' | grep -qx "$sub" \
        || { echo "  [FAIL] --list-commands 缺少子命令 $sub"; exit 1; }
done
"$PY" "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
"$PY" -c "import json,sys; json.load(open('$WORK/schema.json'))" \
    || { echo "  [FAIL] --schema 输出不是合法 JSON"; exit 1; }
echo "  OK: 3 个必备子命令齐备，schema 为合法 JSON"

echo "==> [3/8] argv 构造验证 #1：wgs（-indir/-outdir 取代旧 -p/-r；-a r1k -l paired-ends）"
"$PY" - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Table2asnSkill, build_parser
skill = Table2asnSkill()
skill._resolve_binary = lambda: "/opt/env/bin/table2asn"
cmd = skill.build_command(
    "wgs", template="$WORK/ecoli.sbt", indir="$WORK", outdir="$WORK/out", validate_level="vb")
assert cmd == ["/opt/env/bin/table2asn", "-t", "$WORK/ecoli.sbt",
               "-indir", "$WORK", "-outdir", "$WORK/out",
               "-a", "r1k", "-l", "paired-ends", "-V", "vb", "-M", "n", "-Z"], cmd
s = " ".join(cmd)
# 关键：必须用官方新参数 -indir/-outdir，且不得出现旧版 -p/-r
assert "-indir" in s and "-outdir" in s, s
assert " -p " not in s and " -r " not in s, s
# 关键：-Z 为无参数开关（旧版写作 -Z discrep）
assert s.endswith(" -Z") and "-Z discrep" not in s, s
print("  OK:", s)
ns = build_parser().parse_args(
    ["wgs", "-t", "$WORK/ecoli.sbt", "--indir", "$WORK", "--outdir", "$WORK/out",
     "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "wgs" and ns.indir == "$WORK" and ns.outdir == "$WORK/out", ns
assert ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser wgs")
PY

echo "==> [4/8] argv 构造验证 #2：complete / validate"
"$PY" - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Table2asnSkill
skill = Table2asnSkill()
skill._resolve_binary = lambda: "table2asn"

c1 = skill.build_command("complete", template="$WORK/ecoli.sbt", indir="$WORK")
assert c1 == ["table2asn", "-t", "$WORK/ecoli.sbt", "-indir", "$WORK",
              "-a", "a", "-V", "vb", "-M", "n", "-Z"], c1
print("  OK complete:", " ".join(c1))

c2 = skill.build_command("validate", template="$WORK/ecoli.sbt", indir="$WORK")
assert c2 == ["table2asn", "-t", "$WORK/ecoli.sbt", "-indir", "$WORK",
              "-V", "v", "-M", "n", "-Z"], c2
assert "-a" not in c2, c2  # validate 不注入 -a
print("  OK validate:", " ".join(c2))
PY

echo "==> [5/8] argv 构造验证 #3：run（-i/--gaps-min 透传）与线程优先级"
"$PY" - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Table2asnSkill
skill = Table2asnSkill()
skill._resolve_binary = lambda: "table2asn"
cmd = skill.build_command(
    "run", template="$WORK/ecoli.sbt", indir="$WORK",
    input="$WORK/ecoli.fsa", assembly_type="r1u", gaps_min=10)
assert cmd == ["table2asn", "-t", "$WORK/ecoli.sbt", "-indir", "$WORK",
               "-i", "$WORK/ecoli.fsa", "-a", "r1u", "-gaps-min", "10",
               "-V", "vb", "-M", "n", "-Z"], cmd
print("  OK run:", " ".join(cmd))
# 线程优先级：显式 --threads > per_subcommand_threads > default_cpus
assert skill._effective_threads("wgs", 8) == 8
assert skill._effective_threads("wgs", None) == 4   # meta per_subcommand_threads.default=4（单线程工具）
print("  OK threads priority (explicit=8, default=4)")
PY

echo "==> [6/8] 端到端：stub 二进制 + --tmpdir 注入 TMPDIR"
mkdir -p "$WORK/bin" "$WORK/tmp"
cat > "$WORK/bin/table2asn" <<'SH'
#!/usr/bin/env bash
echo "ARGV: $*"
echo "TMPDIR=${TMPDIR:-<unset>}"
SH
chmod +x "$WORK/bin/table2asn"
PATH="$WORK/bin:$PATH" "$PY" "$NATIVE/main.py" wgs \
    -t "$WORK/ecoli.sbt" --indir "$WORK" --outdir "$WORK/out" --tmpdir "$WORK/tmp" \
    > "$WORK/e2e.txt" 2>&1 || true
cat "$WORK/e2e.txt" | sed 's/^/    /'
grep -qx "ARGV: -t $WORK/ecoli.sbt -indir $WORK -outdir $WORK/out -a r1k -l paired-ends -V vb -M n -Z" \
    "$WORK/e2e.txt" || { echo "  [FAIL] 端到端 argv 与预期不符"; exit 1; }
grep -qx "TMPDIR=$WORK/tmp" "$WORK/e2e.txt" \
    || { echo "  [FAIL] --tmpdir 未注入 TMPDIR"; exit 1; }
echo "  OK: 实际执行 argv 与 TMPDIR 注入均正确"

echo "==> [7/8] 缺二进制报错路径（PATH 置空）"
set +e
out="$(env PATH=/nonexistent "$PY" "$NATIVE/main.py" wgs -t "$WORK/ecoli.sbt" --indir "$WORK" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || { echo "  [FAIL] 缺二进制时期望非零退出"; exit 1; }
grep -q "bioconda" <<<"$out" || { echo "  [FAIL] 报错信息未指向官方渠道："; echo "$out"; exit 1; }
echo "  OK: 缺二进制时报错并指向 bioconda/官方 FTP"

echo "==> [8/8] table2asn 真实冒烟（若已安装）"
if command -v table2asn >/dev/null 2>&1; then
    table2asn -help 2>&1 | head -n 3 | sed 's/^/    /' || true
    echo "  OK: 已调用本机 table2asn（-help）"
else
    echo "  [SKIP] table2asn 未安装，跳过真实冒烟（argv 构造 + stub 端到端验证已通过）"
fi

echo "ALL TESTS PASSED"
