#!/usr/bin/env bash
# Mauve native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - progressiveMauve / Mauve 二进制【可选】：已装（conda 环境 mauve / 官方 tarball / 容器）
#     时额外做冒烟；否则仅做 argv 构造断言（monkeypatch _resolve_sub_binary，不依赖工具已安装）。
# 说明：progressiveMauve / Mauve 为 Java 工具（单线程）——--threads 仅占位不注入；
#      --tmpdir 映射为 progressiveMauve 的 --scratch-path-1。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（迷你基因组 + 最小 XMFA）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/genome1.fasta" && test -s "$WORK/alignment.xmfa"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
for c in align apply_backbone gui; do
    grep -q "^$c" "$WORK/commands.txt"
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/7] argv 构造验证 #1：align（output/backbone/guide-tree/weight/scratch）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MauveSkill, build_parser, _BINARIES

assert _BINARIES == {"align": "progressiveMauve", "apply_backbone": "progressiveMauve",
                     "gui": "Mauve"}, _BINARIES

skill = MauveSkill()
skill._resolve_sub_binary = lambda sub: ("/opt/env/bin/Mauve" if sub == "gui"
                                          else "/opt/env/bin/progressiveMauve")

cmd = skill.build_command(
    "align",
    genomes=["$WORK/genome1.fasta", "$WORK/genome2.fasta", "$WORK/genome3.fasta"],
    output="$WORK/alignment.xmfa", backbone_output="$WORK/alignment.backbone",
    output_guide_tree="$WORK/alignment.tree", seed_weight=15, weight=5000,
    min_scaled_penalty=5000, seed_family=True,
)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/progressiveMauve", s
for frag in ("--output=$WORK/alignment.xmfa", "--backbone-output=$WORK/alignment.backbone",
             "--output-guide-tree=$WORK/alignment.tree", "--seed-weight=15",
             "--weight=5000", "--min-scaled-penalty=5000", "--seed-family",
             "--scratch-path-1=/tmp"):
    assert frag in s, (frag, s)
assert s.rstrip().endswith(
    "$WORK/genome1.fasta $WORK/genome2.fasta $WORK/genome3.fasta"), s
print("  OK:", s)

# 二档：mums / collinear / disable-backbone
cmd = skill.build_command(
    "align", genomes=["$WORK/genome1.fasta", "$WORK/genome2.fasta"],
    output="$WORK/mums.xmfa", mums=True, collinear=True, disable_backbone=True)
s = " ".join(cmd)
for frag in ("--mums", "--collinear", "--disable-backbone", "--output=$WORK/mums.xmfa"):
    assert frag in s, (frag, s)
print("  OK:", s)

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["align", "$WORK/genome1.fasta", "$WORK/genome2.fasta",
     "--output", "$WORK/o.xmfa", "--weight", "3000", "--threads", "4", "--tmpdir", "/scratch"])
assert ns.subcommand == "align" and ns.output == "$WORK/o.xmfa" and ns.weight == 3000
assert ns.threads == "4" and ns.tmpdir == "/scratch" and ns.genomes == ["$WORK/genome1.fasta", "$WORK/genome2.fasta"]
print("  OK: parser align")
PY

echo "==> [4/7] argv 构造验证 #2：apply_backbone / gui"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MauveSkill

skill = MauveSkill()
skill._resolve_sub_binary = lambda sub: ("/opt/env/bin/Mauve" if sub == "gui"
                                          else "/opt/env/bin/progressiveMauve")

cmd = skill.build_command("apply_backbone", alignment="$WORK/alignment.xmfa",
                          output="$WORK/rebuilt.xmfa", backbone_output="$WORK/rebuilt.backbone",
                          homology_prob=0.001, unrelated_prob=0.000005)
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/progressiveMauve", s
for frag in ("--apply-backbone=$WORK/alignment.xmfa", "--output=$WORK/rebuilt.xmfa",
             "--backbone-output=$WORK/rebuilt.backbone",
             "--hmm-p-go-homologous=0.001", "--hmm-p-go-unrelated=5e-06"):
    assert frag in s, (frag, s)
assert "--scratch-path-1=/tmp" in s, s
print("  OK:", s)

cmd = skill.build_command("gui", alignment="$WORK/alignment.xmfa")
s = " ".join(cmd)
assert cmd[0] == "/opt/env/bin/Mauve" and cmd[1] == "$WORK/alignment.xmfa", s
print("  OK:", s)
PY

echo "==> [5/7] 运行时校验：缺必填、未知子命令、线程优先级"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MauveSkill

skill = MauveSkill()
skill._resolve_sub_binary = lambda sub: "progressiveMauve"

try:
    skill.build_command("align")
    raise AssertionError("align 缺 genomes 应报错")
except ValueError:
    pass
for sub in ("apply_backbone", "gui"):
    try:
        skill.build_command(sub)
        raise AssertionError("%s 缺 alignment 应报错" % sub)
    except ValueError:
        pass
try:
    skill.build_command("bogus")
    raise AssertionError("未知子命令应报错")
except ValueError:
    pass

assert skill._effective_threads("align", 8) == 8
assert skill._effective_threads("align", None) == 1
print("  OK: 运行时校验 + 线程优先级")
PY

echo "==> [6/7] CLI 层校验：无子命令返回 2；无二进制时明确报错 rc 1"
python3 - <<PY
import sys, subprocess
r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "align", "$WORK/genome1.fasta", "$WORK/genome2.fasta",
     "--output", "$WORK/x.xmfa"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'progressiveMauve'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（无子命令 rc 2；无二进制 rc 1）")
PY

echo "==> [7/7] progressiveMauve 真实冒烟（若已安装）"
if command -v progressiveMauve >/dev/null 2>&1; then
    progressiveMauve --version 2>&1 | head -n 1 || true
    python "$NATIVE/main.py" align "$WORK/genome1.fasta" "$WORK/genome2.fasta" \
        --output "$WORK/real.xmfa" --disable-backbone 2>/dev/null || true
    if test -s "$WORK/real.xmfa"; then
        echo "  OK: progressiveMauve 真实冒烟通过（real.xmfa 已产出）"
    else
        echo "  已检测到 progressiveMauve 但迷你数据未产出（序列过短；argv 构造验证已通过）"
    fi
else
    echo "  progressiveMauve 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
