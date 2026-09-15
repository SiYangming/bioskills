#!/usr/bin/env bash
# soapfuse native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - SOAPfuse-RUN.pl + perl + samtools + bedtools【可选】：若已部署（native/install.sh 或
#     native/Dockerfile / Apptainer.def），会额外做可执行脚本冒烟；否则跳过真实执行。
# 说明：SOAPfuse 需官方数据库/config 与真实双端 reads 才能产出结果，统一采用「python 构造 argv
#       验证命令构建不崩溃」的断言方式。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免导入 main.py 生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/5] 生成测试数据（config 占位 + 双端 FASTQ + 样本列表）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q '^run' "$WORK/commands.txt"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证 #1：run（官方 wiki 示例参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SoapfuseSkill, build_parser
skill = SoapfuseSkill()
skill._resolve_binary = lambda: "/opt/soapfuse/SOAPfuse-RUN.pl"
cmd = skill.build_command(
    "run", config="$WORK/config.txt", data_dir="$WORK/raw_data",
    sample_list="$WORK/sample.list", output="$WORK/out",
    start_step=1, end_step=9, tmp_postfix="sampleA", threads=8,
)
s = " ".join(cmd)
# 官方用法：perl SOAPfuse-RUN.pl ...
assert cmd[0] == "perl" and cmd[1] == "/opt/soapfuse/SOAPfuse-RUN.pl", s
assert "-c $WORK/config.txt" in s, s
assert "-fd $WORK/raw_data" in s, s
assert "-l $WORK/sample.list" in s, s
assert "-o $WORK/out" in s, s
assert "-fs 1" in s and "-es 9" in s, s
assert "-tp sampleA" in s, s
print("  OK:", s)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(
    ["run", "-c", "$WORK/config.txt", "-fd", "$WORK/raw_data",
     "-l", "$WORK/sample.list", "-o", "$WORK/out",
     "--threads", "4", "--tmpdir", "/tmp"]
)
assert ns.subcommand == "run" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.start_step == 1 and ns.end_step == 9, ns
print("  OK: parser run")
PY

echo "==> [4/5] argv 构造验证 #2：起始/结束步骤裁剪 + 必填校验"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SoapfuseSkill
skill = SoapfuseSkill()
skill._resolve_binary = lambda: "SOAPfuse-RUN.pl"
cmd = skill.build_command(
    "run", config="$WORK/config.txt", data_dir="$WORK/raw_data",
    sample_list="$WORK/sample.list", output="$WORK/out2",
    start_step=3, end_step=6,
)
s = " ".join(cmd)
assert "-fs 3" in s and "-es 6" in s, s
assert "-tp" not in s, s  # 未给 tmp_postfix 时不出现
# SOAPfuse 无线程 CLI 参数：不注入任何线程 flag
assert " -T " not in s and " -p " not in s and "-threads" not in s, s
print("  OK:", s)

for kw in (dict(data_dir="$WORK/raw_data", sample_list="$WORK/sample.list", output="$WORK/o"),
           dict(config="$WORK/config.txt", sample_list="$WORK/sample.list", output="$WORK/o"),
           dict(config="$WORK/config.txt", data_dir="$WORK/raw_data", output="$WORK/o"),
           dict(config="$WORK/config.txt", data_dir="$WORK/raw_data", sample_list="$WORK/sample.list")):
    try:
        skill.build_command("run", **kw)
        raise SystemExit("run 缺必填参数时应报错")
    except ValueError as e:
        print("  OK: run 必填校验 ->", e)
PY

echo "==> [5/5] SOAPfuse 冒烟（若已部署）"
if command -v SOAPfuse-RUN.pl >/dev/null 2>&1; then
    echo "  找到 SOAPfuse-RUN.pl: $(command -v SOAPfuse-RUN.pl)（perl $(perl -v 2>/dev/null | awk '/This is perl/{print $4}')）"
else
    echo "  SOAPfuse-RUN.pl 未部署，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
