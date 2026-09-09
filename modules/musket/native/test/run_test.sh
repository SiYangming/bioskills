#!/usr/bin/env bash
# musket native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - musket 二进制【可选】：若已安装（native/install.sh 源码编译 / 自建容器 / PATH），会额外做
#     真跑冒烟（合成双文库 FASTQ 错误修正 → 断言 out.0/out.1 非空）；
#     否则退化为「自省 + argv 构造验证 + --dry-run」（musket 无 --version/--help，
#     不依赖真实二进制的断言全部走 python 层）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands > "$WORK/commands.txt"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
grep -q "^correct" "$WORK/commands.txt"
grep -q '"title"' "$WORK/schema.json"

echo "==> [2/7] 生成合成双文库 FASTQ（每文库 4 条 60bp，各含 1 条带替换错误的 read）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/f1.fastq"
test -s "$WORK/f2.fastq"
test "$(grep -c '^@' "$WORK/f1.fastq")" -eq 4
test "$(grep -c '^@' "$WORK/f2.fastq")" -eq 4

echo "==> [3/7] argv 构造验证 #1：-k 两值注入 / -o 单输出 / -omulti 前缀 / -p 线程 / reads 末尾"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MusketSkill

skill = MusketSkill()
skill._resolve_binary = lambda: "/usr/local/bin/musket"

# 教学文档形态：-k 21 50000000 -omulti out -p 4 -inorder f1 f2
cmd = skill.build_command("correct", reads=["$WORK/f1.fastq", "$WORK/f2.fastq"],
                          kmer_size=21, est_kmer_count=50000000,
                          omulti="out", inorder=True, threads=4)
s = " ".join(cmd)
assert cmd[0] == "/usr/local/bin/musket", s
assert "-k 21 50000000" in s, s
assert "-omulti out" in s, s
assert "-p 4" in s, s
assert "-inorder" in s, s
assert s.endswith("$WORK/f1.fastq $WORK/f2.fastq"), s
print("  OK:", s)

# -o 单输出形态（官方 Typical Command #1 同构）+ --threads 8 → -p 8
cmd2 = skill.build_command("correct", reads=["$WORK/f1.fastq", "$WORK/f2.fastq"],
                           kmer_size=21, est_kmer_count=536870912,
                           output="merged.fastq", threads=8)
s2 = " ".join(cmd2)
assert "-k 21 536870912" in s2 and "-o merged.fastq" in s2 and "-p 8" in s2, s2
assert "-omulti" not in s2 and "-inorder" not in s2, s2
print("  OK:", s2)

# 缺省线程（不显式 --threads）→ 取 optimization.per_subcommand_threads.correct=4 → -p 4
cmd3 = skill.build_command("correct", reads=["$WORK/f1.fastq"], omulti="o")
s3 = " ".join(cmd3)
assert "-p 4" in s3 and "-k" not in s3, s3   # 未显式给 -k → 不注入（官方默认 21/536870912 等价）
print("  OK:", s3)
PY

echo "==> [4/7] argv 构造验证 #2：互斥与参数校验（-o/-omulti、k>28、threads<2、缺 reads、未知子命令）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import MusketSkill

skill = MusketSkill()
skill._resolve_binary = lambda: "musket"

# -o 与 -omulti 互斥
try:
    skill.build_command("correct", reads=["a.fq"], output="x.fq", omulti="p")
    raise SystemExit("-o 与 -omulti 应报互斥错误")
except ValueError as e:
    assert "互斥" in str(e), e
    print("  OK: -o/-omulti 互斥报错 ->", e)

# k > MAX_KMER_SIZE(28) 报错（官方 Makefile 宏默认 28，需改宏重编译）
try:
    skill.build_command("correct", reads=["a.fq"], kmer_size=31, est_kmer_count=100)
    raise SystemExit("k>28 应报错")
except ValueError as e:
    assert "MAX_KMER_SIZE" in str(e), e
    print("  OK: k=31 报错 ->", e)

# -p 官方要求 >=2：显式 --threads 1 报错
try:
    skill.build_command("correct", reads=["a.fq"], threads=1)
    raise SystemExit("threads=1 应报错")
except ValueError as e:
    assert ">=2" in str(e), e
    print("  OK: threads=1 报错 ->", e)

# 缺 reads 报错
try:
    skill.build_command("correct")
    raise SystemExit("缺 reads 应报错")
except ValueError as e:
    assert "--reads" in str(e), e
    print("  OK: 缺 reads 报错 ->", e)

# 未知子命令报错
try:
    skill.build_command("nope", reads=["a.fq"])
    raise SystemExit("未知子命令应报错")
except ValueError as e:
    assert "未知子命令" in str(e), e
    print("  OK: 未知子命令报错 ->", e)

# 白名单整型参数（zlib/maxtrim/…）显式给出才注入
cmd = skill.build_command("correct", reads=["a.fq"], output="o.fq", threads=4,
                          zlib=1, maxtrim=5, maxerr=3, minmulti=2)
s = " ".join(cmd)
for flag in ("-zlib 1", "-maxtrim 5", "-maxerr 3", "-minmulti 2"):
    assert flag in s, s
assert "-maxbuff" not in s and "-maxiter" not in s, s   # 未给不注入
print("  OK:", s)
PY

echo "==> [5/7] parser argv（子命令后 --threads/--tmpdir；--reads 多文件）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import build_parser

ns = build_parser().parse_args(["correct",
                                "--reads", "$WORK/f1.fastq", "$WORK/f2.fastq",
                                "--kmer-size", "21", "--est-kmer-count", "50000000",
                                "--omulti", "out", "--inorder",
                                "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "correct", ns
assert ns.reads == ["$WORK/f1.fastq", "$WORK/f2.fastq"], ns.reads
assert ns.kmer_size == 21 and ns.est_kmer_count == 50000000, ns
assert ns.omulti == "out" and ns.output is None, ns
assert ns.inorder is True and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser correct argv（--reads/-k/--omulti/--inorder/--threads/--tmpdir）")

# -o 与 --omulti 在同一 parser 互斥
try:
    build_parser().parse_args(["correct", "--reads", "a.fq", "-o", "x", "--omulti", "p"])
    raise SystemExit("parser 层 -o/--omulti 应互斥")
except SystemExit:
    print("  OK: parser 层互斥组生效")
PY

echo "==> [6/7] --dry-run 命令构建（main 入口，不执行）"
python "$NATIVE/main.py" correct --reads "$WORK/f1.fastq" "$WORK/f2.fastq" \
    --kmer-size 21 --est-kmer-count 50000000 --omulti "$WORK/out" --inorder \
    --threads 4 --dry-run | grep -q "^CMD:"
python "$NATIVE/main.py" correct --reads "$WORK/f1.fastq" -o "$WORK/merged.fastq" \
    --tmpdir "$WORK" --dry-run | grep -q "^CMD:"
echo "  OK: dry-run 两条路径均输出 CMD"

echo "==> [7/7] musket 真跑冒烟（若已安装：双文库错误修正 → out.0/out.1 非空）"
if command -v musket >/dev/null 2>&1; then
    echo "  发现 musket，执行真实修正（-k 21 100000 -omulti out -p 2 -inorder）"
    python "$NATIVE/main.py" correct --reads "$WORK/f1.fastq" "$WORK/f2.fastq" \
        --kmer-size 21 --est-kmer-count 100000 --omulti "$WORK/out" --inorder \
        --threads 2
    test -s "$WORK/out.0"
    test -s "$WORK/out.1"
    echo "  musket 真跑通过：out.0/out.1 均已产出"
else
    echo "  musket 未安装，跳过真实冒烟（自省 + argv 构造验证已通过；安装见 native/install.sh）"
fi

echo "ALL TESTS PASSED"
