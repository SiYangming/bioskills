# orffinder / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/orffinder`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `orffinder.smk` — `rule orffinder`：核酸 FASTA → ORF 预测结果

规则迁移自 `snakemake.smk/flrnaseq.smk/workflow/rules/orffinder.smk`，去除对
Snakefile 顶部全局变量（SAMPLES / os / config）与 `docker_wrapper.py` 的依赖：
- 输入路径模板：`long_read/{sample}.fasta`
- 参数内联（与 flrnaseq config.yaml orffinder 段一致）：
  - `outfmt: 2`（Text ASN.1；suffix_map：0=_orf.fa, 1=_cds.fa, 2=.asn1, 3=.ft）
  - `extra: "-s 2 -ml 30"`（起始密码子=任意有义密码子，最小 ORF 长度=30 nt）
- docker/container 分支移除，直接调用 `ORFfinder` 二进制

## 用法

```python
# Snakefile 中
include: "modules/orffinder/snakemake/orffinder.smk"

# 运行（默认 outfmt=2 -> orffinder/sample1.asn1）
snakemake -j 4 orffinder/sample1.asn1
```

改输出格式时，同步调整 `params.outfmt` 与 `output.file` 后缀（见 suffix_map）。

## 依赖环境

规则内 `conda: "envs/orffinder.yaml"`，需要自备：

```yaml
# envs/orffinder.yaml
channels: [conda-forge, bioconda]
dependencies:
  - orffinder=0.4.3
```

## 与其它实现的关系

- 官方 wrapper 当前不存在（`../snakemake-wrappers/` 登记层注明 bio/orffinder 404）；若未来出现可切换
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`
