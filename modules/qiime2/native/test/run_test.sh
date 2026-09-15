#!/usr/bin/env bash
# qiime2 native 最小回归测试（插件-动作两段式命令构造 + argv 自省断言）
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - qiime（QIIME 2 2026.1）【可选】：未安装时用 stub 假二进制做 CLI 冒烟；
#     命令构造链路一律 monkeypatch _resolve_binary，本体不依赖真实 qiime。
# 本测试不下载/不建 conda env/不执行真实 QIIME 2 分析。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在源码目录生成 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（EMP fastq + metadata + qza 占位）"
python3 "$HERE/generate_data.py" "$WORK"
test -s "$WORK/01.emp-single-end-sequences/sequences.fastq.gz"
test -s "$WORK/sample-metadata.tsv"

echo "==> [2/6] 自省：--list-commands / --schema"
python3 "$NATIVE/main.py" --list-commands | grep -q '^tools\.import'
python3 "$NATIVE/main.py" --list-commands | grep -q '^dada2\.denoise-single'
python3 "$NATIVE/main.py" --list-commands | grep -q '^feature-table\.summarize'
python3 "$NATIVE/main.py" --list-commands | grep -q '^info'
python3 "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python3 -c "import json,sys; d=json.load(open('$WORK/schema.json')); assert d['title']=='qiime2_native' or d['title']=='qiime2', d['title']"
echo "  OK: --list-commands 含 29 个插件-动作 + --schema 有效"

echo "==> [3/6] argv 构造：plugins.actions 两段式 + 参数原样透传"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Qiime2Skill, build_parser, THREAD_FLAG

assert len(__import__("main").SUBCOMMANDS) == 29, len(__import__("main").SUBCOMMANDS)

skill = Qiime2Skill()
skill._resolve_binary = lambda: "/opt/env/bin/qiime"

# tools.import：两段式还原为 qiime tools import + 动作参数透传
cmd = skill.build_command(
    "tools.import",
    args=["--type", "EMPSingleEndSequences", "--input-path",
          "$WORK/01.emp-single-end-sequences", "--output-path", "$WORK/emp.qza"],
)
assert cmd[:3] == ["/opt/env/bin/qiime", "tools", "import"], cmd
assert cmd[3:] == ["--type", "EMPSingleEndSequences", "--input-path",
                   "$WORK/01.emp-single-end-sequences", "--output-path", "$WORK/emp.qza"], cmd
print("  OK:", " ".join(cmd))

# 顶层命令 info（无点）
cmd = skill.build_command("info")
assert cmd == ["/opt/env/bin/qiime", "info"], cmd
print("  OK:", " ".join(cmd))

# feature-table.summarize：连字符插件名
cmd = skill.build_command("feature-table.summarize",
                          args=["--i-table", "$WORK/table.qza", "--o-visualization", "$WORK/table.qzv"])
assert cmd[:3] == ["/opt/env/bin/qiime", "feature-table", "summarize"], cmd
print("  OK:", " ".join(cmd))
PY

echo "==> [4/6] 线程注入：--p-n-threads / --p-n-jobs + 优先级（override > per_subcommand > default）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import Qiime2Skill

skill = Qiime2Skill()
skill._resolve_binary = lambda: "qiime"

# dada2.denoise-single：--threads 覆盖 -> --p-n-threads 8
cmd = skill.build_command("dada2.denoise-single",
                          args=["--i-demultiplexed-seqs", "demux.qza", "--p-trunc-len", "120"],
                          threads=8)
s = " ".join(cmd)
assert s.endswith("--p-n-threads 8"), s
assert "dada2 denoise-single" in s, s
print("  OK:", s)

# per_subcommand_threads（meta 里 dada2.denoise-single=8）优先于 default_cpus
cmd = skill.build_command("dada2.denoise-single", args=[])
assert cmd[-2:] == ["--p-n-threads", "8"], cmd
print("  OK: per_subcommand ->", " ".join(cmd))

# feature-classifier.classify-sklearn -> --p-n-jobs
cmd = skill.build_command("feature-classifier.classify-sklearn",
                          args=["--i-classifier", "c.qza"], threads=6)
assert cmd[-2:] == ["--p-n-jobs", "6"], cmd
print("  OK:", " ".join(cmd))

# 无线程旗标的动作：不注入
cmd = skill.build_command("taxa.barplot", args=["--i-table", "t.qza"], threads=8)
assert "--p-n-threads" not in cmd and "--p-n-jobs" not in cmd, cmd
print("  OK: taxa.barplot 不注入线程 ->", " ".join(cmd))

# 用户已自带线程参数：不重复注入
cmd = skill.build_command("alignment.mafft",
                          args=["--i-sequences", "s.qza", "--p-n-threads", "0"], threads=8)
assert cmd.count("--p-n-threads") == 1 and cmd[-1] == "0", cmd
print("  OK: 用户自带线程参数不覆盖 ->", " ".join(cmd))

# 未知子命令
try:
    skill.build_command("tools.bogus")
    raise AssertionError("未知子命令应报错")
except ValueError:
    pass
print("  OK: 未知子命令抛错")
PY

echo "==> [5/6] parser 可解析（子命令后 --threads/--tmpdir）+ CLI 层（stub qiime）"
mkdir -p "$WORK/fakebin"
printf '#!/usr/bin/env bash\nprintf "STUB qiime %%s\\n" "$*"\n' > "$WORK/fakebin/qiime"
chmod +x "$WORK/fakebin/qiime"
python3 - <<PY
import sys, os, subprocess
sys.path.insert(0, "$NATIVE")
from main import build_parser

ns, extras = build_parser().parse_known_args(
    ["dada2.denoise-single", "--i-demultiplexed-seqs", "$WORK/demux.qza",
     "--p-trunc-len", "120", "--threads", "4", "--tmpdir", "$WORK"])
assert ns.subcommand == "dada2.denoise-single", ns
assert ns.threads == 4 and ns.tmpdir == "$WORK"
assert "--i-demultiplexed-seqs" in extras and "--p-trunc-len" in extras, extras
print("  OK: parser 捕获动作参数 extras =", extras)

# CLI 层：stub qiime 在 PATH -> 真实走 run()（构造 + 执行），返回 0
env = dict(os.environ)
env["PATH"] = "$WORK/fakebin:" + env.get("PATH", "")
r = subprocess.run(
    [sys.executable, "$NATIVE/main.py", "dada2.denoise-single",
     "--i-demultiplexed-seqs", "$WORK/demux.qza", "--threads", "8"],
    capture_output=True, text=True, env=env)
assert r.returncode == 0, (r.returncode, r.stderr)
assert "STUB qiime dada2 denoise-single" in r.stdout, r.stdout
assert "--i-demultiplexed-seqs $WORK/demux.qza" in r.stdout, r.stdout
assert "--p-n-threads 8" in r.stdout, r.stdout
print("  OK: CLI 层 stub ->", r.stdout.strip())

# 无子命令 -> help + rc 2
r = subprocess.run([sys.executable, "$NATIVE/main.py"], capture_output=True, text=True)
assert r.returncode == 2, r.returncode
print("  OK: 无子命令 rc 2")

# 无 qiime 二进制（无 stub PATH）-> 明确报错 rc 1
r = subprocess.run([sys.executable, "$NATIVE/main.py", "info"],
                   capture_output=True, text=True)
assert r.returncode == 1 and "未找到可执行文件 'qiime'" in r.stderr, (r.returncode, r.stderr)
print("  OK: 无二进制时明确报错 rc 1")
PY

echo "==> [6/6] 真实冒烟（本机已装 qiime 时才执行；否则跳过）"
if command -v qiime >/dev/null 2>&1; then
    qiime --version | head -n 1
else
    echo "  qiime 未安装，跳过真实冒烟（argv 构造验证已通过；安装见 README「环境安装」）"
fi

echo "ALL TESTS PASSED"
