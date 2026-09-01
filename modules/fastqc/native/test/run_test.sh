#!/usr/bin/env bash
# fastqc native 驱动回归测试：
# 1) 通过 CLI 自省（--schema / --list-commands）
# 2) 如果本机有 fastqc，则合成一个极小 FASTQ，实测生成 html + zip
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"

echo "==> [1/3] CLI 自省：--list-commands"
python3 "$HERE/main.py" --list-commands

echo "==> [2/3] CLI 自省：--schema（非空 + 合法 JSON）"
python3 "$HERE/main.py" --schema > schema.json
test -s schema.json
python3 -c "import json; s=json.load(open('schema.json')); assert s.get('title')=='fastqc_native'"

if ! command -v fastqc >/dev/null 2>&1; then
  echo "[SKIP] 本环境未安装 fastqc binary，跳过真实运行子步骤（3/3）。请用 conda env create -f $HERE/environment.yml 后重跑。"
  echo "ALL TESTS PASSED (introspection only, binary unavailable)"
  exit 0
fi

echo "==> [3/3] 合成 1 个最小 FASTQ 并实际运行 fastqc（单线程小内存）"
cat > tiny.1.fq <<'FASTQ'
@read1
ATCGATCGATCGATCGATCG
+
IIIIIIIIIIIIIIIIIIII
@read2
GCTAGCTAGCTAGCTAGCTA
+
IIIIIIIIIIIIIIIIIIII
FASTQ
gzip -k tiny.1.fq

python3 "$HERE/main.py" run tiny.1.fq.gz -o qc_out --threads 1 --java-mem-mb 1024 --nogroup --extract

test -f qc_out/tiny.1_fastqc.html
test -f qc_out/tiny.1_fastqc.zip
test -d qc_out/tiny.1_fastqc

echo "ALL TESTS PASSED"
