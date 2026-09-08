#!/usr/bin/env bash
# lftp native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - lftp 二进制【可选】：若已安装（conda-forge / brew / PATH 中有 lftp），会额外做 lftp --version
#     冒烟；否则跳过真实执行。
# 说明：lftp 的真实下载/镜像需要远端 FTP/HTTPS 服务且会产生大文件，合成数据无法覆盖真实传输，
#      因此本脚本对各子命令采用「python 构造 argv 验证命令构建不崩溃 + 必填校验 + 假二进制
#      端到端（PATH 注入 fake lftp 记录 argv）」的降级断言方式（同 omiga / dia-nn / dorado 降级
#      测试写法）——重点断言 -e 命令串形态（lcd / get -c / mirror -c / exit）与 host、-P 注入。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/8] 生成测试数据（占位本地目录 + 远程路径清单 fixture）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/8] 假 lftp 二进制（记录 argv 供端到端断言）"
mkdir -p "$WORK/fakebin"
cat > "$WORK/fakebin/lftp" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$LFTP_LOG"
printf 'LFTP | Version 4.9.3 | Copyright (c) 1996-2024 Alexander V. Lukyanov\n'
exit 0
EOF
chmod +x "$WORK/fakebin/lftp"

echo "==> [3/8] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | grep -q "^get "
python "$NATIVE/main.py" --list-commands | grep -q "^mirror "
python "$NATIVE/main.py" --list-commands | grep -q "^eval "
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 - "$WORK/schema.json" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
assert schema["type"] == "object"
assert "subcommand" in schema["properties"], "schema 缺 subcommand 属性"
assert "host" in schema["properties"], "schema 缺 host 属性"
assert "remote_path" in schema["properties"], "schema 缺 remote_path 属性"
print("  OK: schema JSON 有效")
PY

echo "==> [4/8] CLI 端到端（fake lftp + --dry-run / 真实执行）"
export LFTP_LOG="$WORK/call.log"
REMOTE="/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra"
# get dry-run：显式 --threads 4 → 注入 -P 4；lcd 本地目录；get -c 断点续传
out="$(PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" get --host ftp-trace.ncbi.nlm.nih.gov \
    --remote-path "$REMOTE" --local-dir "$WORK/dl" --dry-run --threads 4)"
echo "  CMD: $out"
case "$out" in
    *"-P 4"*) echo "  OK: get --threads 4 → -P 4" ;;
    *) echo "  FAIL: get 未注入 -P 4: $out"; exit 1 ;;
esac
case "$out" in
    *"lcd $WORK/dl"*"get -c $REMOTE"*"exit"*) echo "  OK: get 命令串含 lcd / get -c / exit" ;;
    *) echo "  FAIL: get 命令串缺 lcd/get -c/exit: $out"; exit 1 ;;
esac
# mirror dry-run：默认 --threads 8（per_subcommand_threads.mirror）→ -P 8
out="$(PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" mirror --host ftp.sra.ebi.ac.uk \
    --remote-dir /vol1/fastq/SRR797 --local-dir "$WORK/dl" --dry-run)"
echo "  CMD: $out"
case "$out" in
    *"-P 8"*) echo "  OK: mirror 默认 → -P 8" ;;
    *) echo "  FAIL: mirror 未注入默认 -P 8: $out"; exit 1 ;;
esac
case "$out" in
    *"mirror -c /vol1/fastq/SRR797"*) echo "  OK: mirror 命令串含 mirror -c" ;;
    *) echo "  FAIL: mirror 命令串异常: $out"; exit 1 ;;
esac
# eval 真实执行（fake 记录 argv；命令串自动补 "; exit"）
PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" eval --host ftp.ncbi.nlm.nih.gov \
    --command "set net:timeout 30; get -c /genomes/ref.fa.gz" > /dev/null
grep -Fq "set net:timeout 30; get -c /genomes/ref.fa.gz; exit ftp.ncbi.nlm.nih.gov" "$WORK/call.log" \
    || { echo "  FAIL: eval 未记录期望命令串"; exit 1; }
echo "  OK: eval → 命令串自动补 exit"
# get 真实执行（fake 记录 argv）
PATH="$WORK/fakebin:$PATH" python "$NATIVE/main.py" get --host ftp-trace.ncbi.nlm.nih.gov \
    --remote-path "$REMOTE" --local-dir "$WORK/dl" > /dev/null
grep -Fq -- "-P 4" "$WORK/call.log" || { echo "  FAIL: get 真实执行未注入 -P 4"; exit 1; }
grep -Fq "get -c $REMOTE" "$WORK/call.log" || { echo "  FAIL: get 真实执行缺 get -c"; exit 1; }
echo "  OK: get 真实执行（fake）argv 记录正确"
# 缺二进制真实执行 → [ERROR] 且非零（未装 lftp 的降级路径；若已装真实 lftp 则跳过该负例）
if ! command -v lftp >/dev/null 2>&1; then
    set +e
    python "$NATIVE/main.py" get --host x --remote-path /y > /dev/null 2> "$WORK/err.log"
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
        echo "  FAIL: 无 lftp 时 get 应失败退出"; exit 1
    fi
    grep -q "未找到可执行文件" "$WORK/err.log" && echo "  OK: 缺二进制时报错路径正常"
fi

echo "==> [5/8] argv 构造验证 #1：get（全量参数 + 默认并发 + no-continue + local_dir 缺省）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LftpSkill
work = "$WORK"
skill = LftpSkill()
skill._resolve_binary = lambda: "/usr/bin/lftp"
# 全量参数：host + remote_path + local_dir + threads=4 + 额外命令
cmd = skill.build_command(
    "get", host="ftp-trace.ncbi.nlm.nih.gov",
    remote_path="/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra",
    local_dir=work + "/dl", threads=4,
    extra_lftp_cmds="set net:timeout 30",
)
s = " ".join(cmd)
assert s.startswith("/usr/bin/lftp -P 4 -e "), s
assert "lcd " + work + "/dl" in s and "get -c " in s and "set net:timeout 30; exit" in s, s
assert s.endswith("ftp-trace.ncbi.nlm.nih.gov"), s
print("  OK:", s)
# 默认并发：未显式 --threads → per_subcommand_threads.get=4 → -P 4
cmd2 = skill.build_command("get", host="h", remote_path="/r", local_dir=work + "/dl")
assert "-P 4" in " ".join(cmd2), " ".join(cmd2)
print("  OK (auto threads):", " ".join(cmd2))
# no-continue：continue_=False → 去掉 -c
cmd3 = skill.build_command("get", host="h", remote_path="/r", continue_=False)
assert " get /r" in " ".join(cmd3) and "get -c" not in " ".join(cmd3), " ".join(cmd3)
print("  OK (no-continue):", " ".join(cmd3))
# local_dir 缺省 "." → 不写 lcd
cmd4 = skill.build_command("get", host="h", remote_path="/r")
assert "lcd" not in " ".join(cmd4), " ".join(cmd4)
print("  OK (local_dir default .):", " ".join(cmd4))
# extra_args 透传（lftp 全局参数，置于 -e 之前）
cmd5 = skill.build_command("get", host="h", remote_path="/r", extra_args="-u user:pass")
s5 = " ".join(cmd5)
assert s5.startswith("/usr/bin/lftp -u user:pass -P 4 -e "), s5
print("  OK (extra_args):", s5)
# 必填校验：get 缺 remote_path → ValueError
try:
    skill.build_command("get", host="h")
    raise AssertionError("get 缺 remote_path 未抛错")
except ValueError as e:
    print("  OK: get 缺 remote_path ->", e)
# 必填校验：缺 host → ValueError
try:
    skill.build_command("get", remote_path="/r")
    raise AssertionError("缺 host 未抛错")
except ValueError as e:
    print("  OK: 缺 host ->", e)
PY

echo "==> [6/8] argv 构造验证 #2：mirror / eval / 未知子命令"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import LftpSkill
skill = LftpSkill()
skill._resolve_binary = lambda: "/usr/bin/lftp"
# mirror：默认 -P 8（per_subcommand_threads.mirror）；remote_dir；mirror -c
cmd = skill.build_command("mirror", host="ftp.sra.ebi.ac.uk", remote_dir="/vol1/fastq/SRR797",
                          local_dir="/data/fq")
s = " ".join(cmd)
assert s.startswith("/usr/bin/lftp -P 8 -e "), s
assert "lcd /data/fq" in s and "mirror -c /vol1/fastq/SRR797; exit" in s, s
assert s.endswith("ftp.sra.ebi.ac.uk"), s
print("  OK:", s)
# mirror 显式 --threads 1 → 不注入 -P
cmd2 = skill.build_command("mirror", host="h", remote_dir="/d", threads=1)
assert "-P" not in " ".join(cmd2), " ".join(cmd2)
print("  OK (threads=1 no -P):", " ".join(cmd2))
# eval：命令串已以 exit 结尾 → 不重复追加
cmd3 = skill.build_command("eval", host="h", command="get -c /x; exit")
assert cmd3 == ["/usr/bin/lftp", "-e", "get -c /x; exit", "h"], cmd3
s3 = " ".join(cmd3)
assert "; exit; exit" not in s3 and s3.endswith("get -c /x; exit h"), s3
print("  OK (eval no dup exit):", s3)
# eval 缺 command → ValueError
try:
    skill.build_command("eval", host="h")
    raise AssertionError("eval 缺 command 未抛错")
except ValueError as e:
    print("  OK: eval 缺 command ->", e)
# mirror 缺 remote_dir → ValueError
try:
    skill.build_command("mirror", host="h")
    raise AssertionError("mirror 缺 remote_dir 未抛错")
except ValueError as e:
    print("  OK: mirror 缺 remote_dir ->", e)
# 未知子命令 → ValueError
try:
    skill.build_command("nonexistent", host="h")
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
    (["get", "--host", "h", "--remote-path", "/r", "--local-dir", "/d",
      "--threads", "4", "--tmpdir", "/tmp"], "get", 4),
    (["mirror", "--host", "h", "--remote-dir", "/d", "--threads", "8"], "mirror", 8),
    (["eval", "--host", "h", "--command", "ls; exit", "--threads", "2"], "eval", 2),
]
for argv, sub, th in cases:
    ns = p.parse_args(argv)
    assert ns.subcommand == sub, ns
    assert ns.threads == th, ns
ns = p.parse_args(["get", "--host", "h", "--remote-path", "/r", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.tmpdir == "/tmp", ns
assert ns.remote_path == "/r", ns
# --no-continue → continue_=False
ns = p.parse_args(["get", "--host", "h", "--remote-path", "/r", "--no-continue"])
assert ns.continue_ is False, ns
ns = p.parse_args(["mirror", "--host", "h", "--remote-dir", "/d"])
assert ns.continue_ is True, ns
print("  OK: parser 子命令后 --threads/--tmpdir/--no-continue")
PY

echo "==> [8/8] 真实 lftp 冒烟（若已安装）"
if command -v lftp >/dev/null 2>&1; then
    lftp --version 2>&1 | head -n 1 && echo "  OK: 真实 lftp 冒烟通过"
else
    echo "  lftp 未安装，跳过真实冒烟（降级 argv 断言已通过）"
fi

echo "ALL TESTS PASSED"
