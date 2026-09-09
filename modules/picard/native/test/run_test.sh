#!/usr/bin/env bash
# picard native 驱动回归测试（无需真实 java / picard）：
#   1) --list-commands / --schema 自省
#   2) markduplicates/sortsam/addorreplacereadgroups/validatesamfile dry-run（argv 构造断言）
#   3) stub 假 picard 二进制 CLI 层冒烟（PATH 前置假 picard，验证 I=/O= 组装）
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cd "$TMP"

# ---- stub 假 picard launcher ----
cat > "$TMP/bin/picard" <<'SH'
#!/usr/bin/env bash
echo "STUB-PICARD argv: $*"
printf '%s\n' "$@" >> "${STUB_LOG:?}"
exit 0
SH
chmod +x "$TMP/bin/picard"
export STUB_LOG="$TMP/stub.log"
export PATH="$TMP/bin:$PATH"

echo "==> [1/6] CLI 自省：--list-commands"
python3 "$HERE/main.py" --list-commands | tee cmds.txt
for c in markduplicates sortsam addorreplacereadgroups collectinsertsizemetrics \
         validatesamfile createsequencedictionary mergesamfiles samtofastq; do
    grep -qE "^\s*${c}\b" cmds.txt
done

echo "==> [2/6] CLI 自省：--schema（合法 JSON + title）"
python3 "$HERE/main.py" --schema > schema.json
test -s schema.json
python3 -c "import json; s=json.load(open('schema.json')); assert s.get('title')=='picard', s.get('title')"

echo "==> [3/6] argv 构造（markduplicates dry-run）：工具名 + I=/O=/M="
python3 "$HERE/main.py" markduplicates -I in.sorted.bam -O out.dedup.bam \
    -M metrics.txt --remove-duplicates --dry-run | tee md_cmd.txt
grep -qE '^picard MarkDuplicates ' md_cmd.txt
grep -q 'I=in.sorted.bam' md_cmd.txt
grep -q 'O=out.dedup.bam' md_cmd.txt
grep -q 'M=metrics.txt' md_cmd.txt
grep -q 'REMOVE_DUPLICATES=true' md_cmd.txt

echo "==> [4/6] argv 构造（sortsam / addorreplacereadgroups dry-run）"
python3 "$HERE/main.py" sortsam -I in.bam -O out.qname.bam --sort-order queryname \
    --dry-run | tee ss_cmd.txt
grep -qE '^picard SortSam ' ss_cmd.txt
grep -q 'SORT_ORDER=queryname' ss_cmd.txt
python3 "$HERE/main.py" addorreplacereadgroups -I in.bam -O out.rg.bam \
    --read-group-id s1 --sample-name s1 --library lib1 --platform ILLUMINA \
    --dry-run | tee rg_cmd.txt
grep -q 'AddOrReplaceReadGroups' rg_cmd.txt
grep -q 'RGID=s1' rg_cmd.txt
grep -q 'RGSM=s1' rg_cmd.txt
grep -q 'RGLB=lib1' rg_cmd.txt
grep -q 'RGPL=ILLUMINA' rg_cmd.txt

echo "==> [5/6] argv 构造（validatesamfile / mergesamfiles dry-run）"
python3 "$HERE/main.py" validatesamfile -I in.bam -O v.txt --dry-run | tee vs_cmd.txt
grep -q 'ValidateSamFile' vs_cmd.txt
grep -q 'MODE=SUMMARY' vs_cmd.txt
python3 "$HERE/main.py" mergesamfiles -I a.bam -I b.bam -O merged.bam --dry-run | tee mg_cmd.txt
grep -q 'MergeSamFiles' mg_cmd.txt
test "$(grep -o 'I=a.bam' mg_cmd.txt | wc -l | tr -d ' ')" = "1"
test "$(grep -o 'I=b.bam' mg_cmd.txt | wc -l | tr -d ' ')" = "1"

echo "==> [6/6] stub CLI 冒烟：真实 run 路径 argv 落盘 + stdout 回显"
rm -f "$STUB_LOG"
python3 "$HERE/main.py" markduplicates -I sample.sorted.bam -O sample.dedup.bam \
    -M metrics.txt --remove-duplicates > run_out.txt 2> run_err.txt \
    || { cat run_out.txt run_err.txt; exit 1; }
grep -q 'STUB-PICARD argv: MarkDuplicates' run_out.txt
test -s "$STUB_LOG"
python3 - <<'PY'
import os
args = [l for l in open(os.environ["STUB_LOG"]).read().splitlines() if l.strip()]
assert args[0] == "MarkDuplicates", args
assert args.index("I=sample.sorted.bam") < args.index("O=sample.dedup.bam") < args.index("M=metrics.txt"), args
assert "REMOVE_DUPLICATES=true" in args
print("stub argv ok:", " ".join(args))
PY

# 缺 launcher 报错路径（仅当系统确实无 picard 且无 jar 时断言清晰报错）
if ! command -v picard >/dev/null 2>&1 && ! command -v java >/dev/null 2>&1; then
    echo "==> [bonus] 缺 picard 时错误提示"
    env PATH="/usr/bin:/bin" python3 "$HERE/main.py" markduplicates -I x.bam \
        > err_out.txt 2> err_msg.txt && { echo "[FAIL] 应报错但退出 0"; exit 1; } || true
    grep -q '未找到 picard' err_msg.txt
fi

echo "ALL TESTS PASSED"
