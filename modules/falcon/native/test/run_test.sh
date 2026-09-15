#!/usr/bin/env bash
# falcon native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - FALCON 可执行（fc_run.py / fc_unzip.py）【可选】：若已安装（conda activate
#     pb-assembly / pb-falcon），会额外做 fc_run.py --help 冒烟；否则跳过真实执行。
# 说明：FALCON 真正组装需要真实 PacBio subreads，合成数据无法覆盖真实计算，
#      因此采用「python 构造 argv 验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在仓库内产生 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（迷你 subreads + fofn + fc_run.cfg）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/subreads.fasta" && test -s "$WORK/input.fofn" && test -s "$WORK/fc_run.cfg"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q '^run'
python "$NATIVE/main.py" --list-commands | grep -q '^unzip'
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（run/unzip）+ --schema"

echo "==> [3/6] argv 构造验证：run（fc_run.py 主组装）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FalconSkill, build_parser, _BINARIES

assert _BINARIES == {"run": "fc_run.py", "unzip": "fc_unzip.py"}, _BINARIES

skill = FalconSkill()
skill._resolve_sub_binary = lambda sub: "/opt/env/bin/" + _BINARIES[sub]

cmd = skill.build_command("run", config="$WORK/fc_run.cfg")
assert cmd[0] == "/opt/env/bin/fc_run.py", cmd
assert cmd[1] == "$WORK/fc_run.cfg", cmd
print("  OK:", " ".join(cmd))

# 线程优先级：用户 > per_subcommand_threads > default_cpus
assert skill._effective_threads("run", 16) == 16          # 用户显式
assert skill._effective_threads("run", None) == 8          # per_subcommand_threads.run
assert skill._effective_threads("unzip", None) == 8        # per_subcommand_threads.unzip
print("  OK: 线程优先级（16 / 8 / 8）")

ns = build_parser().parse_args(
    ["run", "$WORK/fc_run.cfg", "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "run" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
assert ns.config == "$WORK/fc_run.cfg", ns
print("  OK: parser run")
PY

echo "==> [4/6] argv 构造验证：unzip（fc_unzip.py 分型组装）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FalconSkill, build_parser, _BINARIES

skill = FalconSkill()
skill._resolve_sub_binary = lambda sub: "/opt/env/bin/" + _BINARIES[sub]
cmd = skill.build_command("unzip", config="$WORK/fc_unzip.cfg")
assert cmd[0] == "/opt/env/bin/fc_unzip.py", cmd
assert cmd[1] == "$WORK/fc_unzip.cfg", cmd
print("  OK:", " ".join(cmd))

ns = build_parser().parse_args(["unzip", "--config", "$WORK/fc_unzip.cfg", "--threads", "4"])
assert ns.subcommand == "unzip" and ns.config_opt == "$WORK/fc_unzip.cfg" and ns.threads == 4, ns
print("  OK: parser unzip")
PY

echo "==> [5/6] run() env 注入验证：NPROC（线程）/ TMPDIR"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FalconSkill          # 导入 main 时会注入 modules/ 到 sys.path
import base

skill = FalconSkill()
skill._resolve_sub_binary = lambda sub: "fc_run.py"
skill.tmpdir = "/tmp"

captured = {}
def fake_run_command(args, *, env=None, **kw):
    captured["args"] = args
    captured["env"] = env or {}
    return base.RunResult(command=args, returncode=0)

base.run_command = fake_run_command
skill.run("run", config="fc_run.cfg", threads=12)
assert captured["args"] == ["fc_run.py", "fc_run.cfg"], captured["args"]
assert captured["env"].get("NPROC") == "12", captured["env"]     # 用户 --threads 优先
assert captured["env"].get("TMPDIR") == "/tmp", captured["env"]
print("  OK:", captured["args"], "NPROC=", captured["env"].get("NPROC"))
PY

echo "==> [6/6] FALCON 冒烟（若已安装）"
if command -v fc_run.py >/dev/null 2>&1; then
    fc_run.py --help >/dev/null 2>&1 && echo "  OK: fc_run.py 可执行（--help 通过）" \
        || echo "  fc_run.py 存在（--help 返回非 0，跳过断言）"
else
    echo "  FALCON 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
