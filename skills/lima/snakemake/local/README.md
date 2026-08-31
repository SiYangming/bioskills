# lima / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/lima`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `lima.smk` — `rule lima`：reads + primers → 去引物/拆分后的 reads（bam/pbi/report/summary/counts）

规则迁移自 `snakemake.smk/isoseq.smk/workflow/skills/lima/snakemake/local/lima.smk`，并去除对
`workflow/lib/helpers.py`（get_lima_input / docker_run / LIMA_DIR / LOG_DIR）的依赖：
- 输入路径模板：`ccs/{sample}/{sample}.chunk{n}.bam` + `primers.fasta`
- 输出：`lima/{sample}/{sample}.chunk{n}.bam` 及 `.pbi` / `.lima.report` / `.lima.summary` / `.lima.counts`
- 参数：`<bam> <primers> <out> [extra] -j {threads}`

## 用法

```python
# Snakefile 中
include: "skills/lima/snakemake/local/lima.smk"

# 运行
snakemake -j 8 lima/sample1/sample1.chunk1.bam
```

## 依赖环境

规则内 `conda: "envs/lima.yaml"`，需要自备：

```yaml
# envs/lima.yaml
channels: [conda-forge, bioconda]
dependencies:
  - lima=2.9.0
```

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/lima 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`
