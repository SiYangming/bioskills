#!/usr/bin/env bash
# qiime1 native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - QIIME 1.9.1 脚本（validate_mapping_file.py 等）【可选】：未装时用 stub 假脚本做 CLI 冒烟；
#     命令构造链路一律 monkeypatch _resolve_script，本体不依赖真实 QIIME 1。
# 本测试不下载/不执行真实 QIIME 1 分析（软件 deprecated）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在源码目录生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（mapping/seqs/fastq/otu_map/taxonomy/tree）"
python3 "$HERE/generate_data.py" "$WORK"
test -s "$WORK/mapping.txt" && test -s "$WORK/seqs.fna"

echo "==> [2/6] 自省：--list-commands / --schema"
python3 "$NATIVE/main.py" --list-commands | grep -q '^validate_mapping_file'
python3 "$NATIVE/main.py" --list-commands | grep -q '^pick_open_reference_otus'
python3 "$NATIVE/main.py" --list-commands | grep -q '^assign_taxonomy'
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 -c "import json; d=json.load(open('$WORK/schema.json')); assert d['title'] in ('qiime1_native','qiime1'), d['title']"
echo "  OK: --list-commands（15 个脚本）+ --schema 有效"

echo "==> [3/6] argv 构造：脚本参数透传 + 两段链路"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Qiime1Skill, build_parser, SCRIPTS, THREAD_FLAG

assert len(SCRIPTS) == 15, len(SCRIPTS)
assert THREAD_FLAG == {"pick_open_reference_otus": "-O", "parallel_identify_chimeric_seqs": "-O"}
assert all(v.endswith(".py") for v in SCRIPTS.values())

skill = Qiime1Skill()
skill._resolve_script = lambda sub: "/opt/qiime/bin/" + SCRIPTS[sub]

# validate_mapping_file：参数原样透传
cmd = skill.build_command(
    "validate_mapping_file",
    args=["-m", "$WORK/mapping.txt", "-o", "$WORK/01.mapping_file_output"],
)
assert cmd[0].endswith("validate_mapping_file.py"), cmd
assert cmd[1:] == ["-m", "$WORK/mapping.txt", "-o", "$WORK/01.mapping_file_output"], cmd
print("  OK:", " ".join(cmd))

# join_paired_ends：无 -O 注入
cmd = skill.build_command("join_paired_ends",
                          args=["-f", "$WORK/R1.fastq.gz", "-r", "$WORK/R2.fastq.gz",
                                "-o", "$WORK/02.join_paired_ends/F3D0"], threads=8)
assert cmd[0].endswith("join_paired_ends.py"), cmd
assert "-O" not in cmd, cmd
print("  OK:", " ".join(cmd))

# parser 可解析子命令与运行期选项（脚本短选项由 extras 捕获）
ns, extras = build_parser().parse_known_args(["validate_mapping_file", "-m", "$WORK/mapping.txt"])
assert ns.subcommand == "validate_mapping_file", ns
assert "$WORK/mapping.txt" in (list(ns.args) + list(extras)), (ns, extras)
print("  OK: parser")
PY

echo "==> [4/6] 线程注入：仅 pick_open_reference_otus / parallel_identify_chimeric_seqs 注入 -O"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Qiime1Skill, SCRIPTS

skill = Qiime1Skill()
skill._resolve_script = lambda sub: SCRIPTS[sub]

# pick_open_reference_otus：--threads 4 -> 注入 -O 4
cmd = skill.build_command(
    "pick_open_reference_otus",
    args=["-i", "$WORK/seqs.fna", "-p", "params.txt", "-o", "$WORK/out", "-a"],
    threads=4,
)
assert cmd[-2:] == ["-O", "4"], cmd
print("  OK:", " ".join(cmd))

# per_subcommand_threads 优先于 default_cpus（meta pick_open_reference_otus=4）
cmd = skill.build_command("pick_open_reference_otus", args=["-i", "x.fna"])
assert cmd[-2:] == ["-O", "4"], cmd
print("  OK: per_subcommand ->", " ".join(cmd))

# 用户已自带 -O：不重复注入
cmd = skill.build_command("parallel_identify_chimeric_seqs",
                          args=["-i", "aligned.fa", "-O", "8"], threads=4)
assert cmd.count("-O") == 1 and cmd[-1] == "8", cmd
print("  OK: 用户自带 -O 不覆盖 ->", " ".join(cmd))

# 未知子命令
try:
    skill.build_command("bogus_script")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 未知子命令抛错")
PY

echo "==> [5/6] CLI 层：stub 脚本构造命令 + deprecated 提示；无二进制报错"
mkdir -p "$WORK/fakebin"
for s in validate_mapping_file.py pick_open_reference_otus.py join_paired_ends.py; do
    printf '#!/usr/bin/env bash\nprintf "STUB %%s\\n" "$0"\n' > "$WORK/fakebin/$s"
    chmod +x "$WORK/fakebin/$s"
done
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

# validate_mapping_file：构造命令 + deprecated 提示
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "validate_mapping_file",
     "-m", "$WORK/mapping.txt", "-o", "$WORK/01.mapping_file_output"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr, r.stderr
assert "validate_mapping_file.py" in r.stdout and "$WORK/mapping.txt" in r.stdout, r.stdout
print("  OK: CLI validate_mapping_file ->", r.stdout.strip().splitlines()[-1].strip())

# pick_open_reference_otus：--threads 4 -> -O 4 出现在 stdout
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "pick_open_reference_otus",
     "-i", "$WORK/seqs.fna", "-o", "$WORK/out", "-a", "--threads", "4"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "-O" in r.stdout and "4" in r.stdout, r.stdout
print("  OK: CLI pick_open_reference_otus（-O 注入）")

# 无子命令 -> help + rc 2
r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode
print("  OK: 无子命令 rc 2")

# 无脚本二进制 -> 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "validate_mapping_file", "-m", "x", "-o", "y"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'validate_mapping_file.py'" in r.stderr, (r.returncode, r.stderr)
print("  OK: 无二进制时明确报错 rc 1")
PY

echo "==> [6/6] 真实冒烟（本机已装 QIIME 1.9.1 时跳过——说明型驱动不执行真实分析）"
if command -v print_qiime_config.py >/dev/null 2>&1; then
    echo "  已检测到 QIIME 1 脚本（说明型驱动不执行真实分析；argv 构造验证已覆盖）"
else
    echo "  QIIME 1.9.1 未安装，argv 构造验证已通过（安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
