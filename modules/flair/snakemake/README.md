# flair / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/flair`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `flair.smk` — 三个 rule，对应 nanoseq FLAIR_CONSENSUS 三段链路：
  - `flair_bam2bed12`：`bam2Bed12 -i <bam> > <bed12>`
  - `flair_annotate`：`identify_gene_isoform <bed12> <gtf> <annotated_bed>`
  - `flair_collapse`：`flair collapse -q -g -r -o -t -f -s -w --trust_ends --remove_internal_priming --intprimingthreshold --stringent --check_splice --mm2_args=... --quiet`

规则迁移自 `snakemake.smk/nanoseq.smk/nanoseq.sh/run_flair_consensus.sh`，去除
nohup/PID/LOCK 后台运行封装与 `$HOME/miniconda3` 绝对路径依赖；`gtf_annotation` /
`genome_fasta` 走 `config.get(...)` 内联默认值。

## 用法

```python
# Snakefile 中
include: "modules/flair/snakemake/flair.smk"

# 运行
snakemake -j 8 consensus/sample1.flair.collapse.fasta
```

## 依赖环境

规则内 `conda: "envs/flair.yaml"`，需要自备：

```yaml
# envs/flair.yaml
channels: [conda-forge, bioconda]
dependencies:
  - flair=3.0.0b1
  - minimap2
```

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/flair 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`
