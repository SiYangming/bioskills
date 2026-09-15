#!/usr/bin/env bash
# beagle-lib native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - BEAGLE 库【可选】：若已安装（native/install.sh 编译 / conda beagle-lib）且 pkg-config
#     在默认前缀找到 hmsbeagle-1，会额外做版本冒烟；否则跳过真实执行。
# 说明：BEAGLE 是库，真实编译安装耗时且需 autotools；合成数据无法覆盖真实编译，
#      因此采用「python 构造 argv 验证命令构建不崩溃 + 自省命令断言」的方式。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; find "$NATIVE" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true; }
trap cleanup EXIT

echo "==> [1/5] 生成测试数据（最小源码目录占位）"
python "$HERE/generate_data.py" "$WORK"
test -x "$WORK/beagle-lib-3.1.2/autogen.sh"

echo "==> [2/5] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
for c in install verify flags; do
    grep -q "^${c}" "$WORK/commands.txt" || { echo "  [FAIL] --list-commands 缺少 ${c}" >&2; exit 1; }
done
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/5] argv 构造验证（monkeypatch _resolve_pkg_config）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import BeagleLibSkill, build_parser

skill = BeagleLibSkill()
skill._resolve_pkg_config = lambda: "/opt/env/bin/pkg-config"   # monkeypatch：惰性解析

# verify / flags：pkg-config 模块名 hmsbeagle-1
assert skill.build_command("verify") == ["/opt/env/bin/pkg-config", "--modversion", "hmsbeagle-1"]
assert skill.build_command("flags") == ["/opt/env/bin/pkg-config", "--cflags", "--libs", "hmsbeagle-1"]

# install：多步源码构建（bash -lc），线程注入 make -j、前缀注入 configure
cmd = skill.build_command("install", source_dir="$WORK/beagle-lib-3.1.2", prefix="$WORK/pfx")
assert cmd[0] == "bash" and cmd[1] == "-lc", cmd
script = cmd[2]
assert "./autogen.sh" in script and '--prefix="$WORK/pfx"' in script, script
assert "make -j 8" in script and "make install" in script, script
# 显式 --threads 覆盖
script2 = skill.build_command("install", source_dir="$WORK/beagle-lib-3.1.2", prefix="$WORK/pfx", threads=2)[2]
assert "make -j 2" in script2, script2
# extra_args 透传给 configure
script3 = skill.build_command("install", source_dir="$WORK/beagle-lib-3.1.2", prefix="$WORK/pfx",
                              extra_args="--enable-sse")[2]
assert "--enable-sse" in script3, script3

# 线程优先级：显式 > per_subcommand_threads(install=8) > default(4)
assert skill._effective_threads("install", 4) == 4
assert skill._effective_threads("install", None) == 8
assert skill._effective_threads("verify", None) == 4

# 环境变量：默认前缀下的三个搜索路径
skill._apply_prefix("$WORK/pfx")
assert skill.env_vars["PKG_CONFIG_PATH"] == "$WORK/pfx/lib/pkgconfig", skill.env_vars
assert skill.env_vars["LD_LIBRARY_PATH"] == "$WORK/pfx/lib", skill.env_vars
assert skill.env_vars["C_INCLUDE_PATH"] == "$WORK/pfx/include", skill.env_vars
print("  OK: install/verify/flags argv + 线程优先级 + 环境变量")

# parser：install 的 --prefix/--source-dir/--threads/--tmpdir
ns = build_parser().parse_args(["install", "--prefix", "$WORK/pfx", "--source-dir", "$WORK/beagle-lib-3.1.2",
                                "--threads", "4", "--tmpdir", "$WORK"])
assert ns.subcommand == "install" and ns.prefix == "$WORK/pfx" and ns.source_dir == "$WORK/beagle-lib-3.1.2", ns
ns2 = build_parser().parse_args(["verify", "--prefix", "$WORK/pfx"])
assert ns2.subcommand == "verify" and ns2.prefix == "$WORK/pfx", ns2
print("  OK: parser install/verify")
PY

echo "==> [4/5] 未知子命令应报错"
if python "$NATIVE/main.py" notacommand 2>/dev/null; then
    echo "  [FAIL] 未知子命令未报错" >&2; exit 1
else
    echo "  OK: 未知子命令被拒绝"
fi

echo "==> [5/5] BEAGLE 冒烟（若默认前缀已装库且 pkg-config 可用）"
PKG="${HOME}/software/beagle-lib-3.1.2/lib/pkgconfig"
if command -v pkg-config >/dev/null 2>&1 && [[ -d "$PKG" ]]; then
    PKG_CONFIG_PATH="$PKG" pkg-config --modversion hmsbeagle-1 || true
else
    echo "  默认前缀未找到 hmsbeagle-1（${PKG}），跳过真实冒烟（argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
