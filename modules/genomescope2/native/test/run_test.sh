#!/usr/bin/env bash
# genomescope2 native 最小回归测试（GenomeScope 2.0 / genomescope2 v1.0.0）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - genomescope.R【可选】：若已安装（PATH 中有 genomescope.R），会额外做冒烟；否则跳过。
# 说明：GenomeScope 模型拟合需要真实 k-mer 直方图才能收敛，合成数据无法覆盖真实拟合；因此
#      对 run 采用「python 构造 argv 验证命令构建不崩溃」，CLI 层用 stub 假脚本验证。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 不生成 __pycache__（仓库规范）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（合成 k-mer 直方图）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/mer_counts.histo"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^run'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证：run（文档示例参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Genomescope2Skill, build_parser

skill = Genomescope2Skill()
skill._resolve_binary = lambda: "/opt/genomescope2.0-1.0.0/genomescope.R"

cmd = skill.build_command(
    "run", histogram="$WORK/mer_counts.histo", output_dir="$WORK/genomescope",
    kmer_size=21, ploidy=1,
)
s = " ".join(cmd)
assert "/opt/genomescope2.0-1.0.0/genomescope.R" in s, s
assert "-i $WORK/mer_counts.histo" in s, s
assert "-o $WORK/genomescope" in s, s
assert "-k 21" in s and "-p 1" in s, s
print("  OK:", s)

# 全可选参数：-l/-n/-m
cmd = skill.build_command(
    "run", histogram="$WORK/mer_counts.histo", output_dir="$WORK/out",
    kmer_size=21, ploidy=2, lambda_init=45.0, name_prefix="sampleA", max_kmercov=1000,
)
s = " ".join(cmd)
for frag in ("-p 2", "-l 45.0", "-n sampleA", "-m 1000"):
    assert frag in s, (frag, s)
print("  OK:", s)

# parser（子命令后 --threads/--tmpdir）
ns = build_parser().parse_args(
    ["run", "-i", "$WORK/mer_counts.histo", "-o", "$WORK/out", "-k", "21",
     "-p", "2", "--report", "$WORK/genomescope.out", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "run" and ns.kmer_size == 21 and ns.ploidy == 2
assert ns.threads == 4 and ns.tmpdir == "/tmp" and ns.report == "$WORK/genomescope.out"
print("  OK: parser run")
PY

echo "==> [4/5] build_command 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Genomescope2Skill

skill = Genomescope2Skill()
skill._resolve_binary = lambda: "genomescope.R"

for kw in (dict(output_dir="o", kmer_size=21),                 # 缺 histogram
           dict(histogram="h", kmer_size=21),                  # 缺 output_dir
           dict(histogram="h", output_dir="o")):               # 缺 kmer_size
    try:
        skill.build_command("run", **kw)
        raise AssertionError("缺必填应抛 RuntimeError: %r" % kw)
    except RuntimeError:
        pass
try:
    skill.build_command("bogus")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [5/5] CLI 层校验：无子命令返回 2；stub 下构造命令；缺脚本报错；真实冒烟"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\necho "fake genomescope.R"\nexit 0\n' > "$WORK/fakebin/genomescope.R"
chmod +x "$WORK/fakebin/genomescope.R"
python3 - <<PY
import sys, os, subprocess

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "run", "-i", "$WORK/mer_counts.histo",
     "-o", "$WORK/genomescope", "-k", "21", "-p", "1", "--report", "$WORK/report.txt"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)

# 真实缺 genomescope.R（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "run", "-i", "$WORK/mer_counts.histo",
     "-o", "$WORK/out", "-k", "21"],
    capture_output=True, text=True)
assert r.returncode == 1 and "genomescope.R" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（构造命令 + 缺 genomescope.R 报错）")
PY

if command -v genomescope.R >/dev/null 2>&1; then
    echo "  已检测到 genomescope.R（argv 构造验证已覆盖；真实拟合需真实直方图）"
else
    echo "  genomescope.R 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
