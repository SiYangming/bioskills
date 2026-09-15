#!/usr/bin/env python3
"""生成 falcon native 测试用的合成输入。

FALCON 真正组装需要真实 PacBio subreads，合成数据无法覆盖真实计算。
因此本脚本生成「迷你 subreads FASTA + input.fofn + fc_run.cfg」，
run_test.sh 在 FALCON 未安装时退化为「用 python 构造 argv 验证命令构建不崩溃」。

产出：
  <outdir>/subreads.fasta  迷你 PacBio subreads（占位）
  <outdir>/input.fofn      输入文件列表（每行一个 fasta 路径）
  <outdir>/fc_run.cfg      FALCON INI 配置（[General] + [job.defaults]）
  <outdir>/fc_unzip.cfg    FALCON-Unzip INI 配置（占位，供 unzip 子命令）
"""
from __future__ import annotations

import sys
from pathlib import Path

FC_RUN_CFG = """[General]
input_fofn = input.fofn
input_type = raw

pa_DBsplit_option = -x500 -s0.05
ovlp_DBsplit_option = -x500 -s0.05

length_cutoff = -1
genome_size = 48000
seed_coverage = 35
pa_daligner_option = -k14 -w6 -h35 -e.70 -l500 -T4
pa_HPCdaligner_option = -v -B4 -M16
falcon_sense_option = --output-multi --min-idt 0.70 --min-cov 4 --max-n-read 500
length_cutoff_pr = 1000
ovlp_daligner_option = -k20 -w6 -h60 -e.96 -l500 -T4
ovlp_HPCdaligner_option = -v -B4 -M16
overlap_filtering_setting = --max-diff 100 --max-cov 100 --min-cov 2 --bestn 10
fc_ovlp_to_graph_option = --min-len 500 --min-idt 0.96

[job.defaults]
job_type = local
pwatcher_type = blocking
submit = bash -C ${CMD} >| ${STDOUT_FILE} 2>| ${STDERR_FILE}
MB=32768
NPROC=4
njobs=2
[job.step.da]
[job.step.pda]
[job.step.la]
[job.step.pla]
[job.step.cns]
[job.step.asm]
"""


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "subreads.fasta").write_text(
        ">subread/0/0_1000\n"
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT\n",
        encoding="utf-8",
    )
    (outdir / "input.fofn").write_text(
        f"{outdir / 'subreads.fasta'}\n", encoding="utf-8"
    )
    (outdir / "fc_run.cfg").write_text(FC_RUN_CFG, encoding="utf-8")
    # Unzip 配置复用同结构（占位）
    (outdir / "fc_unzip.cfg").write_text(FC_RUN_CFG, encoding="utf-8")
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
