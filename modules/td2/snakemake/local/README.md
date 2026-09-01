# td2 / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/td2`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `td2.smk` — 两条规则：
  - `rule td2_longorfs`：转录本 FASTA → `td2/{sample}/longorfs/`（候选最长 ORF）
  - `rule td2_predict`：`td2/{sample}/predict/{sample}.{pep,cds,gff3,bed}`（最终 CDS）

规则迁移自 `snakemake.smk/flrnaseq.smk/workflow/rules/td2.smk`，去除对
Snakefile 顶部全局变量（SAMPLES / os / config）与 `docker_wrapper.py` 的依赖：
- 输入路径模板：`long_read/{sample}.fasta`
- 参数内联（与 flrnaseq config.yaml td2 段一致）：
  - longorfs: `-m 90 -M 90 -G 1 -S --alt-start --all-stopless`（可经 `params.gene_trans_map` 加映射）
  - predict: `--psauron-all-frame`（可经 `params.retain_mmseqs_hits / retain_blastp_hits / retain_hmmer_hits` 加证据）
- docker/container 分支移除，直接调用 `TD2.LongOrfs` / `TD2.Predict` 二进制
- Predict 产物 `<basename>.TD2.{bed,cds,gff3,pep}` 由规则移动为 `{sample}.{ext}`

## 用法

```python
# Snakefile 中
include: "modules/td2/snakemake/local/td2.smk"

# 运行
snakemake -j 8 td2/sample1/predict/sample1.pep
```

## 依赖环境

规则内 `conda: "envs/td2.yaml"`，需要自备：

```yaml
# envs/td2.yaml
channels: [conda-forge, bioconda]
dependencies:
  - td2=1.0.6
```

## 与其它实现的关系

- 官方 wrapper 当前不存在（`../snakemake-wrappers/` 登记层注明 bio/td2 404）；若未来出现可切换
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`
