#!/usr/bin/env bash
# busco native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - busco【可选】：若已安装（PATH 中有 busco，或设置 BUSCO_HOME），会额外做 busco --version 冒烟；
#     否则跳过真实执行。
# 说明：BUSCO 真实运行需要谱系数据库（OrthoDB odb10，数百 MB），合成数据无法覆盖真实评估，
#      因此对 run/list_datasets/config/plot 采用
#      「python 构造 argv 验证命令构建不崩溃（monkeypatch 二进制/脚本解析）」的断言方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（最小 FASTA + config ini 占位）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：run / list_datasets"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BuscoSkill, build_parser
skill = BuscoSkill()
skill._resolve_binary = lambda: "/opt/env/bin/busco"
cmd = skill.build_command(
    "run", input="$WORK/genome.fasta", mode="genome", lineage="basidiomycota_odb10",
    out_name="busco_out", offline=True, force=True, threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/env/bin/busco"), s
assert "-i $WORK/genome.fasta" in s and "-m genome" in s, s
assert "-l basidiomycota_odb10" in s and "-o busco_out" in s, s
assert "--offline" in s and "-f" in s and "-c 8" in s, s
print("  OK run:", s)

cmd = skill.build_command("list_datasets")
assert cmd == ["/opt/env/bin/busco", "--list-datasets"], cmd
print("  OK list_datasets:", " ".join(cmd))

# 缺 lineage 且未开 auto_lineage 应报 ValueError
try:
    skill.build_command("run", input="$WORK/genome.fasta")
    raise SystemExit("[FAIL] run 缺 lineage 未报错")
except ValueError:
    print("  OK: lineage 校验触发")

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["run", "-i", "$WORK/genome.fasta", "-m", "proteins", "-l", "fungi_odb10",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "run" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.mode == "proteins" and ns.lineage == "fungi_odb10", ns
print("  OK: parser run")
PY

echo "==> [4/5] argv 构造验证 #2：config / plot"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BuscoSkill
skill = BuscoSkill()
skill._resolve_script = lambda name: "/opt/env/bin/" + name

cmd = skill.build_command("config", config_in="$WORK/config.ini", config_out="$WORK/myconfig.ini")
s = " ".join(cmd)
assert s.startswith(sys.executable), s
assert "/opt/env/bin/busco_configurator.py" in s, s
assert s.endswith("$WORK/config.ini $WORK/myconfig.ini"), s
print("  OK config:", s)

cmd = skill.build_command("plot", plot_dir="$WORK/busco_out", plot_type="specific")
s = " ".join(cmd)
assert "/opt/env/bin/generate_plot.py" in s, s
assert s.endswith("-wd $WORK/busco_out -rt specific"), s
print("  OK plot:", s)
PY

echo "==> [5/5] busco 冒烟（若已安装）"
if command -v busco >/dev/null 2>&1; then
    busco --version | head -n 1
elif [[ -n "${BUSCO_HOME:-}" && -x "${BUSCO_HOME}/bin/busco" ]]; then
    "${BUSCO_HOME}/bin/busco" --version | head -n 1
else
    echo "  busco 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
