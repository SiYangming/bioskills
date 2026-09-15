#!/usr/bin/env python3
"""生成 dbcan native 测试用的合成输入。

dbCAN V9 注释依赖真实数据库（dbCAN-HMMdb-V9 / CAZyDB.07312020.fa，数百 MB）与
HMMER/BLAST+/DIAMOND 建库产物，合成数据无法覆盖真实计算，因此本脚本生成「文本占位 + 说明」，
run_test.sh 在工具未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/proteins.fasta          最小蛋白 FASTA（hmmscan / diamond_blastp 输入）
  <outdir>/dbCAN-fam-HMMs.txt      HMM 数据库占位（build_hmm 输入）
  <outdir>/CAZyDB.07312020.fa      CAZy 蛋白库占位（build_blastdb / build_diamond 输入）
  <outdir>/hmmscan.domtbl          hmmscan 域级输出占位（parse_hmmscan 输入）
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

    (outdir / "proteins.fasta").write_text(
        ">g1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n"
        ">g2\nMSTAGKVIKCKAAVLWELKKPFSIEEVEVAPPK\n",
        encoding="utf-8",
    )
    (outdir / "dbCAN-fam-HMMs.txt").write_text(
        "# PLACEHOLDER: dbCAN-HMMdb-V9.txt（真实 HMM 库需从 bcb.unl.edu/dbCAN2 下载）\n",
        encoding="utf-8",
    )
    (outdir / "CAZyDB.07312020.fa").write_text(
        ">CAZy|GH1|sp|P12345|\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n",
        encoding="utf-8",
    )
    # hmmscan --domtblout 输出占位（含一条域记录，供 hmmscan-parser.sh 解析）
    (outdir / "hmmscan.domtbl").write_text(
        "# hmmscan :: search sequence(s) against a profile HMM database\n"
        "g1 - 1 GH1.hmm - 4 60 0.0 1e-50 1e-50 60.0 0.0 1 4 1 4 1 4 1 4 -\n",
        encoding="utf-8",
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
