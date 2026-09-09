#!/usr/bin/env bash
# bwa native 驱动回归测试（无需真实 bwa 二进制）：
#   1) --list-commands / --schema 自省
#   2) index/mem/aln/samse/sampe dry-run（argv 构造断言）
#   3) stub 假 bwa 二进制 CLI 层冒烟（PATH 前置假 bwa，验证 run 路径 argv 组装）
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cd "$TMP"

# ---- stub 假 bwa：记录 argv 到 STUB_LOG 并回显 ----
cat > "$TMP/bin/bwa" <<'SH'
#!/usr/bin/env bash
echo "STUB-BWA argv: $*"
printf '%s\n' "$@" >> "${STUB_LOG:?}"
exit 0
SH
chmod +x "$TMP/bin/bwa"
export STUB_LOG="$TMP/stub.log"
export PATH="$TMP/bin:$PATH"   # stub 假 bwa 优先于真实 bwa

echo "==> [1/6] CLI 自省：--list-commands"
python3 "$HERE/main.py" --list-commands | tee cmds.txt
for c in index mem aln samse sampe; do grep -qE "^\s*${c}\b" cmds.txt; done

echo "==> [2/6] CLI 自省：--schema（合法 JSON + title）"
python3 "$HERE/main.py" --schema > schema.json
test -s schema.json
python3 -c "import json; s=json.load(open('schema.json')); assert s.get('title')=='bwa', s.get('title')"

echo "==> [3/6] argv 构造（index dry-run）：-a bwtsw + 参考"
python3 "$HERE/main.py" index ref.fa --index-algorithm bwtsw --dry-run | tee idx_cmd.txt
grep -qE '^bwa index ' idx_cmd.txt
grep -q -- '-a bwtsw' idx_cmd.txt
grep -q 'ref.fa' idx_cmd.txt

echo "==> [4/6] argv 构造（mem dry-run）：-t/-M/-R + 双端 reads 顺序"
python3 "$HERE/main.py" mem --index ref.fa --reads1 R1.fq.gz --reads2 R2.fq.gz \
    --threads 16 -M -R "@RG\tID:s1\tSM:s1" --dry-run | tee mem_cmd.txt
grep -qE '^bwa mem ' mem_cmd.txt
grep -q -- '-t 16' mem_cmd.txt
grep -q -- '-M' mem_cmd.txt
grep -q -- '-R' mem_cmd.txt
grep -q 'ref.fa' mem_cmd.txt
python3 - <<'PY'
line = open("mem_cmd.txt").read().strip()
# 位置参数顺序：idxbase 在 reads1 前、reads1 在 reads2 前
i_idx, i_r1, i_r2 = line.find("ref.fa"), line.find("R1.fq.gz"), line.find("R2.fq.gz")
assert -1 not in (i_idx, i_r1, i_r2) and i_idx < i_r1 < i_r2, line
PY

echo "==> [5/6] argv 构造（sampe dry-run）：-f 输出 + sai1/sai2/R1/R2 顺序"
python3 "$HERE/main.py" sampe --index ref.fa --sai1 r1.sai --sai2 r2.sai \
    --reads1 R1.fq.gz --reads2 R2.fq.gz --output out.sam --dry-run | tee sampe_cmd.txt
grep -q -- '-f out.sam' sampe_cmd.txt
python3 - <<'PY'
line = open("sampe_cmd.txt").read().strip()
a, b, c, d = (line.find(x) for x in ["r1.sai", "r2.sai", "R1.fq.gz", "R2.fq.gz"])
assert -1 not in (a, b, c, d) and a < b < c < d, line
PY

echo "==> [6/6] stub CLI 冒烟：真实 run 路径 argv 落盘 + stdout 回显"
rm -f "$STUB_LOG"
python3 "$HERE/main.py" mem --index genome.fa --reads1 s_R1.fq.gz --reads2 s_R2.fq.gz \
    --threads 8 -M > run_out.txt 2> run_err.txt || { cat run_out.txt run_err.txt; exit 1; }
grep -q 'STUB-BWA argv: mem' run_out.txt
test -s "$STUB_LOG"
python3 - <<'PY'
import os
args = [l for l in open(os.environ["STUB_LOG"]).read().splitlines() if l.strip()]
assert args[:3] == ["mem", "-t", "8"], args
assert "-M" in args
assert args.index("genome.fa") < args.index("s_R1.fq.gz") < args.index("s_R2.fq.gz"), args
print("stub argv ok:", " ".join(args))
PY

# 缺二进制报错路径（仅当系统确实无 bwa 时断言清晰报错）
if ! command -v bwa >/dev/null 2>&1; then
    echo "==> [bonus] 缺 bwa 时错误提示（PATH 不含 bwa）"
    env PATH="$TMP/bin_nonexistent:/usr/bin:/bin" python3 "$HERE/main.py" index ref.fa \
        > err_out.txt 2> err_msg.txt && { echo "[FAIL] 应报错但退出 0"; exit 1; } || true
    grep -q '未找到可执行文件' err_msg.txt
fi

echo "ALL TESTS PASSED"
