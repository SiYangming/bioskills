#!/usr/bin/env bash
# bless native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - bless 二进制【可选】：若已安装（native/install.sh --method source / native/Dockerfile /
#     Apptainer.def），默认只做「无参运行打印选项」冒烟（bless 无 --help/-v）；
#     完整错误修正冒烟（KMC + Bloom filter 真实跑合成数据）需显式 BLESS_FULL_SMOKE=1：
#       BLESS_FULL_SMOKE=1 bash test/run_test.sh
#     （完整链路对 k 值/内存敏感且受 MPI hostname 已知问题影响，默认不跑以免环境差异假失败）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "^correct" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json"

echo "==> [2/6] 生成合成测试数据（双端 + 单端 FASTQ）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/reads_1.fastq"
test -s "$WORK/reads_2.fastq"
test -s "$WORK/single.fastq"

echo "==> [3/6] argv 构造验证 #1：paired-end 默认参数 + 线程注入"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BlessSkill, build_parser
skill = BlessSkill()
skill._resolve_binary = lambda: "/usr/local/bin/bless"
cmd = skill.build_command("correct", read1="$WORK/reads_1.fastq", read2="$WORK/reads_2.fastq",
                          kmerlength=21, prefix="$WORK/out/illumina", threads=8)
s = " ".join(cmd)
assert cmd[0] == "/usr/local/bin/bless", s
assert "-read1 $WORK/reads_1.fastq" in s and "-read2 $WORK/reads_2.fastq" in s, s
assert "-kmerlength 21" in s and "-prefix $WORK/out/illumina" in s, s
assert "-smpthread 8" in s, s
print("  OK:", s)
# 用户文档式用法：-kmerlength 21 -prefix + -notrim + -load（多文库共享 k-mer 库）
cmd2 = skill.build_command("correct", read1="$WORK/reads_1.fastq", read2="$WORK/reads_2.fastq",
                           kmerlength=21, prefix="$WORK/frag", notrim=True, load="$WORK/frag")
s2 = " ".join(cmd2)
assert "-notrim" in s2 and "-load $WORK/frag" in s2, s2
print("  OK:", s2)
# parser 可解析完整 argv（子命令后 --threads/--tmpdir；短参 -1/-2/-k/-p）
ns = build_parser().parse_args(["correct", "-1", "$WORK/reads_1.fastq", "-2", "$WORK/reads_2.fastq",
                                "-k", "31", "-p", "$WORK/o", "--notrim",
                                "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "correct" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
assert ns.kmerlength == 31 and ns.prefix == "$WORK/o" and ns.notrim is True, ns
print("  OK: parser correct (PE 短参)")
PY

echo "==> [4/6] argv 构造验证 #2：单端 / 输入互斥 / 必填校验"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BlessSkill
skill = BlessSkill()
skill._resolve_binary = lambda: "bless"
# 单端模式
cmd = skill.build_command("correct", read="$WORK/single.fastq", kmerlength=15,
                          prefix="$WORK/single_out")
s = " ".join(cmd)
assert "-read $WORK/single.fastq" in s and "-kmerlength 15" in s, s
assert "-read1" not in s and "-read2" not in s, s
print("  OK:", s)
# 双端缺一个 mate → 报错
for kw in (dict(read1="$WORK/reads_1.fastq", prefix="$WORK/o"),
           dict(read2="$WORK/reads_2.fastq", prefix="$WORK/o")):
    try:
        skill.build_command("correct", **kw)
        raise SystemExit("缺一个 mate 时应报错")
    except ValueError as e:
        assert "read1" in str(e) or "read2" in str(e), e
        print("  OK: PE 缺 mate 报错 ->", e)
# 单端与双端互斥 → 报错
try:
    skill.build_command("correct", read="$WORK/single.fastq",
                        read1="$WORK/reads_1.fastq", read2="$WORK/reads_2.fastq",
                        prefix="$WORK/o")
    raise SystemExit("SE 与 PE 同时给时应报错")
except ValueError as e:
    assert "互斥" in str(e), e
    print("  OK: SE/PE 互斥报错 ->", e)
# 缺输入 / 缺 prefix → 报错
for kw in (dict(prefix="$WORK/o"), dict(read="$WORK/single.fastq")):
    try:
        skill.build_command("correct", **kw)
        raise SystemExit("缺输入或缺 prefix 时应报错")
    except ValueError as e:
        assert ("输入" in str(e)) or ("prefix" in str(e)), e
        print("  OK: 必填校验报错 ->", e)
PY

echo "==> [5/6] --dry-run 命令构建（main 入口，不执行）"
python "$NATIVE/main.py" correct -1 "$WORK/reads_1.fastq" -2 "$WORK/reads_2.fastq" \
    -k 21 -p "$WORK/dry" --notrim --dry-run | grep -q "^CMD:"

echo "==> [6/6] bless 冒烟（若已安装：无参运行打印选项；BLESS_FULL_SMOKE=1 时完整修正合成数据）"
if command -v bless >/dev/null 2>&1; then
    # 无参运行 = 打印全部选项（bless 无 --help/-v）；以选项签名识别「真 bless」：
    # ⚠️ macOS 自带 /usr/sbin/bless（设置启动盘的苹果系统工具）同名异义，须排除
    (cd "$WORK" && bless 2>&1 || true) > "$WORK/usage.txt"
    if grep -q '\-kmerlength' "$WORK/usage.txt" && grep -q '\-prefix' "$WORK/usage.txt"; then
        echo "  bless（NGS 错误修正）无参用法冒烟通过"
        if [[ "${BLESS_FULL_SMOKE:-0}" == "1" ]]; then
            mkdir -p "$WORK/real"
            (cd "$WORK" && bless -read1 reads_1.fastq -read2 reads_2.fastq \
                -kmerlength 21 -prefix real/out -notrim -smpthread 2)
            test -f "$WORK/real/out.1.corrected.fastq" || \
                test -f "$WORK/real/out.corrected.fastq"
            echo "  bless 完整修正冒烟通过（已产出 corrected.fastq）"
        else
            echo "  （未设 BLESS_FULL_SMOKE=1，跳过完整修正冒烟；argv 构造验证已通过）"
        fi
    else
        echo "  PATH 上的 bless 非 NGS BLESS（如 macOS /usr/sbin/bless 启动盘工具，同名异义），跳过真实冒烟"
    fi
else
    echo "  bless 未安装，跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
