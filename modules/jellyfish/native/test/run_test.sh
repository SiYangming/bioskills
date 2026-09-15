#!/usr/bin/env bash
# jellyfish native 最小回归测试（Jellyfish 2.3.0：count/histo/stats/query/dump/merge）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - jellyfish 二进制【可选】：若已安装（PATH 中有 jellyfish），会额外做 --version 冒烟；
#     否则跳过真实执行。
# 说明：jellyfish count 需要真实序列才能产出 .jf，合成数据无法覆盖真实计数；因此对
#      count/histo/stats/query/dump/merge 采用「python 构造 argv 验证命令构建不崩溃」，
#      CLI 层用 stub 假二进制验证命令构造与参数校验。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 不生成 __pycache__（仓库规范）

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（迷你 FASTQ + .jf 占位 + 直方图）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/reads_1.fastq" && test -s "$WORK/mer_counts.jf" && test -s "$WORK/mer_counts.histo"

echo "==> [2/6] 自省：--list-commands / --schema"
for c in count histo stats query dump merge; do
    python "$NATIVE/main.py" --list-commands | grep -q "^${c}"
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证 #1：count（文档示例参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import JellyfishSkill, build_parser

skill = JellyfishSkill()
skill._resolve_binary = lambda: "/opt/jellyfish/bin/jellyfish"

cmd = skill.build_command(
    "count", reads=["$WORK/reads_1.fastq", "$WORK/reads_2.fastq"],
    kmer_size=21, hash_size="100M", canonical=True,
    output="$WORK/mer_counts.jf", threads=4,
)
s = " ".join(cmd)
assert "/opt/jellyfish/bin/jellyfish count" in s, s
assert "-C" in s, s
assert "-m 21" in s and "-s 100M" in s and "-t 4" in s, s
assert "-o $WORK/mer_counts.jf" in s, s
assert "$WORK/reads_1.fastq" in s and "$WORK/reads_2.fastq" in s, s
print("  OK:", s)

# 关闭 canonical
cmd = skill.build_command("count", reads="$WORK/reads_1.fastq", canonical=False)
assert "-C" not in " ".join(cmd), cmd
print("  OK: 关闭 -C")

# parser（子命令后 --threads/--tmpdir）
ns = build_parser().parse_args(
    ["count", "$WORK/reads_1.fastq", "-m", "21", "-s", "100M",
     "-o", "$WORK/out.jf", "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "count" and ns.threads == 8 and ns.tmpdir == "/tmp"
assert ns.reads == ["$WORK/reads_1.fastq"] and ns.kmer_size == 21
print("  OK: parser count")
PY

echo "==> [4/6] argv 构造验证 #2：histo / stats / query / dump / merge"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import JellyfishSkill, build_parser

skill = JellyfishSkill()
skill._resolve_binary = lambda: "jellyfish"

cmd = skill.build_command("histo", counts="$WORK/mer_counts.jf", threads=4)
s = " ".join(cmd)
assert s == "jellyfish histo -t 4 $WORK/mer_counts.jf", s
print("  OK:", s)

cmd = skill.build_command("histo", counts="$WORK/mer_counts.jf",
                          histogram_low=1, histogram_high=1000, threads=2)
s = " ".join(cmd)
assert "-l 1" in s and "-h 1000" in s and "-t 2" in s, s
print("  OK:", s)

cmd = skill.build_command("stats", counts="$WORK/mer_counts.jf")
assert " ".join(cmd) == "jellyfish stats $WORK/mer_counts.jf", cmd
print("  OK: stats")

cmd = skill.build_command("query", counts="$WORK/mer_counts.jf", kmer="ATGCATGCATGCATGCATGCA")
assert " ".join(cmd) == "jellyfish query $WORK/mer_counts.jf ATGCATGCATGCATGCATGCA", cmd
print("  OK: query")

cmd = skill.build_command("dump", counts="$WORK/mer_counts.jf")
assert " ".join(cmd) == "jellyfish dump $WORK/mer_counts.jf", cmd
print("  OK: dump")

cmd = skill.build_command("merge", merge_inputs=["a.jf", "b.jf"], output="$WORK/merged.jf")
s = " ".join(cmd)
assert s == "jellyfish merge -o $WORK/merged.jf a.jf b.jf", s
print("  OK:", s)

# parser：query kmer 位置参数
ns = build_parser().parse_args(["query", "$WORK/mer_counts.jf", "AAAA"])
assert ns.subcommand == "query" and ns.kmer == "AAAA"
print("  OK: parser query")
PY

echo "==> [5/6] build_command 运行时校验：缺必填 / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import JellyfishSkill

skill = JellyfishSkill()
skill._resolve_binary = lambda: "jellyfish"

for sub, kw in (("count", {}), ("histo", {}), ("stats", {}), ("query", {}),
                ("dump", {}), ("merge", {})):
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
print("  OK: 运行时参数校验")
PY

echo "==> [6/6] CLI 层校验：无子命令返回 2；stub 下构造命令；缺二进制报错；真实冒烟"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\necho "fake jellyfish"\nexit 0\n' > "$WORK/fakebin/jellyfish"
chmod +x "$WORK/fakebin/jellyfish"
python3 - <<PY
import sys, os, subprocess

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "count", "$WORK/reads_1.fastq",
     "-m", "21", "-s", "100M", "-o", "$WORK/out.jf", "--threads", "4"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "histo", "$WORK/mer_counts.jf",
     "-o", "$WORK/real.histo"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)

# 真实缺二进制（PATH 置空目录，排除宿主已装 jellyfish 的干扰）→ 明确报错 rc 1
emptybin = os.path.join("$WORK", "emptybin")
os.makedirs(emptybin, exist_ok=True)
env_nobin = dict(os.environ)
env_nobin["PATH"] = emptybin
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "stats", "$WORK/mer_counts.jf"],
    capture_output=True, text=True, env=env_nobin)
assert r.returncode == 1 and "未找到可执行文件 'jellyfish'" in r.stderr, (r.returncode, r.stderr)
print("  OK: CLI 层（构造命令 + 缺二进制报错）")
PY

if command -v jellyfish >/dev/null 2>&1; then
    jellyfish --version | head -n 1
else
    echo "  jellyfish 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
