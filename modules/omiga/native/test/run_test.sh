#!/usr/bin/env bash
# omiga native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - omiga 二进制【可选】：若已安装（官方二进制 / PATH 中有 omiga），会额外做 omiga --version
#     冒烟；否则跳过真实执行。
# 说明：OmiGA 的 cis/trans/GWAS 分析需要真实 PLINK 基因型 + 表型数据，合成数据无法覆盖真实
#      关联运算，因此本脚本对各子命令采用「python 构造 argv 验证命令构建不崩溃 + 必填校验 +
#      假二进制端到端（PATH 注入 fake omiga 记录 argv）」的降级断言方式（同 dia-nn / dorado /
#      genetribe 降级测试写法）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/8] 生成测试数据（占位 PLINK 前缀 + 表型 + 协变量）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/8] 假 omiga 二进制（记录 argv 供端到端断言）"
mkdir -p "$WORK/fakebin"
cat > "$WORK/fakebin/omiga" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$OMIGA_LOG"
printf 'OmiGA (fake for tests) 1.8.17\n'
exit 0
EOF
chmod +x "$WORK/fakebin/omiga"

echo "==> [3/8] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q "^run "
python "$NATIVE/main.py" --list-commands | grep -q "^init "
python "$NATIVE/main.py" --list-commands | grep -q "^update "
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - "$WORK/schema.json" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
assert schema["type"] == "object"
assert "subcommand" in schema["properties"], "schema 缺 subcommand 属性"
assert "mode" in schema["properties"], "schema 缺 mode 属性"
print("  OK: schema JSON 有效")
PY

echo "==> [4/8] CLI 端到端（fake omiga + --dry-run / 真实执行）"
export OMIGA_LOG="$WORK/call.log"
# run dry-run：显式 --threads 8 → 注入 --threads 8
out="$(PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" run --mode cis --genotype "$WORK/geno" --phenotype "$WORK/pheno.txt" --prefix out --output-dir "$WORK/res" --dry-run --threads 8)"
echo "  CMD: $out"
case "$out" in
    *"--mode cis"*) ;;
    *) echo "  FAIL: run dry-run 缺 --mode cis: $out"; exit 1 ;;
esac
case "$out" in
    *"--threads 8"*) echo "  OK: run --threads 8 → --threads 8" ;;
    *) echo "  FAIL: run 未注入 --threads 8: $out"; exit 1 ;;
esac
case "$out" in
    *"--genotype $WORK/geno"*"--phenotype $WORK/pheno.txt"*"--prefix out"*"--output-dir $WORK/res"*) echo "  OK: 白名单参数齐全" ;;
    *) echo "  FAIL: 白名单参数缺失: $out"; exit 1 ;;
esac
# init / update 真实执行（fake 记录 argv，exit 0）
PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" init > /dev/null
PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" update > /dev/null
grep -q -- "--init" "$WORK/call.log" || { echo "  FAIL: fake 未记录 --init 调用"; exit 1; }
grep -q -- "--update" "$WORK/call.log" || { echo "  FAIL: fake 未记录 --update 调用"; exit 1; }
echo "  OK: init → --init / update → --update"
# 缺二进制真实执行 → [ERROR] 且非零（未装 omiga 的降级路径；若已装真实 omiga 则跳过该负例）
if ! command -v omiga >/dev/null 2>&1; then
    set +e
    python "$NATIVE/main.py" run --mode cis > /dev/null 2> "$WORK/err.log"
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
        echo "  FAIL: 无 omiga 时 run 应失败退出"; exit 1
    fi
    grep -q "未找到可执行文件" "$WORK/err.log" && echo "  OK: 缺二进制时报错路径正常"
fi

echo "==> [5/8] argv 构造验证 #1：run（cis 全量参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OmiGASkill
work = "$WORK"
skill = OmiGASkill()
skill._resolve_binary = lambda: "/opt/omiga/bin/omiga"
cmd = skill.build_command(
    "run", mode="cis", genotype=work + "/geno", phenotype=work + "/pheno.txt",
    covariates=work + "/covariates.txt", prefix="out", output_dir=work + "/res", threads=8,
)
s = " ".join(cmd)
assert s.startswith("/opt/omiga/bin/omiga --mode cis --threads 8 "), s
assert "--genotype $WORK/geno" in s and "--phenotype $WORK/pheno.txt" in s, s
assert "--covariates $WORK/covariates.txt" in s, s
assert "--prefix out" in s and "--output-dir $WORK/res" in s, s
print("  OK:", s)
# 线程自动注入：未显式 --threads 时注入 optimization 默认（meta per_subcommand_threads.run=4）
cmd2 = skill.build_command("run", mode="trans", genotype=work + "/geno",
                           phenotype=work + "/pheno.txt", prefix="t", output_dir=work)
s2 = " ".join(cmd2)
assert "--threads 4" in s2, s2
print("  OK (auto threads):", s2)
# extra_args 透传（白名单外参数追加末尾）
cmd3 = skill.build_command("run", mode="cis", genotype="g", phenotype="p",
                           prefix="o", output_dir="d", extra_args="--some-upstream-flag value")
s3 = " ".join(cmd3)
assert "--some-upstream-flag value" in s3 and s3.endswith("--some-upstream-flag value"), s3
print("  OK (extra_args):", s3)
# 必填校验：run 缺 --mode 应抛 ValueError
try:
    skill.build_command("run", genotype="g", phenotype="p", threads=4)
    raise AssertionError("run 缺 --mode 未抛错")
except ValueError as e:
    print("  OK: run 缺 --mode ->", e)
PY

echo "==> [6/8] argv 构造验证 #2：init / update / extra 透传"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import OmiGASkill
skill = OmiGASkill()
skill._resolve_binary = lambda: "/opt/omiga/bin/omiga"
assert skill.build_command("init") == ["/opt/omiga/bin/omiga", "--init"], skill.build_command("init")
print("  OK: init ->", " ".join(skill.build_command("init")))
assert skill.build_command("update") == ["/opt/omiga/bin/omiga", "--update"]
print("  OK: update ->", " ".join(skill.build_command("update")))
try:
    skill.build_command("nonexistent")
    raise AssertionError("未知子命令未抛错")
except ValueError as e:
    print("  OK: 未知子命令 ->", e)
PY

echo "==> [7/8] parser 子命令后 --threads/--tmpdir"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import build_parser
p = build_parser()
cases = [
    (["run", "--mode", "cis", "--genotype", "g", "--phenotype", "p",
      "--prefix", "o", "--output-dir", "d", "--threads", "4", "--tmpdir", "/tmp"], "run", 4),
    (["init", "--threads", "2"], "init", 2),
    (["update", "--threads", "2"], "update", 2),
]
for argv, sub, th in cases:
    ns = p.parse_args(argv)
    assert ns.subcommand == sub, ns
    assert ns.threads == th, ns
ns = p.parse_args(["run", "--mode", "cis", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.tmpdir == "/tmp", ns
assert ns.mode == "cis", ns
print("  OK: parser 子命令后 --threads/--tmpdir")
PY

echo "==> [8/8] 真实 omiga 冒烟（若已安装）"
if command -v omiga >/dev/null 2>&1; then
    omiga --version 2>&1 | head -n 2 && echo "  OK: 真实 omiga 冒烟通过"
else
    echo "  omiga 未安装，跳过真实冒烟（降级 argv 断言已通过）"
fi

echo "ALL TESTS PASSED"
