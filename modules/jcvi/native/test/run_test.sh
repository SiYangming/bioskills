#!/usr/bin/env bash
# jcvi native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - jcvi【可选】：未安装时退化为 argv 构造验证（不做真实比对/出图）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/4] 生成测试数据（anchors/seqids/layout/bed/blocks）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/4] 自省：--list-commands / --schema"
for c in ortholog dotplot karyotype synteny; do
    python "$NATIVE/main.py" --list-commands | grep -q "^$c"
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/4] argv 构造验证（monkeypatch 解释器）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import JcviSkill, build_parser

skill = JcviSkill()
skill._resolve_binary = lambda: "/opt/env/bin/python"

# ortholog：--cscore / --no_strip_names / --cpus（线程默认取 per_subcommand=8）
cmd = skill.build_command("ortholog", sp1="laame", sp2="plost",
                          cscore=0.5, no_strip_names=True)
s = " ".join(cmd)
assert cmd[:6] == ["/opt/env/bin/python", "-m", "jcvi.compara.catalog", "ortholog", "laame", "plost"], s
assert "--cscore 0.5" in s and "--no_strip_names" in s, s
assert "--cpus 8" in s, s
print("  OK:", s)

# 线程优先级：显式 --threads 2 覆盖 per_subcommand(8)
cmd = skill.build_command("ortholog", sp1="laame", sp2="plost", threads=2)
assert "--cpus 2" in " ".join(cmd), cmd
print("  OK: --threads 覆盖 -> --cpus 2")

# dotplot
cmd = skill.build_command("dotplot", anchors="$WORK/laame.plost.anchors",
                          title="Laccaria vs Pleurotus", outfile="$WORK/dot.pdf")
s = " ".join(cmd)
assert cmd[:4] == ["/opt/env/bin/python", "-m", "jcvi.graphics.dotplot", "$WORK/laame.plost.anchors"], s
assert "--title Laccaria vs Pleurotus" in s and "-o $WORK/dot.pdf" in s, s
print("  OK:", s)

# karyotype（位置参数 seqids + layout）
cmd = skill.build_command("karyotype", seqids="$WORK/seqids", layout="$WORK/layout",
                          outfile="$WORK/karyotype.pdf")
s = " ".join(cmd)
assert cmd[:5] == ["/opt/env/bin/python", "-m", "jcvi.graphics.karyotype",
                   "$WORK/seqids", "$WORK/layout"], s
assert "-o $WORK/karyotype.pdf" in s, s
print("  OK:", s)

# synteny（位置参数 blocks + bed + layout，--outputprefix）
cmd = skill.build_command("synteny", blocks="$WORK/blocks", bed="$WORK/laame.bed",
                          layout="$WORK/layout", outputprefix="$WORK/syn")
s = " ".join(cmd)
assert cmd[:6] == ["/opt/env/bin/python", "-m", "jcvi.graphics.synteny",
                   "$WORK/blocks", "$WORK/laame.bed", "$WORK/layout"], s
assert "--outputprefix $WORK/syn" in s, s
print("  OK:", s)

# parser 可解析子命令后 --threads/--tmpdir
ns = build_parser().parse_args(["ortholog", "laame", "plost", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "ortholog" and ns.threads == 2 and ns.tmpdir == "/tmp", ns
print("  OK: parser ortholog --threads/--tmpdir")

# 缺参应报错
try:
    skill.build_command("synteny", blocks="$WORK/blocks")
    raise AssertionError("synteny 缺参应抛 ValueError")
except ValueError:
    print("  OK: synteny 缺参被拒绝")
PY

echo "==> [4/4] jcvi 冒烟（若已安装）"
if python3 -c "import jcvi" >/dev/null 2>&1; then
    python3 -m jcvi -h 2>&1 | head -n 3 || true
else
    echo "  jcvi 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
