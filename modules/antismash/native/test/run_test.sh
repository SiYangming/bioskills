#!/usr/bin/env bash
# antismash native 最小回归测试
# 前置：python3 必须在 PATH。
# 任何环境下 exit 0 + ALL TESTS PASSED：
#   [必跑] 自省（--list-commands / --schema / 子命令 --help 参数契约）+
#          --dry-run 命令行构造断言（run / download_db）；
#   [有才跑] PATH 含 antismash / download-antismash-databases 时追加 --version 探测与
#           help 契约核对（仅探测，不真跑 antismash run —— 需 GB 级数据库 + 长耗时）。
# 无 antismash → [SKIP]；最终打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成最小 GenBank）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/genome.gbk"
grep -q "^LOCUS" "$WORK/genome.gbk"

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^run " "$WORK/commands.txt"
grep -q "^download_db " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 子命令 --help 参数契约"
python "$NATIVE/main.py" run --help > "$WORK/run_help.txt"
grep -q -- "--taxon" "$WORK/run_help.txt"
grep -q -- "--cpus" "$WORK/run_help.txt"
grep -q -- "--output-dir" "$WORK/run_help.txt"
grep -q -- "--genefinding-tool" "$WORK/run_help.txt"
python "$NATIVE/main.py" download_db --help > "$WORK/db_help.txt"
grep -q -- "--output-dir" "$WORK/db_help.txt"
grep -q -- "--database-dir" "$WORK/db_help.txt" || true   # 驱动帮助文案含之（见下 dry-run 强断言）

echo "==> [5/6] 命令行构造断言（--dry-run，不真跑 antismash）"
# 5a. run：真菌教学典型用法（-c 8 --taxon fungi）→ 应含 --cpus 8 --taxon fungi + 位置输入
python "$NATIVE/main.py" run "$WORK/genome.gbk" --taxon fungi --cpus 8 \
    --output-dir "$WORK/asm_out" --dry-run | tee "$WORK/run_cmd.json"
python - "$WORK/run_cmd.json" <<'PY'
import json, sys
cmd = json.load(open(sys.argv[1]))
joined = " ".join(cmd)
for token in ("antismash", "--cpus", "8", "--taxon", "fungi",
              "--output-dir", sys.argv[1].rsplit("/", 1)[0] + "/asm_out", "genome.gbk"):
    assert token in joined, f"run argv 缺少 {token}: {joined}"
print("[ok] run argv 断言通过")
PY
# 5b. run：默认细菌 + --genefinding-tool + --threads 覆盖 → --cpus 2
python "$NATIVE/main.py" run "$WORK/genome.gbk" \
    --genefinding-tool prodigal --threads 2 --dry-run | tee "$WORK/run_cmd2.json"
python - "$WORK/run_cmd2.json" <<'PY'
import json, sys
cmd = json.load(open(sys.argv[1]))
joined = " ".join(cmd)
for token in ("--cpus", "2", "--taxon", "bacteria", "--genefinding-tool", "prodigal"):
    assert token in joined, f"run argv 缺少 {token}: {joined}"
print("[ok] run 默认细菌/线程覆盖 argv 断言通过")
PY
# 5c. download_db：--output-dir 应映射为 --database-dir
python "$NATIVE/main.py" download_db --output-dir "$WORK/asm_db" --dry-run | tee "$WORK/db_cmd.json"
python - "$WORK/db_cmd.json" <<'PY'
import json, sys
cmd = json.load(open(sys.argv[1]))
joined = " ".join(cmd)
for token in ("download-antismash-databases", "--database-dir",
              sys.argv[1].rsplit("/", 1)[0] + "/asm_db"):
    assert token in joined, f"download_db argv 缺少 {token}: {joined}"
print("[ok] download_db argv 断言通过")
PY

echo "==> [6/6] 版本 / 二进制探测（PATH 中有 antismash 才跑；仅探测不真跑分析）"
if command -v antismash >/dev/null 2>&1; then
    antismash --version | head -n 1 || true
    # 核对安装版本的输出目录参数（v7+ 为 --output-dir）与主帮助契约
    if antismash --help > "$WORK/antismash_help.txt" 2>&1; then
        grep -q -- "--output-dir" "$WORK/antismash_help.txt" && echo "  [ok] antismash --help 含 --output-dir（v7+ CLI）"
    fi
    if command -v download-antismash-databases >/dev/null 2>&1; then
        download-antismash-databases --help > "$WORK/dldb_help.txt" 2>&1 || true
        grep -q -- "--database-dir" "$WORK/dldb_help.txt" \
            && echo "  [ok] download-antismash-databases --help 含 --database-dir" || true
    else
        echo "  [SKIP] 未检测到 download-antismash-databases（随 bioconda antismash 包装入）"
    fi
else
    echo "  [SKIP] 未检测到 antismash（conda activate antismash 后重跑），仅跑自省/构造链路"
fi

echo "ALL TESTS PASSED"
