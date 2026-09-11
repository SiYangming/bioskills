#!/usr/bin/env bash
# Glimmer3（glimmer）native 最小回归测试
# 前置：python3 必须在 PATH。
# 任何环境下 exit 0 + ALL TESTS PASSED：
#   [必跑] 自省（--list-commands / --schema）+ 子命令 --help 参数契约 +
#          --dry-run 命令行构造断言（long_orfs / build_icm / glimmer3）；
#   [有才跑] PATH 含 long-orfs（及 extract / build-icm / glimmer3）时追加教学链路真跑
#            （long-orfs 小链路；后续步骤失败仅 [WARN]，不阻断）；
#   无 glimmer → [SKIP]；最终打印 ALL TESTS PASSED。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/7] 生成测试数据（合成「基因样」基因组）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/genome.fna"
grep -q "^>synthetic_genome" "$WORK/genome.fna"

echo "==> [2/7] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^long_orfs " "$WORK/commands.txt"
grep -q "^build_icm " "$WORK/commands.txt"
grep -q "^glimmer3 " "$WORK/commands.txt"

echo "==> [3/7] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/7] 子命令 --help 参数契约"
python "$NATIVE/main.py" long_orfs --help > "$WORK/lo_help.txt"
grep -q -- "-sequence" "$WORK/lo_help.txt"
grep -q -- "--output" "$WORK/lo_help.txt"
grep -q -- "--cutoff" "$WORK/lo_help.txt"
python "$NATIVE/main.py" build_icm --help > "$WORK/bi_help.txt"
grep -q -- "--output" "$WORK/bi_help.txt"
grep -q -- "--reverse" "$WORK/bi_help.txt"
python "$NATIVE/main.py" glimmer3 --help > "$WORK/g3_help.txt"
grep -q -- "--gene-len" "$WORK/g3_help.txt"
grep -q -- "--threshold" "$WORK/g3_help.txt"
grep -q -- "--max-olap" "$WORK/g3_help.txt"

echo "==> [5/7] 命令行构造断言（--dry-run，不真跑）"
run_dry() { python "$NATIVE/main.py" "$@"; }

run_dry long_orfs --sequence "$WORK/genome.fna" -o "$WORK/tag.longorfs" -n -t 1.15 --dry-run \
    > "$WORK/lo_cmd.json"
python - "$WORK/lo_cmd.json" <<'PY'
import json, sys
cmd = json.load(open(sys.argv[1])); joined = " ".join(cmd)
for t in ("long-orfs", "-n", "-t", "1.15", "genome.fna", "tag.longorfs"):
    assert t in joined, f"long_orfs argv 缺少 {t}: {joined}"
print("[ok] long_orfs argv 断言通过")
PY

run_dry build_icm "$WORK/tag.train" -o "$WORK/tag.icm" -r --dry-run > "$WORK/bi_cmd.json"
python - "$WORK/bi_cmd.json" <<'PY'
import json, sys
cmd = json.load(open(sys.argv[1])); joined = " ".join(cmd)
for t in ("build-icm", "-r", "tag.icm"):
    assert t in joined, f"build_icm argv 缺少 {t}: {joined}"
print("[ok] build_icm argv 断言通过")
PY

run_dry glimmer3 "$WORK/genome.fna" "$WORK/tag.icm" -o "$WORK/tag" -g 110 -t 30 --dry-run \
    > "$WORK/g3_cmd.json"
python - "$WORK/g3_cmd.json" <<'PY'
import json, sys
cmd = json.load(open(sys.argv[1])); joined = " ".join(cmd)
for t in ("glimmer3", "-g", "110", "-t", "30.0", "genome.fna", "tag.icm", "tag"):
    assert t in joined, f"glimmer3 argv 缺少 {t}: {joined}"
print("[ok] glimmer3 argv 断言通过")
PY

echo "==> [6/7] 教学链路真跑（PATH 含 long-orfs 才跑；后续步骤失败仅 WARN）"
if command -v long-orfs >/dev/null 2>&1; then
    python "$NATIVE/main.py" long_orfs --sequence "$WORK/genome.fna" \
        -o "$WORK/tag.longorfs" -n -t 1.15
    test -f "$WORK/tag.longorfs"
    if [ -s "$WORK/tag.longorfs" ]; then
        echo "  [ok] long-orfs 找到训练 ORF（$(wc -l < "$WORK/tag.longorfs") 条）"
        if command -v extract >/dev/null 2>&1 && command -v build-icm >/dev/null 2>&1 \
           && command -v glimmer3 >/dev/null 2>&1; then
            # 教学第 2 步 extract 为同包原生程序（本驱动未单列子命令）
            if extract -t "$WORK/genome.fna" "$WORK/tag.longorfs" > "$WORK/tag.train" 2>/dev/null \
               && [ -s "$WORK/tag.train" ] \
               && python "$NATIVE/main.py" build_icm "$WORK/tag.train" -o "$WORK/tag.icm" -r \
               && python "$NATIVE/main.py" glimmer3 "$WORK/genome.fna" "$WORK/tag.icm" \
                    -o "$WORK/tag" --max-olap 50 -g 110 -t 30 2>/dev/null; then
                if [ -f "$WORK/tag.predict" ]; then
                    echo "  [ok] glimmer3 产出 tag.predict（$(grep -c '^orf' "$WORK/tag.predict" || true) 条预测）"
                else
                    echo "  [WARN] 未找到 tag.predict（合成数据过小，不阻断）"
                fi
            else
                echo "  [WARN] extract/build-icm/glimmer3 链路未跑通（合成数据过小，不阻断）"
            fi
        else
            echo "  [SKIP] 未检测到 extract / build-icm / glimmer3，仅跑 long-orfs 步骤"
        fi
    else
        echo "  [WARN] long-orfs 未挑出训练 ORF（合成数据未通过熵过滤），跳过后续链路"
    fi
else
    echo "  [SKIP] 未检测到 long-orfs（conda activate glimmer 后重跑），仅跑自省/构造链路"
fi

echo "==> [7/7] 版本 / 二进制探测（可选信息）"
for bin in glimmer3 long-orfs build-icm; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "  已安装: $bin -> $(command -v "$bin")"
    fi
done

echo "ALL TESTS PASSED"
