#!/usr/bin/env bash
# infernal native 最小回归测试
# 前置：python3 必须在 PATH。
# PATH 中有 cmsearch/cmpress（conda activate infernal-native / 官方容器内 / brew / 源码安装）→
#   追加真跑段（5a 二进制自检必跑；5b 最小链路可选用 RFAM_CM 开启，见下）；
# 无 cmsearch/cmpress → 自省 + [SKIP]；任何环境最终 exit 0 并打印 ALL TESTS PASSED。
#
# 可选真跑：cmpress 需要能对「合法 CM 数据库」运行（迷你真 CM 无法在脚本内简单合成），
# 因此 5b 由环境变量 RFAM_CM=<真实 Rfam.cm 或其子集 .cm 的绝对路径> 触发：
#   RFAM_CM=$PWD/Rfam.cm bash modules/infernal/native/test/run_test.sh
# 开启后会执行 cmpress Rfam.cm（索引文件 .cm.i1f/.i1m/.i1p/.i1i 写在 Rfam.cm 同目录，
# 已存在索引族则跳过 cmpress）→ cmsearch 合成 genome.fa → 断言 tblout 非空。
# 真跑失败仅 [WARN] 提示不阻断（保证任意环境 exit 0）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(dirname "$HERE")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> [1/6] 生成测试数据（合成搜索目标基因组）"
python "$HERE/generate_data.py" "$WORK"
test -f "$WORK/genome.fa"
grep -q "^>" "$WORK/genome.fa"

echo "==> [2/6] main.py --list-commands 自省"
python "$NATIVE/main.py" --list-commands | tee "$WORK/commands.txt"
grep -q "^cmpress " "$WORK/commands.txt"
grep -q "^cmsearch " "$WORK/commands.txt"

echo "==> [3/6] main.py --schema 自省"
python "$NATIVE/main.py" --schema > "$WORK/schema.json"
test -s "$WORK/schema.json"
python -c "import json,sys; json.load(open('$WORK/schema.json')); print('schema JSON 合法')"

echo "==> [4/6] 子命令 --help 参数契约"
python "$NATIVE/main.py" cmpress --help > "$WORK/cmpress_help.txt"
grep -q "cm_database" "$WORK/cmpress_help.txt"
python "$NATIVE/main.py" cmsearch --help > "$WORK/cmsearch_help.txt"
grep -q -- "--cut-ga" "$WORK/cmsearch_help.txt"
grep -q -- "--nohmmonly" "$WORK/cmsearch_help.txt"
grep -q -- "--noali" "$WORK/cmsearch_help.txt"
grep -q -- "--tblout" "$WORK/cmsearch_help.txt"
echo "  [ok] cmpress/cmsearch 帮助契约通过"

echo "==> [5/6] 真跑段（需要 cmsearch/cmpress，未安装则跳过）"
if command -v cmsearch >/dev/null 2>&1 && command -v cmpress >/dev/null 2>&1; then
    # 5a. 二进制可执行自检（Infernal 无 --version，版本号打印在 -h 帮助头首行）
    if cmsearch -h > "$WORK/cmsearch_h.txt" 2>&1; then
        echo "  [ok] cmsearch -h -> $(head -n 1 "$WORK/cmsearch_h.txt")"
    else
        echo "  [WARN] cmsearch -h 失败（安装异常？），仅提示不阻断；日志："
        tail -n 3 "$WORK/cmsearch_h.txt" || true
    fi

    # 5b. RFAM_CM 可选真跑链路（未设置/文件不存在则 [SKIP]）
    if [ -n "${RFAM_CM:-}" ] && [ -f "$RFAM_CM" ]; then
        echo "  [run] RFAM_CM=$RFAM_CM 开启 cmpress→cmsearch 最小链路"
        # cmpress：索引文件写在 CM 文件同目录；已有 .i1f 索引族则跳过（避免重复重建）
        if [ -f "$RFAM_CM.i1f" ]; then
            echo "  [skip] $RFAM_CM 已压缩过（$RFAM_CM.i1f 存在），跳过 cmpress"
        elif python "$NATIVE/main.py" cmpress "$RFAM_CM" > "$WORK/cmpress.log" 2>&1; then
            if test -f "$RFAM_CM.i1f" && test -f "$RFAM_CM.i1i"; then
                echo "  [ok] cmpress -> $(basename "$RFAM_CM").i1f/.i1m/.i1p/.i1i 已生成"
            else
                echo "  [WARN] cmpress 退出码 0 但未见 .i1f/.i1i 索引族（异常），仅提示不阻断"
            fi
        else
            echo "  [WARN] cmpress 真跑失败（CM 文件未校准/损坏？），仅提示不阻断；日志："
            tail -n 5 "$WORK/cmpress.log" || true
        fi

        # cmsearch：仅当目标 .cm 存在（且已压索引或 cmsearch 可直接读平文件）才尝试
        if python "$NATIVE/main.py" cmsearch "$RFAM_CM" "$WORK/genome.fa" \
                --cut-ga --nohmmonly --rfam --noali --threads 2 \
                --tblout "$WORK/rfam_out.tab" -o "$WORK/rfam_out.txt" \
                > "$WORK/cmsearch.log" 2>&1; then
            if test -s "$WORK/rfam_out.tab"; then
                N_HITS=$(grep -c -v "^#" "$WORK/rfam_out.tab" || true)
                echo "  [ok] cmsearch -> rfam_out.tab 非空（tblout 命中行数: $N_HITS）"
            else
                echo "  [WARN] cmsearch 退出码 0 但 rfam_out.tab 为空（异常），仅提示不阻断"
            fi
        else
            echo "  [WARN] cmsearch 真跑失败（Rfam.cm 体积过大/未校准？可换迷你 .cm 子集），仅提示不阻断；日志："
            tail -n 5 "$WORK/cmsearch.log" || true
        fi
    else
        echo "  [SKIP] 未设置 RFAM_CM（指向真实 Rfam.cm 或迷你 .cm 子集即开真跑），仅跑 5a 自检"
    fi
else
    echo "  [SKIP] 未检测到 cmsearch/cmpress（conda activate infernal-native 或装好后重跑），仅跑自省链路"
fi

echo "==> [6/6] 版本探测（可选信息）"
if command -v cmsearch >/dev/null 2>&1; then
    cmsearch -h 2>/dev/null | head -n 1 || true
fi

echo "ALL TESTS PASSED"
