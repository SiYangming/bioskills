# isoseq3 / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/isoseq3`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

* `isoseq3.smk` — `rule isoseq3_refine`：lima 产物 → 精炼 reads（去 polyA 尾与人工连接体）

规则迁移自 `snakemake.smk/isoseq.smk/workflow/skills/isoseq3/snakemake/local/isoseq3.smk`，并去除对
`workflow/lib/helpers.py`（get\_isoseq\_input\_bam / docker\_run / ISOSEQ\_DIR / LOG\_DIR）的依赖：

* 输入路径模板：`lima/{sample}/{sample}.chunk{n}.bam` + `primers.fasta`

* 输出：`isoseq3/{sample}/{sample}.chunk{n}.bam` 及 `.pbi` / `.consensusreadset.xml` / `.filter_summary.report.json` / `.report.csv`

* 参数：`isoseq3 refine -j {threads} [--require-polya] <bam> <primers> <out>`

## 用法

```python
# Snakefile 中
include: "skills/isoseq3/snakemake/local/isoseq3.smk"

# 运行
snakemake -j 8 isoseq3/sample1/sample1.chunk1.bam
```

## 依赖环境

规则内 `conda: "envs/isoseq3.yaml"`，需要自备：

```yaml
# envs/isoseq3.yaml
channels: [conda-forge, bioconda]
dependencies:
  - isoseq=4.0.0     # 提供二进制 isoseq3
```

## 与其它实现的关系

* 官方 wrapper 若未来出现（重新抓取 bio/isoseq3 有目录），可切换回 `../snakemake-wrappers/` 登记层

* 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`

