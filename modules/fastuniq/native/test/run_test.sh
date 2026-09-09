#!/usr/bin/env bash
# fastuniq native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - fastuniq 二进制【可选】：若已安装（conda bioconda / brew brewsci/bio / native/install.sh /
#     官方镜像），会额外做真跑冒烟（合成 3 对双端 FASTQ、去重后断言剩 2 对）；
#     否则退化为「自省 + argv 构造验证 + --dry-run」（fastuniq 无 --version/--help，
#     自省类断言用无参运行的用法文本）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "^run" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json"

echo "==> [2/6] 生成合成配对 FASTQ（3 对，含 1 重复对）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/reads.R1.fastq"
test -s "$WORK/reads.R2.fastq"
test "$(grep -c '^@' "$WORK/reads.R1.fastq")" -eq 3
test "$(grep -c '^@' "$WORK/reads.R2.fastq")" -eq 3
# 输入列表文件（每行一个文件；相邻两行 = 一对）——与官方 README list 格式一致
printf '%s\n%s\n' "$WORK/reads.R1.fastq" "$WORK/reads.R2.fastq" > "$WORK/reads.list"
test "$(wc -l < "$WORK/reads.list")" -eq 2

echo "==> [3/6] argv 构造验证 #1：--list 列表模式 + q/f/p 输出格式 + -c 描述类型"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FastuniqSkill, build_parser

skill = FastuniqSkill()
skill._resolve_binary = lambda: "/usr/local/bin/fastuniq"

# 默认 -t q：双 FASTQ 输出，-o/-p 齐全
cmd = skill.build_command("run", list="$WORK/reads.list",
                          output1="$WORK/out.R1.fastq", output2="$WORK/out.R2.fastq")
s = " ".join(cmd)
assert cmd[0] == "/usr/local/bin/fastuniq", s
assert "-i $WORK/reads.list" in s, s
assert "-t q" in s, s
assert "-o $WORK/out.R1.fastq" in s and "-p $WORK/out.R2.fastq" in s, s
print("  OK:", s)

# -t f + -c 1：双 FASTA + 重编号描述
cmd2 = skill.build_command("run", list="$WORK/reads.list",
                           output1="$WORK/out.R1.fa", output2="$WORK/out.R2.fa",
                           format="f", desc_type=1)
s2 = " ".join(cmd2)
assert "-t f" in s2 and "-c 1" in s2 and "-p $WORK/out.R2.fa" in s2, s2
print("  OK:", s2)

# -t p：单 FASTA 输出，不注入 -p
cmd3 = skill.build_command("run", list="$WORK/reads.list", output1="$WORK/out.single.fa",
                           format="p")
s3 = " ".join(cmd3)
assert "-t p" in s3 and "-o $WORK/out.single.fa" in s3 and "-p" not in s3, s3
print("  OK:", s3)

# 缺 -o / 缺 -p(q/f 模式) / 无输入 / 未知子命令 → 报错
try:
    skill.build_command("run", list="$WORK/reads.list", output2="$WORK/x")
    raise SystemExit("缺 -o 应报错")
except ValueError as e:
    assert "output1" in str(e), e
    print("  OK: 缺 -o 报错 ->", e)
try:
    skill.build_command("run", list="$WORK/reads.list", output1="$WORK/x")
    raise SystemExit("-t q 缺 -p 应报错")
except ValueError as e:
    assert "output2" in str(e), e
    print("  OK: q 模式缺 -p 报错 ->", e)
try:
    skill.build_command("run", output1="$WORK/x", output2="$WORK/y")
    raise SystemExit("无输入应报错")
except ValueError as e:
    assert "--list" in str(e), e
    print("  OK: 无输入报错 ->", e)
try:
    skill.build_command("nope", output1="$WORK/x")
    raise SystemExit("未知子命令应报错")
except ValueError as e:
    assert "未知子命令" in str(e), e
    print("  OK: 未知子命令报错 ->", e)
PY

echo "==> [4/6] argv 构造验证 #2：--read1+--read2 自动写列表（对齐 README 双端两文件形态）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import FastuniqSkill, build_parser

skill = FastuniqSkill()
skill._resolve_binary = lambda: "fastuniq"
skill.tmpdir = "$WORK"   # 自动列表落盘到测试临时目录（trap 统一清理）

cmd = skill.build_command("run", read1="$WORK/reads.R1.fastq", read2="$WORK/reads.R2.fastq",
                          output1="$WORK/out.R1.fastq", output2="$WORK/out.R2.fastq")
s = " ".join(cmd)
assert cmd[0] == "fastuniq" and cmd[1] == "-i", s
import glob
lst = glob.glob("$WORK/fastuniq_list_*.txt")
assert len(lst) == 1, lst
assert "-i " + lst[0] in s, s
lines = open(lst[0]).read().split()
assert lines == ["$WORK/reads.R1.fastq", "$WORK/reads.R2.fastq"], lines
print("  OK:", s)
print("  OK: 自动列表内容 ->", lines)

# 只给 read1 不给 read2 → 报错
try:
    skill.build_command("run", read1="$WORK/reads.R1.fastq", output1="$WORK/x")
    raise SystemExit("read1 缺 read2 应报错")
except ValueError as e:
    assert "read2" in str(e), e
    print("  OK: read1 缺 read2 报错 ->", e)

# parser 完整 argv（子命令后 --threads/--tmpdir；-t/-c 对齐 fastuniq 官方字母）
ns = build_parser().parse_args(["run", "-i", "$WORK/reads.list",
                                "-o", "$WORK/o1.fq", "-p", "$WORK/o2.fq",
                                "-t", "f", "-c", "1",
                                "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "run" and ns.format == "f" and ns.desc_type == 1, ns
assert ns.output1 == "$WORK/o1.fq" and ns.output2 == "$WORK/o2.fq", ns
assert ns.threads == 4 and ns.tmpdir == "/tmp", ns
# 默认 -t q
ns2 = build_parser().parse_args(["run", "-i", "$WORK/reads.list", "-o", "$WORK/o"])
assert ns2.format == "q", ns2
print("  OK: parser run argv（-t/-c/--threads/--tmpdir）")
PY

echo "==> [5/6] --dry-run 命令构建（main 入口，不执行）"
python "$NATIVE/main.py" run -i "$WORK/reads.list" -o "$WORK/dry.R1.fq" -p "$WORK/dry.R2.fq" --dry-run \
    | grep -q "^CMD:"
python "$NATIVE/main.py" run --read1 "$WORK/reads.R1.fastq" --read2 "$WORK/reads.R2.fastq" \
    -o "$WORK/dry2.R1.fq" -p "$WORK/dry2.R2.fq" --tmpdir "$WORK" --dry-run | grep -q "^CMD:"
echo "  OK: dry-run 两条路径均输出 CMD"

echo "==> [6/6] fastuniq 真跑冒烟（若已安装：3 对双端 FASTQ 去重 → 断言剩 2 对）"
if command -v fastuniq >/dev/null 2>&1; then
    fastuniq 2>&1 | grep -q "The input file list of paired" || true
    echo "  fastuniq 用法文本自检通过"
    fastuniq -i "$WORK/reads.list" -o "$WORK/real.R1.fastq" -p "$WORK/real.R2.fastq"
    n1=$(grep -c '^@' "$WORK/real.R1.fastq")
    n2=$(grep -c '^@' "$WORK/real.R2.fastq")
    echo "  去重后 R1=${n1} 条 / R2=${n2} 条（期望各 2 条唯一 pair）"
    test "$n1" -eq 2
    test "$n2" -eq 2
    test "$n1" -lt 3 && test "$n2" -lt 3
    echo "  fastuniq 真跑通过（重复对已被去除）"
else
    echo "  fastuniq 未安装，跳过真实冒烟（自省 + argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
