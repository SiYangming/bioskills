#!/usr/bin/env bash
# hisat2 native 驱动回归测试（无需真实 hisat2 二进制）：
#   1) --list-commands / --schema 自省
#   2) index/align dry-run（argv 构造断言）
#   3) stub 假 hisat2 / hisat2-build 二进制 CLI 层冒烟
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cd "$TMP"

# ---- stub 假 hisat2 / hisat2-build ----
cat > "$TMP/bin/hisat2" <<'SH'
#!/usr/bin/env bash
echo "STUB-HISAT2 argv: $*"
printf '%s\n' "$@" >> "${STUB_LOG:?}"
exit 0
SH
chmod +x "$TMP/bin/hisat2"
cat > "$TMP/bin/hisat2-build" <<'SH'
#!/usr/bin/env bash
echo "STUB-HISAT2-BUILD argv: $*"
printf '%s\n' "$@" >> "${STUB_LOG:?}"
exit 0
SH
chmod +x "$TMP/bin/hisat2-build"
export STUB_LOG="$TMP/stub.log"
export PATH="$TMP/bin:$PATH"

echo "==> [1/6] CLI 自省：--list-commands"
python3 "$HERE/main.py" --list-commands | tee cmds.txt
for c in index align; do grep -qE "^\s*${c}\b" cmds.txt; done

echo "==> [2/6] CLI 自省：--schema（合法 JSON + title）"
python3 "$HERE/main.py" --schema > schema.json
test -s schema.json
python3 -c "import json; s=json.load(open('schema.json')); assert s.get('title')=='hisat2', s.get('title')"

echo "==> [3/6] argv 构造（index dry-run）：hisat2-build + -p/--ss/--exon + 双位置参数顺序"
python3 "$HERE/main.py" index genome.fa --index-base hg38 \
    --ss ss.txt --exon exons.txt --threads 16 --dry-run | tee idx_cmd.txt
grep -qE '^hisat2-build ' idx_cmd.txt
grep -q -- '-p 16' idx_cmd.txt
grep -q -- '--ss ss.txt' idx_cmd.txt
grep -q -- '--exon exons.txt' idx_cmd.txt
python3 - <<'PY'
line = open("idx_cmd.txt").read().strip()
i_ref, i_base = line.find("genome.fa"), line.find("hg38")
assert i_ref != -1 and i_base != -1 and i_ref < i_base, line
PY

echo "==> [4/6] argv 构造（align 双端 dry-run）：-p/--dta/--rna-strandness/-x/-1/-2"
python3 "$HERE/main.py" align -x hg38 -1 R1.fq.gz -2 R2.fq.gz \
    --dta --rna-strandness RF --threads 16 -S out.sam --dry-run | tee al_cmd.txt
grep -qE '^hisat2 ' al_cmd.txt
grep -q -- '-p 16' al_cmd.txt
grep -q -- '--dta' al_cmd.txt
grep -q -- '--rna-strandness RF' al_cmd.txt
grep -q -- '-x hg38' al_cmd.txt
grep -q -- '-1 R1.fq.gz' al_cmd.txt
grep -q -- '-2 R2.fq.gz' al_cmd.txt
grep -q -- '-S out.sam' al_cmd.txt

echo "==> [5/6] argv 构造（align 单端 dry-run）：-U 走单端分支"
python3 "$HERE/main.py" align -x hg38 -U se.fq.gz --threads 4 \
    --dry-run | tee alu_cmd.txt
grep -qE '^hisat2 ' alu_cmd.txt
grep -q -- '-U se.fq.gz' alu_cmd.txt

echo "==> [6/6] stub CLI 冒烟：真实 run 路径 argv 落盘 + stdout 回显"
rm -f "$STUB_LOG"
python3 "$HERE/main.py" align -x hg38 -1 R1.fq.gz -2 R2.fq.gz \
    --dta --threads 8 > run_out.txt 2> run_err.txt \
    || { cat run_out.txt run_err.txt; exit 1; }
grep -q 'STUB-HISAT2 argv: ' run_out.txt
test -s "$STUB_LOG"
python3 - <<'PY'
import os
args = [l for l in open(os.environ["STUB_LOG"]).read().splitlines() if l.strip()]
assert args[0] == "-p" and args[1] == "8", args
assert args.index("--dta") < args.index("-x") < args.index("-1") < args.index("-2"), args
print("stub argv ok:", " ".join(args))
PY

# index 真实 run（hisat2-build stub）
rm -f "$STUB_LOG"
python3 "$HERE/main.py" index genome.fa --index-base hg38 --threads 4 \
    > run_idx.txt 2> run_idx_err.txt || { cat run_idx.txt run_idx_err.txt; exit 1; }
grep -q 'STUB-HISAT2-BUILD argv: ' run_idx.txt
grep -q '^genome.fa$' "$STUB_LOG"
grep -q '^hg38$' "$STUB_LOG"

# 缺二进制报错路径（仅当系统确实无 hisat2 时断言清晰报错）
if ! command -v hisat2 >/dev/null 2>&1; then
    echo "==> [bonus] 缺 hisat2 时错误提示"
    env PATH="/usr/bin:/bin" python3 "$HERE/main.py" align -x hg38 -U se.fq.gz \
        > err_out.txt 2> err_msg.txt && { echo "[FAIL] 应报错但退出 0"; exit 1; } || true
    grep -q '未找到可执行文件' err_msg.txt
fi

echo "ALL TESTS PASSED"
