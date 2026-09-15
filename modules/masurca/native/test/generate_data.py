#!/usr/bin/env python3
"""生成 masurca native 测试用的合成输入。

MaSuRCA 组装需要真实 Illumina/PacBio 数据且耗时极长，合成数据无法覆盖真实计算。因此本脚本生成
「可解析的 config.txt + 占位 reads + assemble.sh 占位 + 说明」，run_test.sh 在 masurca 未安装时
退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/config.txt        MaSuRCA 配置（DATA 段 PE=/PACBIO= + PARAMETERS 段，仿文档示例）
  <outdir>/illumina.1.fastq  文本占位（PE R1）
  <outdir>/illumina.2.fastq  文本占位（PE R2）
  <outdir>/subreads.fasta    文本占位（PacBio 长读）
  <outdir>/assemble.sh       文本占位（模拟 masurca config.txt 生成的组装脚本）
"""
from __future__ import annotations

import sys
from pathlib import Path


CONFIG = """DATA
PE= p1 268 66 {d}/illumina.1.fastq {d}/illumina.2.fastq
PACBIO={d}/subreads.fasta
END

PARAMETERS
GRAPH_KMER_SIZE=auto
USE_LINKING_MATES=0
USE_GRID=0
LHE_COVERAGE=40
MEGA_READS_ONE_PASS=0
CA_PARAMETERS =  cgwErrorRate=0.15
CLOSE_GAPS=1
NUM_THREADS=8
JF_SIZE=40000000
SOAP_ASSEMBLY=0
FLYE_ASSEMBLY=1
END
"""


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    for name in ("illumina.1.fastq", "illumina.2.fastq"):
        (outdir / name).write_text(
            "# PLACEHOLDER: MaSuRCA 需真实 Illumina reads 才能组装\n", encoding="utf-8")
    (outdir / "subreads.fasta").write_text(
        "# PLACEHOLDER: MaSuRCA 需真实 PacBio 长读才能组装\n", encoding="utf-8")
    (outdir / "config.txt").write_text(CONFIG.format(d=outdir), encoding="utf-8")
    (outdir / "assemble.sh").write_text(
        "#!/usr/bin/env bash\n# PLACEHOLDER: masurca config.txt 生成的组装脚本\n",
        encoding="utf-8")
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
