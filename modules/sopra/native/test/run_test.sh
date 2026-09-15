#!/usr/bin/env bash
# sopra native 最小回归测试（说明型驱动：命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - SOPRA v1.4.6 的 Perl 脚本【可选】：本驱动为说明型，不执行真实 scaffolding；
#     未装时用 stub 假脚本（PATH 注入）做 CLI 冒烟，argv 构造断言恒跑。
#   - 本测试不下载/不编译/不执行真实 SOPRA（任务约束 + 软件 deprecated）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（contigs/mates/SAM 占位）"
python "$HERE/generate_data.py" "$WORK"
test -s "$WORK/contig.fasta" && test -s "$WORK/frag.fasta" && test -s "$WORK/jump.fasta"
test -s "$WORK/frag_sopra.sam" && test -s "$WORK/jump_sopra.sam"
echo "  OK"

echo "==> [2/6] 自省：--list-commands / --schema"
for c in prep parse_sam read_parsed_sam scaf; do
    python "$NATIVE/main.py" --list-commands | grep -q "^$c"
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
echo "  OK: --list-commands（4 子命令）+ --schema"

echo "==> [3/6] argv 构造验证：prep / parse_sam"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SopraSkill, build_parser, _BINARIES

assert _BINARIES["prep"] == "s_prep_contigAseq_v1.4.6.pl"
assert _BINARIES["parse_sam"] == "s_parse_sam_v1.4.6.pl"
assert _BINARIES["read_parsed_sam"] == "s_read_parsed_sam_v1.4.6.pl"
assert _BINARIES["scaf"] == "s_scaf_v1.4.6.pl"

skill = SopraSkill()
skill._resolve_sub_binary = lambda sub: "/opt/SOPRA/" + _BINARIES[sub]

# prep：-contig -mate <frag> <jump> -a
cmd = skill.build_command("prep", contig="$WORK/contig.fasta",
                          mate_frag="$WORK/frag.fasta", mate_jump="$WORK/jump.fasta",
                          out_dir="$WORK/SOPRA_OUT")
s = " ".join(cmd)
assert "/opt/SOPRA/s_prep_contigAseq_v1.4.6.pl" in s, s
assert "-contig $WORK/contig.fasta" in s, s
assert "-mate $WORK/frag.fasta $WORK/jump.fasta" in s, s
assert "-a $WORK/SOPRA_OUT" in s, s
print("  OK:", s)

# parse_sam：-sam <frag> <jump> -a
cmd = skill.build_command("parse_sam",
                          sam=["$WORK/frag_sopra.sam", "$WORK/jump_sopra.sam"],
                          out_dir="$WORK/SOPRA_OUT")
s = " ".join(cmd)
assert "/opt/SOPRA/s_parse_sam_v1.4.6.pl" in s, s
assert "-sam $WORK/frag_sopra.sam $WORK/jump_sopra.sam" in s, s
assert "-a $WORK/SOPRA_OUT" in s, s
print("  OK:", s)

# parser：prep 子命令后 --threads/--tmpdir
ns = build_parser().parse_args(
    ["prep", "--contig", "$WORK/contig.fasta", "--mate-frag", "$WORK/frag.fasta",
     "-a", "$WORK/SOPRA_OUT", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "prep" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser prep")
PY

echo "==> [4/6] argv 构造验证：read_parsed_sam（多文库 -parsed/-d 配对）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SopraSkill, build_parser, _BINARIES

skill = SopraSkill()
skill._resolve_sub_binary = lambda sub: "/opt/SOPRA/" + _BINARIES[sub]

cmd = skill.build_command(
    "read_parsed_sam",
    parsed=["$WORK/frag_sopra.sam_parsed", "$WORK/jump_sopra.sam_parsed"],
    distance=[177, 3014], out_dir="$WORK/SOPRA_OUT")
s = " ".join(cmd)
assert "/opt/SOPRA/s_read_parsed_sam_v1.4.6.pl" in s, s
assert s.index("-parsed $WORK/frag_sopra.sam_parsed -d 177") < \
       s.index("-parsed $WORK/jump_sopra.sam_parsed -d 3014"), s
assert "-a $WORK/SOPRA_OUT" in s, s
print("  OK:", s)

ns = build_parser().parse_args(
    ["read_parsed_sam", "--parsed", "$WORK/frag_sopra.sam_parsed", "--distance", "177",
     "--parsed", "$WORK/jump_sopra.sam_parsed", "--distance", "3014", "-a", "$WORK/SOPRA_OUT"])
assert ns.parsed == ["$WORK/frag_sopra.sam_parsed", "$WORK/jump_sopra.sam_parsed"], ns
assert ns.distance == [177, 3014], ns
print("  OK: parser read_parsed_sam（多文库）")
PY

echo "==> [5/6] argv 构造验证：scaf + 运行时校验"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import SopraSkill, _BINARIES

skill = SopraSkill()
skill._resolve_sub_binary = lambda sub: "/opt/SOPRA/" + _BINARIES[sub]

cmd = skill.build_command("scaf", orient="orientdistinfo_c5", out_dir="$WORK/SOPRA_OUT")
s = " ".join(cmd)
assert s == "/opt/SOPRA/s_scaf_v1.4.6.pl -o orientdistinfo_c5 -a $WORK/SOPRA_OUT", s
print("  OK:", s)

# 缺必填
for sub, kw in (("prep", dict(mate_frag="f.fa", out_dir="d")),      # 缺 contig
                ("prep", dict(contig="c.fa", out_dir="d")),        # 缺 mate
                ("parse_sam", dict(out_dir="d")),                  # 缺 sam
                ("read_parsed_sam", dict(parsed=["p"], out_dir="d")),  # 缺 distance
                ("read_parsed_sam", dict(parsed=["p"], distance=[177])),  # 缺 out_dir
                ("scaf", dict(out_dir="d"))):                      # 缺 orient
    try:
        skill.build_command(sub, **kw)
        raise AssertionError("缺必填应报错: %r" % kw)
    except RuntimeError:
        pass

# parsed 与 distance 数量不一致
try:
    skill.build_command("read_parsed_sam", parsed=["p1", "p2"], distance=[177],
                        out_dir="d")
    raise AssertionError("parsed/distance 数量不一致应报错")
except RuntimeError:
    pass

# 未知子命令
try:
    skill.build_command("bogus", contig="c")
    raise AssertionError("未知子命令应报错")
except RuntimeError:
    pass
print("  OK: 运行时参数校验")
PY

echo "==> [6/6] CLI 层校验：无子命令 rc 2；stub 脚本时构造命令 + deprecated 提示"
mkdir -p "$WORK/fakebin"
for b in s_prep_contigAseq_v1.4.6.pl s_parse_sam_v1.4.6.pl \
         s_read_parsed_sam_v1.4.6.pl s_scaf_v1.4.6.pl; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/fakebin/$b"
    chmod +x "$WORK/fakebin/$b"
done
python3 - <<PY
import sys, os, subprocess

def norm_stdout(text: str) -> str:
    return " ".join(t for line in text.splitlines() for t in line.split() if t != "\\\\")

r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode

env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "scaf", "-o", "orientdistinfo_c5",
     "-a", "$WORK/SOPRA_OUT"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "已淘汰" in r.stderr, r.stderr
norm = norm_stdout(r.stdout)
assert "s_scaf_v1.4.6.pl" in norm and "-o orientdistinfo_c5" in norm, norm
print("  OK: CLI 层（scaf deprecated 提示 + 命令构造输出）")

# 真实缺脚本（无 stub PATH）→ 明确报错 rc 1
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "scaf", "-o", "orientdistinfo_c5", "-a", "d"],
    capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行脚本 's_scaf_v1.4.6.pl'" in r.stderr, \
    (r.returncode, r.stderr)
print("  OK: CLI 层（无脚本时明确报错 rc 1）")
PY

echo "ALL TESTS PASSED"
