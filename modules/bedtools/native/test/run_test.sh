#!/usr/bin/env bash
# bedtools native 驱动回归测试（无需真实 bedtools 二进制）：
#   1) --list-commands / --schema 自省
#   2) intersect/merge/genomecov/getfasta dry-run（argv 构造断言）
#   3) stub 假 bedtools 二进制 CLI 层冒烟（PATH 前置假 bedtools）
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cd "$TMP"

# ---- stub 假 bedtools ----
cat > "$TMP/bin/bedtools" <<'SH'
#!/usr/bin/env bash
echo "STUB-BEDTOOLS argv: $*"
printf '%s\n' "$@" >> "${STUB_LOG:?}"
exit 0
SH
chmod +x "$TMP/bin/bedtools"
export STUB_LOG="$TMP/stub.log"
export PATH="$TMP/bin:$PATH"

echo "==> [1/6] CLI 自省：--list-commands"
python3 "$HERE/main.py" --list-commands | tee cmds.txt
for c in intersect merge sort coverage genomecov bamtobed getfasta subtract; do
    grep -qE "^\s*${c}\b" cmds.txt
done

echo "==> [2/6] CLI 自省：--schema（合法 JSON + title）"
python3 "$HERE/main.py" --schema > schema.json
test -s schema.json
python3 -c "import json; s=json.load(open('schema.json')); assert s.get('title')=='bedtools', s.get('title')"

echo "==> [3/6] argv 构造（intersect dry-run）：-a/-b/-wa/-wb/-f"
python3 "$HERE/main.py" intersect -a peaks.bed -b genes.bed -wa -wb \
    --min-overlap 0.1 --dry-run | tee it_cmd.txt
grep -qE '^bedtools intersect ' it_cmd.txt
grep -q -- '-a peaks.bed' it_cmd.txt
grep -q -- '-b genes.bed' it_cmd.txt
grep -q -- '-wa' it_cmd.txt
grep -q -- '-wb' it_cmd.txt
grep -q -- '-f 0.1' it_cmd.txt

echo "==> [4/6] argv 构造（intersect -v 反选 + coverage -counts + merge -d）"
python3 "$HERE/main.py" intersect -a peaks.bed -b blacklist.bed -v \
    --dry-run | tee itv_cmd.txt
grep -q -- '-v' itv_cmd.txt
python3 "$HERE/main.py" coverage -a targets.bed -b sample.bam -counts \
    --dry-run | tee cov_cmd.txt
grep -qE '^bedtools coverage ' cov_cmd.txt
grep -q -- '-counts' cov_cmd.txt
python3 "$HERE/main.py" merge -i peaks.bed -d 100 --dry-run | tee mg_cmd.txt
grep -qE '^bedtools merge ' mg_cmd.txt
grep -q -- '-i peaks.bed' mg_cmd.txt
grep -q -- '-d 100' mg_cmd.txt

echo "==> [5/6] argv 构造（genomecov BAM→-ibam / getfasta）"
python3 "$HERE/main.py" genomecov -i sample.bam -g hg38.genome -bg \
    --dry-run | tee gc_cmd.txt
grep -qE '^bedtools genomecov ' gc_cmd.txt
grep -q -- '-ibam sample.bam' gc_cmd.txt
grep -q -- '-g hg38.genome' gc_cmd.txt
grep -q -- '-bg' gc_cmd.txt
python3 "$HERE/main.py" getfasta -fi hg38.fa -bed peaks.bed -name -s \
    --dry-run | tee gf_cmd.txt
grep -qE '^bedtools getfasta ' gf_cmd.txt
grep -q -- '-fi hg38.fa' gf_cmd.txt
grep -q -- '-bed peaks.bed' gf_cmd.txt
grep -q -- '-name' gf_cmd.txt
grep -q -- '-s' gf_cmd.txt

echo "==> [6/6] stub CLI 冒烟：真实 run 路径 argv 落盘 + stdout 回显"
rm -f "$STUB_LOG"
python3 "$HERE/main.py" intersect -a peaks.bed -b genes.bed -wa -wb \
    > run_out.txt 2> run_err.txt || { cat run_out.txt run_err.txt; exit 1; }
grep -q 'STUB-BEDTOOLS argv: intersect' run_out.txt
test -s "$STUB_LOG"
python3 - <<'PY'
import os
args = [l for l in open(os.environ["STUB_LOG"]).read().splitlines() if l.strip()]
assert args[0] == "intersect", args
assert args.index("-a") < args.index("-b") < args.index("-wa") < args.index("-wb"), args
print("stub argv ok:", " ".join(args))
PY

# 缺二进制报错路径（仅当系统确实无 bedtools 时断言清晰报错）
if ! command -v bedtools >/dev/null 2>&1; then
    echo "==> [bonus] 缺 bedtools 时错误提示"
    env PATH="/usr/bin:/bin" python3 "$HERE/main.py" intersect -a a.bed -b b.bed \
        > err_out.txt 2> err_msg.txt && { echo "[FAIL] 应报错但退出 0"; exit 1; } || true
    grep -q '未找到可执行文件' err_msg.txt
fi

echo "ALL TESTS PASSED"
