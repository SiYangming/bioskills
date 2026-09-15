#!/usr/bin/env bash
# tmhmm native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - tmhmm 二进制【可选】：若已安装（PATH 中有 tmhmm 且持有授权模型），会额外做
#     tmhmm -version 冒烟；否则用 stub 二进制验证 stdout→-o 重定向。
# 说明：TMHMM 2.0c 需授权模型 + 真实蛋白序列才能预测，故真实执行部分用 stub 覆盖。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（最小蛋白质 FASTA）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：predict（13.md 分泌蛋白步骤2）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TmhmmSkill, build_parser
skill = TmhmmSkill()
skill._resolve_binary = lambda: "/opt/tmhmm/bin/tmhmm"
cmd = skill.build_command("predict", fasta="$WORK/proteins_mature.fasta")
assert cmd == ["/opt/tmhmm/bin/tmhmm", "$WORK/proteins_mature.fasta"], cmd
print("  OK:", " ".join(cmd))
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["predict", "$WORK/proteins_mature.fasta", "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "predict" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser predict")
PY

echo "==> [4/6] argv 构造验证 #2：plot / mature / 缺 fasta / 线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import TmhmmSkill
skill = TmhmmSkill()
skill._resolve_binary = lambda: "tmhmm"

# plot -> 追加 -plot
c = skill.build_command("plot", fasta="$WORK/proteins_mature.fasta")
assert c == ["tmhmm", "-plot", "$WORK/proteins_mature.fasta"], c
print("  OK plot:", " ".join(c))

# mature -> 追加 -mature
c = skill.build_command("predict", fasta="$WORK/proteins_mature.fasta", mature=True)
assert c == ["tmhmm", "-mature", "$WORK/proteins_mature.fasta"], c
print("  OK mature:", " ".join(c))

# 缺 fasta 必须报错
try:
    skill.build_command("predict")
except ValueError as e:
    print("  OK 缺 fasta 报错:", e)
else:
    raise AssertionError("缺 fasta 应抛 ValueError")

# 线程优先级：显式 --threads > per_subcommand_threads > default_cpus
assert skill._effective_threads("predict", 4) == 4
assert skill._effective_threads("predict", None) == 1   # meta per_subcommand_threads.predict=1
print("  OK threads priority")
PY

echo "==> [5/6] stdout→-o 重定向验证（stub tmhmm，无需授权模型）"
mkdir -p "$WORK/bin"
cat > "$WORK/bin/tmhmm" <<'STUB'
#!/usr/bin/env bash
# stub tmhmm：打印 TMHMM 风格输出，仅供 argv/重定向回归
echo "# $1"
echo "# Number of predicted TMHs:  0"
STUB
chmod +x "$WORK/bin/tmhmm"
PATH="$WORK/bin:$PATH" python "$NATIVE/main.py" predict "$WORK/proteins_mature.fasta" -o "$WORK/tmhmm.out"
test -f "$WORK/tmhmm.out"
grep -q "Number of predicted TMHs:  0" "$WORK/tmhmm.out"
echo "  OK: -o 落盘并命中 'Number of predicted TMHs:  0'"
# 覆盖 13.md 的筛选命令
grep "Number of predicted TMHs:  0" "$WORK/tmhmm.out" | perl -p -e 's/#\s+(\S+).*/$1/' > "$WORK/genes_without_TMHs.list"
test -s "$WORK/genes_without_TMHs.list"
echo "  OK: 无跨膜蛋白清单生成"

echo "==> [6/6] tmhmm 冒烟（若已安装且持有授权模型）"
if command -v tmhmm >/dev/null 2>&1 && [[ "$(command -v tmhmm)" != "$WORK/bin/tmhmm" ]]; then
    tmhmm -version 2>&1 | head -n 2 || true
else
    echo "  tmhmm 未安装，跳过真实冒烟（stub 重定向 + argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
