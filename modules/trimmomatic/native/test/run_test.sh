#!/usr/bin/env bash
# trimmomatic native 驱动回归测试（降级 argv 构造优先，无需真实二进制）：
#   1) --list-commands / --schema 自省
#   2) pe / se 子命令 dry-run（argv 构造断言，不需要 java / trimmomatic）
#   3) 若本机存在 trimmomatic launcher 或 java+jar，则合成极小 FASTQ 做 SE/PE 真实回归
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"

echo "==> [1/5] CLI 自省：--list-commands"
python3 "$HERE/main.py" --list-commands | tee cmds.txt
grep -qE '^\s*pe\b' cmds.txt
grep -qE '^\s*se\b' cmds.txt

echo "==> [2/5] CLI 自省：--schema（合法 JSON + title）"
python3 "$HERE/main.py" --schema > schema.json
test -s schema.json
python3 -c "import json; s=json.load(open('schema.json')); assert s.get('title')=='trimmomatic', s.get('title')"

echo "==> [3/5] argv 构造（SE dry-run）：模式/线程/步骤透传"
python3 "$HERE/main.py" se in.fq.gz out.fq.gz \
    "ILLUMINACLIP:TruSeq3-SE.fa:2:30:10" LEADING:3 TRAILING:3 MINLEN:36 \
    --threads 2 --dry-run | tee se_cmd.txt
grep -qE '\bSE\b' se_cmd.txt
grep -qE -- '-threads 2' se_cmd.txt
grep -q 'ILLUMINACLIP:TruSeq3-SE.fa:2:30:10' se_cmd.txt
grep -q 'MINLEN:36' se_cmd.txt

echo "==> [4/5] argv 构造（PE dry-run）：6 个文件槽位 + 步骤透传"
python3 "$HERE/main.py" pe R1.fq.gz R2.fq.gz oP1.fq.gz oU1.fq.gz oP2.fq.gz oU2.fq.gz \
    "ILLUMINACLIP:TruSeq3-PE.fa:2:30:10" LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36 TOPHRED33 \
    --threads 4 --dry-run | tee pe_cmd.txt
grep -qE '\bPE\b' pe_cmd.txt
grep -qE -- '-threads 4' pe_cmd.txt
grep -q 'ILLUMINACLIP:TruSeq3-PE.fa:2:30:10' pe_cmd.txt
grep -q 'SLIDINGWINDOW:4:15' pe_cmd.txt
grep -q 'TOPHRED33' pe_cmd.txt
grep -q 'oP1.fq.gz' pe_cmd.txt
grep -q 'oU2.fq.gz' pe_cmd.txt

# ---- 真实运行分支（可选）：探测 trimmomatic launcher 或 java + jar ----
RUNNABLE=0
if command -v trimmomatic >/dev/null 2>&1; then
    RUNNABLE=1
    echo "==> [5/5] 检测到 trimmomatic launcher，将执行真实回归"
elif command -v java >/dev/null 2>&1; then
    JAR_CAND=""
    for c in "${TRIMMOMATIC_JAR:-}" "${CONDA_PREFIX:-}"/share/trimmomatic*/trimmomatic-*.jar \
             "${HOME:-}"/software/Trimmomatic-*/trimmomatic-*.jar \
             "${HOME:-}"/software/trimmomatic*/trimmomatic-*.jar; do
        if [[ -n "$c" && -f "$c" ]]; then JAR_CAND="$c"; break; fi
    done
    if [[ -n "$JAR_CAND" ]]; then
        export TRIMMOMATIC_JAR="$JAR_CAND"
        RUNNABLE=1
        echo "==> [5/5] 检测到 java + jar（$JAR_CAND），将执行真实回归"
    fi
fi

if [[ "$RUNNABLE" != 1 ]]; then
    echo "[SKIP] 本环境未安装 trimmomatic（或 java + trimmomatic-*.jar），跳过真实运行子步骤（5/5）。"
    echo "        请用 mamba create -n trimmomatic -c conda-forge -c bioconda trimmomatic=0.39 建环境后重跑。"
    echo "ALL TESTS PASSED (introspection + argv-construction only)"
    exit 0
fi

python3 "$HERE/test/generate_data.py" -o .

# SE 真实回归：32bp×2 存活（MINLEN:20），8bp×1 被滤除
echo "==> SE 真实回归（LEADING/TRAILING/SLIDINGWINDOW/MINLEN）"
python3 "$HERE/main.py" se test_se.fq out_se.fq \
    LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:20 \
    --threads 1 --java-mem-mb 1024 > se_run.log 2>&1 || { cat se_run.log; exit 1; }
test -s out_se.fq
grep -c '^@se_r' out_se.fq | tee n_se.txt
[[ "$(cat n_se.txt)" == "2" ]] || { echo "[FAIL] SE 存活数应为 2，实际见 n_se.txt"; cat se_run.log; exit 1; }

# SE gz 输入输出路径
echo "==> SE 真实回归（gzip 输入/输出）"
python3 "$HERE/main.py" se test_pe_R1.fq.gz out_se.gz.fq.gz \
    LEADING:3 TRAILING:3 MINLEN:20 --threads 1 --java-mem-mb 1024 > se_gz.log 2>&1 \
    || { cat se_gz.log; exit 1; }
test -s out_se.gz.fq.gz

# PE 真实回归：配对 2 对存活；unpaired 输出文件生成
echo "==> PE 真实回归（paired/unpaired 4 输出）"
python3 "$HERE/main.py" pe test_pe_R1.fq.gz test_pe_R2.fq.gz \
    out_P1.fq.gz out_U1.fq.gz out_P2.fq.gz out_U2.fq.gz \
    LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:20 \
    --threads 1 --java-mem-mb 1024 > pe_run.log 2>&1 || { cat pe_run.log; exit 1; }
for f in out_P1.fq.gz out_U1.fq.gz out_P2.fq.gz out_U2.fq.gz; do
    test -e "$f" || { echo "[FAIL] 缺少输出 $f"; exit 1; }
done
python3 - <<'PY'
import gzip
n1 = sum(1 for _ in gzip.open("out_P1.fq.gz", "rt")) // 4
n2 = sum(1 for _ in gzip.open("out_P2.fq.gz", "rt")) // 4
assert n1 == 2 and n2 == 2, (n1, n2)
print(f"PE paired 存活：R1={n1} R2={n2}（预期 2/2）")
PY

echo "ALL TESTS PASSED"
