#!/usr/bin/env bash
# ampliconnoise native 最小回归测试（说明型驱动：MPI 命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - AmpliconNoise V1.27 程序（PyroNoise/PerseusD 等）【可选】：未装时用 stub 假程序做 CLI 冒烟；
#     命令构造链路一律 monkeypatch _resolve_program，本体不依赖真实 MPI/二进制。
# 本测试不下载/不编译/不执行真实 AmpliconNoise 分析（历史工具 + MPI）。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在源码目录生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（fna/qual/sff/Data 占位）"
python3 "$HERE/generate_data.py" "$WORK"
test -s "$WORK/reads.fna" && test -s "$WORK/reads.sff"

echo "==> [2/6] 自省：--list-commands / --schema"
python3 "$NATIVE/main.py" --list-commands | grep -q '^PyroNoise'
python3 "$NATIVE/main.py" --list-commands | grep -q '^PyroNoiseM'
python3 "$NATIVE/main.py" --list-commands | grep -q '^PerseusD'
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 -c "import json; d=json.load(open('$WORK/schema.json')); assert d['title'] in ('ampliconnoise_native','ampliconnoise'), d['title']"
echo "  OK: --list-commands（12 个程序）+ --schema 有效"

echo "==> [3/6] argv 构造：默认 mpirun -np + 程序参数透传"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AmpliconNoiseSkill, build_parser, SUBCOMMANDS

assert len(SUBCOMMANDS) == 12, len(SUBCOMMANDS)

skill = AmpliconNoiseSkill()
skill._resolve_program = lambda sub: "/opt/ampliconnoise-1.27/bin/" + sub

# PyroNoise：--threads 8 -> mpirun -np 8 <prog> + 参数
cmd = skill.build_command(
    "PyroNoise",
    args=["-s", "$WORK/reads.sff", "-d", "$WORK/Data", "-o", "$WORK/out"],
    threads=8,
)
assert cmd[:4] == ["mpirun", "-np", "8", "/opt/ampliconnoise-1.27/bin/PyroNoise"], cmd
assert cmd[4:] == ["-s", "$WORK/reads.sff", "-d", "$WORK/Data", "-o", "$WORK/out"], cmd
print("  OK:", " ".join(cmd))

# PerseusD：无额外参数也成立
cmd = skill.build_command("PerseusD", args=["$WORK/clustered.fna"], threads=4)
assert cmd == ["mpirun", "-np", "4", "/opt/ampliconnoise-1.27/bin/PerseusD",
               "$WORK/clustered.fna"], cmd
print("  OK:", " ".join(cmd))

# parser（程序短/长选项由 extras 捕获）
ns, extras = build_parser().parse_known_args(["PyroNoise", "-s", "$WORK/reads.sff", "--threads", "8"])
assert ns.subcommand == "PyroNoise" and ns.threads == 8, ns
assert "-s" in extras, extras
assert "$WORK/reads.sff" in (list(ns.args) + list(extras)), (ns, extras)
print("  OK: parser")
PY

echo "==> [4/6] 线程=MPI 进程数：优先级 override > per_subcommand > default"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AmpliconNoiseSkill

skill = AmpliconNoiseSkill()
skill._resolve_program = lambda sub: sub

# per_subcommand_threads（meta PyroNoise=8）优先于 default_cpus
cmd = skill.build_command("PyroNoise", args=[])
assert cmd[:3] == ["mpirun", "-np", "8"], cmd
print("  OK: per_subcommand ->", " ".join(cmd))

# override 优先
cmd = skill.build_command("PyroNoise", args=[], threads=2)
assert cmd[:3] == ["mpirun", "-np", "2"], cmd
print("  OK: override ->", " ".join(cmd))

# 无 per_subcommand 的程序走 default_cpus
cmd = skill.build_command("NDist", args=[])
assert cmd[:3] == ["mpirun", "-np", "4"], cmd
print("  OK: default ->", " ".join(cmd))

# 未知子命令
try:
    skill.build_command("Bogus")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 未知子命令抛错")
PY

echo "==> [5/6] CLI 层：stub 程序构造命令 + 历史提示；无二进制报错"
mkdir -p "$WORK/fakebin"
for p in PyroNoise PyroNoiseM PerseusD; do
    printf '#!/usr/bin/env bash\nprintf "STUB %%s\\n" "$0"\n' > "$WORK/fakebin/$p"
    chmod +x "$WORK/fakebin/$p"
done
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")

r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "PyroNoise",
     "-s", "$WORK/reads.sff", "-d", "$WORK/Data", "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "历史工具" in r.stderr or "已被 DADA2" in r.stderr, r.stderr
for frag in ("mpirun", "-np", "8", "PyroNoise", "$WORK/reads.sff"):
    assert frag in r.stdout, (frag, r.stdout)
print("  OK: CLI PyroNoise（mpirun -np 8 + 历史提示）")

r = subprocess.run([sys.executable, "$NATIVE/main.py", "PerseusD", "$WORK/clustered.fna"],
                   capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "PerseusD" in r.stdout and "mpirun" in r.stdout, r.stdout
print("  OK: CLI PerseusD")

# 无子命令 -> help + rc 2
r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode
print("  OK: 无子命令 rc 2")

# 无程序二进制 -> 明确报错 rc 1
r = subprocess.run([sys.executable, "$NATIVE/main.py", "PyroNoise", "-s", "x.sff"],
                   capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'PyroNoise'" in r.stderr, (r.returncode, r.stderr)
print("  OK: 无二进制时明确报错 rc 1")
PY

echo "==> [6/6] 真实冒烟（本机已装 AmpliconNoise 时跳过——说明型驱动不执行真实分析）"
if command -v PyroNoise >/dev/null 2>&1; then
    echo "  已检测到 AmpliconNoise 程序（说明型驱动不执行真实分析；argv 构造验证已覆盖）"
else
    echo "  AmpliconNoise 未安装，argv 构造验证已通过（安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
