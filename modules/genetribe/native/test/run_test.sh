#!/usr/bin/env bash
# genetribe native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - genetribe 二进制【可选】：若已安装（conda / 源码 / PATH 中有 genetribe），会额外做
#     genetribe -h 冒烟（banner 含 Version: 1.2.1）；否则跳过真实执行。
# 说明：GeneTribe core 需要真实基因组蛋白集 + 注释 + BLAST/MCScan 才能实际运行，合成数据无法
#      覆盖真实共线性搜索，因此本脚本对各子命令采用「python 构造 argv 验证命令构建不崩溃 +
#      必填校验 + 假二进制端到端（PATH 注入 fake genetribe 记录 argv）」的降级断言方式
#      （同 dia-nn / dorado 降级测试写法）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/8] 生成测试数据（占位 .fa/.bed/.chrlist/.genelength/.blast 等）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/8] 假 genetribe 二进制（记录 argv 供端到端断言）"
mkdir -p "$WORK/fakebin"
cat > "$WORK/fakebin/genetribe" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$GT_LOG"
printf 'Program: GeneTribe (fake for tests)\nVersion: 1.2.1\n'
exit 0
EOF
chmod +x "$WORK/fakebin/genetribe"

echo "==> [3/8] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q "^core "
python "$NATIVE/main.py" --list-commands | grep -q "^longestcds "
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - "$WORK/schema.json" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
assert schema["type"] == "object"
assert "subcommand" in schema["properties"], "schema 缺 subcommand 属性"
print("  OK: schema JSON 有效")
PY

echo "==> [4/8] CLI 端到端（fake genetribe + --dry-run / 真实执行）"
export GT_LOG="$WORK/call.log"
# core dry-run：显式 --threads 8 → 注入 -n 8
out="$(PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" core -l aet -f rice --dry-run --threads 8)"
echo "  CMD: $out"
case "$out" in
    *"-l aet -f rice"*) ;;
    *) echo "  FAIL: core dry-run 缺 -l/-f: $out"; exit 1 ;;
esac
case "$out" in
    *"-n 8"*) echo "  OK: core --threads 8 → -n 8" ;;
    *) echo "  FAIL: core 未注入 -n 8: $out"; exit 1 ;;
esac
# core dry-run：不带 --threads → 不注入 -n（沿用上游默认 36）
out2="$(PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" core -l aet -f rice --dry-run)"
if [[ "$out2" == *" -n "* ]]; then
    echo "  FAIL: 未显式 --threads 却注入 -n: $out2"; exit 1
fi
echo "  OK: 未显式 --threads 不注入 -n"
# RBH 真实执行（fake 记录 argv，exit 0）
PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" RBH -a "$WORK/A_vs_B.score" -b "$WORK/B_vs_A.score" > /dev/null
grep -q "RBH" "$WORK/call.log" || { echo "  FAIL: fake 未记录 RBH 调用"; exit 1; }
# 缺二进制真实执行 → [ERROR] 且非零（未装 genetribe 的降级路径；若已装真实 genetribe 则跳过该负例）
if ! command -v genetribe >/dev/null 2>&1; then
    set +e
    python "$NATIVE/main.py" CBS -i x.anchors -a a.bed -b b.bed -o o > /dev/null 2> "$WORK/err.log"
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
        echo "  FAIL: 无 genetribe 时 CBS 应失败退出"; exit 1
    fi
    grep -q "未找到可执行文件" "$WORK/err.log" && echo "  OK: 缺二进制时报错路径正常"
fi

echo "==> [5/8] argv 构造验证 #1：core（全量参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeneTribeSkill
work = "$WORK"
skill = GeneTribeSkill()
skill._resolve_binary = lambda: "/opt/genetribe/genetribe"
cmd = skill.build_command(
    "core", first_prefix="aet", second_prefix="rice", blast_dir=work,
    no_chr_group=True, confidence=True, split_sep=".", evalue="1e-5",
    bsr_threshold=75, no_collinearity=True, threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/genetribe/genetribe core "), s
assert "-l aet" in s and "-f rice" in s and "-d $WORK" in s, s
assert "-r" in s and "-c" in s and "-m" in s, s
assert "-s ." in s and "-e 1e-5" in s and "-n 8" in s and "-b 75" in s, s
print("  OK:", s)
# 必填校验：core 缺 -f 应抛 ValueError
try:
    skill.build_command("core", first_prefix="aet", threads=4)
    raise AssertionError("core 缺 -f 未抛错")
except ValueError as e:
    print("  OK: core 缺 -f ->", e)
PY

echo "==> [6/8] argv 构造验证 #2：corenog / sameassembly"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeneTribeSkill
work = "$WORK"
skill = GeneTribeSkill()
skill._resolve_binary = lambda: "/opt/genetribe/genetribe"
# corenog：有 -d/-c/-s/-e/-b/-n，无 -r/-m
cmd = skill.build_command("corenog", first_prefix="aet", second_prefix="rice",
                          blast_dir=work, confidence=True, split_sep=".",
                          evalue="1e-5", bsr_threshold=75, threads=16)
s = " ".join(cmd)
assert s.startswith("/opt/genetribe/genetribe corenog "), s
assert "-l aet" in s and "-f rice" in s and "-d $WORK" in s, s
assert "-c" in s and "-s ." in s and "-e 1e-5" in s and "-b 75" in s and "-n 16" in s, s
assert " -r" not in s and " -m" not in s, s
print("  OK:", s)
# sameassembly：仅 -l/-f
cmd = skill.build_command("sameassembly", first_prefix="IWGSCv1p1", second_prefix="IWGSCv1")
s = " ".join(cmd)
assert s == "/opt/genetribe/genetribe sameassembly -l IWGSCv1p1 -f IWGSCv1", s
print("  OK:", s)
try:
    skill.build_command("sameassembly", first_prefix="IWGSCv1p1")
    raise AssertionError("sameassembly 缺 -f 未抛错")
except ValueError as e:
    print("  OK: sameassembly 缺 -f ->", e)
PY

echo "==> [7/8] argv 构造验证 #3：RBH / CBS / longestcds"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GeneTribeSkill
work = "$WORK"
skill = GeneTribeSkill()
skill._resolve_binary = lambda: "/opt/genetribe/genetribe"
# RBH
cmd = skill.build_command("RBH", blast1=work + "/A_vs_B.score", blast2=work + "/B_vs_A.score")
s = " ".join(cmd)
assert s == "/opt/genetribe/genetribe RBH -a $WORK/A_vs_B.score -b $WORK/B_vs_A.score", s
print("  OK:", s)
# CBS
cmd = skill.build_command("CBS", anchors=work + "/aet.rice.lifted.anchors",
                          bed1=work + "/aet.bed", bed2=work + "/rice.bed", cbs_out=work + "/aet_rice")
s = " ".join(cmd)
assert "-i $WORK/aet.rice.lifted.anchors" in s, s
assert "-a $WORK/aet.bed" in s and "-b $WORK/rice.bed" in s, s
assert "-o $WORK/aet_rice" in s, s
print("  OK:", s)
# longestcds（-s 显式）
cmd = skill.build_command("longestcds", pep=work + "/rice.fa", split_sep=".")
s = " ".join(cmd)
assert s == "/opt/genetribe/genetribe longestcds -i $WORK/rice.fa -s .", s
print("  OK:", s)
# 必填校验
for name, kw in [("RBH", dict(blast1="x")),
                 ("CBS", dict(anchors="x", bed1="y", bed2="z")),
                 ("longestcds", {})]:
    try:
        skill.build_command(name, **kw)
        raise AssertionError("%s 缺参未抛错" % name)
    except ValueError as e:
        print("  OK: %s 缺参 ->" % name, e)
PY

echo "==> [8/8] parser 子命令后 --threads/--tmpdir + 真实 genetribe 冒烟（若已安装）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import build_parser
p = build_parser()
cases = [
    (["core", "-l", "aet", "-f", "rice", "--threads", "4", "--tmpdir", "/tmp"], "core", 4),
    (["corenog", "-l", "aet", "-f", "rice", "--threads", "4"], "corenog", 4),
    (["sameassembly", "-l", "a", "-f", "b", "--threads", "4"], "sameassembly", 4),
    (["RBH", "-a", "x", "-b", "y", "--threads", "2"], "RBH", 2),
    (["CBS", "-i", "x", "-a", "y", "-b", "z", "-o", "o", "--threads", "2"], "CBS", 2),
    (["longestcds", "-i", "x", "--threads", "2"], "longestcds", 2),
]
for argv, sub, th in cases:
    ns = p.parse_args(argv)
    assert ns.subcommand == sub, ns
    assert ns.threads == th, ns
ns = p.parse_args(["core", "-l", "aet", "-f", "rice", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.tmpdir == "/tmp", ns
print("  OK: parser 子命令后 --threads/--tmpdir")
PY
if command -v genetribe >/dev/null 2>&1; then
    genetribe -h 2>&1 | grep -q "Version:" && echo "  OK: 真实 genetribe 冒烟通过"
else
    echo "  genetribe 未安装，跳过真实冒烟（降级 argv 断言已通过）"
fi

echo "ALL TESTS PASSED"
