#!/usr/bin/env python3
"""生成 pasa native 测试用的合成输入。

PASA 需要真实转录本 + 基因组 + MySQL 才能跑通，合成数据无法覆盖真实计算。因此本脚本生成
「可被命令构造读取的迷你输入/配置文件」，run_test.sh 在 PASA 未安装时退化为
「用 python 构造 argv 验证命令构建不崩溃」（不依赖已安装脚本）。

产出：
  <outdir>/alignAssembly.config        最小 PASA 配置占位（DATABASE=...）
  <outdir>/genome.fasta                迷你基因组 FASTA（-g）
  <outdir>/transcripts.fasta.clean     seqclean 清洗后转录本 FASTA（-t）
  <outdir>/transcripts.fasta           原始转录本 FASTA（-u）
  <outdir>/tdn.accs                    Trinity 转录本 ID 列表（--TDN）
  <outdir>/DB.assemblies.fasta         build_comprehensive 产物占位（asmbls_to_training 输入）
  <outdir>/DB.pasa_assemblies.gff3      PASA 组装 GFF3 占位（asmbls_to_training 输入）
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "alignAssembly.config").write_text(
        "# PASA alignAssembly 配置占位\n# DATABASE=<mysql_db_name>\nDATABASE=pasa_test_db\n",
        encoding="utf-8",
    )
    (outdir / "genome.fasta").write_text(
        ">chr1\nATGAAAACGGCGTATTATTATTGCGCACAGCGCCAAATTTCTTTTGTGAAATCTCACTTTTCTCGCCAG\n"
        "CTAGAAGAACGTCTTGGTCTTATTGAAGTTCAGTAA\n",
        encoding="utf-8",
    )
    (outdir / "transcripts.fasta.clean").write_text(
        ">t1\nATGAAAACGGCGTATTATTATTGCGCACAGCGCCAAA\n",
        encoding="utf-8",
    )
    (outdir / "transcripts.fasta").write_text(
        ">t1\nATGAAAACGGCGTATTATTATTGCGCACAGCGCCAAA\n",
        encoding="utf-8",
    )
    (outdir / "tdn.accs").write_text("t1\n", encoding="utf-8")
    (outdir / "DB.assemblies.fasta").write_text(
        ">t1\nATGAAAACGGCGTATTATTATTGCGCACAGCGCCAAA\n",
        encoding="utf-8",
    )
    (outdir / "DB.pasa_assemblies.gff3").write_text(
        "##gff-version 3\nchr1\tPASA\tmRNA\t1\t39\t.\t+\t.\tID=t1\n",
        encoding="utf-8",
    )
    print(f"已生成测试迷你输入 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
