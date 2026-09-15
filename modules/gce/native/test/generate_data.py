#!/usr/bin/env python3
"""生成 gce native 测试用的合成输入。

GCE 两支程序都需要真实测序数据才能产出有意义的估计；合成数据无法覆盖真实计算。
因此本脚本生成「文本占位 + 说明」，run_test.sh 在 gce/kmer_freq_hash 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/reads.fq          迷你 FASTQ（kmer_freq_hash 输入占位）
  <outdir>/reads.list        reads 路径列表（每行一个 FASTQ 路径）
  <outdir>/out.freq.stat     两列 k-mer 深度频率表（depth / species count，gce 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1]).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    reads = outdir / "reads.fq"
    reads.write_text(
        "@r1\nACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n+\n"
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n"
        "@r2\nTGCATGCATGCATGCATGCATGCATGCATGCATGCATGCA\n+\n"
        "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n",
        encoding="utf-8",
    )
    (outdir / "reads.list").write_text(f"{reads}\n", encoding="utf-8")

    # 两列深度频率表（depth \t species）；gce 解析 -f 文件（首行为表头亦可）
    rows = ["1\t120", "2\t40", "3\t25", "4\t18", "5\t14", "6\t10", "7\t8", "8\t6"]
    (outdir / "out.freq.stat").write_text("\n".join(rows) + "\n", encoding="utf-8")

    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
