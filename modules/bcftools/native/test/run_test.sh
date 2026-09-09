#!/usr/bin/env bash
# bcftools native 驱动回归测试（无需真实 bcftools 二进制）：
#   1) --list-commands / --schema 自省
#   2) view/call/mpileup/norm/query dry-run（argv 构造断言）
#   3) stub 假 bcftools 二进制 CLI 层冒烟（PATH 前置假 bcftools）
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cd "$TMP"

# ---- stub 假 bcftools ----
cat > "$TMP/bin/bcftools" <<'SH'
#!/usr/bin/env bash
echo "STUB-BCFTOOLS argv: $*"
printf '%s\n' "$@" >> "${STUB_LOG:?}"
exit 0
SH
chmod +x "$TMP/bin/bcftools"
export STUB_LOG="$TMP/stub.log"
export PATH="$TMP/bin:$PATH"

echo "==> [1/7] CLI 自省：--list-commands"
python3 "$HERE/main.py" --list-commands | tee cmds.txt
for c in view mpileup call sort index norm query consensus; do grep -qE "^\s*${c}\b" cmds.txt; done

echo "==> [2/7] CLI 自省：--schema（合法 JSON + title）"
python3 "$HERE/main.py" --schema > schema.json
test -s schema.json
python3 -c "import json; s=json.load(open('schema.json')); assert s.get('title')=='bcftools', s.get('title')"

echo "==> [3/7] argv 构造（view dry-run）：-O z -o + 表达式/样本"
python3 "$HERE/main.py" view raw.bcf -O z -o out.vcf.gz -i 'QUAL>30 && INFO/DP>10' -s NA12878 \
    --dry-run | tee view_cmd.txt
grep -qE '^bcftools view ' view_cmd.txt
grep -q -- '-O z' view_cmd.txt
grep -q -- '-o out.vcf.gz' view_cmd.txt
grep -q -- '-i' view_cmd.txt
grep -q 'QUAL>30 && INFO/DP>10' view_cmd.txt
grep -q 'raw.bcf' view_cmd.txt

echo "==> [4/7] argv 构造（call dry-run）：-m -v + input 顺序"
python3 "$HERE/main.py" call raw.bcf -m -v -O z -o calls.vcf.gz --dry-run | tee call_cmd.txt
grep -qE '^bcftools call ' call_cmd.txt
grep -q -- '-m' call_cmd.txt
grep -q -- '-v' call_cmd.txt
grep -q 'raw.bcf' call_cmd.txt
python3 - <<'PY'
line = open("call_cmd.txt").read().strip()
# 选项在 input 之前、-O/-o 顺序在 -v 后
assert line.rfind("raw.bcf") > line.rfind("-o calls.vcf.gz") > line.rfind("-m"), line
PY

echo "==> [5/7] argv 构造（mpileup dry-run）：-f + 多 BAM 顺序"
python3 "$HERE/main.py" mpileup -f ref.fa a.bam b.bam -O b -o raw.bcf --dry-run | tee mp_cmd.txt
grep -qE '^bcftools mpileup ' mp_cmd.txt
grep -q -- '-f ref.fa' mp_cmd.txt
python3 - <<'PY'
line = open("mp_cmd.txt").read().strip()
i_a, i_b = line.find("a.bam"), line.find("b.bam")
assert i_a != -1 and i_b != -1 and i_a < i_b, line
PY

echo "==> [6/7] argv 构造（query dry-run）：-f 格式串 + norm 的 -m -any"
python3 "$HERE/main.py" query calls.vcf.gz -f '%CHROM\t%POS\t%REF\t%ALT\n' -r chr1 \
    --dry-run | tee query_cmd.txt
grep -q -- '-f' query_cmd.txt
grep -q 'chr1' query_cmd.txt
python3 "$HERE/main.py" norm calls.vcf.gz -f ref.fa -m any -O z -o norm.vcf.gz \
    --dry-run | tee norm_cmd.txt
grep -qE '^bcftools norm ' norm_cmd.txt
grep -q -- '-m -any' norm_cmd.txt

echo "==> [7/7] stub CLI 冒烟：真实 run 路径 argv 落盘 + stdout 回显"
rm -f "$STUB_LOG"
python3 "$HERE/main.py" call raw.bcf -m -v -O z -o calls.vcf.gz > run_out.txt 2> run_err.txt \
    || { cat run_out.txt run_err.txt; exit 1; }
grep -q 'STUB-BCFTOOLS argv: call' run_out.txt
test -s "$STUB_LOG"
python3 - <<'PY'
import os
args = [l for l in open(os.environ["STUB_LOG"]).read().splitlines() if l.strip()]
assert args[0] == "call", args
assert args.index("-m") < args.index("-v") < args.index("-O") < args.index("raw.bcf"), args
print("stub argv ok:", " ".join(args))
PY

# 缺二进制报错路径（仅当系统确实无 bcftools 时断言清晰报错）
if ! command -v bcftools >/dev/null 2>&1; then
    echo "==> [bonus] 缺 bcftools 时错误提示"
    env PATH="/usr/bin:/bin" python3 "$HERE/main.py" view x.vcf.gz \
        > err_out.txt 2> err_msg.txt && { echo "[FAIL] 应报错但退出 0"; exit 1; } || true
    grep -q '未找到可执行文件' err_msg.txt
fi

echo "ALL TESTS PASSED"
