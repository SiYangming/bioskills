"""SNAKEMAKE-WRAPPER SKEL COPY: bio/fastqc
本文件是根据 snakemake-wrappers 官方 bio/fastqc 行为复制的本地参考骨架，
仅用于：① 离线阅读 / ② 教学 / ③ 做 schema 输入输出验证。
生产环境请通过 rule.wrapper 直接引用官方 wrapper URL。"""
__author__ = "Johannes Köster"
__copyright__ = "Copyright 2016-2023, Johannes Köster"
__email__ = "johannes.koester@uni-due.de"
__license__ = "MIT"

from snakemake.shell import shell

extra = snakemake.params.get("extra", "")
log = snakemake.log_fmt_shell(stdout=False, stderr=True)

shell(
    "fastqc {extra} "
    "--threads {snakemake.threads} "
    "-o {snakemake.params.outdir} "
    "{snakemake.input} {log}"
)
