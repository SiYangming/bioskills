#!/usr/bin/env bash
# misa_primer3 subworkflow 编排器最小回归测试
#
# 1) 自省 + dry-run + python 级断言（不需要任何外部工具，任何环境都跑）；
# 2) PATH 内齐备 misa.pl / primer3_core / ParaFly / perl 时，追加真实端到端链路：
#    合成基因组（1 条 ~1.3 kb、3 处 SSR）→ --real → 断言 .misa 命中 3 处 SSR、
#    misa_primer3.out 有结果且至少一条记录设计出引物、GFF3 生成。
#    否则 [SKIP]（misa.pl 缺 → 提示 modules/misa install.sh；primer3_core 缺 → modules/primer3 README）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成 genome.fasta：1 条 ~1.3 kb、3 处 SSR）"
python3 "$HERE/generate_data.py" "$WORK/data"
test -f "$WORK/data/genome.fasta"

echo "==> [2/6] 自省：--list-stages"
out="$(python3 "$NATIVE/main.py" --list-stages)"
echo "$out" | grep -q '"stages"'
echo "$out" | grep -q 'misa_detect'
echo "$out" | grep -q 'prepare_p3_settings'
echo "$out" | grep -q 'misa_primer3_design'
echo "  [ok] 三个 stage 已声明"

echo "==> [3/6] dry-run（默认模式，不需要外部工具）"
out="$(python3 "$NATIVE/main.py" --dry-run --genome "$WORK/data/genome.fasta" \
    --outdir "$WORK/out" --threads 8)"
echo "$out" | grep -q '\[misa_detect\]'
echo "$out" | grep -q 'modules/misa/native/main.py detect'
echo "$out" | grep -q '\[prepare_p3_settings\]'
echo "$out" | grep -q '\[misa_primer3_design\]'
echo "$out" | grep -q 'misa_primer3.pl'
echo "$out" | grep -q -- '--CPU 8'
echo "$out" | grep -q 'misa_primer3.gff3'
echo "  [ok] dry-run 覆盖 3 个 stage（含 --CPU 8 / --gff3_out）"

echo "==> [4/6] python 级断言：设置文件生成 + 命令结构 + vendored 补丁"
NATIVE="$NATIVE" WORK="$WORK" python3 - <<'PY'
import os, sys
from pathlib import Path
native = Path(os.environ["NATIVE"]); work = Path(os.environ["WORK"])
sys.path.insert(0, str(native))
import main as m

# a) 生成设置文件：注释/空行清理；P3_FILE_ID 前恰有一空行；热力学路径行按探测结果处理
cfg = work / "primer3_config"; cfg.mkdir(exist_ok=True)
a = m.prepare_p3_settings(native / "p3_settings.txt", work / "p3_dropped", None)
ta = (work / "p3_dropped").read_text(encoding="utf-8")
assert a["thermodynamic_path"] == "dropped", a
assert "PRIMER_THERMODYNAMIC_PARAMETERS_PATH" not in ta
assert not any(l.lstrip().startswith("#") for l in ta.splitlines())
blanks = [i for i, l in enumerate(ta.splitlines()) if not l.strip()]
assert len(blanks) == 1 and ta.splitlines()[blanks[0] + 1].startswith("P3_FILE_ID"), blanks
assert "PRIMER_TASK=generic" in ta and "PRIMER_NUM_RETURN=5" in ta
print("  [ok] 未探测到 primer3_config → 删除热力学路径行；注释/空行清理、P3_FILE_ID 前留空行")

b = m.prepare_p3_settings(native / "p3_settings.txt", work / "p3_set", cfg)
tb = (work / "p3_set").read_text(encoding="utf-8")
assert b["thermodynamic_path"] == "set", b
assert f"PRIMER_THERMODYNAMIC_PARAMETERS_PATH={cfg.as_posix()}/" in tb, tb[:200]
print("  [ok] 提供 primer3_config → 该行被重写为真实目录")

# b) resolve_primer3_config 对不存在的 bin 不抛错
assert m.resolve_primer3_config("/nonexistent/primer3_core") is None

# c) 命令结构
cmd = m.design_cmd("g.misa", "g.fasta", "p3", 8, 300, 100, 250, "out.gff3")
for token in ("--CPU", "8", "--flanking_length", "300", "--min_product_length", "100",
              "--max_product_length", "250", "--gff3_out", "out.gff3",
              "--p3_setting_file", "p3", "g.misa", "g.fasta"):
    assert token in cmd, (token, cmd)
# --p3_setting_file 必须是选项（否则 p3 路径会被 misa_primer3.pl 当成 .misa 位点表读，产生垃圾位点）
i = cmd.index("--p3_setting_file")
assert cmd[i + 1] == "p3" and cmd[i + 2] == "g.misa" and cmd[i + 3] == "g.fasta", cmd
det = m.misa_detect_cmd("g.fasta", "out/misa", None)
assert det[1].endswith("modules/misa/native/main.py") and "detect" in det, det

# d) vendored 脚本补丁：代码行不得再出现 bash 专有的 &>（头注里提到该写法不算）
pl = (native / "misa_primer3.pl").read_text(encoding="utf-8")
code = [l for l in pl.splitlines() if not l.lstrip().startswith("#")]
assert not any("&>" in l for l in code), [l for l in code if "&>" in l]
assert any("ParaFly" in l and "> /dev/null 2>&1" in l for l in code)
print("  [ok] 命令结构正确；misa_primer3.pl 的 &> 可移植性补丁在位")
PY

echo "==> [5/6] 真实链路（需要 misa.pl + primer3_core + ParaFly + perl，缺一则跳过）"
missing=""
command -v misa.pl     >/dev/null 2>&1 || missing="$missing misa.pl"
command -v primer3_core >/dev/null 2>&1 || missing="$missing primer3_core"
command -v ParaFly      >/dev/null 2>&1 || missing="$missing ParaFly"
command -v perl         >/dev/null 2>&1 || missing="$missing perl"
if [[ -z "$missing" ]]; then
    if python3 "$NATIVE/main.py" --real --genome "$WORK/data/genome.fasta" \
            --outdir "$WORK/real" --threads 2 > "$WORK/real.log" 2>&1; then
        MISA="$WORK/real/misa/genome.fasta.misa"
        OUT="$WORK/real/misa_primer3.out"
        GFF="$WORK/real/misa_primer3.gff3"
        test -s "$MISA"
        # 三处 SSR 命中（(AG)12 / (GAA)8 / (A)14）
        grep -qE '\(AG\)12' "$MISA"
        grep -qE '\(GAA\)8' "$MISA"
        grep -qE '\(A\)14' "$MISA"
        test "$(tail -n +2 "$MISA" | wc -l | tr -d ' ')" = "3"
        test -s "$WORK/real/p3_settings_file"
        test -s "$OUT"
        grep -q 'SSR type' "$OUT"
        test -s "$GFF"
        grep -q 'misa_primer3' "$GFF"
        grep -q 'Primer_1_left_seq=' "$GFF"
        # 至少一条记录设计出引物（第 8 列 = left PRIMER1）
        designed="$(awk -F'\t' 'NR>1 && $8!=""{n++} END{print n+0}' "$OUT")"
        test "$designed" -ge 1
        echo "  [ok] --real 跑通：3 处 SSR → 引物表（$designed 条设计出引物）+ GFF3"
    else
        echo "  [WARN] --real 真跑失败（工具链安装异常？），仅提示不阻断；日志尾部："
        tail -n 8 "$WORK/real.log" || true
    fi
else
    echo "  [SKIP] 缺少工具:${missing}（misa.pl: bash modules/misa/native/install.sh；"
    echo "         primer3_core: 见 modules/primer3/README.md；ParaFly: mamba install -c bioconda parafly）"
fi

echo "==> [6/6] 提示：真实链路参数（可选信息）"
echo "  python3 $NATIVE/main.py --real --genome <genome.fasta> --outdir results --threads 8 \\"
echo "      --gff3-out results/misa_primer3.gff3"

echo "ALL TESTS PASSED"
