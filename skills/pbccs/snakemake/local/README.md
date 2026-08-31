# pbccs / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/pbccs`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `pbccs.smk` — `rule pbccs`：subreads BAM → HiFi/CCS BAM（含 chunk 分块与过滤阈值）

规则迁移自 `snakemake.smk/isoseq.smk/workflow/skills/pbccs/snakemake/local/pbccs.smk`，并去除对
`workflow/lib/helpers.py`（sample_to_bam / docker_run / LOG_DIR）的依赖：
- 输入路径模板：`subreads/{sample}.subreads.bam`
- 输出：`ccs/{sample}/{sample}.chunk{n}.bam` 及 `.pbi` / `.report.txt` / `.report.json` / `.metrics.json.gz`
- 参数：`--chunk {n}/{chunk_total}` + `--min-rq/--min-passes/--min-snr/--min-length/--max-length/--top-passes` + `-j {threads}`

## 用法

```python
# Snakefile 中
include: "skills/pbccs/snakemake/local/pbccs.smk"

# 运行（n 为分块编号通配符，如 1..4）
snakemake -j 8 ccs/sample1/sample1.chunk1.bam
```

## 依赖环境

规则内 `conda: "envs/pbccs.yaml"`，需要自备：

```yaml
# envs/pbccs.yaml
channels: [conda-forge, bioconda]
dependencies:
  - pbccs=6.4.0
```

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/pbccs 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`
