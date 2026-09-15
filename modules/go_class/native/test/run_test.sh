#!/usr/bin/env bash
# go_class native 最小回归测试
#
# 前置条件：
#   - python3 + pyyaml（base.py 依赖）
#   - go_class Perl 脚本【可选】：本测试用 stub 脚本（$WORK/bin）验证各子命令 argv
#     与 stdout→-o 重定向，无需真实的 go_class.tar.gz。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1   # 避免在模块目录留下 __pycache__

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（go.obo / go.annot / go.wego / out.lst / out.svg）"
python "$HERE/generate_data.py" "$WORK"

echo "==> [2/7] 自省：--list-commands / --schema"
python "$NATIVE/main.py" --list-commands
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"

echo "==> [3/7] argv 构造验证：config / annot2wego / classify"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GoClassSkill, build_parser
skill = GoClassSkill()
skill._resolve_script = lambda name: "/opt/go_class/bin/" + name

c = skill.build_command("config", obo="$WORK/go.obo")
assert c == ["/opt/go_class/bin/make_go_class_config.pl", "$WORK/go.obo"], c
print("  OK config:", " ".join(c))

c = skill.build_command("annot2wego", annot="$WORK/go.annot")
assert c == ["/opt/go_class/bin/annot2wego.pl", "$WORK/go.annot"], c
print("  OK annot2wego:", " ".join(c))

c = skill.build_command("classify", obo="$WORK/go.obo", wego="$WORK/go.wego")
assert c == ["/opt/go_class/bin/get_Genes_From_GO.pl", "$WORK/go.obo", "$WORK/go.wego"], c
print("  OK classify:", " ".join(c))

# parser 可解析完整 argv（子命令后 --threads/--tmpdir 模式）
ns = build_parser().parse_args(["annot2wego", "$WORK/go.annot", "--threads", "4", "--tmpdir", "/tmp"])
assert ns.subcommand == "annot2wego" and ns.threads == 4 and ns.tmpdir == "/tmp", ns
print("  OK: parser annot2wego")
PY

echo "==> [4/7] argv 构造验证：svg / distribute / resize（13.md 参数）"
python3 - <<PY
import sys
sys.path.insert(0, "$NATIVE")
from main import GoClassSkill
skill = GoClassSkill()
skill._resolve_script = lambda name: "/opt/go_class/bin/" + name

c = skill.build_command(
    "svg", wego="$WORK/go.wego", outdir="./", name="out", color="green",
    mark="Whole Genome Genes", note="GO Class of whole genome genes",
)
assert c == [
    "/opt/go_class/bin/go_svg.pl", "--outdir", "./", "--name", "out",
    "--color", "green", "--mark", "Whole Genome Genes",
    "--note", "GO Class of whole genome genes", "$WORK/go.wego",
], c
print("  OK svg:", " ".join(c))

c = skill.build_command("distribute", lst="$WORK/out.lst", svg="$WORK/out.svg")
assert c == ["/opt/go_class/bin/distributing_svg.pl", "$WORK/out.lst", "$WORK/out.svg"], c
print("  OK distribute:", " ".join(c))

c = skill.build_command("resize", svg="$WORK/out.svg", width="150", height="-100")
assert c == ["/opt/go_class/bin/changsvgsize.pl", "$WORK/out.svg", "150", "-100"], c
print("  OK resize:", " ".join(c))

# 缺参必须报错
for call in (("config", {}), ("classify", {"obo": "$WORK/go.obo"}),
             ("distribute", {"lst": "$WORK/out.lst"}),
             ("resize", {"svg": "$WORK/out.svg", "width": "150"})):
    try:
        skill.build_command(*call[0:1], **call[1])
    except ValueError as e:
        print(f"  OK {call[0]} 缺参报错:", e)
    else:
        raise AssertionError(f"{call[0]} 缺参应抛 ValueError")

# 线程优先级：显式 --threads > per_subcommand_threads > default_cpus
assert skill._effective_threads("annot2wego", 4) == 4
assert skill._effective_threads("annot2wego", None) == 1   # meta default=1
print("  OK threads priority")
PY

echo "==> [5/7] 脚本解析：GO_CLASS_HOME/{bin,svg} 回退"
mkdir -p "$WORK/home/bin" "$WORK/home/svg"
printf '#!/usr/bin/env perl\n' > "$WORK/home/bin/annot2wego.pl"
chmod +x "$WORK/home/bin/annot2wego.pl"
GO_CLASS_HOME="$WORK/home" python3 - <<PY
import os, sys
sys.path.insert(0, "$NATIVE")
from main import GoClassSkill
skill = GoClassSkill()
p = skill._resolve_script("annot2wego.pl")
assert p == "$WORK/home/bin/annot2wego.pl", p
print("  OK GO_CLASS_HOME 回退:", p)
PY

echo "==> [6/7] stdout→-o 重定向验证（stub 脚本，无需真实 go_class）"
mkdir -p "$WORK/bin"
for s in annot2wego.pl get_Genes_From_GO.pl; do
    cat > "$WORK/bin/$s" <<STUB
#!/usr/bin/env bash
# stub ${s}: 打印占位输出，仅供 argv/重定向回归
echo "STUB ${s} \$*"
STUB
    chmod +x "$WORK/bin/$s"
done
PATH="$WORK/bin:$PATH" python "$NATIVE/main.py" annot2wego "$WORK/go.annot" -o "$WORK/go.wego"
test -f "$WORK/go.wego"
grep -q "STUB annot2wego.pl" "$WORK/go.wego"
echo "  OK: annot2wego -o 落盘"

PATH="$WORK/bin:$PATH" python "$NATIVE/main.py" classify "$WORK/go.obo" "$WORK/go.wego" -o "$WORK/go_class.tab"
test -f "$WORK/go_class.tab"
grep -q "STUB get_Genes_From_GO.pl" "$WORK/go_class.tab"
echo "  OK: classify -o 落盘"

echo "==> [7/7] go_class 真实脚本冒烟（若已安装）"
if command -v make_go_class_config.pl >/dev/null 2>&1; then
    echo "  make_go_class_config.pl 已在 PATH（真实脚本可用）"
else
    echo "  go_class 未安装，跳过真实冒烟（stub 重定向 + argv 构造验证已通过）"
fi

echo "ALL TESTS PASSED"
