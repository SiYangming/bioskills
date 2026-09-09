#!/usr/bin/env bash
# gatk native 驱动回归测试（无需真实 java / gatk）：
#   1) --list-commands / --schema 自省
#   2) haplotypecaller/genotypegvcfs/combinegvcfs/baserecalibrator/applybqsr dry-run
#   3) stub 假 gatk 二进制 CLI 层冒烟（PATH 前置假 gatk）
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cd "$TMP"

# ---- stub 假 gatk launcher ----
cat > "$TMP/bin/gatk" <<'SH'
#!/usr/bin/env bash
echo "STUB-GATK argv: $*"
printf '%s\n' "$@" >> "${STUB_LOG:?}"
exit 0
SH
chmod +x "$TMP/bin/gatk"
export STUB_LOG="$TMP/stub.log"
export PATH="$TMP/bin:$PATH"

echo "==> [1/6] CLI 自省：--list-commands"
python3 "$HERE/main.py" --list-commands | tee cmds.txt
for c in haplotypecaller genotypegvcfs combinegvcfs variantfiltration \
         selectvariants baserecalibrator applybqsr splitncigarreads; do
    grep -qE "^\s*${c}\b" cmds.txt
done

echo "==> [2/6] CLI 自省：--schema（合法 JSON + title）"
python3 "$HERE/main.py" --schema > schema.json
test -s schema.json
python3 -c "import json; s=json.load(open('schema.json')); assert s.get('title')=='gatk', s.get('title')"

echo "==> [3/6] argv 构造（haplotypecaller dry-run）：-I/-R/-O + ERC + pair-HMM 线程"
python3 "$HERE/main.py" haplotypecaller -I sample.dedup.bam -R hg38.fa \
    -O sample.g.vcf.gz --erc GVCF --threads 8 --dry-run | tee hc_cmd.txt
grep -qE '^gatk HaplotypeCaller ' hc_cmd.txt
grep -q -- '-I sample.dedup.bam' hc_cmd.txt
grep -q -- '-R hg38.fa' hc_cmd.txt
grep -q -- '-O sample.g.vcf.gz' hc_cmd.txt
grep -q -- '--emit-ref-confidence GVCF' hc_cmd.txt
grep -q -- '--native-pair-hmm-threads 8' hc_cmd.txt

echo "==> [4/6] argv 构造（genotypegvcfs / combinegvcfs dry-run）：-V/-R/-O"
python3 "$HERE/main.py" genotypegvcfs -V cohort.g.vcf.gz -R hg38.fa \
    -O cohort.vcf.gz --dry-run | tee gg_cmd.txt
grep -qE '^gatk GenotypeGVCFs ' gg_cmd.txt
grep -q -- '-V cohort.g.vcf.gz' gg_cmd.txt
python3 "$HERE/main.py" combinegvcfs -V s1.g.vcf.gz -V s2.g.vcf.gz -R hg38.fa \
    -O all.g.vcf.gz --dry-run | tee cg_cmd.txt
grep -q 'CombineGVCFs' cg_cmd.txt
test "$(grep -o '\-V s1.g.vcf.gz' cg_cmd.txt | wc -l | tr -d ' ')" = "1"
test "$(grep -o '\-V s2.g.vcf.gz' cg_cmd.txt | wc -l | tr -d ' ')" = "1"

echo "==> [5/6] argv 构造（baserecalibrator / applybqsr / variantfiltration dry-run）"
python3 "$HERE/main.py" baserecalibrator -I sample.bam -R hg38.fa \
    -O recal.table --known-sites dbsnp.vcf.gz --dry-run | tee br_cmd.txt
grep -q 'BaseRecalibrator' br_cmd.txt
grep -q -- '--known-sites dbsnp.vcf.gz' br_cmd.txt
python3 "$HERE/main.py" applybqsr -I sample.bam -R hg38.fa -O sample.bqsr.bam \
    --bqsr-recal-file recal.table --dry-run | tee ab_cmd.txt
grep -q 'ApplyBQSR' ab_cmd.txt
grep -q -- '--bqsr-recal-file recal.table' ab_cmd.txt
python3 "$HERE/main.py" variantfiltration -V cohort.vcf.gz -R hg38.fa \
    -O hf.vcf.gz --filter-expression 'QD < 2.0' --filter-name LowQD \
    --dry-run | tee vf_cmd.txt
grep -q 'VariantFiltration' vf_cmd.txt
grep -qF -- "--filter-expression 'QD < 2.0'" vf_cmd.txt
grep -q -- '--filter-name LowQD' vf_cmd.txt

echo "==> [6/6] stub CLI 冒烟：真实 run 路径 argv 落盘 + stdout 回显"
rm -f "$STUB_LOG"
python3 "$HERE/main.py" haplotypecaller -I sample.bam -R hg38.fa \
    -O sample.g.vcf.gz --erc GVCF --threads 4 > run_out.txt 2> run_err.txt \
    || { cat run_out.txt run_err.txt; exit 1; }
grep -q 'STUB-GATK argv: HaplotypeCaller' run_out.txt
test -s "$STUB_LOG"
python3 - <<'PY'
import os
args = [l for l in open(os.environ["STUB_LOG"]).read().splitlines() if l.strip()]
assert args[0] == "HaplotypeCaller", args
assert args.index("-R") < args.index("-I") < args.index("-O") < args.index("--emit-ref-confidence"), args
assert "--native-pair-hmm-threads" in args
print("stub argv ok:", " ".join(args))
PY

# 缺 launcher 报错路径（仅当系统确实无 gatk 时断言清晰报错）
if ! command -v gatk >/dev/null 2>&1; then
    echo "==> [bonus] 缺 gatk 时错误提示"
    env PATH="/usr/bin:/bin" python3 "$HERE/main.py" genotypegvcfs -V x.g.vcf.gz \
        > err_out.txt 2> err_msg.txt && { echo "[FAIL] 应报错但退出 0"; exit 1; } || true
    grep -q '未找到 gatk' err_msg.txt
fi

echo "ALL TESTS PASSED"
