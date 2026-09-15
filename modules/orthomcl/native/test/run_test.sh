#!/usr/bin/env bash
# orthomcl native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - OrthoMCL 2.0.9 脚本【可选】：未安装时全部退化为「python 构造 argv 验证命令构建」
#     断言（monkeypatch 脚本解析），不实际运行流程（依赖 MySQL、软件 deprecated）。
# 覆盖：adjust_fasta / filter_fasta / blast_parser / load_blast / pairs / dump_pairs /
#      mcl_to_groups / install_schema 八个子命令的 argv 构造 + 线程优先级 + 运行时校验。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免 import main 时生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（FASTA / BLAST / config 占位）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/proteome.fasta" && test -s "$WORK/blast.out" && test -s "$WORK/orthomcl.config"

echo "==> [2/6] 自省：--list-commands / --schema"
for sub in adjust_fasta filter_fasta blast_parser load_blast pairs dump_pairs mcl_to_groups install_schema; do
    python "$NATIVE/main.py" --list-commands | grep -q "^$sub"
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/6] argv 构造验证：adjust_fasta / filter_fasta / blast_parser"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OrthomclSkill, _BINARIES

assert _BINARIES["adjust_fasta"] == "orthomclAdjustFasta"
assert _BINARIES["mcl_to_groups"] == "orthomclMclToGroups"
assert len(_BINARIES) == 8, _BINARIES

skill = OrthomclSkill()
skill._resolve_sub_binary = lambda sub: "/opt/orthomcl/bin/" + _BINARIES[sub]

cmd = skill.build_command("adjust_fasta", species="ncra", fasta="$WORK/proteome.fasta", id_length=10)
s = " ".join(cmd)
assert s == "/opt/orthomcl/bin/orthomclAdjustFasta ncra $WORK/proteome.fasta 10", s
print("  OK:", s)

cmd = skill.build_command("filter_fasta", input_dir="$WORK/compliantFasta", min_len=30, max_percent_stop=20)
s = " ".join(cmd)
assert s == "/opt/orthomcl/bin/orthomclFilterFasta $WORK/compliantFasta 30 20", s
print("  OK:", s)

# filter_fasta 只给 input_dir → 不带长度参数
cmd = skill.build_command("filter_fasta", input_dir="$WORK/compliantFasta")
assert cmd == ["/opt/orthomcl/bin/orthomclFilterFasta", "$WORK/compliantFasta"], cmd
print("  OK:", " ".join(cmd))

cmd = skill.build_command("blast_parser", blast_output="$WORK/blast.out", compliant_dir="$WORK/compliantFasta")
s = " ".join(cmd)
assert s == "/opt/orthomcl/bin/orthomclBlastParser $WORK/blast.out $WORK/compliantFasta", s
print("  OK:", s)
PY

echo "==> [4/6] argv 构造验证：load_blast / pairs / dump_pairs / mcl_to_groups / install_schema"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OrthomclSkill, _BINARIES

skill = OrthomclSkill()
skill._resolve_sub_binary = lambda sub: "/opt/orthomcl/bin/" + _BINARIES[sub]

cmd = skill.build_command("load_blast", config="$WORK/orthomcl.config", similar_sequences="$WORK/similarSequences.txt")
s = " ".join(cmd)
assert s == "/opt/orthomcl/bin/orthomclLoadBlast $WORK/orthomcl.config $WORK/similarSequences.txt", s
print("  OK:", s)

cmd = skill.build_command("pairs", config="$WORK/orthomcl.config", log="$WORK/pairs.log", cleanup="yes")
s = " ".join(cmd)
assert s == "/opt/orthomcl/bin/orthomclPairs $WORK/orthomcl.config $WORK/pairs.log yes", s
print("  OK:", s)

cmd = skill.build_command("dump_pairs", config="$WORK/orthomcl.config")
assert cmd == ["/opt/orthomcl/bin/orthomclDumpPairsFiles", "$WORK/orthomcl.config"], cmd
print("  OK:", " ".join(cmd))

cmd = skill.build_command("mcl_to_groups", prefix="OCG", start=1)
assert cmd == ["/opt/orthomcl/bin/orthomclMclToGroups", "OCG", "1"], cmd
print("  OK:", " ".join(cmd))

cmd = skill.build_command("install_schema", config="$WORK/orthomcl.config", log="$WORK/schema.log")
assert cmd == ["/opt/orthomcl/bin/orthomclInstallSchema", "$WORK/orthomcl.config", "$WORK/schema.log"], cmd
print("  OK:", " ".join(cmd))
PY

echo "==> [5/6] 线程优先级 + 运行时校验（缺必填 / 未知子命令 / 缺脚本）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OrthomclSkill

skill = OrthomclSkill()
# 线程优先级：用户显式 > per_subcommand > 全局默认
assert skill._effective_threads("pairs", 8) == 8, skill._effective_threads("pairs", 8)
assert skill._effective_threads("pairs", None) >= 1
assert skill._effective_threads("pairs", None) == int(
    (skill.meta.get("optimization", {}) or {}).get("per_subcommand_threads", {}).get("default", skill.cpus))
print("  OK: 线程优先级")

skill._resolve_sub_binary = lambda sub: "orthomcl"
# 缺必填参数
for sub, kw in (("adjust_fasta", dict(species="ncra")),
                ("filter_fasta", dict()),
                ("blast_parser", dict(blast_output="b.out")),
                ("load_blast", dict(config="c")),
                ("pairs", dict(config="c")),
                ("dump_pairs", dict()),
                ("mcl_to_groups", dict(prefix="OCG")),
                ("install_schema", dict(config="c"))):
    try:
        skill.build_command(sub, **kw)
        raise AssertionError("应抛 RuntimeError: %s %r" % (sub, kw))
    except RuntimeError:
        pass
# 未知子命令
try:
    skill.build_command("bogus")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
# 真实缺脚本（无 monkeypatch）→ 明确报错
clean = OrthomclSkill()
try:
    clean.build_command("dump_pairs", config="c")
    raise AssertionError("缺脚本应抛 RuntimeError")
except RuntimeError as e:
    assert "未找到可执行脚本" in str(e), e
print("  OK: 运行时参数校验")
PY

echo "==> [6/6] CLI 冒烟：stub 假脚本 → 打印构造命令（不执行真实流程）"
mkdir -p "$WORK/fakebin"
for b in orthomclAdjustFasta orthomclFilterFasta orthomclBlastParser orthomclLoadBlast orthomclPairs orthomclDumpPairsFiles orthomclMclToGroups orthomclInstallSchema; do
    printf '#!/usr/bin/env bash\necho "EXAMPLE usage"\n' > "$WORK/fakebin/$b"
    chmod +x "$WORK/fakebin/$b"
done
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

# 无子命令 → help + rc 2
r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode

# dump_pairs：stub PATH 下构造命令成功（rc 0），打印 deprecated 提示与 hint
r = subprocess.run([sys.executable, "$NATIVE/main.py", "dump_pairs", "$WORK/orthomcl.config"],
                   capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已停止维护" in r.stderr, r.stderr
assert "orthomclDumpPairsFiles" in r.stdout and "$WORK/orthomcl.config" in r.stdout, r.stdout
assert "mclInput" in r.stderr, r.stderr

# mcl_to_groups：stdout 重定向 hint
r = subprocess.run([sys.executable, "$NATIVE/main.py", "mcl_to_groups", "OCG", "1"],
                   capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
# 命令按 " \\\n    " 续行打印：逐行分词并丢弃续行反斜杠
norm = " ".join(t for line in r.stdout.splitlines() for t in line.split() if t != "\\\\")
assert "orthomclMclToGroups OCG 1" in norm, norm
assert "重定向" in r.stderr, r.stderr
print("  OK: CLI 层（stub 脚本 + 命令构造输出）")
PY

if command -v orthomclAdjustFasta >/dev/null 2>&1; then
    echo "  已检测到 OrthoMCL 脚本（说明型驱动不执行真实流程；argv 构造验证已覆盖）"
else
    echo "  OrthoMCL 未安装，argv 构造验证已通过（安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
