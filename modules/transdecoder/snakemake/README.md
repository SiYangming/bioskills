# transdecoder / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 虽有 `bio/transdecoder/{longorfs,predict}`，但本目录提供
**迁移自 flrnaseq.smk 真实规则**的自维护实现（`source_type: custom`、`type: snakemake_local`），
用于本地定制 / 与 flrnaseq 流程行为对齐的场景。

## 规则文件

- `transdecoder.smk` — 两条规则：
  - `rule transdecoder_longorfs`：转录本 FASTA → `transdecoder/{sample}/longorfs/`（候选最长 ORF）
  - `rule transdecoder_predict`：`transdecoder/{sample}/predict/{sample}.{pep,cds,gff3,bed}`（最终 CDS）

规则迁移自 `snakemake.smk/flrnaseq.smk/workflow/rules/transdecoder.smk`，去除对
Snakefile 顶部全局变量（SAMPLES / os / config）与 `docker_wrapper.py` 的依赖：
- 输入路径模板：`long_read/{sample}.fasta`
- 参数内联（与 flrnaseq config.yaml transdecoder 段一致）：
  - longorfs: `-m 50 -G Universal -S --complete_orfs_only`（可经 `params.gene_trans_map` 加映射）
  - predict: `--no_refine_starts`（可经 `params.retain_pfam_hits / retain_blastp_hits` 加证据）
- docker/container 分支移除，直接调用 `TransDecoder.LongOrfs` / `TransDecoder.Predict` 二进制

## 用法

```python
# Snakefile 中
include: "modules/transdecoder/snakemake/transdecoder.smk"

# 运行
snakemake -j 8 transdecoder/sample1/predict/sample1.pep
```

## 依赖环境

规则内 `conda: "envs/transdecoder.yaml"`，需要自备：

```yaml
# envs/transdecoder.yaml
channels: [conda-forge, bioconda]
dependencies:
  - transdecoder=5.7.1
  - perl
  - parallel
```

## 与其它实现的关系

- 官方 wrapper（`../snakemake-wrappers/` 登记层，`v3.13.0/bio/transdecoder/{longorfs,predict}`）为推荐 Snakemake 路径
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`
