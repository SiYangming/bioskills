# sra-tools / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 的 `bio/sra-tools` 目前只有 `fasterq-dump` 一个 wrapper，
因此本目录为 prefetch（下载）与 fastq-dump（兼容转换）提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `sra_tools.smk` — 三个 rule，对应 nanoseq 的 SRA 获取链路：
  - `sra_prefetch`：`prefetch -f yes -t http -O <dir> <srr_id>`（迁移自 batch_prefetch.sh）
  - `sra_fastq_dump`：`fastq-dump --split-3 --gzip -O <outdir> <sra>`（迁移自 batch_sra_to_fastq*.sh）
  - `sra_fasterq_dump`：`fasterq-dump <sra> --split-3 -O <outdir> -e N -t <tmpdir>`（官方推荐高速版）

规则迁移自 `snakemake.smk/nanoseq.smk/nanoseq.sh/`，去除 while 串行循环 / GNU parallel
外部依赖 / 绝对路径（`./sratoolkit.3.2.0-centos_linux64/bin/`）；失败 SRR 列表由
Snakemake 的重试/日志机制覆盖，不再写 `failed_*.txt`。

## 用法

```python
# Snakefile 中
include: "modules/sra-tools/snakemake/local/sra_tools.smk"

# 运行
snakemake -j 8 sra/SRR12345678/SRR12345678.sra       # prefetch 下载
snakemake -j 8 fastq/SRR12345678.fastq.gz            # fastq-dump 转换
```

## 依赖环境

```yaml
# envs/sra-tools.yaml
channels: [conda-forge, bioconda]
dependencies:
  - sra-tools=3.4.1
```

## 与其它实现的关系

- `fasterq-dump` 场景也可直接切到官方 wrapper：`wrapper: "v3.13.0/bio/sra-tools/fasterq-dump"`
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`
