#!/usr/bin/env python3
"""生成 maker native 测试用的合成输入。

MAKER 真实运行需完整证据集与大量依赖工具（AUGUSTUS/SNAP/RepeatMasker/MPI...），无法在测试中覆盖。
本脚本生成最小占位输入，run_test.sh 以 python 构造 argv 验证命令构建（monkeypatch 二进制路径）为主。

产出：
  <outdir>/genome.fasta              最小基因组 FASTA
  <outdir>/Trinity.fasta             EST / 转录本占位
  <outdir>/homolog.fasta             同源蛋白占位
  <outdir>/consensi.fa               RepeatModeler 重复库占位
  <outdir>/species.hmm               SNAP HMM 占位
  <outdir>/gmhmm.mod                 GeneMark HMM 占位
  <outdir>/genome_master_datastore_index.log   merge/fasta_merge 输入占位
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

    (outdir / "genome.fasta").write_text(
        ">scaffold_1\nATGGCAGGTACGTACGTACGTAGCTAGCTAGCATCGATCGATCGTAGCTAGCTAGCTAGCATCG\n",
        encoding="utf-8",
    )
    (outdir / "Trinity.fasta").write_text(
        ">TRINITY_DN1_c0_g1_i1\nATGGCAGGTACGTACGTAGCTAGCTAGCATCGATCG\n",
        encoding="utf-8",
    )
    (outdir / "homolog.fasta").write_text(
        ">homolog1\nMKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ\n",
        encoding="utf-8",
    )
    (outdir / "consensi.fa").write_text(
        ">rnd-1_family-1\nACGTACGTACGTACGTACGT\n",
        encoding="utf-8",
    )
    (outdir / "species.hmm").write_text("# PLACEHOLDER: SNAP HMM\n", encoding="utf-8")
    (outdir / "gmhmm.mod").write_text("# PLACEHOLDER: GeneMark HMM\n", encoding="utf-8")
    (outdir / "genome_master_datastore_index.log").write_text(
        "# PLACEHOLDER: <genome>_master_datastore_index.log\n", encoding="utf-8"
    )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
