#!/usr/bin/env bash
# aspera-connect native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - ascp 二进制【可选】：若已安装（官方 Connect / PATH 中有 ascp），会额外做 ascp 冒烟；
#     否则跳过真实执行。
# 说明：ascp 需要真实 FASP 服务端（NCBI/EBI）才能实际传输，合成数据无法覆盖真实网络下载，
#      因此本脚本对各子命令采用「python 构造 argv 验证命令构建不崩溃 + 必填校验」的断言方式
#      （同 dia-nn/omiga 降级测试写法）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（示例远端路径清单 + 下载目录占位）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/sra_paths.txt"

echo "==> [2/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - "$WORK/schema.json" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
assert schema["type"] == "object"
assert "subcommand" in schema["properties"], "schema 缺 subcommand 属性"
assert "source" in schema["properties"], "schema 缺 source 属性"
print("  OK: schema JSON 有效")
PY

echo "==> [3/6] argv 构造验证 #1：ascp 默认参数（NCBI SRA 形态，用户实装用法）"
python3 - <<PY
import os, sys
sys.path.insert(0, "$NATIVE")
from main import AsperaConnectSkill, build_parser
skill = AsperaConnectSkill()
skill._resolve_binary = lambda: "/usr/local/bin/ascp"
src = "$WORK/sra_paths.txt"
key_default = os.path.expanduser("~/.aspera/connect/etc/asperaweb_id_dsa.openssh")
cmd = skill.build_command("ascp", source="/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242",
                          dest=".", threads=8)
s = " ".join(cmd)
assert cmd[0] == "/usr/local/bin/ascp" and "-T" in cmd, s
assert "--host=ftp-private.ncbi.nlm.nih.gov" in s and "--user=anonftp" in s, s
assert "--mode=recv" in s, s
assert "-l 200M" in s, s
assert f"-i {key_default}" in s, s
assert s.rstrip().endswith("/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 ."), s
# ascp 无线程参数 → --threads/--tmpdir 仅接受不注入
assert "--threads" not in s and "--tmpdir" not in s, s
print("  OK:", s)
# parser：子命令后 --threads/--tmpdir 可解析且不进入命令
ns = build_parser().parse_args(
    ["ascp", "/sra/.../SRR797242", "./out", "--rate", "300M",
     "--threads", "8", "--tmpdir", "/tmp"])
assert ns.subcommand == "ascp" and ns.threads == 8 and ns.tmpdir == "/tmp", ns
assert ns.rate == "300M" and ns.dest == "./out", ns
print("  OK: parser ascp + --threads/--tmpdir（接受不注入）")
PY

echo "==> [4/6] argv 构造验证 #2：ascp 覆盖参数（EBI ENA 形态）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AsperaConnectSkill
skill = AsperaConnectSkill()
skill._resolve_binary = lambda: "ascp"
cmd = skill.build_command(
    "ascp",
    source="vol1/fastq/ERR164/ERR164407/ERR164407.fastq.gz",
    dest="/data/out",
    rate="300m",
    key="/keys/asperaweb_id_dsa.openssh",
    host="fasp.sra.ebi.ac.uk",
    user="era-fasp",
    port=33001,
)
s = " ".join(cmd)
assert "ascp" in s and "-T" in s, s
assert "-l 300m" in s, s
assert "-i /keys/asperaweb_id_dsa.openssh" in s, s
assert "-P 33001" in s, s
assert "--host=fasp.sra.ebi.ac.uk" in s and "--user=era-fasp" in s, s
assert "--mode=recv" in s, s
assert s.endswith("vol1/fastq/ERR164/ERR164407/ERR164407.fastq.gz /data/out"), s
print("  OK:", s)
# extra_args 透传（-k 1 断点续传等高级用法）
cmd2 = skill.build_command("ascp", source="vol1/x.fastq.gz", dest=".", extra_args="-k 1 --overwrite=diff")
assert "-k" in cmd2 and "1" in cmd2 and "--overwrite=diff" in cmd2, cmd2
print("  OK: extra_args 透传")
# 必填校验：缺 source 应抛 ValueError
try:
    skill.build_command("ascp", dest=".")
    raise AssertionError("缺 source 未抛错")
except ValueError as e:
    print("  OK: ascp 缺 source ->", e)
PY

echo "==> [5/6] argv 构造验证 #3：version 子命令 + dry-run 语义"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import AsperaConnectSkill, build_parser
skill = AsperaConnectSkill()
skill._resolve_binary = lambda: "/opt/aspera/.aspera/connect/bin/ascp"
cmd = skill.build_command("version")
assert cmd == ["/opt/aspera/.aspera/connect/bin/ascp", "--version"], cmd
print("  OK:", " ".join(cmd))
ns = build_parser().parse_args(["version", "--threads", "2", "--tmpdir", "/tmp"])
assert ns.subcommand == "version", ns
print("  OK: parser version + 运行期选项")
PY

echo "==> [6/6] ascp 冒烟（若已安装）"
if command -v ascp >/dev/null 2>&1; then
    ascp --version 2>&1 | head -n 2 || true
else
    echo "  ascp 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
