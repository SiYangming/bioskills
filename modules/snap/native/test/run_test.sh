#!/usr/bin/env bash
# snap native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - snap/fathom/forge（可选）：合成数据无法覆盖 SNAP 真实训练/预测，故不依赖真实安装；
#     若有安装则额外做一次二进制存在性冒烟。
# 说明：所有子命令以「python 构造 argv（monkeypatch 二进制路径）验证命令构建」为主。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：fathom 训练前处理（gene_stats/validate/categorize/export）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SnapSkill
skill = SnapSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'snap'}"

c = " ".join(skill.build_command("gene_stats", ann="$WORK/genome.ann", dna="$WORK/genome.dna"))
assert c == f"/opt/env/bin/fathom $WORK/genome.ann $WORK/genome.dna -gene-stats", c
print("  OK:", c)

c = " ".join(skill.build_command("validate", ann="$WORK/genome.ann", dna="$WORK/genome.dna"))
assert c == f"/opt/env/bin/fathom $WORK/genome.ann $WORK/genome.dna -validate", c
print("  OK:", c)

c = " ".join(skill.build_command("categorize", ann="$WORK/genome.ann", dna="$WORK/genome.dna", window=200))
assert c == f"/opt/env/bin/fathom $WORK/genome.ann $WORK/genome.dna -categorize 200", c
print("  OK:", c)

c = " ".join(skill.build_command("export", ann="$WORK/genome.ann", dna="$WORK/genome.dna", window=200, plus=True))
assert c == f"/opt/env/bin/fathom $WORK/genome.ann $WORK/genome.dna -export 200 -plus", c
print("  OK:", c)
PY

echo "==> [4/6] argv 构造验证 #2：forge / hmm-assembler.pl"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SnapSkill
skill = SnapSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'snap'}"

c = " ".join(skill.build_command("forge", export_ann="$WORK/export.ann", export_dna="$WORK/export.dna"))
assert c == f"/opt/env/bin/forge $WORK/export.ann $WORK/export.dna", c
print("  OK:", c)

c = " ".join(skill.build_command("hmm_assembler", name="species", params="$WORK/params"))
assert c == f"/opt/env/bin/hmm-assembler.pl species $WORK/params", c
print("  OK:", c)
PY

echo "==> [5/6] argv 构造验证 #3：snap predict + 线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SnapSkill, build_parser
skill = SnapSkill()
skill._resolve_binary = lambda name=None: f"/opt/env/bin/{name or 'snap'}"

c = " ".join(skill.build_command("predict", hmm="$WORK/species.hmm", genome="$WORK/genome.fasta"))
assert c == f"/opt/env/bin/snap $WORK/species.hmm $WORK/genome.fasta", c
print("  OK:", c)

# 线程优先级：显式 > per_subcommand_threads(default) > default_cpus
assert skill._effective_threads("forge", 8) == 8
assert skill._effective_threads("forge", None) == 4
print("  OK: threads priority (explicit=8, default=4)")

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["predict", "$WORK/species.hmm", "$WORK/genome.fasta", "-o", "$WORK/out.zff",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "predict" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.output.endswith("out.zff"), ns
print("  OK: parser predict")
PY

echo "==> [6/6] 二进制冒烟（若已安装）"
if command -v snap >/dev/null 2>&1; then
    snap -help 2>&1 | head -n 2 || true
else
    echo "  snap 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
